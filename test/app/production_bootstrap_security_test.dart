import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/production_bootstrap_app.dart';
import 'package:providentia/features/homes/application/home_ports.dart';
import 'package:providentia/features/homes/application/home_session_manager.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/presentation/homes_controller.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

void main() {
  test('production composes revocation, policy, and cross-tab protections', () {
    final source = File(
      'lib/app/production_bootstrap_app.dart',
    ).readAsStringSync();
    final revocationSource = File(
      'lib/features/homes/infrastructure/home_data_revocation.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('sessionCoordination: PlatformSessionCoordination()'),
    );
    expect(source, contains('onHomeAccessRevoked: _scheduleRevokedHomePurge'));
    expect(source, contains('coordinateActiveHomeMutation<HomeSummary>'));
    expect(source, contains('coordinateActiveHomeMutation<void>'));
    expect(source, isNot(contains('features/administration')));
    expect(source, isNot(contains('PlatformAdministrationController')));
    expect(source, isNot(contains('CatalogWorkbench')));
    expect(source, contains('ProductionSessionSecurityBoundary'));
    expect(source, contains('workspaceNavigatorKey: _workspaceNavigatorKey'));
    expect(source, contains('GeneratedHouseholdReportRepository'));
    expect(source, contains('GeneratedDataGovernanceRepository'));
    expect(source, contains('HomePermissions.reportsRead'));
    expect(source, contains('ProductionHouseholdReportsRoute'));
    expect(source, contains('ProductionDataGovernanceRoute'));
    expect(source, contains('GeneratedServerAiRepository'));
    expect(source, contains('ServerAiWorkspaceController'));
    expect(source, contains('Api17AiGateway'));
    expect(source, contains('RegisteredMediaSourceReader'));
    expect(source, contains('MemoryEphemeralPreparedMediaStore'));
    expect(source, contains('SanitizingImageMediaPreparer'));
    expect(source, contains('MediaAcquisitionService'));
    expect(source, contains('AiHomeCapabilities.fromPermissions'));
    expect(source, contains('ProductionAiIdentifierFactory'));
    expect(source, contains('limit: 1'));
    expect(
      source,
      contains(
        'Accepted candidates still require an ordinary purchasing or inventory command and final confirmation. No household data changed.',
      ),
    );
    expect(source, isNot(contains('ReceiptCommitPort')));
    expect(source, isNot(contains('StockCountCommitPort')));
    expect(source, contains('HouseholdWorkspaceAccess.fromPermissions'));
    expect(source, contains('SyncAvailability.authorizationDenied'));
    expect(source, contains('RevocationGuardedSynchronization'));
    expect(source, contains('with WidgetsBindingObserver'));
    expect(source, contains('WidgetsBinding.instance.addObserver(this)'));
    expect(source, contains('WidgetsBinding.instance.removeObserver(this)'));
    expect(source, contains('AppLifecycleState.resumed'));
    expect(source, contains('ProductionResumeSyncGate'));
    expect(source, contains('PrivacySafeSyncMetrics'));
    expect(source, contains('CallbackSyncMetricsSnapshotSink'));
    expect(source, contains('revokeAndWait(homeId)'));
    expect(source, contains('RevokedHomeDataPurger'));
    expect(
      source.indexOf('identitySnapshot.session?.activeHomeId'),
      lessThan(source.indexOf('identitySnapshot.currentUser?.activeHomeId')),
    );
    for (final table in <String>[
      'localRecords',
      'clientOperations',
      'localSyncCursors',
      'recordTombstones',
      'localMediaMetadata',
      'syncConflictRecords',
    ]) {
      expect(revocationSource, contains('_database.$table'), reason: table);
    }
  });

  for (final scenario in <({String name, IdentitySessionSnapshot snapshot})>[
    (
      name: 'session expiry',
      snapshot: IdentitySessionSnapshot(
        status: IdentitySessionStatus.sessionExpired,
      ),
    ),
    (
      name: 'current-device revoke',
      snapshot: const IdentitySessionSnapshot.signedOut(),
    ),
  ]) {
    testWidgets(
      '${scenario.name} clears protected snapshots and pops to sign-in root',
      (tester) async {
        final homeManager = HomeSessionManager(
          transport: _SecurityHomeTransport(),
          activeHomeStore: _SecurityActiveHomeStore(),
        );
        final homes = HomesController(homeManager);
        addTearDown(() async {
          homes.dispose();
          await homeManager.dispose();
        });
        await homes.load(sessionActiveHomeId: 'home-a');
        final navigatorKey = GlobalKey<NavigatorState>();
        final workspaceNavigatorKey = GlobalKey<NavigatorState>();
        final boundary = ProductionSessionSecurityBoundary(
          rootNavigatorKey: navigatorKey,
          workspaceNavigatorKey: workspaceNavigatorKey,
          homesController: homes,
        );
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Text('Sign-in root')),
          ),
        );
        unawaited(
          navigatorKey.currentState!.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Text('Protected account and device data'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Protected account and device data'), findsOneWidget);
        expect(homes.snapshot.activeHome, isNotNull);

        boundary.handleIdentitySession(scenario.snapshot);
        await tester.pumpAndSettle();

        expect(find.text('Sign-in root'), findsOneWidget);
        expect(find.text('Protected account and device data'), findsNothing);
        expect(homes.snapshot.homes, isEmpty);
        expect(homes.snapshot.activeHome, isNull);
      },
    );
  }

  testWidgets(
    'home permission loss dismisses outer and nested workspace routes',
    (tester) async {
      final homeManager = HomeSessionManager(
        transport: _SecurityHomeTransport(),
        activeHomeStore: _SecurityActiveHomeStore(),
      );
      final homes = HomesController(homeManager);
      addTearDown(() async {
        homes.dispose();
        await homeManager.dispose();
      });
      final rootNavigatorKey = GlobalKey<NavigatorState>();
      final workspaceNavigatorKey = GlobalKey<NavigatorState>();
      final protectedRoutes = ProductionProtectedRouteRegistry();
      var sensitiveClears = 0;
      protectedRoutes.register(() => sensitiveClears++);
      final boundary = ProductionSessionSecurityBoundary(
        rootNavigatorKey: rootNavigatorKey,
        workspaceNavigatorKey: workspaceNavigatorKey,
        homesController: homes,
        clearProtectedRouteState: protectedRoutes.clearSensitiveState,
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: MaterialApp(
            navigatorKey: workspaceNavigatorKey,
            home: const Scaffold(body: Text('Workspace root')),
          ),
        ),
      );
      unawaited(
        workspaceNavigatorKey.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Private report')),
          ),
        ),
      );
      unawaited(
        rootNavigatorKey.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Account route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(workspaceNavigatorKey.currentState!.canPop(), isTrue);
      expect(rootNavigatorKey.currentState!.canPop(), isTrue);

      boundary.handleHomeAccessChange(
        previousHomeId: 'home-a',
        currentHomeId: 'home-a',
        previousPermissions: const <String>{
          HomePermissions.reportsRead,
          HomePermissions.dataExport,
          HomePermissions.aiRead,
        },
        currentPermissions: const <String>{
          HomePermissions.reportsRead,
          HomePermissions.dataExport,
        },
      );
      await tester.pumpAndSettle();

      expect(find.text('Workspace root'), findsOneWidget);
      expect(find.text('Private report'), findsNothing);
      expect(find.text('Account route'), findsNothing);
      expect(workspaceNavigatorKey.currentState!.canPop(), isFalse);
      expect(rootNavigatorKey.currentState!.canPop(), isFalse);
      expect(sensitiveClears, 1);
    },
  );
}

