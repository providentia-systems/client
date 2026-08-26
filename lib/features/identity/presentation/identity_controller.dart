import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/application/identity_session_manager.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

final class IdentityController extends ChangeNotifier {
  IdentityController(this._manager) : _snapshot = _manager.snapshot {
    _subscription = _manager.states.listen((snapshot) {
      _snapshot = snapshot;
      notifyListeners();
    });
  }

  final IdentitySessionManager _manager;
  late final StreamSubscription<IdentitySessionSnapshot> _subscription;
  IdentitySessionSnapshot _snapshot;

  IdentitySessionSnapshot get snapshot => _snapshot;

  bool get isBusy =>
      _snapshot.status == IdentitySessionStatus.restoring ||
      _snapshot.status == IdentitySessionStatus.requestingLoginLink ||
      _snapshot.status == IdentitySessionStatus.exchangingLoginLink ||
      _snapshot.status == IdentitySessionStatus.refreshing;

  Future<void> restore() => _manager.restore();

  Future<void> requestLoginLink(String email) async {
    try {
      await _manager.requestLoginLink(email);
    } on ArgumentError {
      _setLocalFailure('Enter a valid email address.');
    } on IdentityTransportException {
      // The manager already published a safe transport message.
    } on IdentityCredentialStoreException catch (error) {
      _setLocalFailure(error.safeMessage);
    }
  }

  Future<void> resendLoginLink() async {
    try {
      await _manager.resendLoginLink();
    } on StateError {
      _setLocalFailure('Enter your email address to request a login link.');
    } on IdentityTransportException {
      // The manager already published a safe transport message.
    } on IdentityCredentialStoreException catch (error) {
      _setLocalFailure(error.safeMessage);
    }
  }

  Future<void> cancelLoginLink() => _manager.cancelLoginLink();

  Future<void> checkLoginLinkNow() => _manager.pollLoginLinkNow();

  void pauseLoginLinkPolling() => _manager.pauseLoginLinkPolling();

  void resumeLoginLinkPolling() => _manager.resumeLoginLinkPolling();

  Future<void> logout() => _manager.logout();

  Future<void> refreshCurrentUser() async {
    try {
      await _manager.refreshCurrentUser();
    } on IdentityTransportException catch (error) {
      _setLocalFailure(error.safeMessage);
    }
  }

  Future<void> loadDeviceSessions() async {
    try {
      await _manager.refreshDeviceSessions();
    } on IdentityTransportException catch (error) {
      _setLocalFailure(error.safeMessage);
    }
  }

  Future<void> revokeDeviceSession(String sessionId) async {
    try {
      await _manager.revokeDeviceSession(sessionId);
    } on IdentityTransportException catch (error) {
      _setLocalFailure(error.safeMessage);
    }
  }

  void _setLocalFailure(String safeMessage) {
    _snapshot = _snapshot.copyWith(
      status: _snapshot.isAuthenticated
          ? IdentitySessionStatus.authenticated
          : IdentitySessionStatus.failure,
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
