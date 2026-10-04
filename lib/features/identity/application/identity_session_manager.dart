import 'dart:async';

import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/application/offline_session_store.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

/// Owns the origin-bound email-code verification and authenticated session.
final class IdentitySessionManager implements SessionAuthorizer {
  factory IdentitySessionManager({
    required IdentityTransportPort transport,
    required SessionCredentialStore credentialStore,
    required PendingEmailCodeStore pendingEmailCodeStore,
    required DeviceDescriptor device,
    SessionCoordinationPort sessionCoordination =
        const LocalSessionCoordination(),
    DateTime Function()? clock,
    Duration refreshLeeway = const Duration(minutes: 2),
    Duration logoutTimeout = const Duration(seconds: 15),
    Duration requestTimeout = const Duration(seconds: 15),
    int? requestedSessionIdleSeconds,
    OfflineSessionStore? offlineSessionStore,
    Duration offlineAccessWindow = const Duration(hours: 24),
  }) => IdentitySessionManager._(
    transport,
    credentialStore,
    pendingEmailCodeStore,
    device,
    sessionCoordination,
    clock ?? DateTime.now,
    refreshLeeway,
    logoutTimeout,
    requestTimeout,
    requestedSessionIdleSeconds,
    offlineSessionStore,
    offlineAccessWindow,
  );

  IdentitySessionManager._(
    this._transport,
    this._credentialStore,
    this._pendingEmailCodeStore,
    this._device,
    this._sessionCoordination,
    this._clock,
    this.refreshLeeway,
    this.logoutTimeout,
    this.requestTimeout,
    this.requestedSessionIdleSeconds,
    this._offlineSessionStore,
    this.offlineAccessWindow,
  ) : _snapshot = const IdentitySessionSnapshot.signedOut() {
    if (offlineAccessWindow <= Duration.zero ||
        offlineAccessWindow > const Duration(hours: 24)) {
      throw ArgumentError.value(offlineAccessWindow, 'offlineAccessWindow');
    }
    if (refreshLeeway.isNegative) {
      throw ArgumentError.value(refreshLeeway, 'refreshLeeway');
    }
    if (logoutTimeout <= Duration.zero || requestTimeout <= Duration.zero) {
      throw ArgumentError('Identity lifecycle durations are invalid.');
    }
    if (_transport.sessionTransport == ClientSessionTransport.nativeBearer &&
        !_credentialStore.supportsPersistentSecrets) {
      throw ArgumentError(
        'Native bearer sessions require a secure persistent credential store.',
      );
    }
    if (_transport case final AbortBoundIdentityTransportPort bounded
        when requestTimeout <
                bounded.networkTimeout + const Duration(seconds: 1) ||
            logoutTimeout <
                bounded.networkTimeout + const Duration(seconds: 1)) {
      throw ArgumentError(
        'Application timeouts must exceed the transport abort timeout.',
      );
    }
    _coordinationSubscription = _sessionCoordination.updates.listen(
      _handleCoordinatedSessionUpdate,
    );
  }

  static final Object _cookieLockZoneKey = Object();
  static final Object _mutationZoneKey = Object();

  final IdentityTransportPort _transport;
  final SessionCredentialStore _credentialStore;
  final PendingEmailCodeStore _pendingEmailCodeStore;
  final DeviceDescriptor _device;
  final SessionCoordinationPort _sessionCoordination;
  final DateTime Function() _clock;
  final StreamController<IdentitySessionSnapshot> _states =
      StreamController<IdentitySessionSnapshot>.broadcast(sync: true);
  late final StreamSubscription<CoordinatedSessionUpdate>
  _coordinationSubscription;

  final Duration refreshLeeway;
  final Duration logoutTimeout;
  final Duration requestTimeout;
  final int? requestedSessionIdleSeconds;
  final OfflineSessionStore? _offlineSessionStore;
  final Duration offlineAccessWindow;
  OfflineSessionLease? _offlineLease;
  Timer? _offlineExpiryTimer;
  Timer? _offlineObservationTimer;
  Stopwatch? _offlineElapsed;
  DateTime? _offlineStartedAt;
  Future<void>? _offlineObservation;

  IdentitySessionSnapshot _snapshot;
  PendingEmailCode? _pendingEmailCode;
  SessionSecrets? _secrets;
  Future<void> _mutationTail = Future<void>.value();
  Future<void> _pendingStoreTail = Future<void>.value();
  Future<void> _credentialStoreTail = Future<void>.value();
  Future<bool>? _refreshInFlight;
  SessionGrant? _coordinatedRefreshGrant;
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

  Future<void> restore() {
    _ensureOpen();
    final existing = _restoreInFlight;
    if (existing != null) {
      return existing;
    }
    final generation = _lifecycleGeneration;
    final restore = _serializeMutation<void>(() => _performRestore(generation));
    _restoreInFlight = restore;
    return restore.whenComplete(() {
      if (identical(_restoreInFlight, restore)) {
        _restoreInFlight = null;
      }
    });
  }

  Future<PendingEmailCode> requestEmailCode(String email) {
    _ensureOpen();
    final normalized = normalizedEmail(email);
    final generation = _beginAuthentication();
    final previousPending = _pendingEmailCode;
    _pendingEmailCode = null;
    _secrets = null;
    _emit(
      IdentitySessionSnapshot(
        status: IdentitySessionStatus.requestingEmailCode,
        loginEmail: normalized,
      ),
    );
    return _serializeMutation<PendingEmailCode>(() async {
      await _clearPendingStore(request: previousPending);
      if (!await _retirePreviousSessionForLoginIntent(generation)) {
        throw const IdentityCredentialStoreException(
          'Secure session storage is unavailable.',
        );
      }
      PendingEmailCode? issued;
      try {
        final pending = await _transport
            .requestEmailCode(email: normalized, device: _device)
            .timeout(requestTimeout);
        issued = pending;
        if (!_isCurrent(generation)) {
          throw StateError('Superseded login request.');
        }
        await _withCookieMutationLock<void>(() async {
          if (!_isCurrent(generation)) return;
          await _pendingStore<void>(
            () => _pendingEmailCodeStore.write(pending, activate: true),
          );
          if (!_isCurrent(generation)) {
            await _pendingEmailCodeStore.clear(request: pending);
            return;
          }
          _pendingEmailCode = pending;
          _sessionCoordination.publishAuthenticationIntent(pending.requestId);
        });
        if (_isCurrent(generation)) _emitWaiting(pending);
        return pending;
      } on IdentityTransportException catch (error) {
        if (_isCurrent(generation)) _emitFailure(error.safeMessage);
        rethrow;
      } on Object {
        if (issued != null) {
          await _invalidatePendingStore(issued);
        }
        if (_isCurrent(generation)) {
          _emitFailure(
            'The email code could not be requested. Please try again.',
          );
        }
        if (issued != null) {
          throw const IdentityCredentialStoreException(
            'The email code request could not be secured on this device.',
          );
        }
        rethrow;
      }
    });
  }

  Future<void> verifyEmailCode(String code) {
    _ensureOpen();
    final pending = _pendingEmailCode;
    if (!RegExp(r'^[0-9]{8}$').hasMatch(code)) {
      throw const FormatException('Enter the eight-digit email code.');
    }
    if (pending == null) return Future<void>.value();
    final generation = _lifecycleGeneration;
    return _serializeMutation<void>(
      () => _withCookieMutationLock<void>(() async {
        if (_isCurrent(generation)) {
          await _verifyEmailCodeInsideLock(pending, generation, code);
        }
      }),
    );
  }

  Future<void> cancelEmailCode() {
    _ensureOpen();
    final pending = _pendingEmailCode;
    _invalidateLifecycle();
    final generation = _lifecycleGeneration;
    _pendingEmailCode = null;
    _emit(const IdentitySessionSnapshot.signedOut());
    return _serializeMutation<void>(
      () => _cancelEmailCode(pending, generation),
    );
  }

  Future<void> resendEmailCode() {
    final email = _pendingEmailCode?.email ?? _snapshot.loginEmail;
    if (email == null) {
      throw StateError('There is no login request to resend.');
    }
    return requestEmailCode(email).then<void>((_) {});
  }

  @override
  Future<bool> ensureFresh() {
    _ensureOpen();
    return _serializeMutation<bool>(_ensureFresh);
  }