final class _SecurityActiveHomeStore implements ActiveHomeStore {
  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String homeId) async => value = homeId;
}

final class _SecurityHomeTransport implements HomeTransportPort {
  final HomeSummary home = HomeSummary(
    id: 'home-a',
    name: 'My home',
    locale: 'en-NA',
    currency: 'NAD',
    timezone: 'Africa/Windhoek',
    role: HomeRole.owner,
    revision: 1,
  );

  @override
  Future<List<HomeSummary>> listHomes() async => <HomeSummary>[home];

  @override
  Future<List<RecipientHomeInvitation>> listPendingInvitations() async =>
      const <RecipientHomeInvitation>[];

  @override
  Future<List<HomePermissionPolicy>> listPermissionPolicies(
    String homeId,
  ) async => const <HomePermissionPolicy>[];

  @override
  Future<HomeSummary> switchActiveHome(String homeId) async => home;

  @override
  Future<HomeSummary> createHome(CreateHomeCommand command) =>
      throw UnimplementedError();

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
  Future<List<HomeMembership>> listMemberships(String homeId) =>
      throw UnimplementedError();

  @override
  Future<void> changeMembershipRole({
    required String homeId,
    required String userId,
    required HomeRole role,
    required int expectedRevision,
  }) => throw UnimplementedError();

  @override
  Future<List<HomeInvitation>> listInvitations(String homeId) =>
      throw UnimplementedError();

  @override
  Future<HomeInvitation> createInvitation({
    required String homeId,
    required String email,
    required HomeRole role,
  }) => throw UnimplementedError();

  @override
  Future<void> revokeInvitation({
    required String homeId,
    required String invitationId,
    required int expectedRevision,
  }) => throw UnimplementedError();

  @override
  Future<HomeSummary> acceptPendingInvitation({
    required String invitationId,
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
