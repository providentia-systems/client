import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/homes/application/home_ports.dart';
import 'package:providentia/features/homes/application/home_session_manager.dart';
import 'package:providentia/features/homes/domain/home_models.dart';

void main() {
  test(
    'multiple homes require selection when no active preference exists',
    () async {
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[
          _home('home-a', 'Home A'),
          _home('home-b', 'Home B'),
        ],
      );
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: _MemoryActiveHomeStore(),
      );
      addTearDown(manager.dispose);

      await manager.load();

      expect(manager.snapshot.status, HomeSessionStatus.selectionRequired);
      expect(manager.snapshot.homes, hasLength(2));
      expect(transport.switches, isEmpty);
    },
  );

  test('stored home is server-validated before it becomes active', () async {
    final store = _MemoryActiveHomeStore(value: 'home-b');
    final changed = <String?>[];
    final transport = _FakeHomeTransport(
      homes: <HomeSummary>[
        _home('home-a', 'Home A'),
        _home('home-b', 'Home B'),
      ],
    );
    final manager = HomeSessionManager(
      transport: transport,
      activeHomeStore: store,
      onActiveHomeChanged: changed.add,
    );
    addTearDown(manager.dispose);

    await manager.load();

    expect(transport.switches, <String>['home-b']);
    expect(manager.snapshot.status, HomeSessionStatus.ready);
    expect(manager.snapshot.activeHome?.id, 'home-b');
    expect(store.value, 'home-b');
    expect(changed, <String?>['home-b']);
  });

  test(
    'session active home does not perform a redundant server switch',
    () async {
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[
          _home('home-a', 'Home A'),
          _home('home-b', 'Home B'),
        ],
      );
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: _MemoryActiveHomeStore(),
      );
      addTearDown(manager.dispose);

      await manager.load(sessionActiveHomeId: 'home-a');

      expect(transport.switches, isEmpty);
      expect(manager.snapshot.activeHome?.id, 'home-a');
    },
  );

  test('home switch is serialized through the session coordinator', () async {
    final coordinated = <String>[];
    final transport = _FakeHomeTransport(
      homes: <HomeSummary>[
        _home('home-a', 'Home A'),
        _home('home-b', 'Home B'),
      ],
    );
    final manager = HomeSessionManager(
      transport: transport,
      activeHomeStore: _MemoryActiveHomeStore(),
      coordinateActiveHomeMutation:
          ({required homeId, required mutation}) async {
            coordinated.add(homeId);
            return mutation();
          },
    );
    addTearDown(manager.dispose);
    await manager.load();

    await manager.selectHome('home-b');

    expect(coordinated, <String>['home-b']);
    expect(transport.switches, <String>['home-b']);
    expect(manager.snapshot.activeHome?.id, 'home-b');
  });

  test(
    'superseded delayed B cannot broadcast after queued C selection',
    () async {
      final delayedB = Completer<HomeSummary>();
      final broadcasts = <String>[];
      var mutationTail = Future<void>.value();
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[
          _home('home-a', 'Home A'),
          _home('home-b', 'Home B'),
          _home('home-c', 'Home C'),
        ],
      )..switchCompletions['home-b'] = delayedB;
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: _MemoryActiveHomeStore(),
        coordinateActiveHomeMutation: ({required homeId, required mutation}) {
          final result = Completer<HomeSummary>();
          mutationTail = mutationTail.then((_) async {
            try {
              final selected = await mutation();
              broadcasts.add(homeId);
              result.complete(selected);
            } on Object catch (error, stackTrace) {
              result.completeError(error, stackTrace);
            }
          });
          return result.future;
        },
      );
      addTearDown(manager.dispose);
      await manager.load();

      final selectB = manager.selectHome('home-b');
      await Future<void>.delayed(Duration.zero);
      final selectC = manager.selectHome('home-c');
      delayedB.complete(_home('home-b', 'Home B'));
      await selectB;
      await selectC;

      expect(transport.switches, <String>['home-b', 'home-c']);
      expect(broadcasts, <String>['home-c']);
      expect(manager.snapshot.activeHome?.id, 'home-c');
    },
  );

  test(
    'authoritative session change closes old workspace before reloading',
    () async {
      final store = _MemoryActiveHomeStore(value: 'home-a');
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[
          _home('home-a', 'Home A'),
          _home('home-b', 'Home B'),
        ],
      );
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: store,
      );
      addTearDown(manager.dispose);
      await manager.load(sessionActiveHomeId: 'home-a');
      final homesResponse = Completer<List<HomeSummary>>();
      transport.nextHomesResponse = homesResponse;

      final reconciliation = manager.reconcileSessionActiveHome('home-b');

      expect(manager.snapshot.status, HomeSessionStatus.loading);
      expect(manager.snapshot.activeHome, isNull);
      homesResponse.complete(List<HomeSummary>.of(transport.homes));
      await reconciliation;
      expect(manager.snapshot.activeHome?.id, 'home-b');
      expect(store.value, 'home-b');
      expect(transport.switches, isEmpty);
    },
  );

  test(
    'unauthorized authoritative session home is cleared and rebroadcast',
    () async {
      var coordinatedClears = 0;
      final revoked = <String>[];
      final store = _MemoryActiveHomeStore(value: 'home-a');
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[_home('home-a', 'Home A')],
      );
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: store,
        onHomeAccessRevoked: revoked.add,
        coordinateActiveHomeClearMutation: ({required mutation}) async {
          coordinatedClears++;
          await mutation();
        },
      );
      addTearDown(manager.dispose);
      await manager.load(sessionActiveHomeId: 'home-a');

      await manager.reconcileSessionActiveHome('revoked-home');

      expect(coordinatedClears, 1);
      expect(revoked, <String>['revoked-home']);
      expect(store.value, isNull);
      expect(manager.snapshot.status, HomeSessionStatus.selectionRequired);
      expect(manager.snapshot.activeHome, isNull);
    },
  );

  test('authentication loss defeats a late home-list response', () async {
    final store = _MemoryActiveHomeStore(value: 'home-a');
    final transport = _FakeHomeTransport(
      homes: <HomeSummary>[_home('home-a', 'Home A')],
    );
    final manager = HomeSessionManager(
      transport: transport,
      activeHomeStore: store,
    );
    addTearDown(manager.dispose);
    await manager.load(sessionActiveHomeId: 'home-a');
    final homesResponse = Completer<List<HomeSummary>>();
    transport.nextHomesResponse = homesResponse;
    final lateLoad = manager.load(sessionActiveHomeId: 'home-a');

    manager.handleAuthenticationLost();
    homesResponse.complete(List<HomeSummary>.of(transport.homes));
    await lateLoad;

    expect(manager.snapshot.status, HomeSessionStatus.selectionRequired);
    expect(manager.snapshot.homes, isEmpty);
    expect(manager.snapshot.activeHome, isNull);
    expect(store.value, isNull);
  });

  test(
    'leaving a home coordinates authoritative active-home clearing',
    () async {
      var coordinatedClears = 0;
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[_home('home-a', 'Home A')],
      );
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: _MemoryActiveHomeStore(value: 'home-a'),
        coordinateActiveHomeClearMutation: ({required mutation}) async {
          coordinatedClears++;
          await mutation();
        },
      );
      addTearDown(manager.dispose);
      await manager.load(sessionActiveHomeId: 'home-a');

      await manager.leaveActiveHome();

      expect(coordinatedClears, 1);
      expect(transport.leaveCalls, <String>['home-a']);
      expect(manager.snapshot.status, HomeSessionStatus.accessRevoked);
      expect(manager.snapshot.activeHome, isNull);
    },
  );

  test('membership 403 coordinates a null active-home broadcast', () async {
    var coordinatedClears = 0;
    final transport = _FakeHomeTransport(
      homes: <HomeSummary>[_home('home-a', 'Home A')],
    );
    final manager = HomeSessionManager(
      transport: transport,
      activeHomeStore: _MemoryActiveHomeStore(value: 'home-a'),
      coordinateActiveHomeClearMutation: ({required mutation}) async {
        coordinatedClears++;
        await mutation();
      },
    );
    addTearDown(manager.dispose);
    await manager.load(sessionActiveHomeId: 'home-a');

    await manager.handleMembershipRevoked('home-a');

    expect(coordinatedClears, 1);
    expect(manager.snapshot.activeHome, isNull);
  });

  test(
    'membership revoke closes workspace before coordination can stall',
    () async {
      final coordinationStarted = Completer<void>();
      final releaseCoordination = Completer<void>();
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[_home('home-a', 'Home A')],
      );
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: _MemoryActiveHomeStore(value: 'home-a'),
        coordinateActiveHomeClearMutation: ({required mutation}) async {
          await mutation();
          coordinationStarted.complete();
          await releaseCoordination.future;
        },
      );
      addTearDown(manager.dispose);
      await manager.load(sessionActiveHomeId: 'home-a');

      final revocation = manager.handleMembershipRevoked('home-a');
      await coordinationStarted.future;

      expect(manager.snapshot.status, HomeSessionStatus.accessRevoked);
      expect(manager.snapshot.activeHome, isNull);
      releaseCoordination.complete();
      await revocation;
    },
  );

  test(
    'load purges and broadcasts one stale active home exactly once',
    () async {
      final revoked = <String>[];
      var coordinatedClears = 0;
      final store = _MemoryActiveHomeStore(value: 'revoked-home');
      final transport = _FakeHomeTransport(homes: <HomeSummary>[]);
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: store,
        onHomeAccessRevoked: revoked.add,
        coordinateActiveHomeClearMutation: ({required mutation}) async {
          coordinatedClears++;
          await mutation();
        },
      );
      addTearDown(manager.dispose);

      await manager.load(sessionActiveHomeId: 'revoked-home');

      expect(revoked, <String>['revoked-home']);
      expect(manager.snapshot.status, HomeSessionStatus.selectionRequired);
      expect(manager.snapshot.activeHome, isNull);
      expect(store.value, isNull);
      expect(coordinatedClears, 1);
    },
  );

  test(
    'returning to the chooser clears active state without granting access',
    () async {
      final store = _MemoryActiveHomeStore(value: 'home-a');
      final changed = <String?>[];
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[_home('home-a', 'Home A')],
      );
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: store,
        onActiveHomeChanged: changed.add,
      );
      addTearDown(manager.dispose);
      await manager.load(sessionActiveHomeId: 'home-a');

      await manager.returnToChooser();

      expect(manager.snapshot.status, HomeSessionStatus.selectionRequired);
      expect(manager.snapshot.activeHome, isNull);
      expect(manager.snapshot.memberships, isEmpty);
      expect(manager.snapshot.homes.single.id, 'home-a');
      expect(store.value, isNull);
      expect(
        changed,
        <String?>['home-a'],
        reason: 'the chooser is local-only and must not falsify /me metadata',
      );
      expect(transport.switches, isEmpty);

      await manager.selectHome('home-a');

      expect(transport.switches, <String>['home-a']);
      expect(manager.snapshot.status, HomeSessionStatus.ready);
    },
  );

  test(
    'creating a home selects and persists the authorized response',
    () async {
      final store = _MemoryActiveHomeStore();
      final transport = _FakeHomeTransport(homes: <HomeSummary>[]);
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: store,
      );
      addTearDown(manager.dispose);

      final created = await manager.createHome(
        CreateHomeCommand(
          name: 'Family pantry',
          locale: 'en-NA',
          currency: 'NAD',
          timezone: 'Africa/Windhoek',
        ),
      );

      expect(created?.name, 'Family pantry');
      expect(transport.switches, <String>['created-home']);
      expect(store.value, 'created-home');
      expect(manager.snapshot.status, HomeSessionStatus.ready);
    },
  );

  test(
    'revoked membership closes active workspace and defeats late data',
    () async {
      final switchCompletion = Completer<HomeSummary>();
      final revoked = <String>[];
      final changed = <String?>[];
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[_home('home-a', 'Home A')],
        switchCompletion: switchCompletion,
      );
      final store = _MemoryActiveHomeStore(value: 'home-a');
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: store,
        onActiveHomeChanged: changed.add,
        onHomeAccessRevoked: revoked.add,
      );
      addTearDown(manager.dispose);

      final loading = manager.load();
      await Future<void>.delayed(Duration.zero);
      await manager.handleMembershipRevoked('home-a');
      switchCompletion.complete(_home('home-a', 'Home A'));
      await loading;

      expect(manager.snapshot.status, HomeSessionStatus.accessRevoked);
      expect(manager.snapshot.activeHome, isNull);
      expect(manager.snapshot.memberships, isEmpty);
      expect(store.value, isNull);
      expect(changed, <String?>[null]);
      expect(revoked, <String>['home-a']);
    },
  );

  test(
    'removed home purges before an unrelated invitation request fails',
    () async {
      final revoked = <String>[];
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[_home('home-a', 'Home A')],
      );
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: _MemoryActiveHomeStore(value: 'home-a'),
        onHomeAccessRevoked: revoked.add,
      );
      addTearDown(manager.dispose);
      await manager.load(sessionActiveHomeId: 'home-a');

      transport.homes.clear();
      transport.pendingInvitationFailure = Exception('invitation timeout');
      await manager.load(sessionActiveHomeId: 'home-a');

      expect(revoked, <String>['home-a']);
      expect(manager.snapshot.status, HomeSessionStatus.selectionRequired);
      expect(manager.snapshot.activeHome, isNull);
      expect(manager.snapshot.pendingInvitations, isEmpty);
      expect(manager.snapshot.safeMessage, contains('invitations'));
    },
  );

  test('invitation creation remains scoped to the active home', () async {
    final transport = _FakeHomeTransport(
      homes: <HomeSummary>[_home('home-a', 'Home A')],
    );
    final manager = HomeSessionManager(
      transport: transport,
      activeHomeStore: _MemoryActiveHomeStore(),
    );
    addTearDown(manager.dispose);
    await manager.load(sessionActiveHomeId: 'home-a');

    final invitation = await manager.invite(
      email: 'member@example.com',
      role: HomeRole.member,
    );

    expect(invitation?.homeId, 'home-a');
    expect(manager.snapshot.invitations.single.email, 'member@example.com');
  });

  test(
    'stale member or invitation target never closes the active home',
    () async {
      final store = _MemoryActiveHomeStore(value: 'home-a');
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[_home('home-a', 'Home A')],
        governanceTargetFailure: const HomeTransportException(
          kind: HomeFailureKind.conflict,
          safeMessage: 'This target is no longer available.',
          homeId: 'home-a',
        ),
      );
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: store,
      );
      addTearDown(manager.dispose);
      await manager.load(sessionActiveHomeId: 'home-a');

      await manager.changeMembershipRole(
        membership: _membership(),
        role: HomeRole.member,
      );
      expect(manager.snapshot.status, HomeSessionStatus.ready);
      expect(manager.snapshot.activeHome?.id, 'home-a');
      expect(store.value, 'home-a');

      await manager.revokeInvitation(
        HomeInvitation(
          id: 'stale-invitation',
          homeId: 'home-a',
          email: 'stale@example.com',
          role: HomeRole.viewer,
          status: InvitationStatus.pending,
          expiresAt: DateTime.utc(2026, 8, 20),
          revision: 2,
        ),
      );
      expect(manager.snapshot.status, HomeSessionStatus.ready);
      expect(manager.snapshot.activeHome?.id, 'home-a');
      expect(store.value, 'home-a');
      expect(
        manager.snapshot.safeMessage,
        'This target is no longer available.',
      );
    },
  );

  test(
    'recipient invitation acceptance uses revision and opens new home',
    () async {
      final invitation = RecipientHomeInvitation(
        id: 'invitation-recipient',
        homeId: 'shared-home',
        homeName: 'Shared home',
        inviterUserId: 'owner-user',
        role: HomeRole.viewer,
        expiresAt: DateTime.utc(2026, 8, 20),
        revision: 4,
      );
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[_home('home-a', 'Home A')],
        pendingInvitations: <RecipientHomeInvitation>[invitation],
      );
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: _MemoryActiveHomeStore(),
      );
      addTearDown(manager.dispose);
      await manager.load(sessionActiveHomeId: 'home-a');

      await manager.acceptPendingInvitation(invitation);

      expect(transport.acceptedRevision, 4);
      expect(manager.snapshot.activeHome?.id, 'shared-home');
      expect(manager.snapshot.pendingInvitations, isEmpty);
    },
  );

  test(
    'unavailable recipient invitation keeps an unrelated active home open',
    () async {
      final invitation = RecipientHomeInvitation(
        id: 'expired-invitation',
        homeId: 'other-home',
        homeName: 'Other home',
        inviterUserId: 'other-owner',
        role: HomeRole.member,
        expiresAt: DateTime.utc(2026, 8, 1),
        revision: 3,
      );
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[_home('home-a', 'Home A')],
        pendingInvitations: <RecipientHomeInvitation>[invitation],
        acceptFailure: const HomeTransportException(
          kind: HomeFailureKind.conflict,
          safeMessage: 'This invitation is no longer available.',
        ),
      );
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: _MemoryActiveHomeStore(value: 'home-a'),
      );
      addTearDown(manager.dispose);
      await manager.load(sessionActiveHomeId: 'home-a');

      await manager.acceptPendingInvitation(invitation);

      expect(manager.snapshot.status, HomeSessionStatus.ready);
      expect(manager.snapshot.activeHome?.id, 'home-a');
      expect(manager.snapshot.homes.single.id, 'home-a');
      expect(
        manager.snapshot.safeMessage,
        'This invitation is no longer available.',
      );
    },
  );

  test('home settings update replaces active and chooser summaries', () async {
    final transport = _FakeHomeTransport(
      homes: <HomeSummary>[_home('home-a', 'My home')],
    );
    final manager = HomeSessionManager(
      transport: transport,
      activeHomeStore: _MemoryActiveHomeStore(),
    );
    addTearDown(manager.dispose);
    await manager.load(sessionActiveHomeId: 'home-a');

    await manager.updateActiveHome(
      name: 'Family pantry',
      locale: 'en-GB',
      currency: 'GBP',
      timezone: 'Europe/London',
    );

    expect(transport.updatedExpectedRevision, 1);
    expect(manager.snapshot.activeHome?.name, 'Family pantry');
    expect(manager.snapshot.homes.single.currency, 'GBP');
  });

  test(
    'governance refresh loads members, invitations, and role policies',
    () async {
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[_home('home-a', 'Home A')],
      );
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: _MemoryActiveHomeStore(),
      );
      addTearDown(manager.dispose);
      await manager.load(sessionActiveHomeId: 'home-a');

      await manager.refreshGovernance();

      expect(manager.snapshot.memberships, hasLength(1));
      expect(manager.snapshot.permissionPolicies.single.role, HomeRole.member);
    },
  );

  test(
    'activation publishes backend-effective permissions fail closed',
    () async {
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[_home('home-a', 'Home A', role: HomeRole.member)],
        policies: <HomePermissionPolicy>[
          HomePermissionPolicy(
            role: HomeRole.member,
            revision: 2,
            permissions: const <String>{
              HomePermissions.homeRead,
              HomePermissions.inventoryRead,
            },
            configurable: true,
          ),
        ],
      );
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: _MemoryActiveHomeStore(),
      );
      addTearDown(manager.dispose);

      await manager.load(sessionActiveHomeId: 'home-a');

      expect(manager.snapshot.status, HomeSessionStatus.ready);
      expect(manager.snapshot.allows(HomePermissions.inventoryRead), isTrue);
      expect(manager.snapshot.allows(HomePermissions.inventoryWrite), isFalse);

      final missingPolicy = HomeSessionSnapshot(
        status: HomeSessionStatus.ready,
        homes: <HomeSummary>[_home('home-b', 'Home B', role: HomeRole.manager)],
        activeHome: _home('home-b', 'Home B', role: HomeRole.manager),
      );
      expect(missingPolicy.effectivePermissions, isEmpty);
    },
  );

  test('unexpected activation failure always leaves loading state', () async {
    final transport = _FakeHomeTransport(
      homes: <HomeSummary>[_home('home-a', 'Home A')],
      unexpectedPolicyFailure: Exception('storage failure'),
    );
    final manager = HomeSessionManager(
      transport: transport,
      activeHomeStore: _MemoryActiveHomeStore(),
    );
    addTearDown(manager.dispose);

    await manager.load(sessionActiveHomeId: 'home-a');

    expect(manager.snapshot.status, HomeSessionStatus.failure);
    expect(manager.snapshot.safeMessage, contains('opened safely'));
  });

  for (final scenario
      in <
        ({
          HomeRole role,
          Set<String> permissions,
          int membershipCalls,
          int invitationCalls,
        })
      >[
        (
          role: HomeRole.manager,
          permissions: const <String>{
            'home.read',
            'members.read',
            'members.invite',
          },
          membershipCalls: 1,
          invitationCalls: 1,
        ),
        (
          role: HomeRole.member,
          permissions: const <String>{'home.read', 'members.read'},
          membershipCalls: 1,
          invitationCalls: 0,
        ),
        (
          role: HomeRole.viewer,
          permissions: const <String>{'home.read'},
          membershipCalls: 0,
          invitationCalls: 0,
        ),
      ]) {
    test(
      '${scenario.role.name} governance loads only permitted collections',
      () async {
        final transport = _FakeHomeTransport(
          homes: <HomeSummary>[_home('home-a', 'Home A', role: scenario.role)],
          policies: <HomePermissionPolicy>[
            HomePermissionPolicy(
              role: scenario.role,
              revision: 1,
              permissions: scenario.permissions,
              configurable: false,
            ),
          ],
        );
        final manager = HomeSessionManager(
          transport: transport,
          activeHomeStore: _MemoryActiveHomeStore(),
        );
        addTearDown(manager.dispose);
        await manager.load(sessionActiveHomeId: 'home-a');

        await manager.refreshGovernance();

        expect(transport.membershipListCalls, scenario.membershipCalls);
        expect(transport.invitationListCalls, scenario.invitationCalls);
        expect(manager.snapshot.permissionPolicies, hasLength(1));
      },
    );
  }
}

