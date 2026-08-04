import 'package:providentia/features/identity/domain/identity_models.dart';

enum IdentityFailureKind {
  authentication,
  expiredChallenge,
  rateLimited,
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

  @override
  String toString() => 'IdentityTransportException(${kind.name})';
}

final class IdentityCredentialStoreException implements Exception {
  const IdentityCredentialStoreException(this.safeMessage);

  final String safeMessage;

  @override
  String toString() => 'IdentityCredentialStoreException';
}

/// Application-owned identity transport.
///
/// These passwordless operations are the approved forward contract. OpenAPI
/// 1.7 currently publishes password register/login/verification only, so its
/// adapter must report passwordless as unavailable until the backend publishes
/// challenge and completion endpoints. Nothing here implies those endpoints
/// are executable against 1.7.
abstract interface class IdentityTransportPort {
  ClientSessionTransport get sessionTransport;

  Future<PasswordlessChallengeReceipt> requestPasswordlessChallenge({
    required String email,
  });

  Future<SessionGrant> completePasswordlessChallenge({
    required PasswordlessProof proof,
    required DeviceDescriptor device,
  });

  /// Native callers provide their rotating refresh credential. Browser callers
  /// pass null and authenticate with an HttpOnly refresh cookie.
  Future<SessionGrant> refreshSession({String? refreshToken});

  Future<void> logout({String? accessToken, String? csrfToken});

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

/// Temporary compatibility capability for the published OpenAPI 1.7
/// password login. Product code can remove this interface after passwordless
/// challenge endpoints are released and deployed.
abstract interface class LegacyPasswordIdentityTransportPort {
  Future<SessionGrant> loginWithPassword({
    required String email,
    required String password,
    required DeviceDescriptor device,
  });
}

/// Secure persistence boundary for native rotating refresh credentials.
///
/// The web implementation must return false from [supportsPersistentSecrets],
/// never persist bearer/refresh credentials, and use cookie sessions instead.
abstract interface class SessionCredentialStore {
  bool get supportsPersistentSecrets;

  Future<StoredNativeSession?> read();

  Future<void> write(StoredNativeSession session);

  Future<void> clear();
}

/// Minimal credential view used by authenticated transport adapters.
abstract interface class SessionAuthorizer {
  ClientSessionTransport get sessionTransport;

  String? get accessToken;

  String? get csrfToken;

  Future<bool> ensureFresh();
}