  Future<bool> _ensureFresh() async {
    if (_snapshot.isOffline) {
      await checkOfflineAccess();
      return false;
    }
    final session = _snapshot.session;
    final now = _clock().toUtc();
    if (session != null && session.isExpiredAt(now)) {
      await _clearSession();
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.sessionExpired,
          safeMessage: 'Your session expired after inactivity. Sign in again.',
        ),
      );
      return false;
    }
    if (session != null &&
        session.accessExpiresAt.isAfter(now.add(refreshLeeway))) {
      return true;
    }
    return _startRefresh(expectedSession: session);
  }

  Future<bool> tryRecover() {
    _ensureOpen();
    return _serializeMutation<bool>(_forceRecoveryRefresh);
  }

  /// A real 401 is authoritative even when local expiry metadata still says
  /// the access credential is fresh. Rotate exactly once before replaying it.
  Future<bool> _forceRecoveryRefresh() async {
    final session = _snapshot.session;
    final now = _clock().toUtc();
    if (session == null || session.isExpiredAt(now)) {
      await _clearSession();
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.sessionExpired,
          safeMessage: 'Your session expired. Sign in again.',
        ),
      );
      return false;
    }
    return _startRefresh(expectedSession: session);
  }

  /// Serializes a browser state-changing request with every operation that can
  /// rotate or clear origin-global cookies. The callback receives a recovery
  /// function that force-rotates after a real 401 without reacquiring either
  /// the manager mutation queue or the non-reentrant Web Lock.
  Future<bool> coordinateWebStateChangingRequest(
    Future<void> Function(Future<bool> Function() recover) request,
  ) {
    _ensureOpen();
    if (sessionTransport != ClientSessionTransport.webCookie) {
      throw StateError(
        'Browser request coordination requires cookie sessions.',
      );
    }
    return _serializeMutation<bool>(
      () => _withCookieMutationLock<bool>(() async {
        if (!await _reconcileLatestSessionInsideLock()) return false;
        if (!await _ensureFresh()) return false;
        await request(_forceRecoveryRefresh);
        return true;
      }),
    );
  }

  Future<bool> _startRefresh({
    int? generation,
    SessionMetadata? expectedSession,
    StoredNativeSession? expectedStoredSession,
  }) {
    final existing = _refreshInFlight;
    if (existing != null) {
      return existing;
    }
    final refresh = _performRefresh(
      generation ?? _lifecycleGeneration,
      expectedSession: expectedSession,
      expectedStoredSession: expectedStoredSession,
    );
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<CurrentUserView?> refreshCurrentUser() {
    _ensureOpen();
    return _serializeMutation<CurrentUserView?>(_refreshCurrentUser);
  }

  Future<CurrentUserView?> _refreshCurrentUser() async {
    _ensureAuthenticated();
    if (!await _ensureFresh()) {
      return null;
    }
    try {
      final user = await _transport
          .getCurrentUser(
            accessToken: _secrets?.accessToken,
            csrfToken: _secrets?.csrfToken,
          )
          .timeout(requestTimeout);
      _validateCurrentUser(user, _snapshot.session!);
      await _rememberVerifiedIdentity(_snapshot.session!, user);
      _emit(_snapshot.copyWith(currentUser: user, clearMessage: true));
      return user;
    } on TimeoutException {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.network,
        safeMessage: 'Account details did not respond. Try again.',
      );
    } on IdentityTransportException catch (error) {
      if (error.invalidatesSession || !error.retryablePollingFailure) {
        final rejectedSecrets = _secrets;
        await _clearSession();
        await _retireSession(rejectedSecrets, publishSignedOut: true);
        _emit(
          IdentitySessionSnapshot(
            status: IdentitySessionStatus.sessionExpired,
            safeMessage: error.safeMessage,
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> logout() {
    _ensureOpen();
    final pending = _pendingEmailCode;
    final secrets = _secrets;
    final expectedOriginState = _currentOriginStateFingerprint();
    _invalidateLifecycle();
    final generation = _lifecycleGeneration;
    return _serializeMutation<void>(
      () => _performLogout(
        secrets: secrets,
        pending: pending,
        generation: generation,
        expectedOriginState: expectedOriginState,
      ),
    );
  }

  Future<void> _performLogout({
    required SessionSecrets? secrets,
    required PendingEmailCode? pending,
    required int generation,
    required String expectedOriginState,
  }) async {
    var logoutIntentDurable = false;
    try {
      await _pendingStore<void>(_pendingEmailCodeStore.markLogoutIntent);
      logoutIntentDurable = true;
    } on Object {
      // A proven remote logout can still make local sign-out durable.
    }

    final remoteResult = await _bestEffortLogout(
      secrets,
      intentAlreadyMarked: logoutIntentDurable,
      expectedOriginState: expectedOriginState,
      publishSignedOut: true,
    );
    if (remoteResult == _RemoteLogoutResult.superseded) {
      await _withCookieMutationLock<void>(() async {
        await _reconcileLatestSessionInsideLock();
      });
      return;
    }
    if (!logoutIntentDurable &&
        remoteResult == _RemoteLogoutResult.unavailable) {
      if (_isCurrent(generation)) {
        _emit(
          _snapshot.copyWith(
            status: _snapshot.isAuthenticated
                ? IdentitySessionStatus.authenticated
                : IdentitySessionStatus.failure,
            safeMessage:
                'Sign out could not be secured. Check your connection and try again.',
          ),
        );
      }
      return;
    }

    // Only publish signed-out after either the web tombstone or a completed
    // remote response proves that a reload cannot silently restore cookies.
    _pendingEmailCode = null;
    _secrets = null;
    _emit(const IdentitySessionSnapshot.signedOut());

    _offlineExpiryTimer?.cancel();
    _offlineObservationTimer?.cancel();
    _offlineElapsed?.stop();
    _offlineLease = null;
    try {
      await _offlineSessionStore?.clear();
    } on Object {
      // Missing native credentials or the durable logout journal still
      // prevent a leftover lease from independently granting local access.
    }
    var localCredentialCleared = true;
    try {
      await _credentialStoreOperation<void>(_credentialStore.clear);
    } on Object {
      localCredentialCleared = false;
    }
    await _invalidatePendingStore(pending);
    if (sessionTransport == ClientSessionTransport.nativeBearer &&
        localCredentialCleared) {
      try {
        await _pendingStore<void>(_pendingEmailCodeStore.clearLogoutIntent);
      } on Object {
        localCredentialCleared = false;
      }
    }
    if (remoteResult == _RemoteLogoutResult.unavailable &&
        _snapshot.status == IdentitySessionStatus.signedOut &&
        _pendingEmailCode == null) {
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.signedOut,
          safeMessage: sessionTransport == ClientSessionTransport.webCookie
              ? 'Signed out on this screen. Providentia will finish clearing the browser session before restoring it.'
              : 'Signed out on this device. Remote sign-out could not be confirmed.',
        ),
      );
    }
  }

  Future<List<DeviceSessionView>> refreshDeviceSessions() {
    _ensureOpen();
    return _serializeMutation<List<DeviceSessionView>>(_refreshDeviceSessions);
  }

  Future<List<DeviceSessionView>> _refreshDeviceSessions() async {
    _ensureAuthenticated();
    if (!await _ensureFresh()) {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.authentication,
        safeMessage: 'Please sign in again to manage your sessions.',
      );
    }
    late final List<DeviceSessionView> sessions;
    try {
      sessions = await _transport
          .listDeviceSessions(
            accessToken: _secrets?.accessToken,
            csrfToken: _secrets?.csrfToken,
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.network,
        safeMessage: 'Device sessions did not respond. Try again.',
      );
    }
    final active = _snapshot.session!;
    final current = sessions.where((session) => session.current).toList();
    if (current.length != 1 ||
        current.single.id != active.sessionId ||
        current.single.deviceId != active.deviceId ||
        current.single.transport != active.transport) {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.validation,
        safeMessage: 'The server returned an inconsistent device session list.',
      );
    }
    _emit(_snapshot.copyWith(deviceSessions: sessions, clearMessage: true));
    return sessions;
  }

  Future<void> revokeDeviceSession(String sessionId) {
    _ensureOpen();
    return _serializeMutation<void>(() => _revokeDeviceSession(sessionId));
  }

  Future<void> _revokeDeviceSession(String sessionId) async {
    _ensureAuthenticated();
    if (!await _ensureFresh()) {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.authentication,
        safeMessage: 'Please sign in again to manage your sessions.',
      );
    }
    final revokingCurrent = _snapshot.session?.sessionId == sessionId;
    try {
      await _withCookieMutationLock<void>(() async {
        await _transport
            .revokeDeviceSession(
              sessionId: sessionId,
              accessToken: _secrets?.accessToken,
              csrfToken: _secrets?.csrfToken,
            )
            .timeout(requestTimeout);
        if (revokingCurrent &&
            sessionTransport == ClientSessionTransport.webCookie) {
          _publishSignedOutSafely();
        }
      });
    } on TimeoutException {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.network,
        safeMessage: 'Session revocation did not respond. Try again.',
      );
    }
    if (revokingCurrent) {
      _invalidateLifecycle();
      await _clearSession();
      _emit(const IdentitySessionSnapshot.signedOut());
      return;
    }
    await _refreshDeviceSessions();
  }

  void updateActiveHome(String? homeId) {
    _ensureOpen();
    final session = _snapshot.session;
    if (session == null) {
      return;
    }
    final currentUser = _snapshot.currentUser;
    final canMirrorCurrentUser =
        currentUser == null ||
        homeId == null ||
        currentUser.homes.any((home) => home.id == homeId);
    _emit(
      _snapshot.copyWith(
        session: session.copyWith(
          activeHomeId: homeId,
          clearActiveHome: homeId == null,
        ),
        currentUser: canMirrorCurrentUser
            ? currentUser?.withActiveHome(homeId)
            : null,
        clearCurrentUser: !canMirrorCurrentUser,
        deviceSessions: _snapshot.deviceSessions
            .map(
              (deviceSession) => deviceSession.current
                  ? deviceSession.withActiveHome(homeId)
                  : deviceSession,
            )
            .toList(growable: false),
      ),
    );
    final lease = _offlineLease;
    if (lease != null && !_snapshot.isOffline) {
      if (canMirrorCurrentUser &&
          (homeId == null ||
              lease.user.homes.any((home) => home.id == homeId))) {
        _offlineLease = lease.withActiveHome(homeId);
        unawaited(_saveOfflineLease(_offlineLease!));
      } else {
        // Creating/accepting a home can make the current online identity newer
        // than its cached lease. Never fabricate membership or throw from the
        // ordinary home activation path; refresh /me before caching it again.
        unawaited(invalidateOfflineAccess());
      }
    }
    if (!canMirrorCurrentUser) {
      unawaited(refreshCurrentUser().catchError((_) => null));
    }
  }

  /// Runs a server active-home switch without allowing another web tab to
  /// rotate or replace the shared cookie session mid-mutation.
  ///
  /// Freshness is established before acquiring the non-reentrant origin lock;
  /// SessionHttpClient can therefore authorize [mutation] without attempting a
  /// nested refresh. The resulting session mirror is broadcast before release.
  Future<T> coordinateActiveHomeMutation<T>({
    required String? homeId,
    required Future<T> Function() mutation,
  }) {
    _ensureOpen();
    return _serializeMutation<T>(
      () => _coordinateActiveHomeMutation(homeId: homeId, mutation: mutation),
    );
  }

  Future<T> _coordinateActiveHomeMutation<T>({
    required String? homeId,
    required Future<T> Function() mutation,
  }) async {
    if (!await _ensureFresh()) {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.authentication,
        safeMessage: 'Please sign in again before switching homes.',
      );
    }
    final generation = _lifecycleGeneration;
    return _withCookieMutationLock<T>(() async {
      if (!await _reconcileLatestSessionInsideLock()) {
        throw const IdentityTransportException(
          kind: IdentityFailureKind.authentication,
          safeMessage: 'The browser session changed in another tab.',
        );
      }
      if (!_isCurrent(generation) || _snapshot.session == null) {
        throw const IdentityTransportException(
          kind: IdentityFailureKind.authentication,
          safeMessage: 'The session changed before the home could be opened.',
        );
      }
      final result = await mutation().timeout(requestTimeout);
      if (!_isCurrent(generation)) {
        throw const IdentityTransportException(
          kind: IdentityFailureKind.authentication,
          safeMessage: 'The session changed before the home could be opened.',
        );
      }
      updateActiveHome(homeId);
      if (sessionTransport == ClientSessionTransport.webCookie) {
        final session = _snapshot.session;
        final secrets = _secrets;
        if (session == null || secrets?.csrfToken == null) {
          throw const IdentityTransportException(
            kind: IdentityFailureKind.authentication,
            safeMessage: 'The browser session could not be synchronized.',
          );
        }
        try {
          _sessionCoordination.publishGrant(
            SessionGrant(metadata: session, secrets: secrets!),
          );
        } on Object {
          await _bestEffortLogout(
            secrets,
            publishSignedOut: true,
            skipOriginStateCheck: true,
          );
          await _clearSession();
          _emit(
            IdentitySessionSnapshot(
              status: IdentitySessionStatus.sessionExpired,
              safeMessage:
                  'The home change could not be synchronized across browser tabs. Sign in again.',
            ),
          );
          throw const IdentityTransportException(
            kind: IdentityFailureKind.validation,
            safeMessage:
                'The home change could not be synchronized across browser tabs.',
          );
        }
      }
      return result;
    });
  }

  Future<bool> _reconcileLatestSessionInsideLock() async {
    if (sessionTransport != ClientSessionTransport.webCookie) return true;
    final update = await _sessionCoordination.readLatest();
    if (update == null) return true;
    if (update.signedOut) {
      await _bestEffortLogout(_secrets);
      _secrets = null;
      await _bestEffortClearSessionStore();
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.sessionExpired,
          safeMessage: 'The browser session was signed out in another tab.',
        ),
      );
      return false;
    }
    if (update.authenticationIntentId != null) {
      if (_pendingEmailCode?.requestId == update.authenticationIntentId) {
        return false;
      }
      _secrets = null;
      await _bestEffortClearSessionStore();
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.signedOut,
          safeMessage: 'A new login was started in another tab.',
        ),
      );
      return false;
    }
    final grant = update.grant;
    if (grant == null) return true;
    final current = _snapshot.session;
    if (current != null &&
        current.sessionId == grant.metadata.sessionId &&
        current.deviceId == grant.metadata.deviceId &&
        current.installationId == grant.metadata.installationId &&
        current.userId == grant.metadata.userId &&
        current.accessExpiresAt == grant.metadata.accessExpiresAt &&
        current.refreshExpiresAt == grant.metadata.refreshExpiresAt &&
        current.idleExpiresAt == grant.metadata.idleExpiresAt &&
        current.activeHomeId == grant.metadata.activeHomeId &&
        _secrets?.csrfToken == grant.secrets.csrfToken) {
      return true;
    }
    return _acceptGrant(grant, _lifecycleGeneration, publish: false);
  }

  bool _sameCoordinatedUpdate(
    CoordinatedSessionUpdate received,
    CoordinatedSessionUpdate? latest,
  ) {
    if (latest == null || received.signedOut != latest.signedOut) return false;
    if (received.authenticationIntentId != latest.authenticationIntentId ||
        received.grantIntentId != latest.grantIntentId) {
      return false;
    }
    final receivedGrant = received.grant;
    final latestGrant = latest.grant;
    if (receivedGrant == null || latestGrant == null) {
      return receivedGrant == null && latestGrant == null;
    }
    return _grantFingerprint(receivedGrant) == _grantFingerprint(latestGrant);
  }

  String _grantFingerprint(SessionGrant grant) {
    final metadata = grant.metadata;
    return <Object?>[
      metadata.sessionId,
      metadata.deviceId,
      metadata.installationId,
      metadata.userId,
      metadata.accessExpiresAt.microsecondsSinceEpoch,
      metadata.refreshExpiresAt?.microsecondsSinceEpoch,
      metadata.idleExpiresAt?.microsecondsSinceEpoch,
      metadata.activeHomeId,
      grant.secrets.csrfToken,
    ].join('|');
  }

  String _coordinationStateFingerprint(CoordinatedSessionUpdate? update) {
    if (update == null) return 'none';
    if (update.signedOut) return 'signed-out';
    if (update.authenticationIntentId case final intentId?) {
      return 'intent:$intentId';
    }
    if (update.grant case final grant?) {
      return 'grant:${_grantFingerprint(grant)}';
    }
    return 'none';
  }

  String _currentOriginStateFingerprint() {
    if (_pendingEmailCode case final pending?) {
      return 'intent:${pending.requestId}';
    }
    final current = _currentSessionFingerprint();
    return current == null ? 'signed-out' : 'grant:$current';
  }

  String? _currentSessionFingerprint() {
    final metadata = _snapshot.session;
    if (metadata == null) return null;
    return <Object?>[
      metadata.sessionId,
      metadata.deviceId,
      metadata.installationId,
      metadata.userId,
      metadata.accessExpiresAt.microsecondsSinceEpoch,
      metadata.refreshExpiresAt?.microsecondsSinceEpoch,
      metadata.idleExpiresAt?.microsecondsSinceEpoch,
      metadata.activeHomeId,
      _secrets?.csrfToken,
    ].join('|');
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _invalidateLifecycle();
    _offlineExpiryTimer?.cancel();
    _offlineObservationTimer?.cancel();
    _offlineElapsed?.stop();
    _disposed = true;
    _secrets = null;
    await _coordinationSubscription.cancel();
    await _sessionCoordination.dispose();
    await _states.close();
  }

  void _handleCoordinatedSessionUpdate(CoordinatedSessionUpdate update) {
    if (_disposed || sessionTransport != ClientSessionTransport.webCookie) {
      return;
    }
    final authenticationIntentId = update.authenticationIntentId;
    if (authenticationIntentId != null) {
      unawaited(
        _serializeMutation<void>(
          () => _handleCoordinatedAuthenticationIntent(authenticationIntentId),
        ).catchError((_) {}),
      );
      return;
    }
    if (!update.signedOut && update.grant == null) return;
    unawaited(
      _serializeMutation<void>(
        () => _withCookieMutationLock<void>(
          () => _applyCoordinatedSessionUpdate(update),
        ),
      ).catchError((_) {}),
    );
  }

  Future<void> _applyCoordinatedSessionUpdate(
    CoordinatedSessionUpdate update,
  ) async {
    final latest = await _sessionCoordination.readLatest();
    if (!_sameCoordinatedUpdate(update, latest)) return;
    if (update.signedOut) {
      final pending = _pendingEmailCode;
      if (pending != null || !_snapshot.isAuthenticated) return;
      _invalidateLifecycle();
      _coordinatedRefreshGrant = null;
      _pendingEmailCode = null;
      _secrets = null;
      await _bestEffortClearSessionStore();
      _emit(const IdentitySessionSnapshot.signedOut());
      return;
    }
    final grant = update.grant!;
    final localPending = _pendingEmailCode;
    // A grant for this exact durable intent is the sibling tab's successful
    // single-use exchange and must be adopted. Unrelated/older grants cannot
    // erase a newer local login request.
    if (localPending != null &&
        update.grantIntentId != localPending.requestId) {
      return;
    }
    if (localPending == null &&
        (_snapshot.status == IdentitySessionStatus.requestingEmailCode ||
            _snapshot.status == IdentitySessionStatus.waitingForEmailCode ||
            _snapshot.status == IdentitySessionStatus.verifyingEmailCode)) {
      return;
    }
    if (_refreshInFlight != null) {
      // A refresh waiting on the cross-tab lock consumes the same update from
      // the coordinator instead of racing a second local acceptance.
      _coordinatedRefreshGrant = grant;
      return;
    }
    final generation = _beginAuthentication();
    _pendingEmailCode = null;
    _secrets = null;
    _emit(IdentitySessionSnapshot(status: IdentitySessionStatus.restoring));
    try {
      await _clearPendingStore(request: localPending);
      if (_isCurrent(generation)) {
        await _acceptGrant(grant, generation, publish: false);
      }
    } on Object {
      if (_isCurrent(generation)) {
        _emit(
          IdentitySessionSnapshot(
            status: IdentitySessionStatus.sessionExpired,
            safeMessage:
                'The browser session changed in another tab. Sign in again.',
          ),
        );
      }
    }
  }

  Future<void> _handleCoordinatedAuthenticationIntent(String intentId) async {
    await _withCookieMutationLock<void>(() async {
      final latest = await _sessionCoordination.readLatest();
      if (latest?.authenticationIntentId != intentId) return;
      final active = await _pendingStore<PendingEmailCode?>(
        _pendingEmailCodeStore.read,
      );
      // The durable origin head is the total order. Delayed broadcasts cannot
      // supersede a newer request, regardless of wall-clock ties or rollback.
      if (active?.requestId != intentId ||
          _pendingEmailCode?.requestId == intentId) {
        return;
      }
      final superseded = _pendingEmailCode;
      _invalidateLifecycle();
      _coordinatedRefreshGrant = null;
      _pendingEmailCode = null;
      _secrets = null;
      _emit(const IdentitySessionSnapshot.signedOut());
      await _bestEffortClearSessionStore();
      await _replacePendingRequest(superseded);
    });
  }

  Future<void> _cancelEmailCode(
    PendingEmailCode? pending,
    int generation,
  ) async {
    try {
      if (pending != null) {
        await _pendingStore<void>(
          () => _pendingEmailCodeStore.invalidate(pending),
        );
      }
      if (pending != null) await _clearPendingStore(request: pending);
    } on Object {
      if (_isCurrent(generation)) {
        _emitFailure(
          'The saved code request could not be removed. It will expire automatically.',
        );
      }
    }
  }

  Future<void> _verifyEmailCodeInsideLock(
    PendingEmailCode pending,
    int generation,
    String code,
  ) async {
    if (pending.isExpiredAt(_clock())) {
      await _invalidatePendingStore(pending);
      _pendingEmailCode = null;
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.emailCodeExpired,
          loginEmail: pending.email,
          safeMessage: 'This email code expired. Request a new code.',
        ),
      );
      return;
    }
    _emit(
      IdentitySessionSnapshot(
        status: IdentitySessionStatus.verifyingEmailCode,
        loginEmail: pending.email,
        safeMessage: 'Verifying your email code.',
      ),
    );
    BrowserCookieMutationJournal? cookieMutation;
    var credentialIssued = false;
    try {
      if (sessionTransport == ClientSessionTransport.webCookie) {
        if (await _resumeUnfinishedBrowserCookieMutation(generation)) return;
        final active = await _pendingStore<PendingEmailCode?>(
          _pendingEmailCodeStore.read,
        );
        if (active?.requestId != pending.requestId) {
          _pendingEmailCode = null;
          _emit(
            IdentitySessionSnapshot(status: IdentitySessionStatus.restoring),
          );
          unawaited(
            _serializeMutation<void>(
              () => _performRestore(generation),
            ).catchError((_) {}),
          );
          return;
        }
        cookieMutation = await _beginBrowserCookieMutation(
          BrowserCookieMutationKind.emailCodeVerification,
          pending.requestId,
        );
      }
      final grant = await _transport
          .verifyEmailCode(request: pending, code: code)
          .timeout(requestTimeout);
      credentialIssued = true;
      if (!_isCurrent(generation)) {
        await _discardGrant(grant);
        return;
      }
      if (sessionTransport == ClientSessionTransport.webCookie) {
        try {
          // The single-use proof must become durably terminal before the
          // origin lock releases or a sibling tab could exchange it again and
          // clean up the first tab's newly issued cookie session.
          await _pendingStore<void>(
            () => _pendingEmailCodeStore.clear(request: pending),
          );
        } on Object {
          await _discardGrant(grant);
          if (_isCurrent(generation)) {
            _pendingEmailCode = null;
            _emit(
              IdentitySessionSnapshot(
                status: IdentitySessionStatus.failure,
                loginEmail: pending.email,
                safeMessage:
                    'Sign in completed remotely but could not be secured on this browser. Request a new email code.',
              ),
            );
          }
          return;
        }
      } else {
        await _clearPendingStore(request: pending);
      }
      _pendingEmailCode = null;
      await _acceptGrant(
        grant,
        generation,
        coordinatedIntentId: pending.requestId,
        cookieMutation: cookieMutation,
      );
    } on TimeoutException {
      await _failAmbiguousExchange(
        pending,
        generation,
        cookieMutation: cookieMutation,
      );
    } on IdentityTransportException catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }
      if (!credentialIssued &&
          (error.kind == IdentityFailureKind.rateLimited ||
              error.kind == IdentityFailureKind.validation)) {
        await _clearBrowserCookieMutation(cookieMutation);
        _emitWaiting(pending, message: error.safeMessage);
        return;
      }
      await _failAmbiguousExchange(
        pending,
        generation,
        cookieMutation: cookieMutation,
        safeMessage:
            error.kind == IdentityFailureKind.network ||
                error.kind == IdentityFailureKind.unavailable
            ? null
            : error.safeMessage,
      );
    } on Object {
      await _failAmbiguousExchange(
        pending,
        generation,
        cookieMutation: cookieMutation,
      );
    }
  }

  Future<void> _failAmbiguousExchange(
    PendingEmailCode pending,
    int generation, {
    BrowserCookieMutationJournal? cookieMutation,
    String? safeMessage,
  }) async {
    // A browser response can be lost or fail validation after Set-Cookie was
    // committed. Logout clears those origin cookies on every backend response.
    if (sessionTransport == ClientSessionTransport.webCookie) {
      final result = await _bestEffortLogout(
        null,
        intentAlreadyMarked: cookieMutation != null,
        publishSignedOut: true,
        skipOriginStateCheck: cookieMutation != null,
      );
      if (result == _RemoteLogoutResult.settled) {
        await _clearBrowserCookieMutation(cookieMutation);
      }
    }
    await _clearPendingStore(request: pending);
    if (!_isCurrent(generation)) {
      return;
    }
    _pendingEmailCode = null;
    _emit(
      IdentitySessionSnapshot(
        status: IdentitySessionStatus.failure,
        loginEmail: pending.email,
        safeMessage:
            safeMessage ??
            'Sign in could not be confirmed safely. Request a new email code.',
      ),
    );
  }

  Future<void> _performRestore(int generation) async {
    if (!_isCurrent(generation)) {
      return;
    }
    _emit(IdentitySessionSnapshot(status: IdentitySessionStatus.restoring));
    if (await _resumeUnfinishedBrowserCookieMutation(generation)) {
      return;
    }
    if (await _resumeLogoutIntent(generation)) {
      return;
    }
    if (await _restorePendingRequest(generation)) {
      return;
    }
    if (!_isCurrent(generation)) {
      return;
    }
    var hasSavedSession = sessionTransport == ClientSessionTransport.webCookie;
    StoredNativeSession? stored;
    if (sessionTransport == ClientSessionTransport.nativeBearer) {
      try {
        stored = await _credentialStoreOperation<StoredNativeSession?>(
          _credentialStore.read,
        );
        if (!_isCurrent(generation)) {
          if (stored != null) {
            await _retireSession(
              SessionSecrets(refreshToken: stored.refreshToken),
            );
          }
          return;
        }
        if (stored != null) {
          if (stored.installationId != _device.id) {
            await _retireSession(
              SessionSecrets(refreshToken: stored.refreshToken),
            );
            if (_isCurrent(generation)) {
              _emit(
                IdentitySessionSnapshot(
                  status: IdentitySessionStatus.sessionExpired,
                  safeMessage:
                      'The saved session belonged to a different installation.',
                ),
              );
            }
            return;
          }
          hasSavedSession = true;
          _secrets = SessionSecrets(refreshToken: stored.refreshToken);
        }
      } on Object {
        await _bestEffortClearSessionStore();
      }
    }

    if (hasSavedSession &&
        await _startRefresh(
          generation: generation,
          expectedStoredSession: stored,
        )) {
      return;
    }
    if (!_isCurrent(generation)) {
      return;
    }
    if (_snapshot.status == IdentitySessionStatus.restoring) {
      _emit(const IdentitySessionSnapshot.signedOut());
    }
  }

  Future<bool> _restorePendingRequest(int generation) async {
    PendingEmailCode? pending;
    try {
      pending = await _pendingStore<PendingEmailCode?>(
        _pendingEmailCodeStore.read,
      );
    } on Object {
      await _retirePreviousSessionForLoginIntent(generation);
      if (_isCurrent(generation)) {
        _emitFailure(
          'The saved login request was invalid. Request a new code.',
        );
      }
      return true;
    }
    if (!_isCurrent(generation)) {
      return true;
    }
    if (pending == null) {
      return false;
    }
    if (!await _retirePreviousSessionForLoginIntent(
      generation,
      authenticationIntentId: pending.requestId,
    )) {
      return true;
    }
    if (!_isCurrent(generation)) return true;
    _pendingEmailCode = pending;
    _emitWaiting(
      pending,
      message:
          'Enter the code from your email, or request a new one if it expired.',
    );
    return true;
  }

  Future<bool> _retirePreviousSessionForLoginIntent(
    int generation, {
    String? authenticationIntentId,
  }) async {
    if (sessionTransport == ClientSessionTransport.webCookie) {
      final result = await _bestEffortLogout(
        null,
        publishSignedOut: authenticationIntentId == null,
        publishAuthenticationIntentId: authenticationIntentId,
      );
      if (result != _RemoteLogoutResult.settled) {
        if (result == _RemoteLogoutResult.superseded) return false;
        if (_isCurrent(generation)) {
          _emit(
            IdentitySessionSnapshot(
              status: IdentitySessionStatus.signedOut,
              safeMessage:
                  'Reconnect to finish protecting this login request from the previous browser session.',
            ),
          );
        }
        return false;
      }
      return true;
    }

    try {
      await _pendingStore<void>(_pendingEmailCodeStore.markLogoutIntent);
      final stored = await _credentialStoreOperation<StoredNativeSession?>(
        _credentialStore.read,
      );
      await _credentialStoreOperation<void>(_credentialStore.clear);
      if (stored != null) {
        await _bestEffortLogout(
          SessionSecrets(refreshToken: stored.refreshToken),
          intentAlreadyMarked: true,
        );
      }
      await _pendingStore<void>(_pendingEmailCodeStore.clearLogoutIntent);
      return true;
    } on Object {
      if (_isCurrent(generation)) {
        _emit(
          IdentitySessionSnapshot(
            status: IdentitySessionStatus.signedOut,
            safeMessage:
                'Secure storage must be available before this login request can continue.',
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _performRefresh(
    int generation, {
    SessionMetadata? expectedSession,
    StoredNativeSession? expectedStoredSession,
  }) async {
    if (!_isCurrent(generation)) {
      return false;
    }
    final refreshToken = sessionTransport == ClientSessionTransport.nativeBearer
        ? _secrets?.refreshToken
        : null;
    if (sessionTransport == ClientSessionTransport.nativeBearer &&
        (refreshToken == null || refreshToken.trim().isEmpty)) {
      return false;
    }
    _emit(
      _snapshot.copyWith(
        status: IdentitySessionStatus.refreshing,
        clearMessage: true,
      ),
    );
    BrowserCookieMutationJournal? cookieMutation;
    try {
      return await _withCookieMutationLock<bool>(() async {
        if (!_isCurrent(generation)) return false;
        if (sessionTransport == ClientSessionTransport.webCookie) {
          if (await _resumeUnfinishedBrowserCookieMutation(generation)) {
            return false;
          }
          final before = _currentSessionFingerprint();
          if (!await _reconcileLatestSessionInsideLock()) return false;
          if (_currentSessionFingerprint() != before) return true;
        }
        final coordinated = _coordinatedRefreshGrant;
        if (coordinated != null) {
          _coordinatedRefreshGrant = null;
          return _acceptGrant(coordinated, generation, publish: false);
        }
        cookieMutation = await _beginBrowserCookieMutation(
          BrowserCookieMutationKind.sessionRefresh,
          'refresh:${_snapshot.session?.sessionId ?? 'restore'}:'
          '${_snapshot.session?.accessExpiresAt.microsecondsSinceEpoch ?? generation}',
        );
        final grant = await _transport
            .refreshSession(refreshToken: refreshToken)
            .timeout(requestTimeout);
        try {
          _validateRefreshGrant(
            grant,
            expectedSession: expectedSession,
            expectedStoredSession: expectedStoredSession,
          );
        } on IdentityTransportException {
          await _discardGrant(grant);
          rethrow;
        }
        return await _acceptGrant(
          grant,
          generation,
          cookieMutation: cookieMutation,
        );
      });
    } on TimeoutException {
      if (cookieMutation != null) {
        await _failUnfinishedBrowserCookieMutation(
          cookieMutation!,
          generation,
          'The browser session refresh could not be confirmed safely. Sign in again.',
        );
        return false;
      }
      if (expectedStoredSession != null &&
          await _restoreOffline(expectedStoredSession, generation)) {
        return true;
      }
      if (_isCurrent(generation)) {
        _emitTransientRefreshFailure(
          'The session refresh timed out. Check your connection and try again.',
        );
      }
      return false;
    } on IdentityCredentialStoreException catch (error) {
      if (_isCurrent(generation)) {
        _emit(
          IdentitySessionSnapshot(
            status: IdentitySessionStatus.sessionExpired,
            safeMessage: error.safeMessage,
          ),
        );
      }
      return false;
    } on IdentityTransportException catch (error) {
      if (!_isCurrent(generation)) {
        return false;
      }
      if (cookieMutation != null &&
          error.kind == IdentityFailureKind.rateLimited) {
        await _clearBrowserCookieMutation(cookieMutation);
        cookieMutation = null;
      } else if (cookieMutation != null) {
        await _failUnfinishedBrowserCookieMutation(
          cookieMutation!,
          generation,
          error.safeMessage,
        );
        return false;
      }
      if (error.invalidatesSession || !error.retryablePollingFailure) {
        final rejectedSecrets = _secrets;
        await _clearSession();
        await _bestEffortLogout(rejectedSecrets, publishSignedOut: true);
        if (_isCurrent(generation)) {
          _emit(
            IdentitySessionSnapshot(
              status: IdentitySessionStatus.sessionExpired,
              safeMessage: error.safeMessage,
            ),
          );
        }
      } else {
        if (expectedStoredSession != null &&
            (error.kind == IdentityFailureKind.network ||
                error.kind == IdentityFailureKind.unavailable) &&
            await _restoreOffline(expectedStoredSession, generation)) {
          return true;
        }
        _emitTransientRefreshFailure(error.safeMessage);
      }
      return false;
    } on Object {
      if (cookieMutation != null) {
        await _failUnfinishedBrowserCookieMutation(
          cookieMutation!,
          generation,
          'The browser session refresh could not be confirmed safely. Sign in again.',
        );
        return false;
      }
      if (_isCurrent(generation)) {
        _emitTransientRefreshFailure(
          'The session could not be refreshed. Check your connection and try again.',
        );
      }
      return false;
    }
  }

  void _emitTransientRefreshFailure(String safeMessage) {
    final existingSession = _snapshot.session;
    _emit(
      _snapshot.copyWith(
        status: existingSession == null
            ? IdentitySessionStatus.failure
            : IdentitySessionStatus.authenticated,
        safeMessage: safeMessage,
      ),
    );
  }

  Future<bool> _acceptGrant(
    SessionGrant grant,
    int generation, {
    bool publish = true,
    String? coordinatedIntentId,
    BrowserCookieMutationJournal? cookieMutation,
  }) async {
    if (!_isCurrent(generation)) {
      final result = await _discardGrant(grant);
      if (result == _RemoteLogoutResult.settled) {
        await _clearBrowserCookieMutation(cookieMutation);
      }
      return false;
    }
    if (grant.metadata.installationId != _device.id) {
      final result = await _discardGrant(grant);
      if (result == _RemoteLogoutResult.settled) {
        await _clearBrowserCookieMutation(cookieMutation);
      }
      throw const IdentityTransportException(
        kind: IdentityFailureKind.validation,
        safeMessage: 'The issued session belonged to a different device.',
      );
    }
    if (grant.metadata.transport != sessionTransport) {
      final result = await _discardGrant(grant);
      if (result == _RemoteLogoutResult.settled) {
        await _clearBrowserCookieMutation(cookieMutation);
      }
      throw const IdentityTransportException(
        kind: IdentityFailureKind.authentication,
        safeMessage: 'The returned session transport was not accepted.',
      );
    }
    if (sessionTransport == ClientSessionTransport.nativeBearer) {
      try {
        await _credentialStoreOperation<void>(
          () => _credentialStore.write(
            StoredNativeSession(
              sessionId: grant.metadata.sessionId,
              deviceId: grant.metadata.deviceId,
              installationId: grant.metadata.installationId,
              refreshToken: grant.secrets.refreshToken!,
              userId: grant.metadata.userId,
            ),
          ),
        );
        await _pendingStore<void>(_pendingEmailCodeStore.clearLogoutIntent);
      } on Object {
        await _bestEffortClearSessionStore();
        _secrets = null;
        final result = await _discardGrant(grant);
        if (result == _RemoteLogoutResult.settled) {
          await _clearBrowserCookieMutation(cookieMutation);
        }
        throw const IdentityCredentialStoreException(
          'The rotated session could not be secured. Sign in again.',
        );
      }
    } else {
      await _bestEffortClearSessionStore();
      try {
        await _pendingStore<void>(_pendingEmailCodeStore.clearLogoutIntent);
      } on Object {
        await _discardGrant(grant);
        throw const IdentityCredentialStoreException(
          'The browser session could not be secured. Sign in again.',
        );
      }
    }
    if (!_isCurrent(generation)) {
      await _bestEffortClearSessionStore();
      final result = await _discardGrant(grant);
      if (result == _RemoteLogoutResult.settled) {
        await _clearBrowserCookieMutation(cookieMutation);
      }
      return false;
    }
    _secrets = grant.secrets;
    CurrentUserView? currentUser = _snapshot.currentUser;
    String? bootstrapMessage;
    try {
      currentUser = await _transport
          .getCurrentUser(
            accessToken: _secrets?.accessToken,
            csrfToken: _secrets?.csrfToken,
          )
          .timeout(requestTimeout);
      _validateCurrentUser(currentUser, grant.metadata);
    } on TimeoutException {
      bootstrapMessage =
          'Signed in, but account details timed out. Retry account details.';
    } on IdentityTransportException catch (error) {
      if (error.invalidatesSession || !error.retryablePollingFailure) {
        return _rejectGrant(
          grant,
          generation,
          error.safeMessage,
          cookieMutation: cookieMutation,
        );
      }
      bootstrapMessage =
          'Signed in, but account details could not be refreshed yet.';
    } on Object {
      return _rejectGrant(
        grant,
        generation,
        'The account response was invalid. Sign in again.',
        cookieMutation: cookieMutation,
      );
    }
    if (!_isCurrent(generation)) {
      await _bestEffortClearSessionStore();
      final result = await _discardGrant(grant);
      if (result == _RemoteLogoutResult.settled) {
        await _clearBrowserCookieMutation(cookieMutation);
      }
      return false;
    }
    _offlineExpiryTimer?.cancel();
    _offlineObservationTimer?.cancel();
    _offlineElapsed?.stop();
    _offlineLease = null;
    if (sessionTransport == ClientSessionTransport.nativeBearer &&
        bootstrapMessage == null &&
        currentUser != null) {
      await _rememberVerifiedIdentity(grant.metadata, currentUser);
      if (!_isCurrent(generation)) return false;
    }
    _emit(
      IdentitySessionSnapshot(
        status: IdentitySessionStatus.authenticated,
        session: grant.metadata,
        currentUser: currentUser,
        safeMessage: bootstrapMessage,
      ),
    );
    if (publish && sessionTransport == ClientSessionTransport.webCookie) {
      try {
        _sessionCoordination.publishGrant(grant, intentId: coordinatedIntentId);
        await _clearBrowserCookieMutation(cookieMutation);
      } on Object {
        await _rejectGrant(
          grant,
          generation,
          'The browser session could not be synchronized safely.',
          cookieMutation: cookieMutation,
        );
        throw const IdentityCredentialStoreException(
          'The browser session could not be synchronized safely.',
        );
      }
    }
    return true;
  }

  Future<bool> _rejectGrant(
    SessionGrant grant,
    int generation,
    String safeMessage, {
    BrowserCookieMutationJournal? cookieMutation,
  }) async {
    _secrets = null;
    await _bestEffortClearSessionStore();
    final result = await _discardGrant(grant);
    if (result == _RemoteLogoutResult.settled) {
      await _clearBrowserCookieMutation(cookieMutation);
    }
    if (_isCurrent(generation)) {
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.sessionExpired,
          safeMessage: safeMessage,
        ),
      );
    }
    return false;
  }

  void _validateCurrentUser(CurrentUserView user, SessionMetadata session) {
    if (user.userId != session.userId ||
        !user.currentSession.current ||
        user.currentSession.isRevoked ||
        user.currentSession.id != session.sessionId ||
        user.currentSession.deviceId != session.deviceId ||
        user.currentSession.transport != session.transport ||
        user.activeHomeId != session.activeHomeId ||
        user.currentSession.activeHomeId != session.activeHomeId) {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.validation,
        safeMessage: 'The account session did not match the issued session.',
      );
    }
  }

  void _validateRefreshGrant(
    SessionGrant grant, {
    SessionMetadata? expectedSession,
    StoredNativeSession? expectedStoredSession,
  }) {
    final metadata = grant.metadata;
    if (expectedSession != null &&
        (metadata.sessionId != expectedSession.sessionId ||
            metadata.deviceId != expectedSession.deviceId ||
            metadata.installationId != expectedSession.installationId ||
            metadata.userId != expectedSession.userId ||
            metadata.transport != expectedSession.transport)) {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.validation,
        safeMessage: 'The refreshed session identity changed unexpectedly.',
      );
    }
    if (expectedStoredSession != null &&
        (metadata.sessionId != expectedStoredSession.sessionId ||
            metadata.deviceId != expectedStoredSession.deviceId ||
            metadata.installationId != expectedStoredSession.installationId ||
            (expectedStoredSession.userId != null &&
                metadata.userId != expectedStoredSession.userId))) {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.validation,
        safeMessage: 'The saved session identity changed unexpectedly.',
      );
    }
  }

  Future<_RemoteLogoutResult> _discardGrant(SessionGrant grant) async {
    return _bestEffortLogout(
      grant.secrets,
      publishSignedOut: true,
      skipOriginStateCheck: true,
    );
  }

  void _emitWaiting(PendingEmailCode pending, {String? message}) {
    _pendingEmailCode = pending;
    _emit(
      IdentitySessionSnapshot(
        status: IdentitySessionStatus.waitingForEmailCode,
        pendingEmailCode: pending.toPublicView(),
        loginEmail: pending.email,
        safeMessage:
            message ??
            'If this address can receive email, an eight-digit code has been sent.',
      ),
    );
  }

  Future<void> _replacePendingRequest(PendingEmailCode? pending) async {
    if (pending != null) await _clearPendingStore(request: pending);
  }

  Future<void> _retireSession(
    SessionSecrets? secrets, {
    bool publishSignedOut = false,
  }) async {
    await _bestEffortClearSessionStore();
    if (secrets == null &&
        sessionTransport != ClientSessionTransport.webCookie) {
      return;
    }
    await _bestEffortLogout(secrets, publishSignedOut: publishSignedOut);
  }

  Future<_RemoteLogoutResult> _bestEffortLogout(
    SessionSecrets? secrets, {
    bool intentAlreadyMarked = false,
    String? expectedOriginState,
    bool publishSignedOut = false,
    String? publishAuthenticationIntentId,
    bool skipOriginStateCheck = false,
  }) async {
    var expected = expectedOriginState;
    if (sessionTransport == ClientSessionTransport.webCookie &&
        expected == null) {
      expected = _coordinationStateFingerprint(
        await _sessionCoordination.readLatest(),
      );
    }
    if (sessionTransport == ClientSessionTransport.webCookie &&
        !intentAlreadyMarked) {
      try {
        await _pendingStore<void>(_pendingEmailCodeStore.markLogoutIntent);
      } on Object {
        // Still attempt remote cleanup. A successful response is authoritative.
      }
    }
    var result = _RemoteLogoutResult.unavailable;
    try {
      await _withCookieMutationLock<void>(() async {
        if (sessionTransport == ClientSessionTransport.webCookie &&
            !skipOriginStateCheck) {
          final current = _coordinationStateFingerprint(
            await _sessionCoordination.readLatest(),
          );
          if (current != 'none' && current != expected) {
            result = _RemoteLogoutResult.superseded;
            return;
          }
        }
        try {
          await _transport
              .logout(
                accessToken: secrets?.accessToken,
                refreshToken: secrets?.refreshToken,
                csrfToken: secrets?.csrfToken,
              )
              .timeout(logoutTimeout);
          result = _RemoteLogoutResult.settled;
        } on IdentityTransportException catch (error) {
          result = error.kind == IdentityFailureKind.network
              ? _RemoteLogoutResult.unavailable
              : _RemoteLogoutResult.settled;
        } on Object {
          result = _RemoteLogoutResult.unavailable;
        }
        if (sessionTransport == ClientSessionTransport.webCookie &&
            result != _RemoteLogoutResult.superseded) {
          if (publishAuthenticationIntentId case final intentId?) {
            _sessionCoordination.publishAuthenticationIntent(intentId);
          } else if (publishSignedOut &&
              (result == _RemoteLogoutResult.settled || intentAlreadyMarked)) {
            _sessionCoordination.publishSignedOut();
          }
        }
      });
    } on Object {
      result = _RemoteLogoutResult.unavailable;
    }
    if (sessionTransport == ClientSessionTransport.webCookie &&
        result != _RemoteLogoutResult.unavailable) {
      try {
        await _pendingStore<void>(_pendingEmailCodeStore.clearLogoutIntent);
      } on Object {
        return _RemoteLogoutResult.unavailable;
      }
    }
    return result;
  }

  Future<BrowserCookieMutationJournal?> _beginBrowserCookieMutation(
    BrowserCookieMutationKind kind,
    String operationId,
  ) async {
    if (sessionTransport != ClientSessionTransport.webCookie) return null;
    final journal = BrowserCookieMutationJournal(
      kind: kind,
      operationId: operationId,
    );
    try {
      await _pendingStore<void>(
        () => _pendingEmailCodeStore.beginCookieMutation(journal),
      );
      return journal;
    } on Object {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.unavailable,
        safeMessage:
            'Secure browser state is unavailable. Try again before signing in.',
      );
    }
  }

  Future<void> _clearBrowserCookieMutation(
    BrowserCookieMutationJournal? journal,
  ) async {
    if (journal == null ||
        sessionTransport != ClientSessionTransport.webCookie) {
      return;
    }
    await _pendingStore<void>(
      () => _pendingEmailCodeStore.clearCookieMutation(journal: journal),
    );
  }

  Future<void> _failUnfinishedBrowserCookieMutation(
    BrowserCookieMutationJournal journal,
    int generation,
    String safeMessage,
  ) async {
    final rejectedSecrets = _secrets;
    final result = await _bestEffortLogout(
      rejectedSecrets,
      intentAlreadyMarked: true,
      publishSignedOut: true,
      skipOriginStateCheck: true,
    );
    _secrets = null;
    await _bestEffortClearSessionStore();
    if (result == _RemoteLogoutResult.settled) {
      try {
        await _clearBrowserCookieMutation(journal);
      } on Object {
        // The durable journal keeps restore fail-closed until it can be read.
      }
    }
    if (_isCurrent(generation)) {
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.sessionExpired,
          safeMessage: safeMessage,
        ),
      );
    }
  }

  Future<bool> _resumeUnfinishedBrowserCookieMutation(int generation) async {
    if (sessionTransport != ClientSessionTransport.webCookie) return false;
    BrowserCookieMutationJournal? journal;
    var journalIsCorrupt = false;
    try {
      journal = await _pendingStore<BrowserCookieMutationJournal?>(
        _pendingEmailCodeStore.readCookieMutation,
      );
    } on Object {
      journalIsCorrupt = true;
    }
    if (journal == null && !journalIsCorrupt) return false;

    final result = await _bestEffortLogout(
      null,
      intentAlreadyMarked: true,
      publishSignedOut: true,
      skipOriginStateCheck: true,
    );
    _secrets = null;
    await _bestEffortClearSessionStore();
    var journalCleared = false;
    if (result == _RemoteLogoutResult.settled) {
      try {
        await _pendingStore<void>(
          () => _pendingEmailCodeStore.clearCookieMutation(journal: journal),
        );
        journalCleared = true;
      } on Object {
        // A later restore repeats idempotent cookie cleanup.
      }
    }
    if (_isCurrent(generation)) {
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.signedOut,
          safeMessage: journalCleared
              ? 'An interrupted browser session update was cleared. Request a new email code.'
              : 'Reconnect to finish clearing an interrupted browser session update.',
        ),
      );
    }
    return true;
  }

  Future<bool> _resumeLogoutIntent(int generation) async {
    bool pendingLogout;
    try {
      pendingLogout = await _pendingStore<bool>(
        _pendingEmailCodeStore.hasLogoutIntent,
      );
    } on Object {
      if (_isCurrent(generation)) {
        _emit(
          IdentitySessionSnapshot(
            status: IdentitySessionStatus.signedOut,
            safeMessage:
                'The saved sign-out state could not be verified. Retry before signing in.',
          ),
        );
      }
      return true;
    }
    if (!pendingLogout) return false;
    if (sessionTransport == ClientSessionTransport.nativeBearer) {
      try {
        final stored = await _credentialStoreOperation<StoredNativeSession?>(
          _credentialStore.read,
        );
        await _credentialStoreOperation<void>(_credentialStore.clear);
        if (stored != null) {
          await _bestEffortLogout(
            SessionSecrets(refreshToken: stored.refreshToken),
            intentAlreadyMarked: true,
          );
        }
        await _pendingStore<void>(_pendingEmailCodeStore.clearLogoutIntent);
        return false;
      } on Object {
        if (_isCurrent(generation)) {
          _emit(
            IdentitySessionSnapshot(
              status: IdentitySessionStatus.signedOut,
              safeMessage:
                  'Finishing sign out requires access to secure storage. Retry before restoring a session.',
            ),
          );
        }
        return true;
      }
    }
    final result = await _bestEffortLogout(
      null,
      intentAlreadyMarked: true,
      publishSignedOut: true,
    );
    if (result == _RemoteLogoutResult.unavailable) {
      if (_isCurrent(generation)) {
        _emit(
          IdentitySessionSnapshot(
            status: IdentitySessionStatus.signedOut,
            safeMessage:
                'Finishing sign out requires a connection. Retry before restoring a session.',
          ),
        );
      }
      return true;
    }
    if (result == _RemoteLogoutResult.superseded) return false;
    return false;
  }

  void _publishSignedOutSafely() {
    try {
      _sessionCoordination.publishSignedOut();
    } on Object {
      // Cookie cleanup and the secure logout tombstone remain authoritative.
    }
  }

  Future<void> _rememberVerifiedIdentity(
    SessionMetadata session,
    CurrentUserView user,
  ) async {
    if (sessionTransport != ClientSessionTransport.nativeBearer ||
        _offlineSessionStore == null) {
      return;
    }
    final now = _clock().toUtc();
    var expiresAt = now.add(offlineAccessWindow);
    for (final deadline in <DateTime?>[
      session.idleExpiresAt,
      session.refreshExpiresAt,
    ]) {
      if (deadline != null && deadline.isBefore(expiresAt)) {
        expiresAt = deadline;
      }
    }
    final lease = OfflineSessionLease(
      session: session,
      user: user,
      verifiedAt: now,
      lastObservedAt: now,
      expiresAt: expiresAt,
    );
    _offlineLease = lease;
    await _saveOfflineLease(lease);
  }

  Future<void> _saveOfflineLease(OfflineSessionLease lease) async {
    try {
      await _offlineSessionStore?.write(lease);
    } on Object {
      // Online sign-in remains usable if local offline caching is unavailable.
      // Clear any previous grant rather than extending an unverified lease.
      try {
        await _offlineSessionStore?.clear();
      } on Object {
        /* fail closed on read */
      }
    }
  }

  Future<bool> _restoreOffline(
    StoredNativeSession saved,
    int generation,
  ) async {
    if (sessionTransport != ClientSessionTransport.nativeBearer ||
        _offlineSessionStore == null ||
        !_isCurrent(generation)) {
      return false;
    }
    try {
      final lease = await _offlineSessionStore.read();
      final now = _clock().toUtc();
      if (lease == null ||
          !lease.permits(saved, now) ||
          lease.expiresAt.difference(lease.verifiedAt) > offlineAccessWindow ||
          !_isCurrent(generation)) {
        return false;
      }
      _validateCurrentUser(lease.user, lease.session);
      final observed = lease.observedAt(now);
      // Persist the high-water clock before making cached data accessible.
      await _offlineSessionStore.write(observed);
      if (!_isCurrent(generation)) return false;
      _offlineLease = observed;
      _secrets = SessionSecrets(refreshToken: saved.refreshToken);
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.offline,
          session: lease.session,
          currentUser: lease.user,
          safeMessage:
              'Offline: using previously verified access. Reconnect to verify access and synchronize.',
        ),
      );
      _offlineExpiryTimer?.cancel();
      _offlineElapsed = Stopwatch()..start();
      _offlineStartedAt = now;
      _offlineObservationTimer?.cancel();
      _offlineObservationTimer = Timer.periodic(const Duration(minutes: 1), (
        _,
      ) {
        unawaited(checkOfflineAccess());
      });
      _offlineExpiryTimer = Timer(lease.expiresAt.difference(now), () {
        if (_isCurrent(generation) && _snapshot.isOffline) {
          unawaited(_expireOfflineAccess());
        }
      });
      return true;
    } on Object {
      return false;
    }
  }

  /// Also checked immediately before local repository mutations. A changed
  /// wall clock cannot extend an open lease beyond monotonic elapsed time.
  bool get localAccessIsCurrent {
    if (!_snapshot.isOffline) return _snapshot.isAuthenticated;
    final lease = _offlineLease;
    final started = _offlineStartedAt;
    if (lease == null || started == null) return false;
    final now = _clock().toUtc();
    final monotonicNow = started.add(_offlineElapsed?.elapsed ?? Duration.zero);
    return !now.isBefore(lease.lastObservedAt) &&
        !now.isBefore(monotonicNow.subtract(const Duration(seconds: 5))) &&
        lease.expiresAt.isAfter(now) &&
        lease.expiresAt.isAfter(monotonicNow) &&
        !lease.session.isExpiredAt(now);
  }

  Future<void> checkOfflineAccess() {
    final existing = _offlineObservation;
    if (existing != null) return existing;
    final future = _observeOfflineAccess();
    _offlineObservation = future;
    return future.whenComplete(() {
      if (identical(_offlineObservation, future)) _offlineObservation = null;
    });
  }

  Future<void> _observeOfflineAccess() async {
    if (!_snapshot.isOffline) return;
    if (!localAccessIsCurrent) return _expireOfflineAccess();
    final lease = _offlineLease;
    if (lease == null) return;
    final generation = _lifecycleGeneration;
    final observed = lease.observedAt(_clock().toUtc());
    try {
      await _offlineSessionStore?.write(observed);
      if (_isCurrent(generation) && _snapshot.isOffline) {
        _offlineLease = observed;
      }
    } on Object {
      if (_isCurrent(generation) && _snapshot.isOffline) {
        await _expireOfflineAccess();
      }
    }
  }

  Future<void> _expireOfflineAccess() async {
    _offlineExpiryTimer?.cancel();
    _offlineObservationTimer?.cancel();
    _offlineElapsed?.stop();
    _invalidateLifecycle();
    _secrets = null;
    _offlineLease = null;
    _emit(
      IdentitySessionSnapshot(
        status: IdentitySessionStatus.sessionExpired,
        safeMessage:
            'Offline access expired or the device clock changed. Reconnect to verify your session. Saved work is preserved.',
      ),
    );
    try {
      await _offlineSessionStore?.clear();
    } on Object {
      // If the lease cannot be durably retired, use the independent existing
      // logout journal and credential deletion rather than allowing rollback
      // to revive an expired cached grant on the next process start.
      try {
        await _pendingStore<void>(_pendingEmailCodeStore.markLogoutIntent);
      } on Object {
        /* credential deletion remains an independent barrier */
      }
      await _bestEffortClearSessionStore();
    }
  }

  /// Retires cached local authority after a known home/permission revocation.
  /// A failed durable clear cannot be ignored and later used as offline access.
  Future<void> invalidateOfflineAccess() async {
    if (_snapshot.isOffline) return _expireOfflineAccess();
    _offlineLease = null;
    _offlineExpiryTimer?.cancel();
    _offlineObservationTimer?.cancel();
    _offlineElapsed?.stop();
    try {
      await _offlineSessionStore?.clear();
    } on Object {
      try {
        await _pendingStore<void>(_pendingEmailCodeStore.markLogoutIntent);
      } on Object {
        /* native credential deletion is a second barrier */
      }
      await _clearSession();
      _invalidateLifecycle();
      _emit(
        IdentitySessionSnapshot(
          status: IdentitySessionStatus.sessionExpired,
          safeMessage:
              'Cached access could not be retired safely. Sign in again when secure storage is available.',
        ),
      );
    }
  }

  Future<void> _clearSession() async {
    _secrets = null;
    if (sessionTransport == ClientSessionTransport.nativeBearer) {
      try {
        await _pendingStore<void>(_pendingEmailCodeStore.markLogoutIntent);
      } on Object {
        // Secure credential and lease deletion are independent barriers.
      }
    }
    await _bestEffortClearSessionStore();
  }

  Future<void> _bestEffortClearSessionStore() async {
    _offlineExpiryTimer?.cancel();
    _offlineObservationTimer?.cancel();
    _offlineElapsed?.stop();
    _offlineLease = null;
    try {
      await _offlineSessionStore?.clear();
    } on Object {
      // The durable logout journal and missing native credential also block
      // local restore. Cached data is never an independent credential.
    }
    try {
      await _credentialStoreOperation<void>(_credentialStore.clear);
    } on Object {
      // In-memory credentials are still discarded.
    }
  }

  Future<void> _clearPendingStore({PendingEmailCode? request}) async {
    try {
      await _pendingStore<void>(
        () => _pendingEmailCodeStore.clear(request: request),
      );
    } on Object {
      // The in-memory proof is still discarded and will expire server-side.
    }
  }

  Future<void> _invalidatePendingStore(PendingEmailCode? pending) async {
    if (pending != null) {
      try {
        await _pendingStore<void>(
          () => _pendingEmailCodeStore.invalidate(pending),
        );
      } on Object {
        // Deletion below remains a second independent local safeguard.
      }
    }
    await _clearPendingStore(request: pending);
  }

  /// Store operations keep their own ordering even when the caller times out.
  /// A late platform write/delete settles before the next operation starts, so
  /// it cannot overwrite or erase a newer proof after mutation recovery.
  Future<T> _pendingStore<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _pendingStoreTail = _pendingStoreTail.then<void>((_) async {
      try {
        completer.complete(await _withCookieMutationLock<T>(action));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    // A timeout does not cancel FlutterSecureStorage. While the origin cookie
    // lock is held, releasing this Future early would also release that lock
    // and let another tab interleave before the old write/delete settles.
    // Keep the origin lock until the real platform operation completes; calls
    // outside the lock remain bounded and the per-manager tail still orders
    // their eventual completion.
    if (sessionTransport == ClientSessionTransport.webCookie &&
        identical(Zone.current[_cookieLockZoneKey], this)) {
      return completer.future;
    }
    return completer.future.timeout(requestTimeout);
  }

  /// Native credential operations use the same late-completion discipline as
  /// pending login proofs while remaining independent from that store.
  Future<T> _credentialStoreOperation<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _credentialStoreTail = _credentialStoreTail.then<void>((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future.timeout(requestTimeout);
  }

  Future<T> _serializeMutation<T>(Future<T> Function() action) {
    if (identical(Zone.current[_mutationZoneKey], this)) return action();
    final completer = Completer<T>();
    _mutationTail = _mutationTail.then<void>((_) async {
      if (_disposed) {
        completer.completeError(
          StateError('IdentitySessionManager has been disposed.'),
        );
        return;
      }
      try {
        final result = await runZoned<Future<T>>(
          action,
          zoneValues: <Object, Object>{_mutationZoneKey: this},
        );
        completer.complete(result);
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Duration get _coordinationLockWaitTimeout {
    final transport = _transport;
    if (transport is AbortBoundIdentityTransportPort) {
      final networkTimeout =
          (transport as AbortBoundIdentityTransportPort).networkTimeout;
      return requestTimeout -
          networkTimeout -
          const Duration(milliseconds: 500);
    }
    return Duration(microseconds: requestTimeout.inMicroseconds ~/ 2);
  }

  Future<T> _withCookieMutationLock<T>(Future<T> Function() action) {
    if (sessionTransport != ClientSessionTransport.webCookie ||
        identical(Zone.current[_cookieLockZoneKey], this)) {
      return action();
    }
    return _sessionCoordination.runExclusive<T>(
      () => runZoned<Future<T>>(
        action,
        zoneValues: <Object, Object>{_cookieLockZoneKey: this},
      ),
      lockWaitTimeout: _coordinationLockWaitTimeout,
    );
  }

  int _beginAuthentication() {
    _invalidateLifecycle();
    return _lifecycleGeneration;
  }

  void _invalidateLifecycle() {
    _lifecycleGeneration++;
    _refreshInFlight = null;
    _coordinatedRefreshGrant = null;
    _restoreInFlight = null;
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _lifecycleGeneration;

  void _emitFailure(String safeMessage) {
    _emit(
      IdentitySessionSnapshot(
        status: IdentitySessionStatus.failure,
        loginEmail: _pendingEmailCode?.email ?? _snapshot.loginEmail,
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

enum _RemoteLogoutResult { settled, unavailable, superseded }
