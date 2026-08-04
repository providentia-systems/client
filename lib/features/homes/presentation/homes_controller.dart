import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/homes/application/home_ports.dart';
import 'package:providentia/features/homes/application/home_session_manager.dart';
import 'package:providentia/features/homes/domain/home_models.dart';

final class HomesController extends ChangeNotifier {
  HomesController(this._manager) : _snapshot = _manager.snapshot {
    _subscription = _manager.states.listen((snapshot) {
      _snapshot = snapshot;
      notifyListeners();
    });
  }

  final HomeSessionManager _manager;
  late final StreamSubscription<HomeSessionSnapshot> _subscription;
  HomeSessionSnapshot _snapshot;

  HomeSessionSnapshot get snapshot => _snapshot;

  bool get isBusy => _snapshot.status == HomeSessionStatus.loading;

  Future<void> load({String? sessionActiveHomeId}) {
    return _manager.load(sessionActiveHomeId: sessionActiveHomeId);
  }

  Future<void> selectHome(String homeId) async {
    try {
      await _manager.selectHome(homeId);
    } on ArgumentError {
      _localFailure('That home is no longer available. Refresh your homes.');
    }
  }

  Future<void> createHome({
    required String name,
    required String locale,
    required String currency,
    required String timezone,
  }) async {
    try {
      await _manager.createHome(
        CreateHomeCommand(
          name: name.trim(),
          locale: locale.trim(),
          currency: currency.trim().toUpperCase(),
          timezone: timezone.trim(),
        ),
      );
    } on ArgumentError {
      _localFailure('Complete the home name, locale, currency, and time zone.');
    }
  }

  Future<void> refreshGovernance() async {
    try {
      await _manager.refreshGovernance();
    } on StateError {
      _localFailure('Select a home before managing its members.');
    }
  }

  Future<void> invite({required String email, required HomeRole role}) async {
    try {
      await _manager.invite(email: email, role: role);
    } on ArgumentError {
      _localFailure('Enter a valid invitation email address.');
    } on StateError {
      _localFailure('Select a home before inviting a member.');
    }
  }

  Future<void> changeMembershipRole({
    required HomeMembership membership,
    required HomeRole role,
  }) async {
    try {
      await _manager.changeMembershipRole(membership: membership, role: role);
    } on StateError {
      _localFailure('Select a home before changing member access.');
    }
  }

  Future<void> revokeInvitation(HomeInvitation invitation) async {
    try {
      await _manager.revokeInvitation(invitation);
    } on StateError catch (error) {
      _localFailure(error.message?.toString() ?? 'The invitation changed.');
    } on UnsupportedError {
      _localFailure(
        'Invitation revocation is not available on this server version.',
      );
    }
  }

  Future<void> acceptInvitation(String token) async {
    if (token.trim().isEmpty) {
      _localFailure('The invitation link is incomplete.');
      return;
    }
    await _manager.acceptInvitation(token);
  }

  Future<void> leaveActiveHome() => _manager.leaveActiveHome();

  Future<void> handleMembershipRevoked(String homeId) {
    return _manager.handleMembershipRevoked(homeId);
  }

  void _localFailure(String safeMessage) {
    _snapshot = _snapshot.copyWith(
      status: HomeSessionStatus.failure,
      safeMessage: safeMessage,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
