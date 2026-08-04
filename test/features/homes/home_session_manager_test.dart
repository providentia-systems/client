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
      final membershipCompletion = Completer<List<HomeMembership>>();
      final revoked = <String>[];
      final changed = <String?>[];
      final transport = _FakeHomeTransport(
        homes: <HomeSummary>[_home('home-a', 'Home A')],
        membershipCompletion: membershipCompletion,
      );
      final store = _MemoryActiveHomeStore(value: 'home-a');
      final manager = HomeSessionManager(
        transport: transport,
        activeHomeStore: store,
        onActiveHomeChanged: changed.add,
        onHomeAccessRevoked: revoked.add,
      );
      addTearDown(manager.dispose);

      final loading = manager.load(sessionActiveHomeId: 'home-a');
      await Future<void>.delayed(Duration.zero);
      await manager.handleMembershipRevoked('home-a');
      membershipCompletion.complete(<HomeMembership>[_membership()]);
      await loading;

      expect(manager.snapshot.status, HomeSessionStatus.accessRevoked);
      expect(manager.snapshot.activeHome, isNull);
      expect(manager.snapshot.memberships, isEmpty);
      expect(store.value, isNull);
      expect(changed, <String?>[null]);
      expect(revoked, <String>['home-a']);
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
}

HomeSummary _home(String id, String name) {
  return HomeSummary(
    id: id,
    name: name,
    locale: 'en-NA',
    currency: 'NAD',
    timezone: 'Africa/Windhoek',
    role: HomeRole.owner,
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

final class _FakeHomeTransport
    implements HomeTransportPort, HomeInvitationAdministrationPort {
  _FakeHomeTransport({required this.homes, this.membershipCompletion});

  final List<HomeSummary> homes;
  final Completer<List<HomeMembership>>? membershipCompletion;
  final List<String> switches = <String>[];

  @override
  Future<HomeSummary> acceptInvitation(String token) async =>
      homes.isEmpty ? _home('accepted-home', 'Accepted home') : homes.first;

  @override
  Future<void> changeMembershipRole({
    required String homeId,
    required String userId,
    required HomeRole role,
    required int expectedRevision,
  }) async {}

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
  Future<void> leaveHome(String homeId) async {}

  @override
  Future<List<HomeSummary>> listHomes() async => List<HomeSummary>.of(homes);

  @override
  Future<List<HomeInvitation>> listInvitations(String homeId) async =>
      <HomeInvitation>[];

  @override
  Future<List<HomeMembership>> listMemberships(String homeId) async {
    if (membershipCompletion != null) {
      return membershipCompletion!.future;
    }
    return <HomeMembership>[_membership()];
  }

  @override
  Future<void> revokeInvitation({
    required String homeId,
    required String invitationId,
    required int expectedRevision,
  }) async {}

  @override
  Future<HomeSummary> switchActiveHome(String homeId) async {
    switches.add(homeId);
    return homes.firstWhere((home) => home.id == homeId);
  }
}
