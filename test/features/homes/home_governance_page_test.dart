import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/homes/application/home_ports.dart';
import 'package:providentia/features/homes/application/home_session_manager.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/presentation/home_governance_page.dart';
import 'package:providentia/features/homes/presentation/homes_controller.dart';

import '../../support/access_fixture.dart';

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
            profilePort: FixtureProfilePort(),
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

  testWidgets(
    'owner proposes and revokes an ownership transfer through step-up',
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
            profilePort: FixtureProfilePort(),
            controller: fixture.controller,
            currentUserId: _currentUserId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ownership'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ownership-transfer-target')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Household helper · member').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('propose-ownership-transfer')));
      await tester.pumpAndSettle();

      expect(transport.stepUpRequests, 1);
      expect(find.text('Confirm ownership transfer'), findsOneWidget);
      final tokenField = tester.widget<TextField>(
        find.byKey(const Key('ownership-step-up-token')),
      );
      expect(
        tokenField.controller?.text,
        _stepUpToken,
        reason: 'development profiles prefill the emailed code',
      );
      await tester.tap(find.byKey(const Key('confirm-ownership-transfer')));
      await tester.pumpAndSettle();

      expect(transport.proposedTransfer, (
        targetUserId: 'user-member',
        expectedTargetRevision: 2,
        stepUpToken: _stepUpToken,
      ));
      final pendingTile = find.byKey(
        const Key('ownership-transfer-transfer-proposed'),
      );
      expect(pendingTile, findsOneWidget);
      expect(find.text('Proposed to Household helper'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('revoke-ownership-transfer-transfer-proposed')),
      );
      await tester.pumpAndSettle();

      expect(transport.revokedTransfer, (
        transferId: 'transfer-proposed',
        expectedRevision: 1,
      ));
      expect(pendingTile, findsNothing);
    },
  );

  testWidgets(
    'transfer target accepts pending ownership with revision semantics',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);

      final transport = _GovernanceTransport(role: HomeRole.member)
        ..ownershipTransfers.add(_offeredTransfer());
      final fixture = await _GovernanceFixture.create(transport);
      addTearDown(fixture.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeGovernancePage(
            profilePort: FixtureProfilePort(),
            controller: fixture.controller,
            currentUserId: _currentUserId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ownership transfer for you'), findsOneWidget);
      expect(
        find.byKey(const Key('ownership-transfer-offer-transfer-offer')),
        findsOneWidget,
      );
      expect(find.text('Become the owner of My home?'), findsOneWidget);
      expect(
        find.text('Ownership'),
        findsNothing,
        reason: 'the management section stays owner-only',
      );

      await tester.tap(
        find.byKey(const Key('accept-ownership-transfer-transfer-offer')),
      );
      await tester.pumpAndSettle();

      expect(transport.acceptedTransfer, (
        transferId: 'transfer-offer',
        expectedRevision: 6,
      ));
      expect(find.text('Your role: owner'), findsOneWidget);
    },
  );

  testWidgets('transfer target can reject a pending ownership offer', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 2400);
    addTearDown(tester.view.reset);

    final transport = _GovernanceTransport(role: HomeRole.member)
      ..ownershipTransfers.add(_offeredTransfer());
    final fixture = await _GovernanceFixture.create(transport);
    addTearDown(fixture.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeGovernancePage(
          profilePort: FixtureProfilePort(),
          controller: fixture.controller,
          currentUserId: _currentUserId,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('reject-ownership-transfer-transfer-offer')),
    );
    await tester.pumpAndSettle();

    expect(transport.rejectedTransfer, (
      transferId: 'transfer-offer',
      expectedRevision: 6,
    ));
    expect(
      find.byKey(const Key('ownership-transfer-offer-transfer-offer')),
      findsNothing,
    );
    expect(find.text('Your role: member'), findsOneWidget);
  });

  testWidgets(
    'owner removes a member only after an explicit named confirmation',
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
            profilePort: FixtureProfilePort(),
            controller: fixture.controller,
            currentUserId: _currentUserId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('remove-home-membership-user-member')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('remove-home-membership-$_currentUserId')),
        findsNothing,
        reason: 'the caller leaves through Leave, never removes itself',
      );

      await tester.tap(
        find.byKey(const Key('remove-home-membership-user-member')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove Household helper?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(
            'ends the member access of Household helper to My home',
          ),
        ),
        findsOneWidget,
        reason: 'the confirmation names the member and role',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(transport.removedMembership, isNull);

      await tester.tap(
        find.byKey(const Key('remove-home-membership-user-member')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-remove-membership')));
      await tester.pumpAndSettle();

      expect(transport.removedMembership, (
        userId: 'user-member',
        expectedRevision: 2,
      ));
      expect(
        find.byKey(const Key('home-membership-user-member')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'member removal conflict reloads governance and shows retry guidance',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 4000);
      addTearDown(tester.view.reset);

      final transport = _GovernanceTransport(role: HomeRole.owner)
        ..removalFailure = const HomeTransportException(
          kind: HomeFailureKind.conflict,
          safeMessage:
              'This member is no longer available. Refresh and try again.',
          homeId: _homeId,
        );
      final fixture = await _GovernanceFixture.create(transport);
      addTearDown(fixture.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeGovernancePage(
            profilePort: FixtureProfilePort(),
            controller: fixture.controller,
            currentUserId: _currentUserId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final refreshesBefore = transport.membershipListCalls;

      await tester.tap(
        find.byKey(const Key('remove-home-membership-user-member')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-remove-membership')));
      await tester.pumpAndSettle();

      expect(
        transport.membershipListCalls,
        refreshesBefore + 1,
        reason: 'a 409 reloads authoritative governance revisions',
      );
      expect(
        find.text('This member is no longer available. Refresh and try again.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-membership-user-member')),
        findsOneWidget,
      );
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
          profilePort: FixtureProfilePort(),
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
    expect(find.text('Ownership'), findsNothing);
    expect(
      find.byKey(const Key('remove-home-membership-user-member')),
      findsNothing,
    );
    expect(find.byKey(const Key('leave-active-home')), findsOneWidget);

    await tester.tap(find.byKey(const Key('leave-active-home')));
    await tester.pumpAndSettle();

    expect(transport.leftHomeId, _homeId);
    expect(find.text('Select a home first.'), findsOneWidget);
  });
}

const _homeId = 'home-primary';
const _currentUserId = 'user-current';
const _stepUpToken =
    'development-step-up-token-0000000000000000000000000000000000000000';

HomeOwnershipTransfer _offeredTransfer() => HomeOwnershipTransfer(
  id: 'transfer-offer',
  homeId: _homeId,
  proposedByUserId: 'user-inviter',
  targetUserId: _currentUserId,
  expectedTargetRevision: 1,
  status: OwnershipTransferStatus.pending,
  expiresAt: DateTime.utc(2030),
  revision: 6,
);

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

  final List<HomeOwnershipTransfer> ownershipTransfers =
      <HomeOwnershipTransfer>[];

  String? updatedHomeName;
  HomeRole? changedRole;
  String? invitedEmail;
  HomeRole? invitedRole;
  String? revokedInvitationId;
  Set<String>? savedPolicyPermissions;
  String? acceptedInvitationId;
  String? leftHomeId;
  int stepUpRequests = 0;
  int membershipListCalls = 0;
  HomeTransportException? removalFailure;
  ({String userId, int expectedRevision})? removedMembership;
  ({String targetUserId, int expectedTargetRevision, String stepUpToken})?
  proposedTransfer;
  ({String transferId, int expectedRevision})? acceptedTransfer;
  ({String transferId, int expectedRevision})? rejectedTransfer;
  ({String transferId, int expectedRevision})? revokedTransfer;

  @override
  Future<HomeSummary> getHome(String homeId) async => home;

  @override
  Future<void> declinePendingInvitation({
    required String invitationId,
    required int expectedRevision,
  }) async {
    pendingInvitations.removeWhere(
      (invitation) => invitation.id == invitationId,
    );
  }

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
      effectivePermissions: fixtureHomePermissions(home.role),
      access: fixtureHomeAccess(),
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
  Future<List<HomeMembership>> listMemberships(String homeId) async {
    membershipListCalls++;
    return List<HomeMembership>.of(memberships);
  }

  @override
  Future<void> removeHomeMembership({
    required String homeId,
    required String userId,
    required int expectedRevision,
  }) async {
    if (removalFailure case final failure?) {
      throw failure;
    }
    removedMembership = (userId: userId, expectedRevision: expectedRevision);
    memberships.removeWhere((member) => member.userId == userId);
  }

  @override
  Future<List<HomeOwnershipTransfer>> listHomeOwnershipTransfers(
    String homeId,
  ) async => List<HomeOwnershipTransfer>.of(ownershipTransfers);

  @override
  Future<HomeOwnershipTransfer> proposeHomeOwnershipTransfer({
    required String homeId,
    required String targetUserId,
    required int expectedTargetRevision,
    required String stepUpToken,
  }) async {
    proposedTransfer = (
      targetUserId: targetUserId,
      expectedTargetRevision: expectedTargetRevision,
      stepUpToken: stepUpToken,
    );
    final transfer = HomeOwnershipTransfer(
      id: 'transfer-proposed',
      homeId: homeId,
      proposedByUserId: _currentUserId,
      targetUserId: targetUserId,
      expectedTargetRevision: expectedTargetRevision,
      status: OwnershipTransferStatus.pending,
      expiresAt: DateTime.utc(2030),
      revision: 1,
    );
    ownershipTransfers.add(transfer);
    return transfer;
  }

  @override
  Future<void> acceptHomeOwnershipTransfer({
    required String homeId,
    required String transferId,
    required int expectedRevision,
  }) async {
    acceptedTransfer = (
      transferId: transferId,
      expectedRevision: expectedRevision,
    );
    ownershipTransfers.removeWhere((transfer) => transfer.id == transferId);
    home = HomeSummary(
      effectivePermissions: fixtureHomePermissions(HomeRole.owner),
      access: fixtureHomeAccess(),
      id: home.id,
      name: home.name,
      locale: home.locale,
      currency: home.currency,
      timezone: home.timezone,
      role: HomeRole.owner,
      revision: home.revision + 1,
    );
  }

  @override
  Future<void> rejectHomeOwnershipTransfer({
    required String homeId,
    required String transferId,
    required int expectedRevision,
  }) async {
    rejectedTransfer = (
      transferId: transferId,
      expectedRevision: expectedRevision,
    );
    ownershipTransfers.removeWhere((transfer) => transfer.id == transferId);
  }

  @override
  Future<void> revokeHomeOwnershipTransfer({
    required String homeId,
    required String transferId,
    required int expectedRevision,
  }) async {
    revokedTransfer = (
      transferId: transferId,
      expectedRevision: expectedRevision,
    );
    ownershipTransfers.removeWhere((transfer) => transfer.id == transferId);
  }

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
  effectivePermissions: fixtureHomePermissions(role),
  access: fixtureHomeAccess(),
  id: _homeId,
  name: 'My home',
  locale: 'en-NA',
  currency: 'NAD',
  timezone: 'Africa/Windhoek',
  role: role,
  revision: 1,
);