HomeSummary _home(String id, String name, {HomeRole role = HomeRole.owner}) {
  return HomeSummary(
    id: id,
    name: name,
    locale: 'en-NA',
    currency: 'NAD',
    timezone: 'Africa/Windhoek',
    role: role,
    revision: 1,
  );
}

HomeMembership _membership() {
  return HomeMembership(
    userId: 'user-1',
    displayName: 'Owner',
    role: HomeRole.owner,
    revision: 1,
  );
}

final class _MemoryActiveHomeStore implements ActiveHomeStore {
  _MemoryActiveHomeStore({this.value});

  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String homeId) async => value = homeId;
}

final class _FakeHomeTransport implements HomeTransportPort {
  _FakeHomeTransport({
    required this.homes,
    this.switchCompletion,
    List<RecipientHomeInvitation>? pendingInvitations,
    this.policies,
    this.acceptFailure,
    this.governanceTargetFailure,
    this.unexpectedPolicyFailure,
  }) : pendingInvitations = pendingInvitations ?? <RecipientHomeInvitation>[];

  final List<HomeSummary> homes;
  final Completer<HomeSummary>? switchCompletion;
  final List<RecipientHomeInvitation> pendingInvitations;
  final List<HomePermissionPolicy>? policies;
  final HomeTransportException? acceptFailure;
  final HomeTransportException? governanceTargetFailure;
  final Object? unexpectedPolicyFailure;
  Object? pendingInvitationFailure;
  Completer<List<HomeSummary>>? nextHomesResponse;
  final List<String> switches = <String>[];
  final Map<String, Completer<HomeSummary>> switchCompletions =
      <String, Completer<HomeSummary>>{};
  final List<String> leaveCalls = <String>[];
  int? acceptedRevision;
  int? updatedExpectedRevision;
  int membershipListCalls = 0;
  int invitationListCalls = 0;

