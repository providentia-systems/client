import 'dart:async';

import 'package:providentia/features/homes/application/home_ports.dart';
import 'package:providentia/features/homes/domain/home_models.dart';

typedef ActiveHomeMutationCoordinator =
    Future<HomeSummary> Function({
      required String homeId,
      required Future<HomeSummary> Function() mutation,
    });

typedef ActiveHomeClearMutationCoordinator =
    Future<void> Function({required Future<void> Function() mutation});

/// Coordinates server-authorized homes with a non-authoritative local active
/// home preference. Every selected home is revalidated against [HomeTransportPort].
final class HomeSessionManager {
  factory HomeSessionManager({
    required HomeTransportPort transport,
    required ActiveHomeStore activeHomeStore,
    void Function(String? homeId)? onActiveHomeChanged,
    void Function(String homeId)? onHomeAccessRevoked,
    ActiveHomeMutationCoordinator? coordinateActiveHomeMutation,
    ActiveHomeClearMutationCoordinator? coordinateActiveHomeClearMutation,
  }) => HomeSessionManager._(
    transport,
    activeHomeStore,
    onActiveHomeChanged,
    onHomeAccessRevoked,
    coordinateActiveHomeMutation,
    coordinateActiveHomeClearMutation,
  );

  HomeSessionManager._(
    this._transport,
    this._activeHomeStore,
    this._onActiveHomeChanged,
    this._onHomeAccessRevoked,
    this._coordinateActiveHomeMutation,
    this._coordinateActiveHomeClearMutation,
  ) : _snapshot = HomeSessionSnapshot(
        status: HomeSessionStatus.selectionRequired,
      );

  final HomeTransportPort _transport;
  final ActiveHomeStore _activeHomeStore;
  final void Function(String? homeId)? _onActiveHomeChanged;
  final void Function(String homeId)? _onHomeAccessRevoked;
  final ActiveHomeMutationCoordinator? _coordinateActiveHomeMutation;
  final ActiveHomeClearMutationCoordinator? _coordinateActiveHomeClearMutation;
  final StreamController<HomeSessionSnapshot> _states =
      StreamController<HomeSessionSnapshot>.broadcast(sync: true);

  HomeSessionSnapshot _snapshot;
  int _generation = 0;
  bool _disposed = false;

  HomeSessionSnapshot get snapshot => _snapshot;

  Stream<HomeSessionSnapshot> get states => _states.stream;

