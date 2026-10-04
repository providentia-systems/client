import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/security/platform_offline_access_store.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/identity/application/offline_session_store.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

const userId = '11111111-1111-4111-8111-111111111111';
const sessionId = '22222222-2222-4222-8222-222222222222';
const deviceId = '33333333-3333-4333-8333-333333333333';
const homeId = '44444444-4444-4444-8444-444444444444';
final now = DateTime.utc(2026, 10, 4, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  PlatformOfflineAccessStore store({
    String host = 'a.example',
    bool enabled = true,
    DateTime Function()? clock,
  }) => PlatformOfflineAccessStore(
    origin: Uri.parse('https://$host'),
    enabled: enabled,
    clock: clock ?? () => now,
  );

  test(
    'roundtrips bounded identity without tokens or administrative roles',
    () async {
      final cache = store();
      await cache.write(lease());
      final saved = await cache.read();
      expect(saved!.user.userId, userId);
      expect(saved.session.activeHomeId, homeId);
      expect(saved.expiresAt, now.add(const Duration(hours: 24)));
      expect(saved.user.platformRoles, isEmpty);
      final encoded =
          (await const FlutterSecureStorage().readAll()).values.single;
      expect(encoded, isNot(contains('accessToken')));
      expect(encoded, isNot(contains('refreshToken')));
    },
  );

  test('origin isolation and explicit web disabled policy', () async {
    await store().write(lease());
    expect(await store(host: 'b.example').read(), isNull);
    final browser = store(enabled: false);
    expect(await browser.read(), isNull);
    await browser.clear();
    expect(await store().read(), isNotNull);
  });

  test(
    'home cache strips online-only permissions without elevating viewer',
    () async {
      final cache = store();
      await cache.write(lease());
      await cache.rememberHome(lease().session, home());
      final saved = await cache.readHome(lease().session, homeId);
      expect(saved!.effectivePermissions, <String>{
        'inventory.read',
        'shopping.read',
      });
      expect(saved.effectivePermissions, isNot(contains('members.manage')));
      expect(saved.effectivePermissions, isNot(contains('inventory.write')));
    },
  );

  test(
    'home requires exact session account installation and active home',
    () async {
      final cache = store();
      await cache.write(lease());
      await cache.rememberHome(lease().session, home());
      expect(
        await cache.readHome(lease(otherUser: true).session, homeId),
        isNull,
      );
      expect(await cache.readHome(lease().session, 'another-home'), isNull);
      await cache.write(lease(otherUser: true));
      expect(
        await cache.readHome(lease(otherUser: true).session, homeId),
        isNull,
      );
    },
  );

  test('expiry and clock rollback cannot unlock household cache', () async {
    var time = now;
    final cache = store(clock: () => time);
    await cache.write(lease());
    await cache.rememberHome(lease().session, home());
    time = now.subtract(const Duration(minutes: 1));
    expect(await cache.readHome(lease().session, homeId), isNull);
    time = now.add(const Duration(hours: 24));
    expect(await cache.readHome(lease().session, homeId), isNull);
  });

  test(
    'revoked home and logout permanently remove local-access lease',
    () async {
      final cache = store();
      await cache.write(lease());
      await cache.rememberHome(lease().session, home());
      await cache.revokeHome(homeId);
      expect(await cache.readHome(lease().session, homeId), isNull);
      await cache.clear();
      expect(await cache.read(), isNull);
    },
  );

  test('queued late writes cannot recreate lease after logout clear', () async {
    final cache = store();
    final write = cache.write(lease());
    final clear = cache.clear();
    await Future.wait<void>([write, clear]);
    expect(await cache.read(), isNull);
  });
}

HomeSummary home() => HomeSummary(
  id: homeId,
  name: 'Synthetic home',
  locale: 'en-NA',
  currency: 'NAD',
  timezone: 'Africa/Windhoek',
  role: HomeRole.viewer,
  revision: 1,
  effectivePermissions: <String>{
    'inventory.read',
    'shopping.read',
    'members.manage',
    'ai.use',
    'data.export',
  },
);
OfflineSessionLease lease({bool otherUser = false}) {
  final uid = otherUser ? '99999999-9999-4999-8999-999999999999' : userId;
  final metadata = SessionMetadata(
    sessionId: sessionId,
    deviceId: deviceId,
    userId: uid,
    accessExpiresAt: now.add(const Duration(minutes: 15)),
    refreshExpiresAt: null,
    idleExpiresAt: null,
    refreshIdleTtl: null,
    transport: ClientSessionTransport.nativeBearer,
    activeHomeId: homeId,
  );
  return OfflineSessionLease(
    session: metadata,
    user: CurrentUserView(
      userId: uid,
      email: 'synthetic@example.test',
      emailVerified: true,
      homes: [
        CurrentUserHomeView(id: homeId, name: 'Synthetic home', role: 'viewer'),
      ],
      pendingInvitations: const [],
      platformRoles: const {},
      profile: const {'onboardingComplete': true},
      activeHomeId: homeId,
      currentSession: DeviceSessionView(
        id: sessionId,
        deviceId: deviceId,
        deviceName: 'Synthetic',
        platform: 'linux',
        transport: ClientSessionTransport.nativeBearer,
        current: true,
        createdAt: now,
        lastSeenAt: now,
        accessExpiresAt: metadata.accessExpiresAt,
        refreshExpiresAt: null,
        idleExpiresAt: null,
        activeHomeId: homeId,
      ),
    ),
    verifiedAt: now,
    lastObservedAt: now,
    expiresAt: now.add(const Duration(hours: 24)),
  );
}