  @override
  Future<HomeSummary> acceptPendingInvitation({
    required String invitationId,
    required int expectedRevision,
  }) async {
    if (acceptFailure case final failure?) {
      throw failure;
    }
    acceptedRevision = expectedRevision;
    pendingInvitations.removeWhere((item) => item.id == invitationId);
    final accepted = _home('shared-home', 'Shared home');
    homes.add(accepted);
    return accepted;
  }

  @override
  Future<void> changeMembershipRole({
    required String homeId,
    required String userId,
    required HomeRole role,
    required int expectedRevision,
  }) async {
    if (governanceTargetFailure case final failure?) {
      throw failure;
    }
  }

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
  Future<HomeInvitation> createInvitation({
    required String homeId,
    required String email,
    required HomeRole role,
  }) async {
    return HomeInvitation(
      id: 'invitation-1',
      homeId: homeId,
      email: email,
      role: role,
      status: InvitationStatus.pending,
      expiresAt: DateTime.utc(2026, 8, 5),
      revision: 1,
    );
  }

  @override
  Future<void> leaveHome(String homeId) async => leaveCalls.add(homeId);

  @override
  Future<List<HomeSummary>> listHomes() async {
    final response = nextHomesResponse;
    if (response != null) {
      nextHomesResponse = null;
      return response.future;
    }
    return List<HomeSummary>.of(homes);
  }

