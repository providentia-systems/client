import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/homes/application/home_ports.dart';
import 'package:providentia/features/homes/application/home_session_manager.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/presentation/home_selection_page.dart';
import 'package:providentia/features/homes/presentation/homes_controller.dart';
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/application/identity_session_manager.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia/features/identity/presentation/identity_controller.dart';
import 'package:providentia/features/identity/presentation/passwordless_sign_in_page.dart';

void main() {
  testWidgets('passwordless page keeps challenge response non-enumerating', (
    tester,
  ) async {
    final manager = IdentitySessionManager(
      transport: _PresentationIdentityTransport(),
      credentialStore: _PresentationCredentialStore(),
      device: DeviceDescriptor(
        id: 'device-1',
        name: 'Test device',
        platform: 'test',
      ),
    );
    final controller = IdentityController(manager);
    addTearDown(() async {
      controller.dispose();
      await manager.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PasswordlessSignInPage(
          controller: controller,
          restoreOnStart: false,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('identity-email')),
      'person@example.com',
    );
    await tester.tap(find.byKey(const Key('identity-request-link')));
    await tester.pumpAndSettle();

    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.text(
        'If the address can receive email, a sign-in link has been sent.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('identity-one-time-code')), findsOneWidget);
  });

  testWidgets('home page creates and opens the first authorized home', (
    tester,
  ) async {
    final manager = HomeSessionManager(
      transport: _PresentationHomeTransport(),
      activeHomeStore: _PresentationActiveHomeStore(),
    );
    final controller = HomesController(manager);
    addTearDown(() async {
      controller.dispose();
      await manager.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HomeSelectionPage(
          controller: controller,
          loadOnStart: false,
          activeHomeBuilder: (context, home) =>
              Scaffold(body: Center(child: Text('Opened ${home.name}'))),
        ),
      ),
    );
    expect(find.text('Create your first home'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('create-home-name')),
      'Family pantry',
    );
    await tester.tap(find.byKey(const Key('create-home-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Opened Family pantry'), findsOneWidget);
  });
}

final class _PresentationCredentialStore implements SessionCredentialStore {
  StoredNativeSession? _stored;

  @override
  bool get supportsPersistentSecrets => true;

  @override
  Future<void> clear() async => _stored = null;

  @override
  Future<StoredNativeSession?> read() async => _stored;

  @override
  Future<void> write(StoredNativeSession session) async => _stored = session;
}

final class _PresentationIdentityTransport implements IdentityTransportPort {
  @override
  ClientSessionTransport get sessionTransport =>
      ClientSessionTransport.nativeBearer;

  @override
  Future<SessionGrant> completePasswordlessChallenge({
    required PasswordlessProof proof,
    required DeviceDescriptor device,
  }) async {
    return SessionGrant(
      metadata: SessionMetadata(
        sessionId: 'session-1',
        deviceId: device.id,
        accessExpiresAt: DateTime.utc(2026, 8, 4, 13),
        transport: sessionTransport,
      ),
      secrets: const SessionSecrets(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      ),
    );
  }

  @override
  Future<List<DeviceSessionView>> listDeviceSessions({
    String? accessToken,
    String? csrfToken,
  }) async => <DeviceSessionView>[];

  @override
  Future<void> logout({String? accessToken, String? csrfToken}) async {}

  @override
  Future<SessionGrant> refreshSession({String? refreshToken}) {
    throw UnimplementedError();
  }

  @override
  Future<PasswordlessChallengeReceipt> requestPasswordlessChallenge({
    required String email,
  }) async {
    return PasswordlessChallengeReceipt(
      email: email,
      challengeId: 'challenge-1',
      expiresAt: DateTime.utc(2026, 8, 4, 13),
    );
  }

  @override
  Future<void> revokeDeviceSession({
    required String sessionId,
    String? accessToken,
    String? csrfToken,
  }) async {}
}

final class _PresentationActiveHomeStore implements ActiveHomeStore {
  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String homeId) async => value = homeId;
}

final class _PresentationHomeTransport
    implements HomeTransportPort, HomeInvitationAdministrationPort {
  final List<HomeSummary> _homes = <HomeSummary>[];

  @override
  Future<HomeSummary> acceptInvitation(String token) async => _homes.first;

  @override
  Future<void> changeMembershipRole({
    required String homeId,
    required String userId,
    required HomeRole role,
    required int expectedRevision,
  }) async {}

  @override
  Future<HomeSummary> createHome(CreateHomeCommand command) async {
    final home = HomeSummary(
      id: 'home-1',
      name: command.name,
      locale: command.locale,
      currency: command.currency,
      timezone: command.timezone,
      role: HomeRole.owner,
      revision: 1,
    );
    _homes.add(home);
    return home;
  }

  @override
  Future<HomeInvitation> createInvitation({
    required String homeId,
    required String email,
    required HomeRole role,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> leaveHome(String homeId) async {}

  @override
  Future<List<HomeSummary>> listHomes() async => List<HomeSummary>.of(_homes);

  @override
  Future<List<HomeInvitation>> listInvitations(String homeId) async =>
      <HomeInvitation>[];

  @override
  Future<List<HomeMembership>> listMemberships(String homeId) async =>
      <HomeMembership>[];

  @override
  Future<void> revokeInvitation({
    required String homeId,
    required String invitationId,
    required int expectedRevision,
  }) async {}

  @override
  Future<HomeSummary> switchActiveHome(String homeId) async =>
      _homes.firstWhere((home) => home.id == homeId);
}