  Future<void> load({
    String? sessionActiveHomeId,
    bool sessionActiveHomeIsAuthoritative = false,
  }) async {
    _ensureOpen();
    final generation = ++_generation;
    final previouslyActiveHomeId = _snapshot.activeHome?.id;
    final previouslyAuthorizedIds = _snapshot.homes
        .map((home) => home.id)
        .toSet();
    final reportedRevokedIds = <String>{};
    _emit(HomeSessionSnapshot(status: HomeSessionStatus.loading));
    try {
      final homes = await _transport.listHomes();
      if (generation != _generation) {
        return;
      }
      _emit(
        HomeSessionSnapshot(status: HomeSessionStatus.loading, homes: homes),
      );

      // The homes list is authoritative. Process removals before any unrelated
      // invitation request can fail or time out, so revoked household data is
      // closed and purged immediately.
      final authorizedIds = homes.map((home) => home.id).toSet();
      for (final revokedHomeId in previouslyAuthorizedIds.difference(
        authorizedIds,
      )) {
        if (reportedRevokedIds.add(revokedHomeId)) {
          _notifyHomeAccessRevoked(revokedHomeId);
        }
      }
      if (sessionActiveHomeId != null &&
          !authorizedIds.contains(sessionActiveHomeId) &&
          reportedRevokedIds.add(sessionActiveHomeId)) {
        _notifyHomeAccessRevoked(sessionActiveHomeId);
      }
      var storedHomeId = await _activeHomeStore.read();
      if (generation != _generation) {
        return;
      }
      if (storedHomeId != null &&
          !authorizedIds.contains(storedHomeId) &&
          reportedRevokedIds.add(storedHomeId)) {
        _notifyHomeAccessRevoked(storedHomeId);
      }
      if (sessionActiveHomeIsAuthoritative &&
          storedHomeId != sessionActiveHomeId) {
        try {
          await _activeHomeStore.clear();
        } on Exception {
          // A local preference is not an authorization grant.
        }
        storedHomeId = null;
      }

      var pendingInvitations = const <RecipientHomeInvitation>[];
      String? invitationLoadMessage;
      try {
        pendingInvitations = await _transport.listPendingInvitations();
      } on HomeTransportException catch (error) {
        invitationLoadMessage = error.safeMessage;
      } on Exception {
        invitationLoadMessage =
            'Home invitations could not be loaded. Your authorized homes remain available.';
      }
      if (generation != _generation) {
        return;
      }
      if (homes.isEmpty) {
        String? preferenceMessage;
        try {
          await _activeHomeStore.clear();
        } on Exception {
          preferenceMessage =
              'The saved home preference could not be cleared, but it cannot grant access.';
        }
        _emit(
          HomeSessionSnapshot(
            status: HomeSessionStatus.selectionRequired,
            homes: homes,
            pendingInvitations: pendingInvitations,
            safeMessage: _combinedMessage(
              invitationLoadMessage,
              preferenceMessage,
            ),
          ),
        );
        if (sessionActiveHomeId != null ||
            (!sessionActiveHomeIsAuthoritative &&
                previouslyActiveHomeId != null)) {
          await _coordinateAuthoritativeActiveHomeClear();
        }
        if (generation != _generation) {
          return;
        }
        _onActiveHomeChanged?.call(null);
        return;
      }

      if (storedHomeId != null && !authorizedIds.contains(storedHomeId)) {
        try {
          await _activeHomeStore.clear();
        } on Exception {
          // A stale preference is not an authorization grant.
        }
      }
      final candidateId = sessionActiveHomeIsAuthoritative
          ? sessionActiveHomeId != null &&
                    authorizedIds.contains(sessionActiveHomeId)
                ? sessionActiveHomeId
                : null
          : _authorizedCandidate(homes, sessionActiveHomeId, storedHomeId);
      if (candidateId == null) {
        _emit(
          HomeSessionSnapshot(
            status: HomeSessionStatus.selectionRequired,
            homes: homes,
            pendingInvitations: pendingInvitations,
            safeMessage: invitationLoadMessage,
          ),
        );
        if (sessionActiveHomeId != null ||
            (!sessionActiveHomeIsAuthoritative &&
                previouslyActiveHomeId != null)) {
          await _coordinateAuthoritativeActiveHomeClear();
          if (generation != _generation) {
            return;
          }
          _onActiveHomeChanged?.call(null);
        }
        return;
      }
      await _activate(
        candidateId,
        homes: homes,
        notifyBackend: candidateId != sessionActiveHomeId,
        generation: generation,
        pendingInvitations: pendingInvitations,
        safeMessage: invitationLoadMessage,
      );
    } on HomeTransportException catch (error) {
      if (generation == _generation) {
        await _handleTransportFailure(error);
      }
    } on Exception {
      if (generation == _generation) {
        _handleUnexpectedFailure(
          'Your homes could not be loaded. Try again safely.',
        );
      }
    }
  }

  /// Reconciles an active-home change broadcast by the shared web session.
  ///
  /// [load] first closes the old workspace, then reloads the authoritative
  /// home list and adopts [homeId] without sending a second switch mutation.
  Future<void> reconcileSessionActiveHome(String? homeId) {
    _ensureOpen();
    if (_snapshot.status == HomeSessionStatus.ready &&
        _snapshot.activeHome?.id == homeId) {
      return Future<void>.value();
    }
    return load(
      sessionActiveHomeId: homeId,
      sessionActiveHomeIsAuthoritative: true,
    );
  }

