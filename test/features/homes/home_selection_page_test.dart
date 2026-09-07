import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/homes/application/home_ports.dart';
import 'package:providentia/features/homes/application/home_session_manager.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/presentation/home_selection_page.dart';
import 'package:providentia/features/homes/presentation/homes_controller.dart';
import 'package:providentia/features/profile/profile_port.dart';

import '../../support/access_fixture.dart';

void main() {
  testWidgets(
    'invited first-timers see invitations first and create as secondary',
    (tester) async {
      final fixture = _SelectionFixture(withInvitation: true);
      addTearDown(fixture.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeSelectionPage(
            controller: fixture.controller,
            accountAccess: _createAccountAccess,
            activeHomeBuilder: (context, home) =>
                Scaffold(body: Text('Opened ${home.name}')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final invitationCard = find.byKey(
        const Key('pending-home-invitation-invitation-id'),
      );
      final secondaryCreate = find.byKey(const Key('show-create-home'));
      expect(invitationCard, findsOneWidget);
      expect(find.text('Invitation to Shared pantry'), findsOneWidget);
      expect(
        find.descendant(
          of: invitationCard,
          matching: find.widgetWithText(FilledButton, 'Accept'),
        ),
        findsOneWidget,
      );
      expect(secondaryCreate, findsOneWidget);
      expect(find.text('Create a home instead'), findsOneWidget);
      expect(
        find.byKey(const Key('create-home-name')),
        findsNothing,
        reason: 'the create form must stay an explicit secondary choice',
      );
      expect(
        tester.getTopLeft(invitationCard).dy,
        lessThan(tester.getTopLeft(secondaryCreate).dy),
        reason: 'invitations render before the create affordance',
      );

      await tester.tap(secondaryCreate);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('create-home-name')), findsOneWidget);
      expect(find.byKey(const Key('cancel-create-home')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel-create-home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('create-home-name')), findsNothing);

      await tester.tap(
        find.descendant(
          of: invitationCard,
          matching: find.widgetWithText(FilledButton, 'Accept'),
        ),
      );
      await tester.pumpAndSettle();

      expect(fixture.transport.acceptedRevision, 3);
      expect(find.text('Opened Shared pantry'), findsOneWidget);
    },
  );

  testWidgets('zero homes without invitations leads with the create form', (
    tester,
  ) async {
    final fixture = _SelectionFixture(withInvitation: false);
    addTearDown(fixture.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeSelectionPage(
          controller: fixture.controller,
          accountAccess: _createAccountAccess,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create your first home'), findsOneWidget);
    expect(find.byKey(const Key('create-home-name')), findsOneWidget);
    expect(find.byKey(const Key('create-home-submit')), findsOneWidget);
    expect(find.byKey(const Key('show-create-home')), findsNothing);
    expect(find.byKey(const Key('cancel-create-home')), findsNothing);
  });
  testWidgets('new home uses the selected country currency and time zone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.reset);
    final fixture = _SelectionFixture(withInvitation: false);
    addTearDown(fixture.dispose);
    final profile = _CountryProfilePort();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeSelectionPage(
          controller: fixture.controller,
          accountAccess: _createAccountAccess,
          accountProfile: const <String, Object?>{
            'countryCode': 'ZA',
            'locale': 'af-ZA',
            'timezone': 'Africa/Windhoek',
          },
          profilePort: profile,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('create-home-name')),
      'Our home',
    );
    await tester.tap(find.byKey(const Key('create-home-submit')));
    await tester.pumpAndSettle();
    final created = fixture.transport.homes.single;
    expect(created.locale, 'af-ZA');
    expect(created.currency, 'ZAR');
    expect(created.timezone, 'Africa/Johannesburg');
    expect(profile.calls, <String>['listAvailableCountries']);
  });

  for (final access in <Map<String, Object?>>[
    <String, Object?>{},
    <String, Object?>{
      'features': <String, bool>{'homes.create': false},
      'limits': <String, int>{'homes.owned': 1},
    },
    <String, Object?>{
      'features': <String, bool>{'homes.create': true},
      'limits': <String, int>{'homes.owned': 0},
    },
  ]) {
    testWidgets(
      'invited account cannot create without an available allowance: $access',
      (tester) async {
        final fixture = _SelectionFixture(withInvitation: true);
        addTearDown(fixture.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: HomeSelectionPage(
              controller: fixture.controller,
              accountAccess: access,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('pending-home-invitation-invitation-id')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('show-create-home')), findsNothing);
        expect(find.byKey(const Key('create-home-submit')), findsNothing);
        expect(find.textContaining('join homes by invitation'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
        await tester.pumpAndSettle();
        expect(fixture.transport.acceptedRevision, 3);
        expect(fixture.manager.snapshot.activeHome?.id, 'shared-home');
      },
    );
  }
}

const _createAccountAccess = <String, Object?>{
  'features': <String, bool>{'homes.create': true},
  'limits': <String, int>{'homes.owned': 1},
};

final class _SelectionFixture {
  _SelectionFixture({required bool withInvitation})
    : transport = _SelectionHomeTransport(withInvitation: withInvitation) {
    manager = HomeSessionManager(
      transport: transport,
      activeHomeStore: _MemoryActiveHomeStore(),
    );
    controller = HomesController(manager);
  }

  final _SelectionHomeTransport transport;
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

final class _SelectionHomeTransport implements HomeTransportPort {
  _SelectionHomeTransport({required bool withInvitation})
    : invitations = withInvitation
          ? <RecipientHomeInvitation>[
              RecipientHomeInvitation(
                id: 'invitation-id',
                homeId: 'shared-home',
                homeName: 'Shared pantry',
                inviterUserId: 'inviter-id',
                role: HomeRole.member,
                expiresAt: DateTime.utc(2030),
                revision: 3,
              ),
            ]
          : <RecipientHomeInvitation>[];

  final List<HomeSummary> homes = <HomeSummary>[];
  final List<RecipientHomeInvitation> invitations;
  int? acceptedRevision;

  @override
  Future<HomeSummary> getHome(String homeId) async =>
      homes.singleWhere((home) => home.id == homeId);

  @override
  Future<void> declinePendingInvitation({
    required String invitationId,
    required int expectedRevision,
  }) async {
    invitations.removeWhere((invitation) => invitation.id == invitationId);
  }

  @override
  Future<List<HomeSummary>> listHomes() async => List<HomeSummary>.of(homes);

  @override
  Future<HomeSummary> createHome(CreateHomeCommand command) async {
    final created = HomeSummary(
      effectivePermissions: fixtureHomePermissions(HomeRole.owner),
      access: fixtureHomeAccess(),
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
  Future<HomeSummary> switchActiveHome(String homeId) async =>
      homes.firstWhere((home) => home.id == homeId);

  @override
  Future<List<RecipientHomeInvitation>> listPendingInvitations() async =>
      List<RecipientHomeInvitation>.of(invitations);

  @override
  Future<HomeSummary> acceptPendingInvitation({
    required String invitationId,
    required int expectedRevision,
  }) async {
    acceptedRevision = expectedRevision;
    invitations.removeWhere((invitation) => invitation.id == invitationId);
    final accepted = HomeSummary(
      effectivePermissions: fixtureHomePermissions(HomeRole.member),
      access: fixtureHomeAccess(),
      id: 'shared-home',
      name: 'Shared pantry',
      locale: 'en-NA',
      currency: 'NAD',
      timezone: 'Africa/Windhoek',
      role: HomeRole.member,
      revision: 1,
    );
    homes.add(accepted);
    return accepted;
  }

  @override
  Future<List<HomePermissionPolicy>> listPermissionPolicies(
    String homeId,
  ) async => const <HomePermissionPolicy>[];

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
  }) => throw UnimplementedError();

  @override
  Future<void> removeHomeMembership({
    required String homeId,
    required String userId,
    required int expectedRevision,
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

  @override
  Future<List<HomeOwnershipTransfer>> listHomeOwnershipTransfers(
    String homeId,
  ) async => const <HomeOwnershipTransfer>[];

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
  Future<HomePermissionPolicy> putPermissionPolicy({
    required String homeId,
    required HomeRole role,
    required Set<String> permissions,
    required int expectedRevision,
  }) => throw UnimplementedError();

  @override
  Future<void> leaveHome(String homeId) => throw UnimplementedError();
}

final class _CountryProfilePort implements ProfilePort {
  final List<String> calls = <String>[];
  @override
  Future<Object?> call(
    String operation, {
    Map<String, String>? path,
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    calls.add(operation);
    return <String, Object?>{
      'data': <Map<String, Object?>>[
        <String, Object?>{
          'code': 'NA',
          'defaultCurrency': 'NAD',
          'defaultTimezone': 'Africa/Windhoek',
        },
        <String, Object?>{
          'code': 'ZA',
          'defaultCurrency': 'ZAR',
          'defaultTimezone': 'Africa/Johannesburg',
        },
      ],
    };
  }
}
