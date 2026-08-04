import 'dart:collection';

enum ClientSessionTransport { nativeBearer, webCookie }

enum PasswordlessProofKind { magicLinkToken, oneTimeCode }

enum IdentitySessionStatus {
  restoring,
  signedOut,
  challengeRequested,
  authenticating,
  authenticated,
  refreshing,
  expired,
  failure,
}

final class DeviceDescriptor {
  DeviceDescriptor({
    required this.id,
    required this.name,
    required this.platform,
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(name, 'name');
    _requireNonEmpty(platform, 'platform');
  }

  final String id;
  final String name;
  final String platform;
}

/// A deliberately generic acknowledgement that does not disclose whether an
/// account already exists.
final class PasswordlessChallengeReceipt {
  PasswordlessChallengeReceipt({
    required this.email,
    required this.expiresAt,
    this.challengeId,
    this.codeEntryAvailable = true,
  }) {
    _requireEmail(email);
    if (challengeId != null) {
      _requireNonEmpty(challengeId!, 'challengeId');
    }
  }

  final String email;
  final DateTime expiresAt;
  final String? challengeId;
  final bool codeEntryAvailable;

  bool isExpiredAt(DateTime instant) => !expiresAt.isAfter(instant.toUtc());
}

final class PasswordlessProof {
  PasswordlessProof.magicLink({required String token})
    : kind = PasswordlessProofKind.magicLinkToken,
      token = _validated(token, 'token'),
      email = null,
      code = null,
      challengeId = null;

  PasswordlessProof.oneTimeCode({
    required String email,
    required String code,
    String? challengeId,
  }) : kind = PasswordlessProofKind.oneTimeCode,
       token = null,
       email = _validatedEmail(email),
       code = _validated(code, 'code'),
       challengeId = challengeId == null
           ? null
           : _validated(challengeId, 'challengeId');

  final PasswordlessProofKind kind;
  final String? token;
  final String? email;
  final String? code;
  final String? challengeId;
}

/// Secret material returned by a session endpoint.
///
/// This type intentionally has no `toString`, equality, or serialization
/// helpers. Secrets must move directly into the in-memory session and secure
/// native store, never into logs or Drift.
final class SessionSecrets {
  const SessionSecrets({this.accessToken, this.refreshToken, this.csrfToken});

  final String? accessToken;
  final String? refreshToken;
  final String? csrfToken;
}

final class SessionMetadata {
  SessionMetadata({
    required this.sessionId,
    required this.deviceId,
    required this.accessExpiresAt,
    required this.transport,
    this.activeHomeId,
  }) {
    _requireNonEmpty(sessionId, 'sessionId');
    _requireNonEmpty(deviceId, 'deviceId');
    if (activeHomeId != null) {
      _requireNonEmpty(activeHomeId!, 'activeHomeId');
    }
  }

  final String sessionId;
  final String deviceId;
  final DateTime accessExpiresAt;
  final ClientSessionTransport transport;
  final String? activeHomeId;

  SessionMetadata copyWith({
    String? activeHomeId,
    bool clearActiveHome = false,
  }) {
    return SessionMetadata(
      sessionId: sessionId,
      deviceId: deviceId,
      accessExpiresAt: accessExpiresAt,
      transport: transport,
      activeHomeId: clearActiveHome
          ? null
          : (activeHomeId ?? this.activeHomeId),
    );
  }
}

final class SessionGrant {
  SessionGrant({required this.metadata, required this.secrets}) {
    if (metadata.transport == ClientSessionTransport.nativeBearer) {
      _requireNonEmpty(secrets.accessToken ?? '', 'accessToken');
      _requireNonEmpty(secrets.refreshToken ?? '', 'refreshToken');
    } else if (secrets.accessToken != null || secrets.refreshToken != null) {
      throw ArgumentError(
        'Browser cookie sessions cannot expose bearer or refresh tokens.',
      );
    }
  }

  final SessionMetadata metadata;
  final SessionSecrets secrets;
}

final class StoredNativeSession {
  StoredNativeSession({
    required this.sessionId,
    required this.deviceId,
    required this.refreshToken,
  }) {
    _requireNonEmpty(sessionId, 'sessionId');
    _requireNonEmpty(deviceId, 'deviceId');
    _requireNonEmpty(refreshToken, 'refreshToken');
  }

  final String sessionId;
  final String deviceId;
  final String refreshToken;
}

final class DeviceSessionView {
  DeviceSessionView({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.createdAt,
    required this.lastSeenAt,
    this.activeHomeId,
    this.revokedAt,
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(deviceId, 'deviceId');
  }

  final String id;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String? activeHomeId;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;
}

final class IdentitySessionSnapshot {
  IdentitySessionSnapshot({
    required this.status,
    this.session,
    this.challenge,
    this.safeMessage,
    List<DeviceSessionView> deviceSessions = const <DeviceSessionView>[],
  }) : deviceSessions = UnmodifiableListView<DeviceSessionView>(
         List<DeviceSessionView>.of(deviceSessions),
       );

  const IdentitySessionSnapshot.signedOut()
    : status = IdentitySessionStatus.signedOut,
      session = null,
      challenge = null,
      safeMessage = null,
      deviceSessions = const <DeviceSessionView>[];

  final IdentitySessionStatus status;
  final SessionMetadata? session;
  final PasswordlessChallengeReceipt? challenge;
  final String? safeMessage;
  final List<DeviceSessionView> deviceSessions;

  bool get isAuthenticated =>
      status == IdentitySessionStatus.authenticated ||
      status == IdentitySessionStatus.refreshing;

  IdentitySessionSnapshot copyWith({
    IdentitySessionStatus? status,
    SessionMetadata? session,
    PasswordlessChallengeReceipt? challenge,
    String? safeMessage,
    bool clearMessage = false,
    bool clearChallenge = false,
    List<DeviceSessionView>? deviceSessions,
  }) {
    return IdentitySessionSnapshot(
      status: status ?? this.status,
      session: session ?? this.session,
      challenge: clearChallenge ? null : (challenge ?? this.challenge),
      safeMessage: clearMessage ? null : (safeMessage ?? this.safeMessage),
      deviceSessions: deviceSessions ?? this.deviceSessions,
    );
  }
}

String _validated(String value, String name) {
  _requireNonEmpty(value, name);
  return value.trim();
}

String _validatedEmail(String value) {
  _requireEmail(value);
  return value.trim().toLowerCase();
}

void _requireEmail(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
    throw ArgumentError.value(value, 'email', 'must be a valid email address');
  }
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}
