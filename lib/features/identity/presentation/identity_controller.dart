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
      _snapshot.status == IdentitySessionStatus.authenticating ||
      _snapshot.status == IdentitySessionStatus.refreshing;

  bool get supportsLegacyPassword => _manager.supportsLegacyPassword;

  Future<void> restore() => _manager.restore();

  Future<void> requestSignInLink(String email) async {
    try {
      await _manager.requestChallenge(email);
    } on ArgumentError {
      _setLocalFailure('Enter a valid email address.');
    } on IdentityTransportException {
      // The manager already published the transport's safe message.
    }
  }

  Future<void> submitCode(String code) async {
    final challenge = _snapshot.challenge;
    if (challenge == null) {
      _setLocalFailure('Request a new sign-in link first.');
      return;
    }
    try {
      await _manager.completeChallenge(
        PasswordlessProof.oneTimeCode(
          email: challenge.email,
          code: code,
          challengeId: challenge.challengeId,
        ),
      );
    } on ArgumentError {
      _setLocalFailure('Enter the complete one-time code.');
    } on IdentityTransportException {
      // The manager already published the transport's safe message.
    }
  }

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      await _manager.signInWithPassword(email: email, password: password);
    } on ArgumentError {
      _setLocalFailure('Enter a valid email address and password.');
    } on UnsupportedError {
      _setLocalFailure('Password sign-in is not available.');
    } on IdentityTransportException {
      // The manager already published the transport's safe message.
    } on IdentityCredentialStoreException catch (error) {
      _setLocalFailure(error.safeMessage);
    }
  }

  Future<void> completeMagicLink(String token) async {
    try {
      await _manager.completeChallenge(
        PasswordlessProof.magicLink(token: token),
      );
    } on ArgumentError {
      _setLocalFailure('This sign-in link is incomplete. Request a new link.');
    } on IdentityTransportException {
      // The manager already published the transport's safe message.
    }
  }

  Future<void> logout() => _manager.logout();

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

  void useAnotherEmail() => _manager.clearChallenge();

  void _setLocalFailure(String safeMessage) {
    _snapshot = _snapshot.copyWith(
      status: IdentitySessionStatus.failure,
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
