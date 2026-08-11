import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/production_bootstrap_app.dart';
import 'package:providentia/features/data_governance/application/data_governance_service.dart';
import 'package:providentia/features/data_governance/domain/data_governance_models.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/reporting/application/household_report_service.dart';
import 'package:providentia/features/reporting/domain/household_report.dart';

void main() {
  test('protected route registry clears only currently registered owners', () {
    final registry = ProductionProtectedRouteRegistry();
    var firstClears = 0;
    var secondClears = 0;
    void clearFirst() => firstClears++;
    void clearSecond() => secondClears++;

    registry
      ..register(clearFirst)
      ..register(clearSecond)
      ..unregister(clearSecond)
      ..clearSensitiveState();

    expect(firstClears, 1);
    expect(secondClears, 0);
  });

  testWidgets('report route owns loading, clearing, and registry disposal', (
    tester,
  ) async {
    final registry = ProductionProtectedRouteRegistry();
    final repository = _ReportRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ProductionHouseholdReportsRoute(
          repository: repository,
          homeId: _homeId,
          protectedRouteRegistry: registry,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.homeIds, <String>[_homeId]);
    expect(find.text('Balances by location'), findsOneWidget);

    registry.clearSensitiveState();
    await tester.pump();
    expect(find.text('Load reports'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    registry.clearSensitiveState();
    expect(tester.takeException(), isNull);
  });

  testWidgets('report route emits authorization loss once', (tester) async {
    final registry = ProductionProtectedRouteRegistry();
    var authorizationLosses = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ProductionHouseholdReportsRoute(
          repository: const _ForbiddenReportRepository(),
          homeId: _homeId,
          protectedRouteRegistry: registry,
          onAuthorizationLost: () async {
            authorizationLosses++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home access required'), findsOneWidget);
    expect(authorizationLosses, 1);
    await tester.tap(find.text('Check access'));
    await tester.pumpAndSettle();
    expect(authorizationLosses, 1);
  });

  testWidgets(
    'data governance route executes account and home request lifecycles',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final registry = ProductionProtectedRouteRegistry();
      final repository = _GovernanceRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionDataGovernanceRoute(
            repository: repository,
            capabilities: DataGovernanceCapabilities.fromEffectivePermissions(
              authenticated: true,
              effectiveHomePermissions: const <String>{
                HomePermissions.dataExport,
                HomePermissions.dataErasure,
              },
            ),
            activeHomeId: _homeId,
            protectedRouteRegistry: registry,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.calls, <String>['account-list', 'home-list:$_homeId']);
      await tester.tap(find.byKey(const Key('account-export')));
      await tester.pumpAndSettle();
      expect(repository.calls, contains('account-export'));
      expect(find.text('Your request has been queued.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('selected-home-export')));
      await tester.pumpAndSettle();
      expect(repository.calls, contains('home-export:$_homeId'));

      final homeCard = find.byKey(const Key('data-request-home-export'));
      await tester.ensureVisible(homeCard);
      await tester.tap(
        find.descendant(of: homeCard, matching: find.text('Cancel request')),
      );
      await tester.pumpAndSettle();
      expect(repository.calls, contains('cancel:home-export:1'));
      expect(find.text('The request was cancelled.'), findsOneWidget);

      registry.clearSensitiveState();
      await tester.pump();
      expect(find.text('No requests yet.'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      registry.clearSensitiveState();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('data governance route emits authorization loss once', (
    tester,
  ) async {
    final registry = ProductionProtectedRouteRegistry();
    var authorizationLosses = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ProductionDataGovernanceRoute(
          repository: const _ForbiddenGovernanceRepository(),
          capabilities: DataGovernanceCapabilities.fromEffectivePermissions(
            authenticated: true,
            effectiveHomePermissions: const <String>{},
          ),
          activeHomeId: null,
          protectedRouteRegistry: registry,
          onAuthorizationLost: () async {
            authorizationLosses++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Sign in again to manage your data requests.'),
      findsOneWidget,
    );
    expect(authorizationLosses, 1);
    registry.clearSensitiveState();
    await tester.pump();
    expect(authorizationLosses, 1);
  });
}

final class _ReportRepository implements HouseholdReportRepository {
  final List<String> homeIds = <String>[];

  @override
  Future<HouseholdReport> load({required String homeId}) async {
    homeIds.add(homeId);
    return HouseholdReport(homeId: homeId, generatedAt: _instant);
  }
}

final class _ForbiddenReportRepository implements HouseholdReportRepository {
  const _ForbiddenReportRepository();

  @override
  Future<HouseholdReport> load({required String homeId}) async {
    throw const ReportForbiddenException();
  }
}

final class _GovernanceRepository implements DataGovernanceRepository {
  final List<String> calls = <String>[];
  final Set<String> cancelled = <String>{};

  @override
  Future<void> cancelRequest({
    required String requestId,
    required int expectedRevision,
  }) async {
    calls.add('cancel:$requestId:$expectedRevision');
    cancelled.add(requestId);
  }

  @override
  Future<List<DataGovernanceRequest>> listAccountRequests() async {
    calls.add('account-list');
    return <DataGovernanceRequest>[
      if (!cancelled.contains('account-export'))
        _request(
          id: 'account-export',
          kind: DataGovernanceRequestKind.accountExport,
        ),
    ];
  }

  @override
  Future<List<DataGovernanceRequest>> listHomeRequests({
    required String homeId,
  }) async {
    calls.add('home-list:$homeId');
    return <DataGovernanceRequest>[
      if (!cancelled.contains('home-export'))
        _request(
          id: 'home-export',
          kind: DataGovernanceRequestKind.homeExport,
          homeId: homeId,
        ),
    ];
  }

  @override
  Future<DataGovernanceRequest> requestAccountErasure() async {
    calls.add('account-erasure');
    return _request(
      id: 'account-erasure',
      kind: DataGovernanceRequestKind.accountErasure,
    );
  }

  @override
  Future<DataGovernanceRequest> requestAccountExport() async {
    calls.add('account-export');
    return _request(
      id: 'account-export',
      kind: DataGovernanceRequestKind.accountExport,
    );
  }

  @override
  Future<DataGovernanceRequest> requestHomeErasure({
    required String homeId,
  }) async {
    calls.add('home-erasure:$homeId');
    return _request(
      id: 'home-erasure',
      kind: DataGovernanceRequestKind.homeErasure,
      homeId: homeId,
    );
  }

  @override
  Future<DataGovernanceRequest> requestHomeExport({
    required String homeId,
  }) async {
    calls.add('home-export:$homeId');
    return _request(
      id: 'home-export',
      kind: DataGovernanceRequestKind.homeExport,
      homeId: homeId,
    );
  }
}

final class _ForbiddenGovernanceRepository implements DataGovernanceRepository {
  const _ForbiddenGovernanceRepository();

  Never _forbidden() => throw const DataGovernanceRepositoryException(
    DataGovernanceFailureKind.authenticationRequired,
  );

  @override
  Future<void> cancelRequest({
    required String requestId,
    required int expectedRevision,
  }) async => _forbidden();

  @override
  Future<List<DataGovernanceRequest>> listAccountRequests() async =>
      _forbidden();

  @override
  Future<List<DataGovernanceRequest>> listHomeRequests({
    required String homeId,
  }) async => _forbidden();

  @override
  Future<DataGovernanceRequest> requestAccountErasure() async => _forbidden();

  @override
  Future<DataGovernanceRequest> requestAccountExport() async => _forbidden();

  @override
  Future<DataGovernanceRequest> requestHomeErasure({
    required String homeId,
  }) async => _forbidden();

  @override
  Future<DataGovernanceRequest> requestHomeExport({
    required String homeId,
  }) async => _forbidden();
}

DataGovernanceRequest _request({
  required String id,
  required DataGovernanceRequestKind kind,
  String? homeId,
}) => DataGovernanceRequest(
  id: id,
  kind: kind,
  scope: homeId == null
      ? DataGovernanceScope.account
      : DataGovernanceScope.home,
  status: DataGovernanceRequestStatus.queued,
  revision: 1,
  retainedDataDisclosure: const <RetainedDataDisclosure>[
    RetainedDataDisclosure(
      category: 'Audit log',
      treatment: 'Retained',
      reason: 'Legal obligation',
    ),
  ],
  homeId: homeId,
);

const String _homeId = '01912345-6789-7abc-8def-0123456789ab';
final DateTime _instant = DateTime.utc(2026, 8, 11);