  @override
  Future<List<HomeInvitation>> listInvitations(String homeId) async {
    invitationListCalls++;
    return <HomeInvitation>[];
  }

  @override
  Future<List<RecipientHomeInvitation>> listPendingInvitations() async {
    if (pendingInvitationFailure case final failure?) {
      throw failure;
    }
    return List<RecipientHomeInvitation>.of(pendingInvitations);
  }

  @override
  Future<List<HomeMembership>> listMemberships(String homeId) async {
    membershipListCalls++;
    return <HomeMembership>[_membership()];
  }

  @override
  Future<void> revokeInvitation({
    required String homeId,
    required String invitationId,
    required int expectedRevision,
  }) async {
    if (governanceTargetFailure case final failure?) {
      throw failure;
    }
  }

  @override
  Future<List<HomePermissionPolicy>> listPermissionPolicies(
    String homeId,
  ) async {
    if (unexpectedPolicyFailure case final failure?) {
      throw failure;
    }
    return policies ??
        <HomePermissionPolicy>[
          HomePermissionPolicy(
            role: HomeRole.member,
            revision: 1,
            permissions: const <String>{'home.read'},
            configurable: true,
          ),
        ];
  }

  @override
  Future<HomePermissionPolicy> putPermissionPolicy({
    required String homeId,
    required HomeRole role,
    required Set<String> permissions,
    required int expectedRevision,
  }) async => HomePermissionPolicy(
    role: role,
    revision: expectedRevision + 1,
    permissions: permissions,
    configurable: true,
  );

  @override
  Future<HomeSummary> switchActiveHome(String homeId) async {
    switches.add(homeId);
    final targetedCompletion = switchCompletions[homeId];
    if (targetedCompletion != null) {
      return targetedCompletion.future;
    }
    if (switchCompletion != null) {
      return switchCompletion!.future;
    }
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
  }) async {
    updatedExpectedRevision = expectedRevision;
    final updated = HomeSummary(
      id: homeId,
      name: name,
      locale: locale,
      currency: currency,
      timezone: timezone,
      role: HomeRole.owner,
      revision: expectedRevision + 1,
    );
    final index = homes.indexWhere((home) => home.id == homeId);
    homes[index] = updated;
    return updated;
  }
}
