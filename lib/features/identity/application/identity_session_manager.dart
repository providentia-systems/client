import 'dart:async';

import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

/// Owns the authenticated session lifecycle without depending on Flutter,
/// HTTP, secure-storage plugins, or the generated API client.
final class IdentitySessionManager implements SessionAuthorizer {
  IdentitySessionManager({
    required IdentityTransportPort transport,
    required SessionCredentialStore credentialStore,
    required DeviceDescriptor device,
    DateTime Function()? clock,
    this.refreshLeeway = const Duration(minutes: 2),
  }) : _transport = transport,
       _credentialStore = credentialStore,
       _device = device,
       _clock = clock ?? DateTime.now,
       _snapshot = const IdentitySessionSnapshot.signedOut() {
    if (refreshLeeway.isNegative) {
      throw ArgumentError.value(
        refreshLeeway,
        'refreshLeeway',
        'must not be negative',
      );
    }
    if (_transport.sessionTransport == ClientSessionTransport.nativeBearer &&
        !_credentialStore.supportsPersistentSecrets) {
      throw ArgumentError(
        'Native bearer sessions require a secure persistent credential store.',
      );
    }
  }

  final IdentityTransportPort _transport;
  final SessionCredentialStore _credentialStore;
  final DeviceDescriptor _device;
  final DateTime Function() _clock;
  final StreamController<IdentitySessionSnapshot> _states =
      StreamController<IdentitySessionSnapshot>.broadcast(sync: true);

  final Duration refreshLeeway;

  IdentitySessionSnapshot _snapshot;
  SessionSecrets? _secrets;
  Future<bool>? _refreshInFlight;
  Future<void>? _restoreInFlight;
  bool _disposed = false;

  IdentitySessionSnapshot get snapshot => _snapshot;

  Stream<IdentitySessionSnapshot> get states => _states.stream;

  @override
  String? get accessToken => _secrets?.accessToken;

  @override
  String? get csrfToken => _secrets?.csrfToken;

  @override
  ClientSessionTransport get sessionTransport => _transport.sessionTransport;

  bool get supportsLegacyPassword =>
      _transport is LegacyPasswordIdentityTransportPort;

  Future<void> restore() {
    _ensureOpen();
    final existing = _restoreInFlight;
    if (existing != null) {
      return existing;
    }
    final restore = _performRestore();
    _restoreInFlight = restore;
    return restore.whenComplete(() {
      if (identical(_restoreInFlight, restore)) {
        _restoreInFlight = null;
      }
    });
  }

