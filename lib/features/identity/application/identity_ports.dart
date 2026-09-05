import 'package:providentia/features/identity/domain/identity_models.dart';

enum IdentityFailureKind {
  authentication,
  loginRequestExpired,
  rateLimited,
  conflict,
  validation,
  forbidden,
  unavailable,
  network,
}

final class IdentityTransportException implements Exception {
  const IdentityTransportException({
    required this.kind,
    required this.safeMessage,
  });

  final IdentityFailureKind kind;
  final String safeMessage;

  bool get invalidatesSession =>
      kind == IdentityFailureKind.authentication ||
      kind == IdentityFailureKind.forbidden;

  bool get retryablePollingFailure =>
      kind == IdentityFailureKind.network ||
      kind == IdentityFailureKind.unavailable ||
      kind == IdentityFailureKind.rateLimited;

  @override
  String toString() => 'IdentityTransportException(${kind.name})';
}

final class IdentityCredentialStoreException implements Exception {
  const IdentityCredentialStoreException(this.safeMessage);

  final String safeMessage;

  @override
  String toString() => 'IdentityCredentialStoreException';
}

abstract interface class IdentityTransportPort {
  ClientSessionTransport get sessionTransport;

  Future<PendingEmailCode> requestEmailCode({
    required String email,
    required DeviceDescriptor device,
  });

  Future<SessionGrant> verifyEmailCode({
    required PendingEmailCode request,
    required String code,
  });

  /// Native callers provide their rotating refresh credential. Browser callers
  /// pass null and authenticate with an HttpOnly refresh cookie.
  Future<SessionGrant> refreshSession({String? refreshToken});

  Future<CurrentUserView> getCurrentUser({
    String? accessToken,
    String? csrfToken,
  });

  Future<void> logout({
    String? accessToken,
    String? refreshToken,
    String? csrfToken,
  });

  Future<List<DeviceSessionView>> listDeviceSessions({
    String? accessToken,
    String? csrfToken,
  });

  Future<void> revokeDeviceSession({
    required String sessionId,
    String? accessToken,
    String? csrfToken,
  });
}

/// Transport capability proving that every HTTP request is actively aborted
/// before application-level lifecycle timeouts release serialized mutations.
abstract interface class AbortBoundIdentityTransportPort {
  Duration get networkTimeout;
}

final class CoordinatedSessionUpdate {
  const CoordinatedSessionUpdate.grant(SessionGrant value, {String? intentId})
    : grant = value,
      signedOut = false,
      authenticationIntentId = null,
      grantIntentId = intentId;

  const CoordinatedSessionUpdate.signedOut()
    : grant = null,
      signedOut = true,
      authenticationIntentId = null,
      grantIntentId = null;

  const CoordinatedSessionUpdate.authenticationIntent(String intentId)
    : grant = null,
      signedOut = false,
      authenticationIntentId = intentId,
      grantIntentId = null;

  final SessionGrant? grant;
  final bool signedOut;
  final String? authenticationIntentId;
  final String? grantIntentId;
}

/// Coordinates origin-wide browser cookies with per-client session metadata.
abstract interface class SessionCoordinationPort {
  Stream<CoordinatedSessionUpdate> get updates;

  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    required Duration lockWaitTimeout,
  });

  /// Reads the last origin-wide grant/sign-out record while holding the same
  /// lock as cookie mutations. This closes the Web Lock/BroadcastChannel
  /// handoff race; native coordinators return null.
  Future<CoordinatedSessionUpdate?> readLatest();

  void publishGrant(SessionGrant grant, {String? intentId});

  void publishAuthenticationIntent(String intentId);

  void publishSignedOut();

  Future<void> dispose();
}

/// Native/default coordinator; a process already serializes its own refreshes.
class LocalSessionCoordination implements SessionCoordinationPort {
  const LocalSessionCoordination();

  @override
  Stream<CoordinatedSessionUpdate> get updates =>
      const Stream<CoordinatedSessionUpdate>.empty();

  @override
  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    required Duration lockWaitTimeout,
  }) => action();

  @override
  Future<CoordinatedSessionUpdate?> readLatest() async => null;

  @override
  void publishGrant(SessionGrant grant, {String? intentId}) {}

  @override
  void publishAuthenticationIntent(String intentId) {}

  @override
  void publishSignedOut() {}

  @override
  Future<void> dispose() async {}
}

enum BrowserCookieMutationKind { emailCodeVerification, sessionRefresh }

/// Non-secret crash journal for an origin-wide browser cookie mutation.
///
/// A browser can commit `Set-Cookie` before Dart receives or persists the
/// response body. Restore treats any unfinished entry as an unknown cookie
/// state and clears it before trusting coordinated session metadata.
final class BrowserCookieMutationJournal {
  const BrowserCookieMutationJournal({
    required this.kind,
    required this.operationId,
  });

  final BrowserCookieMutationKind kind;
  final String operationId;
}

abstract interface class PendingEmailCodeStore {
  Future<PendingEmailCode?> read();

  Future<void> write(PendingEmailCode request, {required bool activate});

  /// Replaces a private proof with a non-secret cancellation tombstone.
  Future<void> invalidate(PendingEmailCode request);

  /// Completes only [request] when supplied. Web stores use request-scoped
  /// records so one tab can never delete another tab's newer private proof.
  Future<void> clear({PendingEmailCode? request});

  Future<bool> hasLogoutIntent();

  Future<void> markLogoutIntent();

  Future<void> clearLogoutIntent();

  Future<BrowserCookieMutationJournal?> readCookieMutation();

  Future<void> beginCookieMutation(BrowserCookieMutationJournal journal);

  /// Clears [journal] only when it is still the origin-authoritative entry.
  /// Passing null is reserved for fail-closed repair of corrupt state.
  Future<void> clearCookieMutation({BrowserCookieMutationJournal? journal});
}

/// Secure persistence boundary for native rotating refresh credentials.
///
/// The web implementation returns false from [supportsPersistentSecrets],
/// never persists bearer/refresh credentials, and uses cookie sessions.
abstract interface class SessionCredentialStore {
  bool get supportsPersistentSecrets;

  Future<StoredNativeSession?> read();

  Future<void> write(StoredNativeSession session);

  Future<void> clear();
}

abstract interface class SessionAuthorizer {
  ClientSessionTransport get sessionTransport;

  String? get accessToken;

  String? get csrfToken;

  Future<bool> ensureFresh();
}
