import 'dart:async';

import 'package:flutter/foundation.dart';
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

  Future<void> reconcileSessionActiveHome(String? homeId) {
    return _manager.reconcileSessionActiveHome(homeId);
  }

  void handleAuthenticationLost() {
    _manager.handleAuthenticationLost();
  }

  Future<void> selectHome(String homeId) async {
    try {
      await _manager.selectHome(homeId);
    } on ArgumentError {
      _localFailure('That home is no longer available. Refresh your homes.');
    }
  }

  Future<void> returnToChooser() => _manager.returnToChooser();

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

  Future<void> removeMembership(HomeMembership membership) async {
    try {
      await _manager.removeMembership(membership);
    } on StateError catch (error) {
      _localFailure(error.message.toString());
    }
  }

  Future<void> proposeOwnershipTransfer({
    required HomeMembership target,
    required String stepUpToken,
  }) async {
    try {
      await _manager.proposeOwnershipTransfer(
        target: target,
        stepUpToken: stepUpToken,
      );
    } on ArgumentError {
      _localFailure(
        'Enter the complete confirmation code from the ownership email.',
      );
    } on StateError catch (error) {
      _localFailure(error.message.toString());
    }
  }

  Future<void> acceptOwnershipTransfer(HomeOwnershipTransfer transfer) async {
    try {
      await _manager.acceptOwnershipTransfer(transfer);
    } on StateError catch (error) {
      _localFailure(error.message.toString());
    }
  }

  Future<void> rejectOwnershipTransfer(HomeOwnershipTransfer transfer) async {
    try {
      await _manager.rejectOwnershipTransfer(transfer);
    } on StateError catch (error) {
      _localFailure(error.message.toString());
    }
  }

  Future<void> revokeOwnershipTransfer(HomeOwnershipTransfer transfer) async {
    try {
      await _manager.revokeOwnershipTransfer(transfer);
    } on StateError catch (error) {
      _localFailure(error.message.toString());
    }
  }

  Future<void> updateActiveHome({
    required String name,
    required String locale,
    required String currency,
    required String timezone,
  }) async {
    try {
      await _manager.updateActiveHome(
        name: name,
        locale: locale,
        currency: currency,
        timezone: timezone,
      );
    } on ArgumentError {
      _localFailure('Complete the home name, locale, currency, and time zone.');
    }
  }

  Future<void> revokeInvitation(HomeInvitation invitation) async {
    try {
      await _manager.revokeInvitation(invitation);
    } on StateError catch (error) {
      _localFailure(error.message.toString());
    }
  }

  Future<void> declinePendingInvitation(
    RecipientHomeInvitation invitation,
  ) async {
    try {
      await _manager.declinePendingInvitation(invitation);
    } on StateError {
      _localFailure('That invitation is no longer available. Refresh first.');
    }
  }

  Future<void> acceptPendingInvitation(
    RecipientHomeInvitation invitation,
  ) async {
    try {
      await _manager.acceptPendingInvitation(invitation);
    } on StateError {
      _localFailure('That invitation is no longer available. Refresh first.');
    }
  }

  Future<void> updatePermissionPolicy({
    required HomePermissionPolicy policy,
    required Set<String> permissions,
  }) async {
    try {
      await _manager.updatePermissionPolicy(
        policy: policy,
        permissions: permissions,
      );
    } on StateError {
      _localFailure('Select a home before changing role permissions.');
    }
  }

  Future<void> refreshPendingInvitations() =>
      _manager.load(sessionActiveHomeId: _snapshot.activeHome?.id);

  Future<void> leaveActiveHome() async {
    try {
      await _manager.leaveActiveHome();
    } on StateError {
      _localFailure('Select a home before leaving it.');
    }
  }

  Future<void> handleMembershipRevoked(String homeId) {
    return _manager.handleMembershipRevoked(homeId);
  }

  void _localFailure(String safeMessage) {
    _snapshot = _snapshot.copyWith(
      status: _snapshot.activeHome == null
          ? HomeSessionStatus.failure
          : HomeSessionStatus.ready,
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
