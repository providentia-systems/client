import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia/features/identity/infrastructure/secure_login_link_request_factory.dart';

void main() {
  test(
    'secure factory creates origin-only proof and distinct S256 challenges',
    () {
      final factory = SecureLoginLinkRequestFactory();
      final request = factory.create(
        email: 'Person@Example.com',
        createdAt: DateTime.utc(2026, 8, 9, 12),
        expiresAt: DateTime.utc(2026, 8, 9, 12, 15),
        pollInterval: const Duration(seconds: 3),
      );

      expect(request.email, 'person@example.com');
      expect(request.requestId, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(request.pollToken.length, greaterThanOrEqualTo(43));
      expect(request.codeVerifier.length, greaterThanOrEqualTo(43));
      expect(request.state.length, greaterThanOrEqualTo(32));
      expect(factory.challenge(request.pollToken), hasLength(43));
      expect(factory.challenge(request.codeVerifier), hasLength(43));
      expect(
        factory.challenge(request.pollToken),
        isNot(factory.challenge(request.codeVerifier)),
      );
    },
  );

  test('server receipt cannot replace the client request identity', () {
    final factory = SecureLoginLinkRequestFactory();
    final request = factory.create(
      email: 'person@example.com',
      createdAt: DateTime.utc(2026, 8, 9, 12),
      expiresAt: DateTime.utc(2026, 8, 9, 12, 15),
      pollInterval: const Duration(seconds: 3),
    );

    expect(
      () => request.withServerReceipt(
        LoginLinkStartReceipt(
          requestId: '0198a0b1-c2d3-7e4f-8123-456789abcdef',
          expiresAt: DateTime.utc(2026, 8, 9, 12, 15),
          pollInterval: const Duration(seconds: 3),
        ),
      ),
      throwsFormatException,
    );
  });

  test('web cookie grant rejects bearer credentials', () {
    final now = DateTime.utc(2026, 8, 9, 12);
    expect(
      () => SessionGrant(
        metadata: SessionMetadata(
          sessionId: '0198a0b1-c2d3-7e4f-8123-456789abcdea',
          deviceId: '0198a0b1-c2d3-7e4f-8123-456789abcdeb',
          userId: '0198a0b1-c2d3-7e4f-8123-456789abcdec',
          accessExpiresAt: now.add(const Duration(minutes: 15)),
          refreshExpiresAt: now.add(const Duration(days: 30)),
          idleExpiresAt: now.add(const Duration(days: 30)),
          refreshIdleTtl: const Duration(days: 30),
          transport: ClientSessionTransport.webCookie,
        ),
        secrets: const SessionSecrets(accessToken: 'must-not-be-exposed'),
      ),
      throwsArgumentError,
    );
  });

  test('session metadata enforces backend idle policy range', () {
    final now = DateTime.utc(2026, 8, 9, 12);
    expect(
      () => SessionMetadata(
        sessionId: '0198a0b1-c2d3-7e4f-8123-456789abcdea',
        deviceId: '0198a0b1-c2d3-7e4f-8123-456789abcdeb',
        userId: '0198a0b1-c2d3-7e4f-8123-456789abcdec',
        accessExpiresAt: now,
        refreshExpiresAt: now,
        idleExpiresAt: now,
        refreshIdleTtl: const Duration(days: 61),
        transport: ClientSessionTransport.nativeBearer,
      ),
      throwsArgumentError,
    );
    expect(
      () => SessionMetadata(
        sessionId: '0198a0b1-c2d3-7e4f-8123-456789abcdea',
        deviceId: '0198a0b1-c2d3-7e4f-8123-456789abcdeb',
        userId: '0198a0b1-c2d3-7e4f-8123-456789abcdec',
        accessExpiresAt: now,
        refreshExpiresAt: now,
        idleExpiresAt: now,
        refreshIdleTtl: const Duration(days: 31),
        transport: ClientSessionTransport.webCookie,
      ),
      throwsArgumentError,
    );
  });

  test('signed-in device activity requires both unexpired session limits', () {
    final now = DateTime.utc(2026, 8, 9, 12);
    DeviceSessionView session({
      DateTime? idleExpiresAt,
      DateTime? refreshExpiresAt,
      DateTime? revokedAt,
    }) => DeviceSessionView(
      id: '0198a0b1-c2d3-7e4f-8123-456789abcdea',
      deviceId: '0198a0b1-c2d3-7e4f-8123-456789abcdeb',
      deviceName: 'Test device',
      platform: 'linux',
      transport: ClientSessionTransport.nativeBearer,
      current: true,
      createdAt: now.subtract(const Duration(days: 1)),
      lastSeenAt: now,
      accessExpiresAt: now.add(const Duration(minutes: 15)),
      refreshExpiresAt: refreshExpiresAt ?? now.add(const Duration(days: 60)),
      idleExpiresAt: idleExpiresAt ?? now.add(const Duration(days: 60)),
      revokedAt: revokedAt,
    );

    expect(session().isActiveAt(now), isTrue);
    expect(
      session(
        idleExpiresAt: now.subtract(const Duration(seconds: 1)),
      ).isActiveAt(now),
      isFalse,
    );
    expect(session(refreshExpiresAt: now).isActiveAt(now), isFalse);
    expect(session(revokedAt: now).isActiveAt(now), isFalse);
  });
}
