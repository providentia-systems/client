import 'dart:async';

import 'package:providentia/features/homes/application/home_ports.dart';
import 'package:providentia/features/homes/domain/home_models.dart';

/// Coordinates server-authorized homes with a non-authoritative local active
/// home preference. Every selected home is revalidated against [HomeTransportPort].
final class HomeSessionManager {
  HomeSessionManager({
    required HomeTransportPort transport,
    required ActiveHomeStore activeHomeStore,
    void Function(String? homeId)? onActiveHomeChanged,
    void Function(String homeId)? onHomeAccessRevoked,
  }) : _transport = transport,
       _activeHomeStore = activeHomeStore,
       _onActiveHomeChanged = onActiveHomeChanged,
       _onHomeAccessRevoked = onHomeAccessRevoked,
       _snapshot = HomeSessionSnapshot(
         status: HomeSessionStatus.selectionRequired,
       );

  final HomeTransportPort _transport;
  final ActiveHomeStore _activeHomeStore;
  final void Function(String? homeId)? _onActiveHomeChanged;
  final void Function(String homeId)? _onHomeAccessRevoked;
  final StreamController<HomeSessionSnapshot> _states =
      StreamController<HomeSessionSnapshot>.broadcast(sync: true);

  HomeSessionSnapshot _snapshot;
  int _generation = 0;
  bool _disposed = false;

  HomeSessionSnapshot get snapshot => _snapshot;

  Stream<HomeSessionSnapshot> get states => _states.stream;

  Future<void> load({String? sessionActiveHomeId}) async {
    _ensureOpen();
    final generation = ++_generation;
    _emit(HomeSessionSnapshot(status: HomeSessionStatus.loading));
    try {
      final homes = await _transport.listHomes();
      if (generation != _generation) {
        return;
      }
      if (homes.isEmpty) {
        await _activeHomeStore.clear();
        _onActiveHomeChanged?.call(null);
        _emit(
          HomeSessionSnapshot(
            status: HomeSessionStatus.selectionRequired,
            homes: homes,
          ),
        );
        return;
      }

      final storedHomeId = await _activeHomeStore.read();
      if (generation != _generation) {
        return;
      }
      final candidateId = _authorizedCandidate(
        homes,
        sessionActiveHomeId,
        storedHomeId,
      );
      if (candidateId == null) {
        _emit(
          HomeSessionSnapshot(
            status: HomeSessionStatus.selectionRequired,
            homes: homes,
          ),
        );
        return;
      }
      await _activate(
        candidateId,
        homes: homes,
        notifyBackend: candidateId != sessionActiveHomeId,
        generation: generation,
      );
    } on HomeTransportException catch (error) {
      if (generation == _generation) {
        await _handleTransportFailure(error);
      }
    } on Exception {
      if (generation == _generation) {
        _emit(
          HomeSessionSnapshot(
            status: HomeSessionStatus.failure,
            safeMessage: 'Your homes could not be loaded. Try again safely.',
          ),
        );
      }
    }
  }

  Future<HomeSummary?> createHome(CreateHomeCommand command) async {
    _ensureOpen();
    final generation = ++_generation;
    _emit(_snapshot.copyWith(status: HomeSessionStatus.loading));
    try {
      final created = await _transport.createHome(command);
      final homes = <HomeSummary>[
        ..._snapshot.homes.where((home) => home.id != created.id),
        created,
      ];
      await _activate(
        created.id,
        homes: homes,
        notifyBackend: true,
        generation: generation,
      );
      return generation == _generation ? _snapshot.activeHome : null;
    } on HomeTransportException catch (error) {
      if (generation == _generation) {
        await _handleTransportFailure(error);
      }
      return null;
    }
  }

  Future<void> selectHome(String homeId) async {
    _ensureOpen();
    if (!_snapshot.homes.any((home) => home.id == homeId)) {
      throw ArgumentError.value(homeId, 'homeId', 'must be an authorized home');
    }
    final generation = ++_generation;
    await _activate(
      homeId,
      homes: _snapshot.homes,
      notifyBackend: true,
      generation: generation,
    );
  }

