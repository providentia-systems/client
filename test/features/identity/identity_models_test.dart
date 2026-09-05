import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

void main() {
  test('email-code view exposes deadlines without the binding proof', () {
    final created = DateTime.utc(2026, 9, 1);
    final request = PendingEmailCode(
      requestId: '0198a0b1-c2d3-7e4f-8123-456789abcdef',
      email: 'person@example.com',
      bindingToken: 'binding-token-000000000000000000000000000000',
      createdAt: created,
      expiresAt: created.add(const Duration(minutes: 10)),
      resendAt: created.add(const Duration(seconds: 60)),
    );
    final view = request.toPublicView();
    expect(view.email, request.email);
    expect(view.resendAt, created.add(const Duration(seconds: 60)));
    expect(view.isExpiredAt(created.add(const Duration(minutes: 9))), isFalse);
    expect(view.isExpiredAt(request.expiresAt), isTrue);
    expect(view.toString(), isNot(contains(request.bindingToken)));
    expect(request.toString(), isNot(contains(request.bindingToken)));
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

  test('durable session metadata accepts null expiry and never expires', () {
    final now = DateTime.utc(2026, 8, 9, 12);
    final durable = SessionMetadata(
      sessionId: '0198a0b1-c2d3-7e4f-8123-456789abcdea',
      deviceId: '0198a0b1-c2d3-7e4f-8123-456789abcdeb',
      userId: '0198a0b1-c2d3-7e4f-8123-456789abcdec',
      accessExpiresAt: now.add(const Duration(minutes: 15)),
      refreshExpiresAt: null,
      idleExpiresAt: null,
      refreshIdleTtl: null,
      transport: ClientSessionTransport.webCookie,
    );

    expect(durable.isDurable, isTrue);
    expect(durable.refreshExpiresAt, isNull);
    expect(durable.idleExpiresAt, isNull);
    expect(durable.refreshIdleTtl, isNull);
    expect(durable.isExpiredAt(now), isFalse);
    expect(durable.isExpiredAt(now.add(const Duration(days: 5000))), isFalse);
    final copied = durable.copyWith(
      activeHomeId: '0198a0b1-c2d3-7e4f-8123-456789abcded',
    );
    expect(copied.isDurable, isTrue);
    expect(copied.refreshIdleTtl, isNull);
  });

  test('bounded session metadata keeps its freshness deadline', () {
    final now = DateTime.utc(2026, 8, 9, 12);
    SessionMetadata bounded(Duration idleTtl) => SessionMetadata(
      sessionId: '0198a0b1-c2d3-7e4f-8123-456789abcdea',
      deviceId: '0198a0b1-c2d3-7e4f-8123-456789abcdeb',
      userId: '0198a0b1-c2d3-7e4f-8123-456789abcdec',
      accessExpiresAt: now.add(const Duration(minutes: 15)),
      refreshExpiresAt: now.add(idleTtl),
      idleExpiresAt: now.add(idleTtl),
      refreshIdleTtl: idleTtl,
      transport: ClientSessionTransport.nativeBearer,
    );

    final session = bounded(const Duration(days: 30));
    expect(session.isDurable, isFalse);
    expect(session.isExpiredAt(now), isFalse);
    expect(session.isExpiredAt(now.add(const Duration(days: 30))), isTrue);

    // The 30/60-day transport ceiling is gone: any server-selected finite
    // bound within the contract is accepted, including one beyond 60 days.
    expect(bounded(const Duration(days: 61)).isExpiredAt(now), isFalse);
    // A bounded window shorter than the contract's 15-minute floor is still
    // rejected as malformed.
    expect(() => bounded(const Duration(minutes: 14)), throwsArgumentError);
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

  test('durable device session stays active until it is revoked', () {
    final now = DateTime.utc(2026, 8, 9, 12);
    DeviceSessionView durable({DateTime? revokedAt}) => DeviceSessionView(
      id: '0198a0b1-c2d3-7e4f-8123-456789abcdea',
      deviceId: '0198a0b1-c2d3-7e4f-8123-456789abcdeb',
      deviceName: 'Trusted phone',
      platform: 'android',
      transport: ClientSessionTransport.nativeBearer,
      current: false,
      createdAt: now.subtract(const Duration(days: 400)),
      lastSeenAt: now.subtract(const Duration(days: 90)),
      accessExpiresAt: now.add(const Duration(minutes: 15)),
      refreshExpiresAt: null,
      idleExpiresAt: null,
      revokedAt: revokedAt,
    );

    expect(durable().isDurable, isTrue);
    expect(durable().isActiveAt(now), isTrue);
    expect(durable().isActiveAt(now.add(const Duration(days: 5000))), isTrue);
    expect(durable(revokedAt: now).isActiveAt(now), isFalse);

    final withActiveHome = durable().withActiveHome(
      '0198a0b1-c2d3-7e4f-8123-456789abcdec',
    );
    expect(withActiveHome.idleExpiresAt, isNull);
    expect(withActiveHome.refreshExpiresAt, isNull);
    expect(withActiveHome.isActiveAt(now), isTrue);
  });
}
