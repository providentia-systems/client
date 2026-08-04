import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

void main() {
  test('session metadata can select and explicitly clear an active home', () {
    final metadata = SessionMetadata(
      sessionId: 'session-1',
      deviceId: 'device-1',
      accessExpiresAt: DateTime.utc(2026, 8, 4, 18),
      transport: ClientSessionTransport.nativeBearer,
      activeHomeId: 'home-1',
    );

    final switched = metadata.copyWith(activeHomeId: 'home-2');
    final cleared = switched.copyWith(clearActiveHome: true);
    final preserved = metadata.copyWith();

    expect(switched.sessionId, metadata.sessionId);
    expect(switched.deviceId, metadata.deviceId);
    expect(switched.accessExpiresAt, metadata.accessExpiresAt);
    expect(switched.transport, metadata.transport);
    expect(switched.activeHomeId, 'home-2');
    expect(cleared.activeHomeId, isNull);
    expect(preserved.activeHomeId, 'home-1');
  });

  test('identity snapshots copy state and clear transient values', () {
    final challenge = PasswordlessChallengeReceipt(
      email: 'person@example.com',
      expiresAt: DateTime.utc(2026, 8, 4, 18),
      challengeId: 'challenge-1',
    );
    final snapshot = IdentitySessionSnapshot(
      status: IdentitySessionStatus.challengeRequested,
      challenge: challenge,
      safeMessage: 'Check your email.',
    );

    final refreshing = snapshot.copyWith(
      status: IdentitySessionStatus.refreshing,
      clearChallenge: true,
      clearMessage: true,
      deviceSessions: const <DeviceSessionView>[],
    );
    final preserved = snapshot.copyWith();

    expect(refreshing.status, IdentitySessionStatus.refreshing);
    expect(refreshing.isAuthenticated, isTrue);
    expect(refreshing.challenge, isNull);
    expect(refreshing.safeMessage, isNull);
    expect(refreshing.deviceSessions, isEmpty);
    expect(preserved.status, IdentitySessionStatus.challengeRequested);
    expect(preserved.safeMessage, 'Check your email.');
  });

  test('challenge expiry uses UTC instants at the boundary', () {
    final receipt = PasswordlessChallengeReceipt(
      email: 'person@example.com',
      expiresAt: DateTime.utc(2026, 8, 4, 18),
    );

    expect(receipt.isExpiredAt(DateTime.utc(2026, 8, 4, 17, 59)), isFalse);
    expect(receipt.isExpiredAt(DateTime.utc(2026, 8, 4, 18)), isTrue);
  });

  test('browser cookie grants reject exposed bearer secrets', () {
    final metadata = SessionMetadata(
      sessionId: 'session-1',
      deviceId: 'device-1',
      accessExpiresAt: DateTime.utc(2026, 8, 4, 18),
      transport: ClientSessionTransport.webCookie,
    );

    expect(
      () => SessionGrant(
        metadata: metadata,
        secrets: const SessionSecrets(accessToken: 'must-not-leak'),
      ),
      throwsArgumentError,
    );
  });
}
