import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/homes/application/home_ports.dart';
import 'package:providentia/features/homes/application/home_session_manager.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/presentation/home_governance_page.dart';
import 'package:providentia/features/homes/presentation/homes_controller.dart';

void main() {
  testWidgets(
    'owner governance exposes and executes the server-authorized controls',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 4000);
      addTearDown(tester.view.reset);

      final transport = _GovernanceTransport(role: HomeRole.owner);
      final fixture = await _GovernanceFixture.create(transport);
      addTearDown(fixture.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeGovernancePage(
            controller: fixture.controller,
            currentUserId: _currentUserId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home access'), findsOneWidget);
      expect(find.text('My home'), findsWidgets);
      expect(find.text('Your role: owner'), findsOneWidget);
      expect(find.byKey(const Key('edit-home-settings')), findsOneWidget);
      expect(find.text('Members'), findsOneWidget);
      expect(find.text('Invite someone'), findsOneWidget);
      expect(find.text('Sent invitations'), findsOneWidget);
      expect(find.text('Role permissions'), findsOneWidget);
      expect(find.text('Your pending invitations'), findsOneWidget);
      expect(find.byKey(const Key('leave-active-home')), findsNothing);

      await tester.tap(find.byKey(const Key('edit-home-settings')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('edit-home-name')),
        'Updated home',
      );
      await tester.enterText(
        find.byKey(const Key('edit-home-locale')),
        'en-NA',
      );
      await tester.enterText(
        find.byKey(const Key('edit-home-currency')),
        'nad',
      );
      await tester.enterText(
        find.byKey(const Key('edit-home-timezone')),
        'Africa/Windhoek',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(transport.updatedHomeName, 'Updated home');

      final memberCard = find.byKey(const Key('home-membership-user-member'));
      await tester.tap(
        find.descendant(
          of: memberCard,
          matching: find.byType(DropdownButton<HomeRole>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('viewer').last);
      await tester.pumpAndSettle();
      expect(transport.changedRole, HomeRole.viewer);

      await tester.enterText(
        find.byKey(const Key('home-invitation-email')),
        'new@example.test',
      );
      await tester.tap(find.byKey(const Key('home-invitation-role')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('viewer').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-home-invitation')));
      await tester.pumpAndSettle();
      expect(transport.invitedEmail, 'new@example.test');
      expect(transport.invitedRole, HomeRole.viewer);

      final sentInvitation = find.byKey(
        const Key('sent-home-invitation-invitation-sent'),
      );
      await tester.tap(
        find.descendant(
          of: sentInvitation,
          matching: find.byTooltip('Revoke invitation'),
        ),
      );
      await tester.pumpAndSettle();
      expect(transport.revokedInvitationId, 'invitation-sent');

      final managerPolicy = find.byKey(const Key('permission-policy-manager'));
      await tester.tap(
        find.descendant(
          of: managerPolicy,
          matching: find.byTooltip('Edit manager permissions'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'home.read'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        transport.savedPolicyPermissions,
        isNot(contains(HomePermissions.homeRead)),
      );

      final pendingInvitation = find.byKey(
        const Key('governance-pending-invitation-invitation-pending'),
      );
      await tester.tap(
        find.descendant(
          of: pendingInvitation,
          matching: find.widgetWithText(FilledButton, 'Accept'),
        ),
      );
      await tester.pumpAndSettle();
      expect(transport.acceptedInvitationId, 'invitation-pending');
    },
  );

  testWidgets('viewer governance remains read-only and can leave', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1800);
    addTearDown(tester.view.reset);

    final transport = _GovernanceTransport(role: HomeRole.viewer);
    final fixture = await _GovernanceFixture.create(transport);
    addTearDown(fixture.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeGovernancePage(
          controller: fixture.controller,
          currentUserId: _currentUserId,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your role: viewer'), findsOneWidget);
    expect(find.text('Members'), findsOneWidget);
    expect(find.byKey(const Key('edit-home-settings')), findsNothing);
    expect(find.byKey(const Key('home-invitation-email')), findsNothing);
    expect(find.text('Sent invitations'), findsNothing);
    expect(find.text('Role permissions'), findsNothing);
    expect(find.byType(DropdownButton<HomeRole>), findsNothing);
    expect(find.byKey(const Key('leave-active-home')), findsOneWidget);

    await tester.tap(find.byKey(const Key('leave-active-home')));
    await tester.pumpAndSettle();

    expect(transport.leftHomeId, _homeId);
    expect(find.text('Select a home first.'), findsOneWidget);
  });
}

const _homeId = 'home-primary';
const _currentUserId = 'user-current';

final class _GovernanceFixture {
  const _GovernanceFixture(this.manager, this.controller);

  final HomeSessionManager manager;
  final HomesController controller;

  static Future<_GovernanceFixture> create(
    _GovernanceTransport transport,
  ) async {
    final manager = HomeSessionManager(
      transport: transport,
      activeHomeStore: _MemoryActiveHomeStore(),
    );
    final controller = HomesController(manager);
    await controller.load(sessionActiveHomeId: _homeId);
    return _GovernanceFixture(manager, controller);
  }

  Future<void> dispose() async {
    controller.dispose();
    await manager.dispose();
  }
}

final class _GovernanceTransport implements HomeTransportPort {
  _GovernanceTransport({required HomeRole role})
    : home = _home(role),
      policies = <HomePermissionPolicy>[
        HomePermissionPolicy(
          role: HomeRole.owner,
          revision: 0,
          permissions: HomePermissions.owner,
          configurable: false,
        ),
        HomePermissionPolicy(
          role: HomeRole.manager,
          revision: 2,
          permissions: const <String>{
            HomePermissions.homeRead,
            HomePermissions.membersRead,
            HomePermissions.membersInvite,
          },
          configurable: true,
        ),
        HomePermissionPolicy(
          role: HomeRole.viewer,
          revision: 3,
          permissions: const <String>{
            HomePermissions.homeRead,
            HomePermissions.membersRead,
          },
          configurable: true,
        ),
      ];

  HomeSummary home;
  final List<HomePermissionPolicy> policies;
  final List<HomeMembership> memberships = <HomeMembership>[
    HomeMembership(
      userId: _currentUserId,
      displayName: 'Current person',
      email: 'current@example.test',
      role: HomeRole.owner,
      revision: 1,
    ),
    HomeMembership(
      userId: 'user-member',
      displayName: 'Household helper',
      email: 'helper@example.test',
      role: HomeRole.member,
      revision: 2,
    ),
  ];
  final List<HomeInvitation> invitations = <HomeInvitation>[
    HomeInvitation(
      id: 'invitation-sent',
      homeId: _homeId,
      email: 'sent@example.test',
      role: HomeRole.member,
      status: InvitationStatus.pending,
      expiresAt: DateTime.utc(2030),
      revision: 1,
    ),
  ];
  final List<RecipientHomeInvitation> pendingInvitations =
      <RecipientHomeInvitation>[
        RecipientHomeInvitation(
          id: 'invitation-pending',
          homeId: _homeId,
          homeName: 'My home',
          inviterUserId: 'user-inviter',
          role: HomeRole.member,
          expiresAt: DateTime.utc(2030),
          revision: 1,
        ),
      ];

  String? updatedHomeName;
  HomeRole? changedRole;
  String? invitedEmail;
  HomeRole? invitedRole;
  String? revokedInvitationId;
  Set<String>? savedPolicyPermissions;
  String? acceptedInvitationId;
  String? leftHomeId;

  @override
  Future<List<HomeSummary>> listHomes() async => <HomeSummary>[home];

  @override
  Future<HomeSummary> createHome(CreateHomeCommand command) =>
      throw UnimplementedError();

  @override
  Future<HomeSummary> switchActiveHome(String homeId) async => home;

  @override
  Future<HomeSummary> updateHome({
    required String homeId,
    required String name,
    required String locale,
    required String currency,
    required String timezone,
    required int expectedRevision,
  }) async {
    updatedHomeName = name;
    home = HomeSummary(
      id: home.id,
      name: name,
      locale: locale,
      currency: currency,
      timezone: timezone,
      role: home.role,
      revision: expectedRevision + 1,
    );
    return home;
  }

  @override
  Future<List<HomeMembership>> listMemberships(String homeId) async =>
      List<HomeMembership>.of(memberships);

  @override
  Future<void> changeMembershipRole({
    required String homeId,
    required String userId,
    required HomeRole role,
    required int expectedRevision,
  }) async {
    changedRole = role;
    final index = memberships.indexWhere((member) => member.userId == userId);
    final member = memberships[index];
    memberships[index] = HomeMembership(
      userId: member.userId,
      displayName: member.displayName,
      email: member.email,
      role: role,
      revision: expectedRevision + 1,
    );
  }

  @override
  Future<HomeInvitation> createInvitation({
    required String homeId,
    required String email,
    required HomeRole role,
  }) async {
    invitedEmail = email;
    invitedRole = role;
    final invitation = HomeInvitation(
      id: 'invitation-new',
      homeId: homeId,
      email: email,
      role: role,
      status: InvitationStatus.pending,
      expiresAt: DateTime.utc(2030),
      revision: 1,
    );
    invitations.add(invitation);
    return invitation;
  }

  @override
  Future<List<HomeInvitation>> listInvitations(String homeId) async =>
      List<HomeInvitation>.of(invitations);

  @override
  Future<void> revokeInvitation({
    required String homeId,
    required String invitationId,
    required int expectedRevision,
  }) async {
    revokedInvitationId = invitationId;
    invitations.removeWhere((invitation) => invitation.id == invitationId);
  }

  @override
  Future<List<RecipientHomeInvitation>> listPendingInvitations() async =>
      List<RecipientHomeInvitation>.of(pendingInvitations);

  @override
  Future<HomeSummary> acceptPendingInvitation({
    required String invitationId,
    required int expectedRevision,
  }) async {
    acceptedInvitationId = invitationId;
    pendingInvitations.removeWhere(
      (invitation) => invitation.id == invitationId,
    );
    return home;
  }

  @override
  Future<List<HomePermissionPolicy>> listPermissionPolicies(
    String homeId,
  ) async => List<HomePermissionPolicy>.of(policies);

  @override
  Future<HomePermissionPolicy> putPermissionPolicy({
    required String homeId,
    required HomeRole role,
    required Set<String> permissions,
    required int expectedRevision,
  }) async {
    savedPolicyPermissions = Set<String>.of(permissions);
    final updated = HomePermissionPolicy(
      role: role,
      revision: expectedRevision + 1,
      permissions: permissions,
      configurable: true,
    );
    final index = policies.indexWhere((policy) => policy.role == role);
    policies[index] = updated;
    return updated;
  }

  @override
  Future<void> leaveHome(String homeId) async => leftHomeId = homeId;
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

HomeSummary _home(HomeRole role) => HomeSummary(
  id: _homeId,
  name: 'My home',
  locale: 'en-NA',
  currency: 'NAD',
  timezone: 'Africa/Windhoek',
  role: role,
  revision: 1,
);
