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
import 'package:providentia/features/identity/presentation/account_access_page.dart';
import 'package:providentia/features/identity/presentation/device_sessions_page.dart';
import 'package:providentia/features/identity/presentation/identity_controller.dart';
import 'package:providentia/features/identity/presentation/login_link_sign_in_page.dart';

void main() {
  testWidgets('production sign-in is email-only and non-enumerating', (
    tester,
  ) async {
    final identity = _IdentityFixture();
    addTearDown(identity.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginLinkSignInPage(
          controller: identity.controller,
          restoreOnStart: false,
        ),
      ),
    );

    expect(
      find.text('Enter your email. No password is needed.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('development password'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('identity-email')),
      'person@example.com',
    );
    await tester.tap(find.byKey(const Key('identity-request-login-link')));
    await tester.pump();

    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('on any device'), findsOneWidget);
    expect(find.textContaining('whether this address is new'), findsNothing);
    expect(find.byKey(const Key('identity-check-login-link')), findsOneWidget);
    expect(find.byKey(const Key('identity-cancel-login-link')), findsOneWidget);
    await identity.controller.cancelLoginLink();
    await tester.pump();
  });

  testWidgets('sign-in never renders any password affordance', (tester) async {
    final identity = _IdentityFixture();
    addTearDown(identity.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginLinkSignInPage(
          controller: identity.controller,
          restoreOnStart: false,
        ),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.byKey(const Key('identity-toggle-development-password')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('identity-development-password')),
      findsNothing,
    );
    expect(find.textContaining('password'), findsOneWidget);
    expect(
      find.text('Enter your email. No password is needed.'),
      findsOneWidget,
    );
  });

  testWidgets('device list renders durable sessions without an idle deadline', (
    tester,
  ) async {
    final identity = _AuthenticatedIdentityFixture();
    addTearDown(identity.dispose);
    await identity.controller.restore();

    await tester.pumpWidget(
      MaterialApp(home: DeviceSessionsPage(controller: identity.controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Durable phone'), findsOneWidget);
    expect(find.textContaining('Signed in until you sign out'), findsOneWidget);
    expect(find.textContaining('30 days'), findsNothing);
    expect(find.textContaining('60 days'), findsNothing);
    final boundedCard = find.byKey(
      const Key('device-session-$_remoteSessionId'),
    );
    expect(
      find.descendant(
        of: boundedCard,
        matching: find.textContaining('Idle deadline'),
      ),
      findsOneWidget,
    );
    expect(find.text('Expired browser'), findsNothing);
  });

  testWidgets('chooser exposes recipient invitations and accepts by revision', (
    tester,
  ) async {
    final homes = _HomeFixture(withInvitation: true, existingHomes: 2);
    addTearDown(homes.dispose);
    await tester.pumpWidget(
      MaterialApp(home: HomeSelectionPage(controller: homes.controller)),
    );
    await tester.pump();

    expect(find.text('Invitation to Shared pantry'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pump();
    await tester.pump();

    expect(homes.transport.acceptedRevision, 3);
    expect(homes.controller.snapshot.activeHome?.name, 'Shared pantry');
  });

  testWidgets('home chooser keeps account and sign-out available', (
    tester,
  ) async {
    final homes = _HomeFixture();
    addTearDown(homes.dispose);
    var signedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeSelectionPage(
          controller: homes.controller,
          loadOnStart: false,
          accountPageBuilder: (_) => const Scaffold(body: Text('Account page')),
          onSignOut: () async => signedOut = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('home-chooser-account-access')));
    await tester.pumpAndSettle();
    expect(find.text('Account page'), findsOneWidget);
    Navigator.of(tester.element(find.text('Account page'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-chooser-sign-out')));
    await tester.pump();
    expect(signedOut, isTrue);
  });

  testWidgets('account access lists and revokes only active devices', (
    tester,
  ) async {
    final identity = _AuthenticatedIdentityFixture();
    final homes = _HomeFixture(existingHomes: 1);
    addTearDown(identity.dispose);
    addTearDown(homes.dispose);
    await identity.controller.restore();
    await homes.controller.load(sessionActiveHomeId: 'home-0');
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessPage(
          identityController: identity.controller,
          homesController: homes.controller,
        ),
      ),
    );

    expect(find.text('person@example.com'), findsOneWidget);
    expect(find.text('Home 0 · member'), findsOneWidget);
    expect(find.byKey(const Key('open-signed-in-devices')), findsOneWidget);
    expect(find.byKey(const Key('open-home-governance')), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-signed-in-devices')));
    await tester.pumpAndSettle();

    expect(find.text('Test device · current device'), findsOneWidget);
    expect(find.text('Shared tablet'), findsOneWidget);
    expect(find.text('Expired browser'), findsNothing);
    await tester.tap(
      find.byKey(const Key('revoke-device-session-$_remoteSessionId')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Revoke this device?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(identity.transport.revokedSessionIds, isEmpty);

    await tester.tap(
      find.byKey(const Key('revoke-device-session-$_remoteSessionId')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();

    expect(identity.transport.revokedSessionIds, <String>[_remoteSessionId]);
    expect(find.text('Shared tablet'), findsNothing);
    expect(find.text('Test device · current device'), findsOneWidget);
  });

  testWidgets('platform roles never expose administration in homeowner UI', (
    tester,
  ) async {
    final identity = _AuthenticatedIdentityFixture(
      platformRoles: const <PlatformRole>{
        PlatformRole.platformAdministrator,
        PlatformRole.catalogCurator,
        PlatformRole.catalogReviewer,
        PlatformRole.billingOperator,
      },
    );
    final homes = _HomeFixture(existingHomes: 1);
    addTearDown(identity.dispose);
    addTearDown(homes.dispose);
    await identity.controller.restore();
    await homes.controller.load(sessionActiveHomeId: 'home-0');

    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessPage(
          identityController: identity.controller,
          homesController: homes.controller,
        ),
      ),
    );

    expect(find.text('Catalog administration'), findsNothing);
    expect(find.text('Platform administrators'), findsNothing);
    expect(find.textContaining('operator', findRichText: true), findsNothing);
    expect(find.byKey(const Key('open-signed-in-devices')), findsOneWidget);
  });

  testWidgets(
    'catalog contributors can reach all homeowner contribution routes',
    (tester) async {
      final identity = _AuthenticatedIdentityFixture();
      final homes = _HomeFixture();
      homes.transport.homes.add(
        HomeSummary(
          id: 'owner-home',
          name: 'Owner home',
          locale: 'en-NA',
          currency: 'NAD',
          timezone: 'Africa/Windhoek',
          role: HomeRole.owner,
          revision: 1,
        ),
      );
      addTearDown(identity.dispose);
      addTearDown(homes.dispose);
      await identity.controller.restore();
      await homes.controller.load(sessionActiveHomeId: 'owner-home');

      await tester.pumpWidget(
        MaterialApp(
          home: AccountAccessPage(
            identityController: identity.controller,
            homesController: homes.controller,
            catalogContributionPageBuilder: (_) =>
                const Scaffold(body: Text('Product contribution route')),
            catalogProductImageContributionPageBuilder: (_) =>
                const Scaffold(body: Text('Product image contribution route')),
            catalogStorePriceContributionPageBuilder: (_) =>
                const Scaffold(body: Text('Store price contribution route')),
          ),
        ),
      );

      expect(
        find.byKey(const Key('open-catalog-product-contribution')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('open-catalog-product-image-contribution')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('open-catalog-store-price-contribution')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('open-catalog-product-image-contribution')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Product image contribution route'), findsOneWidget);
    },
  );

  testWidgets(
    'data governance remains account-accessible without a selected home',
    (tester) async {
      final identity = _AuthenticatedIdentityFixture();
      final homes = _HomeFixture();
      addTearDown(identity.dispose);
      addTearDown(homes.dispose);
      await identity.controller.restore();
      await tester.pumpWidget(
        MaterialApp(
          home: AccountAccessPage(
            identityController: identity.controller,
            homesController: homes.controller,
            householdReportsPageBuilder: (_) =>
                const Scaffold(body: Text('Reports route')),
            householdAiPageBuilder: (_) =>
                const Scaffold(body: Text('Household AI route')),
            dataGovernancePageBuilder: (_) =>
                const Scaffold(body: Text('Data governance route')),
          ),
        ),
      );

      expect(find.byKey(const Key('open-data-governance')), findsOneWidget);
      expect(find.byKey(const Key('open-household-reports')), findsNothing);
      expect(find.byKey(const Key('open-household-ai')), findsNothing);
      await tester.tap(find.byKey(const Key('open-data-governance')));
      await tester.pumpAndSettle();
      expect(find.text('Data governance route'), findsOneWidget);
    },
  );

  testWidgets('household reports and AI require exact home permissions', (
    tester,
  ) async {
    final identity = _AuthenticatedIdentityFixture();
    final homes = _HomeFixture();
    homes.transport.homes.add(
      HomeSummary(
        id: 'owner-home',
        name: 'Owner home',
        locale: 'en-NA',
        currency: 'NAD',
        timezone: 'Africa/Windhoek',
        role: HomeRole.owner,
        revision: 1,
      ),
    );
    addTearDown(identity.dispose);
    addTearDown(homes.dispose);
    await identity.controller.restore();
    await homes.controller.load(sessionActiveHomeId: 'owner-home');
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessPage(
          identityController: identity.controller,
          homesController: homes.controller,
          householdReportsPageBuilder: (_) =>
              const Scaffold(body: Text('Reports route')),
          householdAiPageBuilder: (_) =>
              const Scaffold(body: Text('Household AI route')),
          dataGovernancePageBuilder: (_) =>
              const Scaffold(body: Text('Data governance route')),
        ),
      ),
    );

    expect(find.byKey(const Key('open-household-reports')), findsOneWidget);
    expect(find.byKey(const Key('open-household-ai')), findsOneWidget);
    expect(find.byKey(const Key('open-data-governance')), findsOneWidget);
    expect(
      mayAccessHouseholdReports(const <String>{'reports.read.extra'}),
      isFalse,
    );
    expect(
      mayAccessHouseholdReports(const <String>{HomePermissions.reportsRead}),
      isTrue,
    );
    expect(mayAccessHouseholdAi(const <String>{'ai.read.extra'}), isFalse);
    expect(
      mayAccessHouseholdAi(const <String>{HomePermissions.aiRead}),
      isTrue,
    );
  });

  test(
    'device-management failure preserves an authenticated account',
    () async {
      final identity = _AuthenticatedIdentityFixture();
      addTearDown(identity.dispose);
      await identity.controller.restore();
      identity.transport.deviceListError = const IdentityTransportException(
        kind: IdentityFailureKind.network,
        safeMessage: 'Devices are temporarily unavailable.',
      );

      await identity.controller.loadDeviceSessions();

      expect(identity.controller.snapshot.isAuthenticated, isTrue);
      expect(
        identity.controller.snapshot.safeMessage,
        'Devices are temporarily unavailable.',
      );
    },
  );

  testWidgets('first home creation opens the owner workspace', (tester) async {
    final homes = _HomeFixture();
    addTearDown(homes.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeSelectionPage(
          controller: homes.controller,
          loadOnStart: false,
          activeHomeBuilder: (context, home) =>
              Scaffold(body: Text('Opened ${home.name} as ${home.role.name}')),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('create-home-name')),
      'Family pantry',
    );
    await tester.tap(find.byKey(const Key('create-home-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Opened Family pantry as owner'), findsOneWidget);
  });

  testWidgets(
    'a sibling active-home broadcast closes and reconciles the old workspace',
    (tester) async {
      final firstTransport =
          _PresentationHomeTransport(withInvitation: false, existingHomes: 0)
            ..homes.addAll(<HomeSummary>[
              _home('home-a', 'Home A'),
              _home('home-b', 'Home B'),
            ]);
      final secondTransport =
          _PresentationHomeTransport(withInvitation: false, existingHomes: 0)
            ..homes.addAll(<HomeSummary>[
              _home('home-a', 'Home A'),
              _home('home-b', 'Home B'),
            ]);
      final firstManager = HomeSessionManager(
        transport: firstTransport,
        activeHomeStore: _MemoryActiveHomeStore(),
      );
      final secondManager = HomeSessionManager(
        transport: secondTransport,
        activeHomeStore: _MemoryActiveHomeStore(),
      );
      final firstController = HomesController(firstManager);
      final secondController = HomesController(secondManager);
      addTearDown(() async {
        firstController.dispose();
        secondController.dispose();
        await firstManager.dispose();
        await secondManager.dispose();
      });
      await firstController.load(sessionActiveHomeId: 'home-a');

      var sessionActiveHomeId = 'home-a';
      late StateSetter rebuild;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return MaterialApp(
              home: HomeSelectionPage(
                controller: secondController,
                sessionActiveHomeId: sessionActiveHomeId,
                activeHomeBuilder: (context, home) =>
                    Scaffold(body: Text('Opened ${home.name}')),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Opened Home A'), findsOneWidget);

      await firstController.selectHome('home-b');
      rebuild(() => sessionActiveHomeId = 'home-b');
      await tester.pump();

      expect(find.text('Opened Home A'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Opened Home B'), findsOneWidget);
      expect(firstTransport.switches, <String>['home-b']);
      expect(secondTransport.switches, isEmpty);
    },
  );
}

const _requestId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const _pollToken = 'poll-token-000000000000000000000000000000000';
const _verifier =
    'code-verifier-000000000000000000000000000000000000000000000000';
const _state = 'login-state-000000000000000000000000000000000';

final class _IdentityFixture {
  _IdentityFixture() : transport = _PresentationIdentityTransport() {
    manager = IdentitySessionManager(
      transport: transport,
      credentialStore: _MemoryCredentialStore(),
      pendingLoginLinkStore: _MemoryPendingStore(),
      loginLinkRequestFactory: _RequestFactory(),
      device: DeviceDescriptor(
        id: '0198a0b1-c2d3-7e4f-8123-456789abcdeb',
        name: 'Test device',
        platform: 'test',
      ),
      defaultPollInterval: const Duration(seconds: 30),
      maximumPollInterval: const Duration(seconds: 30),
    );
    controller = IdentityController(manager);
  }

  final IdentityTransportPort transport;
  late final IdentitySessionManager manager;
  late final IdentityController controller;

  Future<void> dispose() async {
    controller.dispose();
    await manager.dispose();
  }
}

final class _AuthenticatedIdentityFixture {
  _AuthenticatedIdentityFixture({
    Set<PlatformRole> platformRoles = const <PlatformRole>{},
  }) : transport = _AuthenticatedPresentationIdentityTransport(
         DateTime.now().toUtc(),
         platformRoles,
       ),
       credentials = _StoredCredentialStore(
         StoredNativeSession(
           sessionId: _identitySessionId,
           deviceId: _identityDeviceId,
           refreshToken: 'saved-refresh-token',
         ),
       ) {
    manager = IdentitySessionManager(
      transport: transport,
      credentialStore: credentials,
      pendingLoginLinkStore: _MemoryPendingStore(),
      loginLinkRequestFactory: _RequestFactory(),
      device: DeviceDescriptor(
        id: _identityDeviceId,
        name: 'Test device',
        platform: 'test',
      ),
      defaultPollInterval: const Duration(seconds: 30),
      maximumPollInterval: const Duration(seconds: 30),
    );
    controller = IdentityController(manager);
  }

  final _AuthenticatedPresentationIdentityTransport transport;
  final _StoredCredentialStore credentials;
  late final IdentitySessionManager manager;
  late final IdentityController controller;

  Future<void> dispose() async {
    controller.dispose();
    await manager.dispose();
  }
}

class _PresentationIdentityTransport implements IdentityTransportPort {
  @override
  ClientSessionTransport get sessionTransport =>
      ClientSessionTransport.nativeBearer;

  @override
  Future<LoginLinkStartReceipt> startLoginLink(
    LoginLinkStartCommand command,
  ) async => LoginLinkStartReceipt(
    requestId: command.requestId,
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
    pollInterval: const Duration(seconds: 30),
  );

  @override
  Future<LoginLinkStatusView> getLoginLinkStatus({
    required String requestId,
    required String pollToken,
  }) async => LoginLinkStatusView(
    requestId: requestId,
    status: LoginLinkRequestStatus.pending,
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
  );

  @override
  Future<SessionGrant> exchangeLoginLink({
    required PendingLoginLinkRequest request,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelLoginLink({
    required String requestId,
    required String pollToken,
  }) async {}

  @override
  Future<SessionGrant> refreshSession({String? refreshToken}) =>
      throw UnimplementedError();

  @override
  Future<CurrentUserView> getCurrentUser({
    String? accessToken,
    String? csrfToken,
  }) => throw UnimplementedError();

  @override
  Future<void> logout({
    String? accessToken,
    String? refreshToken,
    String? csrfToken,
  }) async {}

  @override
  Future<List<DeviceSessionView>> listDeviceSessions({
    String? accessToken,
    String? csrfToken,
  }) async => const <DeviceSessionView>[];

  @override
  Future<void> revokeDeviceSession({
    required String sessionId,
    String? accessToken,
    String? csrfToken,
  }) async {}
}

final class _AuthenticatedPresentationIdentityTransport
    extends _PresentationIdentityTransport {
  _AuthenticatedPresentationIdentityTransport(this.now, this.platformRoles)
    : sessions = <DeviceSessionView>[
        _identityDeviceSession(
          now,
          id: _identitySessionId,
          deviceId: _identityDeviceId,
          deviceName: 'Test device',
          platform: 'linux',
          current: true,
        ),
        _identityDeviceSession(
          now,
          id: _remoteSessionId,
          deviceId: _remoteDeviceId,
          deviceName: 'Shared tablet',
          platform: 'android',
        ),
        _identityDeviceSession(
          now,
          id: _expiredSessionId,
          deviceId: _expiredDeviceId,
          deviceName: 'Expired browser',
          platform: 'web',
          expired: true,
        ),
        _identityDeviceSession(
          now,
          id: _durableSessionId,
          deviceId: _durableDeviceId,
          deviceName: 'Durable phone',
          platform: 'android',
          durable: true,
        ),
      ];

  final DateTime now;
  final Set<PlatformRole> platformRoles;
  final List<DeviceSessionView> sessions;
  final List<String> revokedSessionIds = <String>[];
  IdentityTransportException? deviceListError;

  @override
  Future<SessionGrant> refreshSession({String? refreshToken}) async =>
      _identityGrant(now);

  @override
  Future<CurrentUserView> getCurrentUser({
    String? accessToken,
    String? csrfToken,
  }) async => CurrentUserView(
    userId: _identityUserId,
    email: 'person@example.com',
    emailVerified: true,
    homes: const <CurrentUserHomeView>[],
    pendingInvitations: const <CurrentUserInvitationView>[],
    platformRoles: platformRoles,
    currentSession: sessions.singleWhere((session) => session.current),
  );

  @override
  Future<List<DeviceSessionView>> listDeviceSessions({
    String? accessToken,
    String? csrfToken,
  }) async {
    if (deviceListError case final error?) throw error;
    return List<DeviceSessionView>.of(sessions);
  }

  @override
  Future<void> revokeDeviceSession({
    required String sessionId,
    String? accessToken,
    String? csrfToken,
  }) async {
    revokedSessionIds.add(sessionId);
    sessions.removeWhere((session) => session.id == sessionId);
  }
}

final class _RequestFactory implements LoginLinkRequestFactory {
  @override
  String challenge(String secret) =>
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  @override
  PendingLoginLinkRequest create({
    required String email,
    required DateTime createdAt,
    required DateTime expiresAt,
    required Duration pollInterval,
  }) => PendingLoginLinkRequest(
    requestId: _requestId,
    email: email,
    pollToken: _pollToken,
    codeVerifier: _verifier,
    state: _state,
    createdAt: createdAt,
    expiresAt: expiresAt,
    pollInterval: pollInterval,
  );
}

final class _MemoryPendingStore implements PendingLoginLinkStore {
  PendingLoginLinkRequest? value;
  bool logoutIntent = false;
  BrowserCookieMutationJournal? cookieMutation;
  @override
  Future<void> clear({PendingLoginLinkRequest? request}) async {
    if (request == null || value?.requestId == request.requestId) value = null;
  }

  @override
  Future<void> invalidate(PendingLoginLinkRequest request) async =>
      value = null;

  @override
  Future<bool> hasLogoutIntent() async => logoutIntent;

  @override
  Future<void> markLogoutIntent() async => logoutIntent = true;

  @override
  Future<void> clearLogoutIntent() async => logoutIntent = false;
  @override
  Future<BrowserCookieMutationJournal?> readCookieMutation() async =>
      cookieMutation;
  @override
  Future<void> beginCookieMutation(
    BrowserCookieMutationJournal journal,
  ) async => cookieMutation = journal;
  @override
  Future<void> clearCookieMutation({
    BrowserCookieMutationJournal? journal,
  }) async {
    if (journal == null || cookieMutation?.operationId == journal.operationId) {
      cookieMutation = null;
    }
  }

  @override
  Future<PendingLoginLinkRequest?> read() async => value;
  @override
  Future<void> write(
    PendingLoginLinkRequest request, {
    required bool activate,
  }) async => value = request;
}

final class _MemoryCredentialStore implements SessionCredentialStore {
  @override
  bool get supportsPersistentSecrets => true;
  @override
  Future<void> clear() async {}
  @override
  Future<StoredNativeSession?> read() async => null;
  @override
  Future<void> write(StoredNativeSession session) async {}
}

final class _StoredCredentialStore implements SessionCredentialStore {
  _StoredCredentialStore(this.value);

  StoredNativeSession? value;

  @override
  bool get supportsPersistentSecrets => true;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<StoredNativeSession?> read() async => value;

  @override
  Future<void> write(StoredNativeSession session) async => value = session;
}

final class _HomeFixture {
  _HomeFixture({bool withInvitation = false, int existingHomes = 0})
    : transport = _PresentationHomeTransport(
        withInvitation: withInvitation,
        existingHomes: existingHomes,
      ) {
    manager = HomeSessionManager(
      transport: transport,
      activeHomeStore: _MemoryActiveHomeStore(),
    );
    controller = HomesController(manager);
  }

  final _PresentationHomeTransport transport;
  late final HomeSessionManager manager;
  late final HomesController controller;

  Future<void> dispose() async {
    controller.dispose();
    await manager.dispose();
  }
}

final class _MemoryActiveHomeStore implements ActiveHomeStore {
  String? value;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String homeId) async => value = homeId;
}

final class _PresentationHomeTransport implements HomeTransportPort {
  _PresentationHomeTransport({
    required bool withInvitation,
    required int existingHomes,
  }) : invitations = withInvitation
           ? <RecipientHomeInvitation>[
               RecipientHomeInvitation(
                 id: 'invitation-id',
                 homeId: 'shared-home',
                 homeName: 'Shared pantry',
                 inviterUserId: 'inviter-id',
                 role: HomeRole.member,
                 expiresAt: DateTime.utc(2026, 8, 20),
                 revision: 3,
               ),
             ]
           : <RecipientHomeInvitation>[] {
    for (var index = 0; index < existingHomes; index++) {
      homes.add(_home('home-$index', 'Home $index'));
    }
  }

  final List<HomeSummary> homes = <HomeSummary>[];
  final List<RecipientHomeInvitation> invitations;
  final List<String> switches = <String>[];
  int? acceptedRevision;

  @override
  Future<List<HomeSummary>> listHomes() async => List<HomeSummary>.of(homes);
  @override
  Future<HomeSummary> createHome(CreateHomeCommand command) async {
    final created = HomeSummary(
      id: 'created-home',
      name: command.name,
      locale: command.locale,
      currency: command.currency,
      timezone: command.timezone,
      role: HomeRole.owner,
      revision: 1,
    );
    homes.add(created);
    return created;
  }

  @override
  Future<HomeSummary> switchActiveHome(String homeId) async {
    switches.add(homeId);
    return homes.firstWhere((home) => home.id == homeId);
  }

  @override
  Future<HomeSummary> updateHome({
    required String homeId,
    required String name,
    required String locale,
    required String currency,
    required String timezone,
    required int expectedRevision,
  }) => throw UnimplementedError();
  @override
  Future<List<HomeMembership>> listMemberships(String homeId) async =>
      const <HomeMembership>[];
  @override
  Future<void> changeMembershipRole({
    required String homeId,
    required String userId,
    required HomeRole role,
    required int expectedRevision,
  }) async {}
  @override
  Future<HomeInvitation> createInvitation({
    required String homeId,
    required String email,
    required HomeRole role,
  }) => throw UnimplementedError();
  @override
  Future<List<HomeInvitation>> listInvitations(String homeId) async =>
      const <HomeInvitation>[];
  @override
  Future<void> revokeInvitation({
    required String homeId,
    required String invitationId,
    required int expectedRevision,
  }) async {}
  @override
  Future<List<RecipientHomeInvitation>> listPendingInvitations() async =>
      List<RecipientHomeInvitation>.of(invitations);
  @override
  Future<HomeSummary> acceptPendingInvitation({
    required String invitationId,
    required int expectedRevision,
  }) async {
    acceptedRevision = expectedRevision;
    invitations.clear();
    final accepted = _home('shared-home', 'Shared pantry');
    homes.add(accepted);
    return accepted;
  }

  @override
  Future<List<HomePermissionPolicy>> listPermissionPolicies(
    String homeId,
  ) async => const <HomePermissionPolicy>[];
  @override
  Future<HomePermissionPolicy> putPermissionPolicy({
    required String homeId,
    required HomeRole role,
    required Set<String> permissions,
    required int expectedRevision,
  }) => throw UnimplementedError();
  @override
  Future<void> removeHomeMembership({
    required String homeId,
    required String userId,
    required int expectedRevision,
  }) => throw UnimplementedError();
  @override
  Future<List<HomeOwnershipTransfer>> listHomeOwnershipTransfers(
    String homeId,
  ) async => const <HomeOwnershipTransfer>[];
  @override
  Future<StepUpLinkReceipt> requestStepUpLink() => throw UnimplementedError();
  @override
  Future<HomeOwnershipTransfer> proposeHomeOwnershipTransfer({
    required String homeId,
    required String targetUserId,
    required int expectedTargetRevision,
    required String stepUpToken,
  }) => throw UnimplementedError();
  @override
  Future<void> acceptHomeOwnershipTransfer({
    required String homeId,
    required String transferId,
    required int expectedRevision,
  }) => throw UnimplementedError();
  @override
  Future<void> rejectHomeOwnershipTransfer({
    required String homeId,
    required String transferId,
    required int expectedRevision,
  }) => throw UnimplementedError();
  @override
  Future<void> revokeHomeOwnershipTransfer({
    required String homeId,
    required String transferId,
    required int expectedRevision,
  }) => throw UnimplementedError();
  @override
  Future<void> leaveHome(String homeId) async {}
}

HomeSummary _home(String id, String name) => HomeSummary(
  id: id,
  name: name,
  locale: 'en-NA',
  currency: 'NAD',
  timezone: 'Africa/Windhoek',
  role: HomeRole.member,
  revision: 1,
);

const _identitySessionId = '0198a0b1-c2d3-7e4f-8123-456789abcda1';
const _identityDeviceId = '0198a0b1-c2d3-7e4f-8123-456789abcda2';
const _identityUserId = '0198a0b1-c2d3-7e4f-8123-456789abcda3';
const _remoteSessionId = '0198a0b1-c2d3-7e4f-8123-456789abcda4';
const _remoteDeviceId = '0198a0b1-c2d3-7e4f-8123-456789abcda5';
const _expiredSessionId = '0198a0b1-c2d3-7e4f-8123-456789abcda6';
const _expiredDeviceId = '0198a0b1-c2d3-7e4f-8123-456789abcda7';
const _durableSessionId = '0198a0b1-c2d3-7e4f-8123-456789abcda8';
const _durableDeviceId = '0198a0b1-c2d3-7e4f-8123-456789abcda9';

SessionGrant _identityGrant(DateTime now) => SessionGrant(
  metadata: SessionMetadata(
    sessionId: _identitySessionId,
    deviceId: _identityDeviceId,
    userId: _identityUserId,
    accessExpiresAt: now.add(const Duration(minutes: 15)),
    refreshExpiresAt: now.add(const Duration(days: 60)),
    idleExpiresAt: now.add(const Duration(days: 60)),
    refreshIdleTtl: const Duration(days: 60),
    transport: ClientSessionTransport.nativeBearer,
  ),
  secrets: const SessionSecrets(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
  ),
);

DeviceSessionView _identityDeviceSession(
  DateTime now, {
  required String id,
  required String deviceId,
  required String deviceName,
  required String platform,
  bool current = false,
  bool expired = false,
  bool durable = false,
}) => DeviceSessionView(
  id: id,
  deviceId: deviceId,
  deviceName: deviceName,
  platform: platform,
  transport: platform == 'web'
      ? ClientSessionTransport.webCookie
      : ClientSessionTransport.nativeBearer,
  current: current,
  createdAt: now.subtract(const Duration(days: 5)),
  lastSeenAt: now.subtract(const Duration(minutes: 5)),
  accessExpiresAt: expired
      ? now.subtract(const Duration(minutes: 1))
      : now.add(const Duration(minutes: 15)),
  refreshExpiresAt: durable
      ? null
      : expired
      ? now.subtract(const Duration(minutes: 1))
      : now.add(const Duration(days: 60)),
  idleExpiresAt: durable
      ? null
      : expired
      ? now.subtract(const Duration(minutes: 1))
      : now.add(const Duration(days: 60)),
);