  Future<PasswordlessChallengeReceipt> requestChallenge(String email) async {
    _ensureOpen();
    final normalizedEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
      throw ArgumentError.value(email, 'email', 'must be a valid email');
    }
    _emit(
      IdentitySessionSnapshot(
        status: IdentitySessionStatus.authenticating,
        session: _snapshot.session,
      ),
    );
    try {
      final receipt = await _transport.requestPasswordlessChallenge(
        email: normalizedEmail,
      );
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.challengeRequested,
          challenge: receipt,
          safeMessage:
              'If the address can receive email, a sign-in link has been sent.',
        ),
      );
      return receipt;
    } on IdentityTransportException catch (error) {
      _emitFailure(error.safeMessage);
      rethrow;
    }
  }

  Future<void> completeChallenge(PasswordlessProof proof) async {
    _ensureOpen();
    _emit(
      _snapshot.copyWith(
        status: IdentitySessionStatus.authenticating,
        clearMessage: true,
      ),
    );
    try {
      final grant = await _transport.completePasswordlessChallenge(
        proof: proof,
        device: _device,
      );
      await _acceptGrant(grant);
    } on IdentityTransportException catch (error) {
      _emit(
        _snapshot.copyWith(
          status: error.invalidatesSession
              ? IdentitySessionStatus.expired
              : IdentitySessionStatus.failure,
          safeMessage: error.safeMessage,
        ),
      );
      rethrow;
    } on IdentityCredentialStoreException catch (error) {
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.expired,
          safeMessage: error.safeMessage,
        ),
      );
      rethrow;
    }
  }

  /// Compatibility sign-in for OpenAPI 1.7. Passwordless remains the product
  /// default, while this path keeps the currently deployed contract usable.
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    _ensureOpen();
    final legacyTransport = _transport;
    if (legacyTransport is! LegacyPasswordIdentityTransportPort) {
      throw UnsupportedError('Password sign-in is not available.');
    }
    final passwordTransport =
        legacyTransport as LegacyPasswordIdentityTransportPort;
    final normalizedEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail) ||
        password.isEmpty) {
      throw ArgumentError('A valid email and password are required.');
    }
    _emit(
      _snapshot.copyWith(
        status: IdentitySessionStatus.authenticating,
        clearMessage: true,
      ),
    );
    try {
      final grant = await passwordTransport.loginWithPassword(
        email: normalizedEmail,
        password: password,
        device: _device,
      );
      await _acceptGrant(grant);
    } on IdentityTransportException catch (error) {
      _emit(
        _snapshot.copyWith(
          status: error.invalidatesSession
              ? IdentitySessionStatus.signedOut
              : IdentitySessionStatus.failure,
          safeMessage: error.safeMessage,
        ),
      );
      rethrow;
    } on IdentityCredentialStoreException catch (error) {
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.expired,
          safeMessage: error.safeMessage,
        ),
      );
      rethrow;
    }
  }

  @override
  Future<bool> ensureFresh() async {
    _ensureOpen();
    final session = _snapshot.session;
    if (session != null &&
        session.accessExpiresAt.isAfter(_clock().toUtc().add(refreshLeeway))) {
      return true;
    }
    return tryRecover();
  }

  /// Single-flight recovery suitable for synchronization and other adapters.
  Future<bool> tryRecover() {
    _ensureOpen();
    final restore = _restoreInFlight;
    if (restore != null &&
        _snapshot.status == IdentitySessionStatus.restoring) {
      return restore.then((_) => _snapshot.isAuthenticated);
    }
    return _startRefresh();
  }

  Future<bool> _startRefresh() {
    final existing = _refreshInFlight;
    if (existing != null) {
      return existing;
    }
    final refresh = _performRefresh();
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<void> logout() async {
    _ensureOpen();
    try {
      await _transport.logout(
        accessToken: _secrets?.accessToken,
        csrfToken: _secrets?.csrfToken,
      );
    } on IdentityTransportException {
      // Local credential removal is mandatory even if the remote session is
      // already gone or the network is unavailable.
    } finally {
      await _clearSession();
      _emit(const IdentitySessionSnapshot.signedOut());
    }
  }

  Future<List<DeviceSessionView>> refreshDeviceSessions() async {
    _ensureAuthenticated();
    if (!await ensureFresh()) {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.authentication,
        safeMessage: 'Please sign in again to manage your sessions.',
      );
    }
    final sessions = await _transport.listDeviceSessions(
      accessToken: _secrets?.accessToken,
      csrfToken: _secrets?.csrfToken,
    );
    _emit(_snapshot.copyWith(deviceSessions: sessions, clearMessage: true));
    return sessions;
  }

  Future<void> revokeDeviceSession(String sessionId) async {
    _ensureAuthenticated();
    if (!await ensureFresh()) {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.authentication,
        safeMessage: 'Please sign in again to manage your sessions.',
      );
    }
    await _transport.revokeDeviceSession(
      sessionId: sessionId,
      accessToken: _secrets?.accessToken,
      csrfToken: _secrets?.csrfToken,
    );
    if (_snapshot.session?.sessionId == sessionId) {
      await _clearSession();
      _emit(const IdentitySessionSnapshot.signedOut());
      return;
    }
    await refreshDeviceSessions();
  }

  void updateActiveHome(String? homeId) {
    _ensureOpen();
    final session = _snapshot.session;
    if (session == null) {
      return;
    }
    _emit(
      _snapshot.copyWith(
        session: session.copyWith(
          activeHomeId: homeId,
          clearActiveHome: homeId == null,
        ),
      ),
    );
  }

  void clearChallenge() {
    _ensureOpen();
    if (_snapshot.status == IdentitySessionStatus.challengeRequested ||
        _snapshot.status == IdentitySessionStatus.failure) {
      _emit(const IdentitySessionSnapshot.signedOut());
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _states.close();
  }

  Future<void> _performRestore() async {
    _emit(IdentitySessionSnapshot(status: IdentitySessionStatus.restoring));
    if (sessionTransport == ClientSessionTransport.nativeBearer) {
      StoredNativeSession? stored;
      try {
        stored = await _credentialStore.read();
      } on Exception {
        await _bestEffortClearStore();
        _emit(
          IdentitySessionSnapshot(
            status: IdentitySessionStatus.failure,
            safeMessage:
                'Secure session storage could not be opened. Sign in again.',
          ),
        );
        return;
      }
      if (stored == null) {
        _emit(const IdentitySessionSnapshot.signedOut());
        return;
      }
      _secrets = SessionSecrets(refreshToken: stored.refreshToken);
    }
    final recovered = await _startRefresh();
    if (!recovered && _snapshot.status == IdentitySessionStatus.restoring) {
      _emit(const IdentitySessionSnapshot.signedOut());
    }
  }

  Future<bool> _performRefresh() async {
    final refreshToken = sessionTransport == ClientSessionTransport.nativeBearer
        ? _secrets?.refreshToken
        : null;
    if (sessionTransport == ClientSessionTransport.nativeBearer &&
        (refreshToken == null || refreshToken.trim().isEmpty)) {
      await _clearSession();
      _emit(IdentitySessionSnapshot(status: IdentitySessionStatus.expired));
      return false;
    }

    _emit(
      _snapshot.copyWith(
        status: IdentitySessionStatus.refreshing,
        clearMessage: true,
      ),
    );
    try {
      final grant = await _transport.refreshSession(refreshToken: refreshToken);
      await _acceptGrant(grant);
      return true;
    } on IdentityTransportException catch (error) {
      if (error.invalidatesSession) {
        await _clearSession();
        _emit(
          IdentitySessionSnapshot(
            status: IdentitySessionStatus.expired,
            safeMessage: error.safeMessage,
          ),
        );
      } else {
        _emit(
          _snapshot.copyWith(
            status: IdentitySessionStatus.failure,
            safeMessage: error.safeMessage,
          ),
        );
      }
      return false;
    } on IdentityCredentialStoreException catch (error) {
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.expired,
          safeMessage: error.safeMessage,
        ),
      );
      return false;
    }
  }

  Future<void> _acceptGrant(SessionGrant grant) async {
    if (grant.metadata.transport != sessionTransport) {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.authentication,
        safeMessage: 'The returned session transport was not accepted.',
      );
    }
    if (sessionTransport == ClientSessionTransport.nativeBearer) {
      final refreshToken = grant.secrets.refreshToken!;
      try {
        await _credentialStore.write(
          StoredNativeSession(
            sessionId: grant.metadata.sessionId,
            deviceId: grant.metadata.deviceId,
            refreshToken: refreshToken,
          ),
        );
      } on Exception {
        await _bestEffortClearStore();
        _secrets = null;
        throw const IdentityCredentialStoreException(
          'The rotated session could not be secured. Sign in again.',
        );
      }
    } else {
      await _bestEffortClearStore();
    }
    _secrets = grant.secrets;
    _emit(
      IdentitySessionSnapshot(
        status: IdentitySessionStatus.authenticated,
        session: grant.metadata,
      ),
    );
  }

  Future<void> _clearSession() async {
    _secrets = null;
    await _bestEffortClearStore();
  }

  Future<void> _bestEffortClearStore() async {
    try {
      await _credentialStore.clear();
    } on Exception {
      // The in-memory secret is still discarded. Platform implementations
      // should surface secure-store telemetry without logging values.
    }
  }

  void _emitFailure(String safeMessage) {
    _emit(
      IdentitySessionSnapshot(
        status: IdentitySessionStatus.failure,
        safeMessage: safeMessage,
      ),
    );
  }

  void _emit(IdentitySessionSnapshot snapshot) {
    if (_disposed) {
      return;
    }
    _snapshot = snapshot;
    _states.add(snapshot);
  }

  void _ensureAuthenticated() {
    if (!_snapshot.isAuthenticated || _snapshot.session == null) {
      throw StateError('An authenticated session is required.');
    }
  }

  void _ensureOpen() {
    if (_disposed) {
      throw StateError('IdentitySessionManager has been disposed.');
    }
  }
}
