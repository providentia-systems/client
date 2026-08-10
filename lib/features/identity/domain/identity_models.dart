import 'dart:collection';

enum ClientSessionTransport { nativeBearer, webCookie }

enum LoginLinkRequestStatus {
  pending,
  approved,
  denied,
  exchanged,
  expired,
  cancelled,
}

enum IdentitySessionStatus {
  restoring,
  signedOut,
  requestingLoginLink,
  waitingForLoginLink,
  exchangingLoginLink,
  authenticated,
  refreshing,
  loginLinkExpired,
  sessionExpired,
  failure,
}

enum PlatformRole {
  platformAdministrator,
  catalogCurator,
  catalogReviewer,
  billingOperator,
}

final class DeviceDescriptor {
  DeviceDescriptor({
    required this.id,
    required this.name,
    required this.platform,
  }) {
    _requireUuid(id, 'id');
    _requireNonEmpty(name, 'name');
    _requireNonEmpty(platform, 'platform');
  }

  final String id;
  final String name;
  final String platform;
}

/// A login request whose private proof is owned by the originating client.
///
/// This type deliberately has no serialization or `toString` helpers. The
/// poll token, PKCE verifier, and state must only cross the dedicated secure
/// store and identity transport boundaries.
final class PendingLoginLinkRequest {
  PendingLoginLinkRequest({
    required this.requestId,
    required this.email,
    required this.pollToken,
    required this.codeVerifier,
    required this.state,
    required this.createdAt,
    required this.expiresAt,
    required this.pollInterval,
  }) {
    _requireUuid(requestId, 'requestId');
    _requireEmail(email);
    _requireSecret(pollToken, 'pollToken');
    _requireSecret(codeVerifier, 'codeVerifier');
    _requireSecret(state, 'state', minimumLength: 32);
    if (pollInterval < const Duration(seconds: 1) ||
        pollInterval > const Duration(seconds: 30)) {
      throw ArgumentError.value(
        pollInterval,
        'pollInterval',
        'must be between 1 and 30 seconds',
      );
    }
  }

  final String requestId;
  final String email;
  final String pollToken;
  final String codeVerifier;
  final String state;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Duration pollInterval;

  bool isExpiredAt(DateTime instant) => !expiresAt.isAfter(instant.toUtc());

  PendingLoginLinkRequest withServerReceipt(LoginLinkStartReceipt receipt) {
    if (receipt.requestId != requestId) {
      throw const FormatException('Login request identity changed.');
    }
    return PendingLoginLinkRequest(
      requestId: requestId,
      email: email,
      pollToken: pollToken,
      codeVerifier: codeVerifier,
      state: state,
      createdAt: createdAt,
      expiresAt: receipt.expiresAt,
      pollInterval: receipt.pollInterval,
    );
  }

  PendingLoginLinkRequest withServerExpiry(DateTime serverExpiresAt) {
    return PendingLoginLinkRequest(
      requestId: requestId,
      email: email,
      pollToken: pollToken,
      codeVerifier: codeVerifier,
      state: state,
      createdAt: createdAt,
      expiresAt: serverExpiresAt.toUtc(),
      pollInterval: pollInterval,
    );
  }

  PendingLoginLinkView toPublicView() => PendingLoginLinkView(
    email: email,
    expiresAt: expiresAt,
    pollInterval: pollInterval,
  );
}

/// Non-secret presentation state for an origin-bound login request.
///
/// The request identifier and possession proofs deliberately remain private to
/// [IdentitySessionManager] and its secure persistence/transport boundaries.
final class PendingLoginLinkView {
  PendingLoginLinkView({
    required this.email,
    required this.expiresAt,
    required this.pollInterval,
  }) {
    _requireEmail(email);
  }

  final String email;
  final DateTime expiresAt;
  final Duration pollInterval;

  bool isExpiredAt(DateTime instant) => !expiresAt.isAfter(instant.toUtc());
}

