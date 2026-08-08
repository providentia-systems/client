import 'dart:async';

import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

/// Owns the authenticated session lifecycle without depending on Flutter,
/// HTTP, secure-storage plugins, or the generated API client.
final class IdentitySessionManager implements SessionAuthorizer {
  factory IdentitySessionManager({
    required IdentityTransportPort transport,
    required SessionCredentialStore credentialStore,
    required DeviceDescriptor device,
    DateTime Function()? clock,
    Duration refreshLeeway = const Duration(minutes: 2),
    Duration logoutTimeout = const Duration(seconds: 5),
  }) => IdentitySessionManager._(
    transport,
    credentialStore,
    device,
    clock ?? DateTime.now,
    refreshLeeway,
    logoutTimeout,
  );

  IdentitySessionManager._(
    this._transport,
    this._credentialStore,
    this._device,
    this._clock,
    this.refreshLeeway,
    this.logoutTimeout,
  ) : _snapshot = const IdentitySessionSnapshot.signedOut() {
    if (refreshLeeway.isNegative) {
      throw ArgumentError.value(
        refreshLeeway,
        'refreshLeeway',
        'must not be negative',
      );
    }
    if (logoutTimeout <= Duration.zero) {
      throw ArgumentError.value(
        logoutTimeout,
        'logoutTimeout',
        'must be positive',
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
  final Duration logoutTimeout;

  IdentitySessionSnapshot _snapshot;
  SessionSecrets? _secrets;
  Future<bool>? _refreshInFlight;
  Future<void>? _restoreInFlight;
  int _lifecycleGeneration = 0;
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
    final restore = _performRestore(_lifecycleGeneration);
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
    final generation = _beginAuthentication();
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
      if (_isCurrent(generation)) {
        _emit(
          IdentitySessionSnapshot(
            status: IdentitySessionStatus.challengeRequested,
            challenge: receipt,
            safeMessage:
                'If the address can receive email, a sign-in link has been sent.',
          ),
        );
      }
      return receipt;
    } on IdentityTransportException catch (error) {
      if (_isCurrent(generation)) {
        _emitFailure(error.safeMessage);
      }
      rethrow;
    }
  }

  Future<void> completeChallenge(PasswordlessProof proof) async {
    _ensureOpen();
    final generation = _beginAuthentication();
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
      await _acceptGrant(grant, generation);
    } on IdentityTransportException catch (error) {
      if (_isCurrent(generation)) {
        _emit(
          _snapshot.copyWith(
            status: error.invalidatesSession
                ? IdentitySessionStatus.expired
                : IdentitySessionStatus.failure,
            safeMessage: error.safeMessage,
          ),
        );
      }
      rethrow;
    } on IdentityCredentialStoreException catch (error) {
      if (_isCurrent(generation)) {
        _emit(
          IdentitySessionSnapshot(
            status: IdentitySessionStatus.expired,
            safeMessage: error.safeMessage,
          ),
        );
      }
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
    final generation = _beginAuthentication();
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
      await _acceptGrant(grant, generation);
    } on IdentityTransportException catch (error) {
      if (_isCurrent(generation)) {
        _emit(
          _snapshot.copyWith(
            status: error.invalidatesSession
                ? IdentitySessionStatus.signedOut
                : IdentitySessionStatus.failure,
            safeMessage: error.safeMessage,
          ),
        );
      }
      rethrow;
    } on IdentityCredentialStoreException catch (error) {
      if (_isCurrent(generation)) {
        _emit(
          IdentitySessionSnapshot(
            status: IdentitySessionStatus.expired,
            safeMessage: error.safeMessage,
          ),
        );
      }
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

  Future<bool> _startRefresh({int? generation}) {
    final existing = _refreshInFlight;
    if (existing != null) {
      return existing;
    }
    final refresh = _performRefresh(generation ?? _lifecycleGeneration);
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<void> logout() async {
    _ensureOpen();
    _invalidateLifecycle();
    final accessToken = _secrets?.accessToken;
    final csrfToken = _secrets?.csrfToken;
    _secrets = null;
    _emit(const IdentitySessionSnapshot.signedOut());
    final credentialClear = _bestEffortClearStore();
    try {
      await _transport
          .logout(accessToken: accessToken, csrfToken: csrfToken)
          .timeout(logoutTimeout);
    } on Exception {
      // The local session is already closed. Remote logout is bounded and
      // best-effort when the session is gone or the network is unavailable.
    } finally {
      await credentialClear;
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
      _invalidateLifecycle();
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
    _invalidateLifecycle();
    _disposed = true;
    _secrets = null;
    await _states.close();
  }

  Future<void> _performRestore(int generation) async {
    if (!_isCurrent(generation)) {
      return;
    }
    _emit(IdentitySessionSnapshot(status: IdentitySessionStatus.restoring));
    if (sessionTransport == ClientSessionTransport.nativeBearer) {
      StoredNativeSession? stored;
      try {
        stored = await _credentialStore.read();
      } on Exception {
        if (!_isCurrent(generation)) {
          return;
        }
        await _bestEffortClearStore();
        if (!_isCurrent(generation)) {
          return;
        }
        _emit(
          IdentitySessionSnapshot(
            status: IdentitySessionStatus.failure,
            safeMessage:
                'Secure session storage could not be opened. Sign in again.',
          ),
        );
        return;
      }
      if (!_isCurrent(generation)) {
        return;
      }
      if (stored == null) {
        _emit(const IdentitySessionSnapshot.signedOut());
        return;
      }
      _secrets = SessionSecrets(refreshToken: stored.refreshToken);
    }
    if (!_isCurrent(generation)) {
      return;
    }
    final recovered = await _startRefresh(generation: generation);
    if (!recovered &&
        _isCurrent(generation) &&
        _snapshot.status == IdentitySessionStatus.restoring) {
      _emit(const IdentitySessionSnapshot.signedOut());
    }
  }

  Future<bool> _performRefresh(int generation) async {
    if (!_isCurrent(generation)) {
      return false;
    }
    final refreshToken = sessionTransport == ClientSessionTransport.nativeBearer
        ? _secrets?.refreshToken
        : null;
    if (sessionTransport == ClientSessionTransport.nativeBearer &&
        (refreshToken == null || refreshToken.trim().isEmpty)) {
      await _clearSession();
      if (!_isCurrent(generation)) {
        return false;
      }
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
      final accepted = await _acceptGrant(grant, generation);
      return accepted;
    } on IdentityTransportException catch (error) {
      if (!_isCurrent(generation)) {
        return false;
      }
      if (error.invalidatesSession) {
        await _clearSession();
        if (!_isCurrent(generation)) {
          return false;
        }
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
      if (_isCurrent(generation)) {
        _emit(
          IdentitySessionSnapshot(
            status: IdentitySessionStatus.expired,
            safeMessage: error.safeMessage,
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _acceptGrant(SessionGrant grant, int generation) async {
    if (!_isCurrent(generation)) {
      await _discardGrant(grant);
      return false;
    }
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
        if (!_isCurrent(generation)) {
          await _discardGrant(grant);
          return false;
        }
        await _bestEffortClearStore();
        _secrets = null;
        throw const IdentityCredentialStoreException(
          'The rotated session could not be secured. Sign in again.',
        );
      }
    } else {
      await _bestEffortClearStore();
    }
    if (!_isCurrent(generation)) {
      await _bestEffortClearStore();
      await _discardGrant(grant);
      return false;
    }
    _secrets = grant.secrets;
    _emit(
      IdentitySessionSnapshot(
        status: IdentitySessionStatus.authenticated,
        session: grant.metadata,
      ),
    );
    return true;
  }

  Future<void> _discardGrant(SessionGrant grant) async {
    try {
      await _transport
          .logout(
            accessToken: grant.secrets.accessToken,
            csrfToken: grant.secrets.csrfToken,
          )
          .timeout(logoutTimeout);
    } on Exception {
      // A stale grant can no longer change local authentication state. Remote
      // revocation is bounded and best-effort for the same reason as logout.
    }
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

  int _beginAuthentication() {
    _invalidateLifecycle();
    return _lifecycleGeneration;
  }

  void _invalidateLifecycle() {
    _lifecycleGeneration++;
    _refreshInFlight = null;
    _restoreInFlight = null;
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _lifecycleGeneration;

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
