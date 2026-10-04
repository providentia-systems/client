import 'package:providentia/features/identity/domain/identity_models.dart';

/// A bounded local-access lease. It is never a server credential or a new
/// membership grant, and it is useful only with the same saved native session.
final class OfflineSessionLease {
  const OfflineSessionLease({
    required this.session,
    required this.user,
    required this.verifiedAt,
    required this.lastObservedAt,
    required this.expiresAt,
  });

  final SessionMetadata session;
  final CurrentUserView user;
  final DateTime verifiedAt;
  final DateTime lastObservedAt;
  final DateTime expiresAt;

  bool permits(StoredNativeSession saved, DateTime now) =>
      session.transport == ClientSessionTransport.nativeBearer &&
      session.sessionId == saved.sessionId &&
      session.userId == saved.userId &&
      session.deviceId == saved.deviceId &&
      session.installationId == saved.installationId &&
      user.userId == session.userId &&
      user.currentSession.id == session.sessionId &&
      user.currentSession.deviceId == session.deviceId &&
      user.currentSession.current &&
      !user.currentSession.isRevoked &&
      user.onboardingComplete &&
      !now.isBefore(verifiedAt) &&
      !now.isBefore(lastObservedAt) &&
      expiresAt.isAfter(now) &&
      !session.isExpiredAt(now);

  OfflineSessionLease observedAt(DateTime now) => OfflineSessionLease(
    session: session,
    user: user,
    verifiedAt: verifiedAt,
    lastObservedAt: now,
    expiresAt: expiresAt,
  );

  OfflineSessionLease withActiveHome(String? homeId) => OfflineSessionLease(
    session: session.copyWith(
      activeHomeId: homeId,
      clearActiveHome: homeId == null,
    ),
    user: user.withActiveHome(homeId),
    verifiedAt: verifiedAt,
    lastObservedAt: lastObservedAt,
    expiresAt: expiresAt,
  );
}

abstract interface class OfflineSessionStore {
  Future<OfflineSessionLease?> read();
  Future<void> write(OfflineSessionLease lease);
  Future<void> clear();
}