  Future<void> refreshGovernance() async {
    final active = _requireActiveHome();
    final generation = ++_generation;
    try {
      final memberships = await _transport.listMemberships(active.id);
      final invitationTransport = _transport is HomeInvitationAdministrationPort
          ? _transport as HomeInvitationAdministrationPort
          : null;
      final invitations = invitationTransport == null
          ? _snapshot.invitations
          : await invitationTransport.listInvitations(active.id);
      if (generation != _generation || _snapshot.activeHome?.id != active.id) {
        return;
      }
      _emit(
        _snapshot.copyWith(
          memberships: memberships,
          invitations: invitations,
          clearMessage: true,
        ),
      );
    } on HomeTransportException catch (error) {
      if (generation == _generation) {
        await _handleTransportFailure(error, fallbackHomeId: active.id);
      }
    }
  }

  Future<void> changeMembershipRole({
    required HomeMembership membership,
    required HomeRole role,
  }) async {
    final active = _requireActiveHome();
    try {
      await _transport.changeMembershipRole(
        homeId: active.id,
        userId: membership.userId,
        role: role,
        expectedRevision: membership.revision,
      );
      await refreshGovernance();
    } on HomeTransportException catch (error) {
      await _handleTransportFailure(error, fallbackHomeId: active.id);
    }
  }