final class LoginLinkStartCommand {
  LoginLinkStartCommand({
    required this.requestId,
    required this.email,
    required this.pollChallenge,
    required this.codeChallenge,
    required this.state,
    required this.device,
    required this.transport,
    this.requestedSessionIdleSeconds,
  }) {
    _requireUuid(requestId, 'requestId');
    _requireEmail(email);
    _requireChallenge(pollChallenge, 'pollChallenge');
    _requireChallenge(codeChallenge, 'codeChallenge');
    _requireSecret(state, 'state', minimumLength: 32);
    if (requestedSessionIdleSeconds != null &&
        (requestedSessionIdleSeconds! < 900 ||
            requestedSessionIdleSeconds! > 5184000)) {
      throw ArgumentError.value(
        requestedSessionIdleSeconds,
        'requestedSessionIdleSeconds',
        'must be between 900 and 5184000',
      );
    }
  }

  final String requestId;
  final String email;
  final String pollChallenge;
  final String codeChallenge;
  final String state;
  final DeviceDescriptor device;
  final ClientSessionTransport transport;
  final int? requestedSessionIdleSeconds;
}

final class LoginLinkStartReceipt {
  LoginLinkStartReceipt({
    required this.requestId,
    required this.expiresAt,
    required this.pollInterval,
  }) {
    _requireUuid(requestId, 'requestId');
    if (pollInterval < const Duration(seconds: 1) ||
        pollInterval > const Duration(seconds: 30)) {
      throw ArgumentError.value(
        pollInterval,
        'pollInterval',
        'must be between 1 and 30 seconds',
      );
    }
  }

  final String requestId;
  final DateTime expiresAt;
  final Duration pollInterval;
}

final class LoginLinkStatusView {
  LoginLinkStatusView({
    required this.requestId,
    required this.status,
    required this.expiresAt,
    this.approvedAt,
  }) {
    _requireUuid(requestId, 'requestId');
  }

  final String requestId;
  final LoginLinkRequestStatus status;
  final DateTime expiresAt;
  final DateTime? approvedAt;
}

/// Creates high-entropy request identifiers and proofs outside application
/// state so deterministic fakes can be supplied in tests.
abstract interface class LoginLinkRequestFactory {
  PendingLoginLinkRequest create({
    required String email,
    required DateTime createdAt,
    required DateTime expiresAt,
    required Duration pollInterval,
  });

  String challenge(String secret);
}

/// Secret material returned by a session endpoint.
///
/// This type intentionally has no `toString`, equality, or serialization
/// helpers. Secrets move directly into memory and the secure native store.
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
    String? installationId,
    required this.userId,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
    required this.idleExpiresAt,
    required this.refreshIdleTtl,
    required this.transport,
    this.activeHomeId,
  }) : installationId = installationId ?? deviceId {
    _requireUuid(sessionId, 'sessionId');
    _requireUuid(deviceId, 'deviceId');
    _requireUuid(this.installationId, 'installationId');
    _requireUuid(userId, 'userId');
    final maximumIdleTtl = transport == ClientSessionTransport.webCookie
        ? const Duration(days: 30)
        : const Duration(days: 60);
    if (refreshIdleTtl < const Duration(minutes: 15) ||
        refreshIdleTtl > maximumIdleTtl) {
      throw ArgumentError.value(
        refreshIdleTtl,
        'refreshIdleTtl',
        'exceeds the session transport policy',
      );
    }
    if (activeHomeId != null) {
      _requireUuid(activeHomeId!, 'activeHomeId');
    }
  }

  final String sessionId;
  final String deviceId;
  final String installationId;
  final String userId;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;
  final DateTime idleExpiresAt;
  final Duration refreshIdleTtl;
  final ClientSessionTransport transport;
  final String? activeHomeId;

  SessionMetadata copyWith({
    String? activeHomeId,
    bool clearActiveHome = false,
  }) {
    return SessionMetadata(
      sessionId: sessionId,
      deviceId: deviceId,
      installationId: installationId,
      userId: userId,
      accessExpiresAt: accessExpiresAt,
      refreshExpiresAt: refreshExpiresAt,
      idleExpiresAt: idleExpiresAt,
      refreshIdleTtl: refreshIdleTtl,
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
    String? installationId,
    required this.refreshToken,
  }) : installationId = installationId ?? deviceId {
    _requireUuid(sessionId, 'sessionId');
    _requireUuid(deviceId, 'deviceId');
    _requireUuid(this.installationId, 'installationId');
    _requireNonEmpty(refreshToken, 'refreshToken');
  }

  final String sessionId;
  final String deviceId;
  final String installationId;
  final String refreshToken;
}

