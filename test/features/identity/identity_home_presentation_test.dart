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

  testWidgets('development password is hidden unless explicitly enabled', (
    tester,
  ) async {
    final identity = _IdentityFixture(developmentPassword: true);
    addTearDown(identity.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginLinkSignInPage(
          controller: identity.controller,
          restoreOnStart: false,
          developmentPasswordAvailable: true,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('identity-toggle-development-password')),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('identity-development-password')),
      findsOneWidget,
    );
    expect(find.text('Use development access'), findsOneWidget);
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
  _IdentityFixture({bool developmentPassword = false})
    : transport = developmentPassword
          ? _DevelopmentIdentityTransport()
          : _PresentationIdentityTransport() {
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
  _AuthenticatedIdentityFixture()
    : transport = _AuthenticatedPresentationIdentityTransport(
        DateTime.now().toUtc(),
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

final class _DevelopmentIdentityTransport extends _PresentationIdentityTransport
    implements DevelopmentPasswordIdentityTransportPort {
  @override
  Future<SessionGrant> loginWithPassword({
    required String email,
    required String password,
    required DeviceDescriptor device,
  }) => throw UnimplementedError();
}

final class _AuthenticatedPresentationIdentityTransport
    extends _PresentationIdentityTransport {
  _AuthenticatedPresentationIdentityTransport(this.now)
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
      ];

  final DateTime now;
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
    platformRoles: const <PlatformRole>{},
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
  refreshExpiresAt: expired
      ? now.subtract(const Duration(minutes: 1))
      : now.add(const Duration(days: 60)),
  idleExpiresAt: expired
      ? now.subtract(const Duration(minutes: 1))
      : now.add(const Duration(days: 60)),
);