  /// Immediately drops authenticated presentation state after session loss.
  /// Persisted household rows remain home-isolated and require a future
  /// authenticated authorization check before they can be reopened.
  void handleAuthenticationLost() {
    if (_disposed) {
      return;
    }
    _generation++;
    unawaited(_activeHomeStore.clear().catchError((_) {}));
    _onActiveHomeChanged?.call(null);
    _emit(HomeSessionSnapshot(status: HomeSessionStatus.selectionRequired));
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
    } on Exception {
      if (generation == _generation) {
        _handleUnexpectedFailure(
          'The home could not be created safely. Try again.',
        );
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

  /// Closes the current workspace and returns to the authorized-home chooser.
  ///
  /// This only clears the local preference. It never treats the cached home
  /// list as an authorization grant: opening a home still calls
  /// [HomeTransportPort.switchActiveHome] and validates the server response.
  Future<void> returnToChooser() async {
    _ensureOpen();
    _generation++;
    final homes = _snapshot.homes;
    final pendingInvitations = _snapshot.pendingInvitations;
    String? safeMessage;
    try {
      await _activeHomeStore.clear();
    } on Exception {
      safeMessage =
          'The saved home preference could not be cleared. Choose an authorized home to continue.';
    }
    _emit(
      HomeSessionSnapshot(
        status: HomeSessionStatus.selectionRequired,
        homes: homes,
        pendingInvitations: pendingInvitations,
        safeMessage: safeMessage,
      ),
    );
  }

  Future<void> refreshGovernance() async {
    final active = _requireActiveHome();
    final generation = ++_generation;
    try {
      final refreshed = await _transport.getHome(active.id);
      final effectivePermissions = refreshed.effectivePermissions;
      final permissionPolicies =
          effectivePermissions.contains('permissions.manage')
          ? await _transport.listPermissionPolicies(active.id)
          : const <HomePermissionPolicy>[];
      final memberships = effectivePermissions.contains('members.read')
          ? await _transport.listMemberships(active.id)
          : const <HomeMembership>[];
      final invitations = effectivePermissions.contains('members.invite')
          ? await _transport.listInvitations(active.id)
          : const <HomeInvitation>[];
      // Ownership proposals are participant-scoped on the backend: holders of
      // 'ownership.transfer' manage the proposals they created, while any
      // other member may be the target of a pending proposal and must be able
      // to see it to accept or reject.
      final ownershipTransfers =
          effectivePermissions.contains('ownership.transfer') ||
              active.role != HomeRole.owner
          ? await _transport.listHomeOwnershipTransfers(active.id)
          : const <HomeOwnershipTransfer>[];
      if (generation != _generation || _snapshot.activeHome?.id != active.id) {
        return;
      }
      _emit(
        _snapshot.copyWith(
          activeHome: refreshed,
          memberships: memberships,
          invitations: invitations,
          permissionPolicies: permissionPolicies,
          ownershipTransfers: ownershipTransfers,
          clearMessage: true,
        ),
      );
    } on HomeTransportException catch (error) {
      if (generation == _generation) {
        await _handleTransportFailure(error, fallbackHomeId: active.id);
      }
    } on Exception {
      if (generation == _generation) {
        _handleUnexpectedFailure(
          'Home permissions could not be refreshed safely.',
        );
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
    } on Exception {
      _handleUnexpectedFailure('Member access could not be changed safely.');
    }
  }

  /// Removes another member's active membership. The caller's own membership
  /// ends through [leaveActiveHome] and the owner membership changes only
  /// through an accepted ownership transfer.
  Future<void> removeMembership(HomeMembership membership) async {
    final active = _requireActiveHome();
    if (membership.role == HomeRole.owner) {
      throw StateError(
        'The owner membership changes only through an ownership transfer.',
      );
    }
    try {
      await _transport.removeHomeMembership(
        homeId: active.id,
        userId: membership.userId,
        expectedRevision: membership.revision,
      );
      await refreshGovernance();
    } on HomeTransportException catch (error) {
      await _handleGovernanceConflict(error, active.id);
    } on Exception {
      _handleUnexpectedFailure('The member could not be removed safely.');
    }
  }

  /// Requests the emailed single-use confirmation that authorizes proposing
  /// an ownership transfer. Returns null when the request failed; the failure
  /// is surfaced through the snapshot's safe message.

  Future<void> proposeOwnershipTransfer({
    required HomeMembership target,
    required String stepUpToken,
  }) async {
    final active = _requireActiveHome();
    if (target.role == HomeRole.owner) {
      throw StateError('Ownership can only move to another active member.');
    }
    final token = stepUpToken.trim();
    if (token.length < 40) {
      throw ArgumentError.value(
        stepUpToken,
        'stepUpToken',
        'must be the complete emailed confirmation code',
      );
    }
    try {
      await _transport.proposeHomeOwnershipTransfer(
        homeId: active.id,
        targetUserId: target.userId,
        expectedTargetRevision: target.revision,
        stepUpToken: token,
      );
      await refreshGovernance();
    } on HomeTransportException catch (error) {
      await _handleGovernanceConflict(error, active.id);
    } on Exception {
      _handleUnexpectedFailure(
        'The ownership transfer could not be proposed safely.',
      );
    }
  }

  /// Accepts a pending transfer addressed to the signed-in member. Ownership
  /// changes atomically on the backend, so the authoritative home list and
  /// role are reloaded before governance data is republished.
  Future<void> acceptOwnershipTransfer(HomeOwnershipTransfer transfer) async {
    final active = _requireActiveHome();
    if (transfer.homeId != active.id || !transfer.isPending) {
      throw StateError(
        'This ownership transfer is no longer available for the active home.',
      );
    }
    try {
      await _transport.acceptHomeOwnershipTransfer(
        homeId: active.id,
        transferId: transfer.id,
        expectedRevision: transfer.revision,
      );
      await load(sessionActiveHomeId: active.id);
      if (_snapshot.status == HomeSessionStatus.ready &&
          _snapshot.activeHome?.id == active.id) {
        await refreshGovernance();
      }
    } on HomeTransportException catch (error) {
      await _handleGovernanceConflict(error, active.id);
    } on Exception {
      _handleUnexpectedFailure(
        'The ownership transfer could not be accepted safely.',
      );
    }
  }

  Future<void> rejectOwnershipTransfer(HomeOwnershipTransfer transfer) async {
    final active = _requireActiveHome();
    if (transfer.homeId != active.id || !transfer.isPending) {
      throw StateError(
        'This ownership transfer is no longer available for the active home.',
      );
    }
    try {
      await _transport.rejectHomeOwnershipTransfer(
        homeId: active.id,
        transferId: transfer.id,
        expectedRevision: transfer.revision,
      );
      await refreshGovernance();
    } on HomeTransportException catch (error) {
      await _handleGovernanceConflict(error, active.id);
    } on Exception {
      _handleUnexpectedFailure(
        'The ownership transfer could not be rejected safely.',
      );
    }
  }

  Future<void> revokeOwnershipTransfer(HomeOwnershipTransfer transfer) async {
    final active = _requireActiveHome();
    if (transfer.homeId != active.id || !transfer.isPending) {
      throw StateError(
        'This ownership transfer is no longer available for the active home.',
      );
    }
    try {
      await _transport.revokeHomeOwnershipTransfer(
        homeId: active.id,
        transferId: transfer.id,
        expectedRevision: transfer.revision,
      );
      await refreshGovernance();
    } on HomeTransportException catch (error) {
      await _handleGovernanceConflict(error, active.id);
    } on Exception {
      _handleUnexpectedFailure(
        'The ownership transfer could not be revoked safely.',
      );
    }
  }

  Future<void> updateActiveHome({
    required String name,
    required String locale,
    required String currency,
    required String timezone,
  }) async {
    final active = _requireActiveHome();
    final normalizedName = name.trim();
    final normalizedLocale = locale.trim();
    final normalizedCurrency = currency.trim().toUpperCase();
    final normalizedTimezone = timezone.trim();
    if (normalizedName.isEmpty ||
        normalizedLocale.length < 2 ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(normalizedCurrency) ||
        normalizedTimezone.isEmpty) {
      throw ArgumentError('Home settings are incomplete.');
    }
    try {
      final updated = await _transport.updateHome(
        homeId: active.id,
        name: normalizedName,
        locale: normalizedLocale,
        currency: normalizedCurrency,
        timezone: normalizedTimezone,
        expectedRevision: active.revision,
      );
      final homes = _snapshot.homes
          .map((home) => home.id == updated.id ? updated : home)
          .toList(growable: false);
      _emit(
        _snapshot.copyWith(
          homes: homes,
          activeHome: updated,
          clearMessage: true,
        ),
      );
    } on HomeTransportException catch (error) {
      await _handleTransportFailure(error, fallbackHomeId: active.id);
    } on Exception {
      _handleUnexpectedFailure('Home settings could not be saved safely.');
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
    } on Exception {
      _handleUnexpectedFailure('The invitation could not be sent safely.');
      return null;
    }
  }

  Future<void> revokeInvitation(HomeInvitation invitation) async {
    final active = _requireActiveHome();
    if (invitation.homeId != active.id || !invitation.mayBeRevoked) {
      throw StateError(
        'This invitation cannot be revoked from the active home.',
      );
    }
    try {
      await _transport.revokeInvitation(
        homeId: active.id,
        invitationId: invitation.id,
        expectedRevision: invitation.revision,
      );
      await refreshGovernance();
    } on HomeTransportException catch (error) {
      await _handleTransportFailure(error, fallbackHomeId: active.id);
    } on Exception {
      _handleUnexpectedFailure('The invitation could not be revoked safely.');
    }
  }

  Future<void> declinePendingInvitation(
    RecipientHomeInvitation invitation,
  ) async {
    _ensureOpen();
    final generation = ++_generation;
    try {
      await _transport.declinePendingInvitation(
        invitationId: invitation.id,
        expectedRevision: invitation.revision,
      );
      final pending = await _transport.listPendingInvitations();
      if (generation == _generation) {
        _emit(
          _snapshot.copyWith(pendingInvitations: pending, clearMessage: true),
        );
      }
    } on HomeTransportException catch (error) {
      if (generation == _generation) await _handleTransportFailure(error);
    } on Exception {
      if (generation == _generation) {
        _handleUnexpectedFailure(
          'The invitation could not be declined. Refresh and retry.',
        );
      }
    }
  }

  Future<void> acceptPendingInvitation(
    RecipientHomeInvitation invitation,
  ) async {
    _ensureOpen();
    final generation = ++_generation;
    try {
      final accepted = await _transport.acceptPendingInvitation(
        invitationId: invitation.id,
        expectedRevision: invitation.revision,
      );
      final homes = await _transport.listHomes();
      final pendingInvitations = await _transport.listPendingInvitations();
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
        pendingInvitations: pendingInvitations,
      );
    } on HomeTransportException catch (error) {
      if (generation == _generation) {
        if (error.revoked) {
          await _handleTransportFailure(error);
        } else {
          // A recipient invitation is not scoped to the currently open home.
          // An expired/revoked invitation must not close an unrelated active
          // workspace or discard its locally selected home.
          _emit(
            _snapshot.copyWith(
              status: _snapshot.activeHome == null
                  ? HomeSessionStatus.selectionRequired
                  : HomeSessionStatus.ready,
              safeMessage: error.safeMessage,
            ),
          );
        }
      }
    } on Exception {
      if (generation == _generation) {
        _handleUnexpectedFailure(
          'The invitation could not be accepted safely.',
        );
      }
    }
  }

  Future<void> updatePermissionPolicy({
    required HomePermissionPolicy policy,
    required Set<String> permissions,
  }) async {
    final active = _requireActiveHome();
    try {
      await _transport.putPermissionPolicy(
        homeId: active.id,
        role: policy.role,
        permissions: permissions,
        expectedRevision: policy.revision,
      );
      await refreshGovernance();
    } on HomeTransportException catch (error) {
      await _handleTransportFailure(error, fallbackHomeId: active.id);
    } on Exception {
      _handleUnexpectedFailure('Role permissions could not be saved safely.');
    }
  }

  Future<void> leaveActiveHome() async {
    final active = _requireActiveHome();
    try {
      final coordinate = _coordinateActiveHomeClearMutation;
      if (coordinate == null) {
        await _transport.leaveHome(active.id);
      } else {
        await coordinate(mutation: () => _transport.leaveHome(active.id));
      }
      await handleMembershipRevoked(
        active.id,
        identityAlreadyCleared: coordinate != null,
      );
    } on HomeTransportException catch (error) {
      await _handleTransportFailure(error, fallbackHomeId: active.id);
    } on Exception {
      _handleUnexpectedFailure('The home could not be left safely.');
    }
  }

  /// Immediately removes an inaccessible home from presentation and prevents
  /// late responses from repopulating its private data.
  Future<void> handleMembershipRevoked(
    String homeId, {
    bool identityAlreadyCleared = false,
  }) async {
    _ensureOpen();
    final generation = ++_generation;
    final remaining = _snapshot.homes
        .where((home) => home.id != homeId)
        .toList(growable: false);
    final closesCurrentWorkspace =
        _snapshot.activeHome?.id == homeId ||
        (_snapshot.status == HomeSessionStatus.loading &&
            _snapshot.homes.any((home) => home.id == homeId));
    if (!closesCurrentWorkspace) {
      _notifyHomeAccessRevoked(homeId);
      _emit(_snapshot.copyWith(homes: remaining));
      return;
    }
    final pendingInvitations = _snapshot.pendingInvitations;
    _notifyHomeAccessRevoked(homeId);
    _emit(
      HomeSessionSnapshot(
        status: HomeSessionStatus.accessRevoked,
        homes: remaining,
        pendingInvitations: pendingInvitations,
        revokedHomeId: homeId,
        safeMessage:
            'Access to this home changed. Its private workspace has been closed.',
      ),
    );
    try {
      await _activeHomeStore.clear();
    } on Exception {
      // The preference is never an authorization grant. Continue closing the
      // workspace even if local preference storage is temporarily unavailable.
    }
    if (!identityAlreadyCleared) {
      await _coordinateAuthoritativeActiveHomeClear();
    }
    if (generation != _generation) {
      return;
    }
    _onActiveHomeChanged?.call(null);
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
    List<RecipientHomeInvitation>? pendingInvitations,
    String? safeMessage,
  }) async {
    _emit(
      HomeSessionSnapshot(
        status: HomeSessionStatus.loading,
        homes: homes,
        pendingInvitations: pendingInvitations ?? _snapshot.pendingInvitations,
        safeMessage: safeMessage,
      ),
    );
    try {
      late final HomeSummary selected;
      if (!notifyBackend) {
        selected = await _transport.getHome(homeId);
      } else if (_coordinateActiveHomeMutation case final coordinate?) {
        selected = await coordinate(
          homeId: homeId,
          mutation: () async {
            final switched = await _transport.switchActiveHome(homeId);
            if (generation != _generation) {
              throw const _SupersededHomeMutation();
            }
            return switched;
          },
        );
      } else {
        selected = await _transport.switchActiveHome(homeId);
      }
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
      final permissionPolicies =
          selected.effectivePermissions.contains('permissions.manage')
          ? await _transport.listPermissionPolicies(selected.id)
          : const <HomePermissionPolicy>[];
      if (generation != _generation) {
        return;
      }
      await _activeHomeStore.write(selected.id);
      if (generation != _generation) {
        return;
      }
      _onActiveHomeChanged?.call(selected.id);
      _emit(
        HomeSessionSnapshot(
          status: HomeSessionStatus.ready,
          homes: homes,
          activeHome: selected,
          pendingInvitations: _snapshot.pendingInvitations,
          permissionPolicies: permissionPolicies,
          safeMessage: safeMessage,
        ),
      );
    } on HomeTransportException catch (error) {
      if (generation == _generation) {
        await _handleTransportFailure(error, fallbackHomeId: homeId);
      }
    } on Exception {
      if (generation == _generation) {
        _handleUnexpectedFailure(
          'The selected home could not be opened safely. Try again.',
        );
      }
    }
  }

  /// Revision conflicts mean the governance target changed on another device.
  /// The authoritative state is reloaded first so the next attempt uses
  /// current revisions, then the safe retry guidance is surfaced.
  Future<void> _handleGovernanceConflict(
    HomeTransportException error,
    String homeId,
  ) async {
    if (error.kind != HomeFailureKind.conflict) {
      await _handleTransportFailure(error, fallbackHomeId: homeId);
      return;
    }
    await refreshGovernance();
    if (_snapshot.status == HomeSessionStatus.ready &&
        _snapshot.activeHome?.id == homeId) {
      _emit(_snapshot.copyWith(safeMessage: error.safeMessage));
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
        try {
          await _activeHomeStore.clear();
        } on Exception {
          // Stale preferences never grant access and will be revalidated.
        }
        _onActiveHomeChanged?.call(null);
        _emit(
          HomeSessionSnapshot(
            status: HomeSessionStatus.accessRevoked,
            homes: _snapshot.homes,
            pendingInvitations: _snapshot.pendingInvitations,
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
        status: _snapshot.activeHome == null
            ? HomeSessionStatus.failure
            : HomeSessionStatus.ready,
        safeMessage: error.safeMessage,
      ),
    );
  }

  void _handleUnexpectedFailure(String safeMessage) {
    _emit(
      _snapshot.copyWith(
        status: _snapshot.activeHome == null
            ? HomeSessionStatus.failure
            : HomeSessionStatus.ready,
        safeMessage: safeMessage,
      ),
    );
  }

  void _notifyHomeAccessRevoked(String homeId) {
    try {
      _onHomeAccessRevoked?.call(homeId);
    } on Exception {
      // Callback failures must never keep an inaccessible workspace open.
    }
  }

  Future<void> _coordinateAuthoritativeActiveHomeClear() async {
    final coordinate = _coordinateActiveHomeClearMutation;
    if (coordinate == null) {
      return;
    }
    try {
      await coordinate(mutation: () async {});
    } on Exception {
      // Workspace closure and data purge remain authoritative even if a
      // sibling-tab session mirror cannot be published immediately.
    }
  }

  String? _combinedMessage(String? first, String? second) {
    final messages = <String>[
      if (first != null && first.isNotEmpty) first,
      if (second != null && second.isNotEmpty) second,
    ];
    return messages.isEmpty ? null : messages.join(' ');
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

final class _SupersededHomeMutation implements Exception {
  const _SupersededHomeMutation();
}