final class DeviceSessionView {
  DeviceSessionView({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.transport,
    required this.current,
    required this.createdAt,
    required this.lastSeenAt,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
    required this.idleExpiresAt,
    this.activeHomeId,
    this.revokedAt,
  }) {
    _requireUuid(id, 'id');
    _requireUuid(deviceId, 'deviceId');
    if (activeHomeId != null) {
      _requireUuid(activeHomeId!, 'activeHomeId');
    }
  }

  final String id;
  final String deviceId;
  final String deviceName;
  final String platform;
  final ClientSessionTransport transport;
  final bool current;
  final String? activeHomeId;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;
  final DateTime idleExpiresAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;

  bool isActiveAt(DateTime instant) {
    final utc = instant.toUtc();
    return !isRevoked &&
        idleExpiresAt.toUtc().isAfter(utc) &&
        refreshExpiresAt.toUtc().isAfter(utc);
  }

  DeviceSessionView withActiveHome(String? homeId) => DeviceSessionView(
    id: id,
    deviceId: deviceId,
    deviceName: deviceName,
    platform: platform,
    transport: transport,
    current: current,
    activeHomeId: homeId,
    createdAt: createdAt,
    lastSeenAt: lastSeenAt,
    accessExpiresAt: accessExpiresAt,
    refreshExpiresAt: refreshExpiresAt,
    idleExpiresAt: idleExpiresAt,
    revokedAt: revokedAt,
  );
}

final class CurrentUserHomeView {
  CurrentUserHomeView({
    required this.id,
    required this.name,
    required this.role,
  }) {
    _requireUuid(id, 'id');
    _requireNonEmpty(name, 'name');
    _requireNonEmpty(role, 'role');
  }

  final String id;
  final String name;
  final String role;
}

/// A non-secret invitation summary returned by the current-user bootstrap.
///
/// Home-specific presentation maps this value into its own domain model; the
/// identity boundary keeps `/me` complete without depending on a feature
/// module that is composed after authentication.
final class CurrentUserInvitationView {
  CurrentUserInvitationView({
    required this.id,
    required this.homeId,
    required this.homeName,
    required this.inviterUserId,
    required this.role,
    required this.expiresAt,
    required this.revision,
    this.inviterDisplayName,
  }) {
    _requireUuid(id, 'id');
    _requireUuid(homeId, 'homeId');
    _requireNonEmpty(homeName, 'homeName');
    _requireUuid(inviterUserId, 'inviterUserId');
    _requireNonEmpty(role, 'role');
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
  }

  final String id;
  final String homeId;
  final String homeName;
  final String inviterUserId;
  final String? inviterDisplayName;
  final String role;
  final DateTime expiresAt;
  final int revision;
}

final class CurrentUserView {
  CurrentUserView({
    required this.userId,
    required this.email,
    required this.emailVerified,
    required this.homes,
    required this.pendingInvitations,
    required Set<PlatformRole> platformRoles,
    required this.currentSession,
    this.displayName,
    this.locale,
    this.timezone,
    this.activeHomeId,
  }) : platformRoles = UnmodifiableSetView<PlatformRole>(
         Set<PlatformRole>.of(platformRoles),
       ) {
    _requireUuid(userId, 'userId');
    _requireEmail(email);
    if (!emailVerified) {
      throw ArgumentError.value(
        emailVerified,
        'emailVerified',
        'must be true for an authenticated user',
      );
    }
    if (activeHomeId != null && !homes.any((home) => home.id == activeHomeId)) {
      throw ArgumentError.value(
        activeHomeId,
        'activeHomeId',
        'must reference an authorized home',
      );
    }
  }