  Future<HomeInvitation?> invite({
    required String email,
    required HomeRole role,
  }) async {
    final active = _requireActiveHome();
    final normalizedEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
      throw ArgumentError.value(email, 'email', 'must be a valid email');
    }
    try {
      final invitation = await _transport.createInvitation(
        homeId: active.id,
        email: normalizedEmail,
        role: role,
      );
      _emit(
        _snapshot.copyWith(
          invitations: <HomeInvitation>[
            ..._snapshot.invitations.where(
              (existing) => existing.id != invitation.id,
            ),
            invitation,
          ],
          clearMessage: true,
        ),
      );
      return invitation;
    } on HomeTransportException catch (error) {
      await _handleTransportFailure(error, fallbackHomeId: active.id);
      return null;
    }
  }

  Future<void> revokeInvitation(HomeInvitation invitation) async {
    final active = _requireActiveHome();
    final invitationTransport = _transport;
    if (invitationTransport is! HomeInvitationAdministrationPort) {
      throw UnsupportedError(
        'Invitation revocation is not published by this server contract.',
      );
    }
    final administration =
        invitationTransport as HomeInvitationAdministrationPort;
    if (invitation.homeId != active.id || !invitation.mayBeRevoked) {
      throw StateError(
        'This invitation cannot be revoked from the active home.',
      );
    }
    await administration.revokeInvitation(
      homeId: active.id,
      invitationId: invitation.id,
      expectedRevision: invitation.revision,
    );
    await refreshGovernance();
  }

  Future<void> acceptInvitation(String token) async {
    _ensureOpen();
    final generation = ++_generation;
    try {
      final accepted = await _transport.acceptInvitation(token.trim());
      final homes = await _transport.listHomes();
      if (generation != _generation) {
        return;
      }
      if (!homes.any((home) => home.id == accepted.id)) {
        throw const HomeTransportException(
          kind: HomeFailureKind.authorization,
          safeMessage: 'The accepted home is not available to this session.',
        );
      }
      await _activate(
        accepted.id,
        homes: homes,
        notifyBackend: true,
        generation: generation,
      );
    } on HomeTransportException catch (error) {
      if (generation == _generation) {
        await _handleTransportFailure(error);
      }
    }
  }

  Future<void> leaveActiveHome() async {
    final active = _requireActiveHome();
    try {
      await _transport.leaveHome(active.id);
      await handleMembershipRevoked(active.id);
    } on HomeTransportException catch (error) {
      await _handleTransportFailure(error, fallbackHomeId: active.id);
    }
  }

  /// Immediately removes an inaccessible home from presentation and prevents
  /// late responses from repopulating its private data.
  Future<void> handleMembershipRevoked(String homeId) async {
    _ensureOpen();
    _generation++;
    final remaining = _snapshot.homes
        .where((home) => home.id != homeId)
        .toList(growable: false);
    if (_snapshot.activeHome?.id != homeId) {
      _emit(_snapshot.copyWith(homes: remaining));
      return;
    }
    await _activeHomeStore.clear();
    _onActiveHomeChanged?.call(null);
    _onHomeAccessRevoked?.call(homeId);
    _emit(
      HomeSessionSnapshot(
        status: HomeSessionStatus.accessRevoked,
        homes: remaining,
        revokedHomeId: homeId,
        safeMessage:
            'Access to this home changed. Its private workspace has been closed.',
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation++;
    await _states.close();
  }

  Future<void> _activate(
    String homeId, {
    required List<HomeSummary> homes,
    required bool notifyBackend,
    required int generation,
  }) async {
    _emit(HomeSessionSnapshot(status: HomeSessionStatus.loading, homes: homes));
    try {
      final selected = notifyBackend
          ? await _transport.switchActiveHome(homeId)
          : homes.firstWhere((home) => home.id == homeId);
      if (generation != _generation) {
        return;
      }
      if (selected.id != homeId ||
          !homes.any((home) => home.id == selected.id)) {
        throw const HomeTransportException(
          kind: HomeFailureKind.authorization,
          safeMessage: 'The selected home could not be authorized.',
        );
      }
      await _activeHomeStore.write(selected.id);
      final memberships = await _transport.listMemberships(selected.id);
      if (generation != _generation) {
        return;
      }
      _onActiveHomeChanged?.call(selected.id);
      _emit(
        HomeSessionSnapshot(
          status: HomeSessionStatus.ready,
          homes: homes,
          activeHome: selected,
          memberships: memberships,
        ),
      );
    } on HomeTransportException catch (error) {
      if (generation == _generation) {
        await _handleTransportFailure(error, fallbackHomeId: homeId);
      }
    }
  }

  Future<void> _handleTransportFailure(
    HomeTransportException error, {
    String? fallbackHomeId,
  }) async {
    if (error.revoked) {
      final affectedHomeId =
          error.homeId ?? fallbackHomeId ?? _snapshot.activeHome?.id;
      if (affectedHomeId == null || affectedHomeId.trim().isEmpty) {
        await _activeHomeStore.clear();
        _onActiveHomeChanged?.call(null);
        _emit(
          HomeSessionSnapshot(
            status: HomeSessionStatus.accessRevoked,
            homes: _snapshot.homes,
            safeMessage:
                'Home access changed. Select an authorized home to continue.',
          ),
        );
        return;
      }
      await handleMembershipRevoked(affectedHomeId);
      return;
    }
    _emit(
      _snapshot.copyWith(
        status: HomeSessionStatus.failure,
        safeMessage: error.safeMessage,
      ),
    );
  }

  String? _authorizedCandidate(
    List<HomeSummary> homes,
    String? sessionActiveHomeId,
    String? storedHomeId,
  ) {
    final authorized = homes.map((home) => home.id).toSet();
    if (sessionActiveHomeId != null &&
        authorized.contains(sessionActiveHomeId)) {
      return sessionActiveHomeId;
    }
    if (storedHomeId != null && authorized.contains(storedHomeId)) {
      return storedHomeId;
    }
    return homes.length == 1 ? homes.single.id : null;
  }

  HomeSummary _requireActiveHome() {
    _ensureOpen();
    final active = _snapshot.activeHome;
    if (active == null || _snapshot.status != HomeSessionStatus.ready) {
      throw StateError('Select an active home first.');
    }
    return active;
  }

  void _emit(HomeSessionSnapshot snapshot) {
    if (_disposed) {
      return;
    }
    _snapshot = snapshot;
    _states.add(snapshot);
  }

  void _ensureOpen() {
    if (_disposed) {
      throw StateError('HomeSessionManager has been disposed.');
    }
  }
}