  final String userId;
  final String email;
  final bool emailVerified;
  final String? displayName;
  final String? locale;
  final String? timezone;
  final String? activeHomeId;
  final List<CurrentUserHomeView> homes;
  final List<CurrentUserInvitationView> pendingInvitations;
  final Set<PlatformRole> platformRoles;
  final DeviceSessionView currentSession;

  bool get isPlatformAdministrator =>
      platformRoles.contains(PlatformRole.platformAdministrator);

  CurrentUserView withActiveHome(String? homeId) => CurrentUserView(
    userId: userId,
    email: email,
    emailVerified: emailVerified,
    homes: homes,
    pendingInvitations: pendingInvitations,
    platformRoles: platformRoles,
    currentSession: currentSession.withActiveHome(homeId),
    displayName: displayName,
    locale: locale,
    timezone: timezone,
    activeHomeId: homeId,
  );
}

final class IdentitySessionSnapshot {
  IdentitySessionSnapshot({
    required this.status,
    this.session,
    this.pendingLoginLink,
    this.loginEmail,
    this.currentUser,
    this.safeMessage,
    List<DeviceSessionView> deviceSessions = const <DeviceSessionView>[],
  }) : deviceSessions = UnmodifiableListView<DeviceSessionView>(
         List<DeviceSessionView>.of(deviceSessions),
       );

  const IdentitySessionSnapshot.signedOut()
    : status = IdentitySessionStatus.signedOut,
      session = null,
      pendingLoginLink = null,
      loginEmail = null,
      currentUser = null,
      safeMessage = null,
      deviceSessions = const <DeviceSessionView>[];

  final IdentitySessionStatus status;
  final SessionMetadata? session;
  final PendingLoginLinkView? pendingLoginLink;

  /// Non-secret recipient retained for terminal resend presentation.
  final String? loginEmail;
  final CurrentUserView? currentUser;
  final String? safeMessage;
  final List<DeviceSessionView> deviceSessions;

  bool get isAuthenticated =>
      status == IdentitySessionStatus.authenticated ||
      status == IdentitySessionStatus.refreshing;

  IdentitySessionSnapshot copyWith({
    IdentitySessionStatus? status,
    SessionMetadata? session,
    bool clearSession = false,
    PendingLoginLinkView? pendingLoginLink,
    bool clearPendingLoginLink = false,
    String? loginEmail,
    bool clearLoginEmail = false,
    CurrentUserView? currentUser,
    bool clearCurrentUser = false,
    String? safeMessage,
    bool clearMessage = false,
    List<DeviceSessionView>? deviceSessions,
  }) {
    return IdentitySessionSnapshot(
      status: status ?? this.status,
      session: clearSession ? null : (session ?? this.session),
      pendingLoginLink: clearPendingLoginLink
          ? null
          : (pendingLoginLink ?? this.pendingLoginLink),
      loginEmail: clearLoginEmail ? null : (loginEmail ?? this.loginEmail),
      currentUser: clearCurrentUser ? null : (currentUser ?? this.currentUser),
      safeMessage: clearMessage ? null : (safeMessage ?? this.safeMessage),
      deviceSessions: deviceSessions ?? this.deviceSessions,
    );
  }
}

String normalizedEmail(String value) {
  _requireEmail(value);
  return value.trim().toLowerCase();
}

void _requireChallenge(String value, String name) {
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be an S256 challenge');
  }
}

void _requireSecret(String value, String name, {int minimumLength = 43}) {
  if (value.length < minimumLength || value.length > 128) {
    throw ArgumentError.value(value, name, 'has an invalid length');
  }
}

void _requireEmail(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
    throw ArgumentError.value(value, 'email', 'must be a valid email address');
  }
}

void _requireUuid(String value, String name) {
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be a UUID');
  }
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}
