import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/reporting/application/household_report_service.dart';
import 'package:providentia/features/reporting/application/reporting_controller.dart';
import 'package:providentia/features/reporting/domain/household_report.dart';
import 'package:providentia/features/reporting/presentation/household_reports_page.dart';

void main() {
  group('home-scoped report service', () {
    test(
      'accepts a complete same-home report and calculates evidence metrics',
      () async {
        final report = _report();
        final loaded = await HouseholdReportService(
          _ReportRepository(report),
        ).load(homeId: 'home-1');

        expect(loaded.allScopedLines, hasLength(9));
        expect(loaded.countVariances.single.variance, -2);
        expect(loaded.consumption.single.hasEstimate, isFalse);
        expect(loaded.backtest!.coverage, 0.5);
        expect(loaded.backtest!.precision, 0.75);
        expect(loaded.backtest!.overrideRate, 0.25);
        const estimated = ConsumptionEvidenceReportLine(
          homeId: 'home-1',
          productName: 'Rice',
          confidence: EvidenceConfidence.medium,
          eligibleIntervalCount: 3,
          coveredDays: 90,
          limitation: '',
          estimatedDailyBaseQuantity: 25,
          baseUnit: 'g',
        );
        expect(estimated.hasEstimate, isTrue);
        const emptyBacktest = BacktestCoverageReport(
          homeId: 'home-1',
          algorithmVersion: 'v0',
          totalCandidatePeriods: 0,
          evaluatedPeriods: 0,
          suggestionCount: 0,
          trueNeedCount: 0,
          missedStockOutCount: 0,
          overbuyBaseQuantity: 0,
          overrideCount: 0,
        );
        expect(emptyBacktest.coverage, isNull);
        expect(emptyBacktest.precision, isNull);
        expect(emptyBacktest.overrideRate, isNull);
      },
    );

    test('rejects any nested line from a different home', () async {
      final mixed = HouseholdReport(
        homeId: 'home-1',
        generatedAt: _instant,
        balances: <InventoryBalanceReportLine>[_balance(homeId: 'home-2')],
      );
      final service = HouseholdReportService(_ReportRepository(mixed));

      await expectLater(
        service.load(homeId: 'home-1'),
        throwsA(isA<CrossHomeReportDataException>()),
      );
      await expectLater(service.load(homeId: ' '), throwsArgumentError);
    });

    test('explicit unavailable adapter fails closed', () async {
      const repository = UnavailableHouseholdReportRepository();
      await expectLater(
        repository.load(homeId: 'home-1'),
        throwsA(isA<ReportContractUnavailableException>()),
      );
    });
  });

  group('reporting controller', () {
    test('clears report immediately when the active home changes', () async {
      final repository = _SwitchableReportRepository();
      final controller = ReportingController(
        service: HouseholdReportService(repository),
        activeHomeId: 'home-1',
      );
      await controller.load();
      expect(controller.status, ReportingStatus.ready);
      expect(controller.report?.homeId, 'home-1');

      controller.switchHome('home-2');
      expect(controller.activeHomeId, 'home-2');
      expect(controller.status, ReportingStatus.idle);
      expect(controller.report, isNull);
      expect(() => controller.switchHome(' '), throwsArgumentError);
    });

    test('ignores a response from the previously selected home', () async {
      final repository = _DelayedReportRepository();
      final controller = ReportingController(
        service: HouseholdReportService(repository),
        activeHomeId: 'home-1',
      );
      final oldLoad = controller.load();
      controller.switchHome('home-2');
      repository.complete('home-1', _report());
      await oldLoad;

      expect(controller.activeHomeId, 'home-2');
      expect(controller.status, ReportingStatus.idle);
      expect(controller.report, isNull);
    });

    test('maps unavailable, forbidden and safe failure states', () async {
      final cases = <Object, ReportingStatus>{
        const ReportContractUnavailableException():
            ReportingStatus.contractUnavailable,
        const ReportForbiddenException(): ReportingStatus.forbidden,
        Exception('private server detail'): ReportingStatus.failure,
      };
      for (final entry in cases.entries) {
        final controller = ReportingController(
          service: HouseholdReportService(_ThrowingRepository(entry.key)),
          activeHomeId: 'home-1',
        );
        await controller.load();
        expect(controller.status, entry.value);
        expect(controller.report, isNull);
      }
    });
  });

  testWidgets('report page renders all evidence-aware sections responsively', (
    tester,
  ) async {
    final controller = ReportingController(
      service: HouseholdReportService(_ReportRepository(_report())),
      activeHomeId: 'home-1',
    );
    await controller.load();
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HouseholdReportsPage(controller: controller)),
      ),
    );

    for (final heading in <String>[
      'Balances by location',
      'Movement ledger',
      'Monthly purchases',
      'Consumption evidence',
      'Count variance',
      'Private price observations',
      'Unresolved lines',
      'Suggestion feedback',
      'Suggestion evaluation',
    ]) {
      expect(find.text(heading), findsOneWidget);
    }
    expect(find.textContaining('only one reliable count'), findsOneWidget);
    expect(find.textContaining('insufficient comparison'), findsOneWidget);
    expect(find.textContaining('Coverage 50%'), findsOneWidget);

    tester.view.physicalSize = const Size(600, 1600);
    await tester.pump();
    expect(find.text('Household reports'), findsOneWidget);
  });

  testWidgets(
    'report page exposes unavailable contract without private detail',
    (tester) async {
      final controller = ReportingController(
        service: HouseholdReportService(
          _ThrowingRepository(const ReportContractUnavailableException()),
        ),
        activeHomeId: 'home-1',
      );
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HouseholdReportsPage(controller: controller)),
        ),
      );

      expect(find.text('Reports are not connected'), findsOneWidget);
      expect(find.textContaining('pinned backend contract'), findsOneWidget);
      expect(find.textContaining('home-1'), findsNothing);
    },
  );

  testWidgets('report page renders idle, loading, forbidden and safe failure', (
    tester,
  ) async {
    final delayed = _DelayedReportRepository();
    final loadingController = ReportingController(
      service: HouseholdReportService(delayed),
      activeHomeId: 'home-1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdReportsPage(controller: loadingController),
        ),
      ),
    );
    expect(find.text('Household reports'), findsOneWidget);

    final pending = loadingController.load();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    delayed.complete('home-1', _report());
    await pending;

    final states = <Object, String>{
      const ReportForbiddenException(): 'Home access required',
      Exception('private server detail'): 'Reports could not be loaded',
    };
    for (final entry in states.entries) {
      final controller = ReportingController(
        service: HouseholdReportService(_ThrowingRepository(entry.key)),
        activeHomeId: 'home-1',
      );
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HouseholdReportsPage(controller: controller)),
        ),
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(find.textContaining('private server detail'), findsNothing);
    }
  });
}

final DateTime _instant = DateTime.utc(2026, 7, 30);

HouseholdReport _report() {
  return HouseholdReport(
    homeId: 'home-1',
    generatedAt: _instant,
    balances: <InventoryBalanceReportLine>[_balance(homeId: 'home-1')],
    movements: <StockMovementReportLine>[
      StockMovementReportLine(
        homeId: 'home-1',
        movementId: 'movement-1',
        productName: 'Rice Basmati',
        movementType: 'count_adjustment',
        signedQuantity: 1,
        unit: 'bag',
        effectiveAt: _instant,
      ),
    ],
    monthlyPurchases: const <MonthlyPurchaseReportLine>[
      MonthlyPurchaseReportLine(
        homeId: 'home-1',
        productName: 'Rice Basmati',
        yearMonth: '2026-07',
        originalQuantity: 1,
        originalUnit: '5 kg bag',
        normalizedBaseQuantity: 5000,
        normalizedBaseUnit: 'g',
      ),
    ],
    consumption: const <ConsumptionEvidenceReportLine>[
      ConsumptionEvidenceReportLine(
        homeId: 'home-1',
        productName: 'Rice Basmati',
        confidence: EvidenceConfidence.insufficient,
        eligibleIntervalCount: 0,
        coveredDays: 0,
        limitation: 'Low confidence: only one reliable count is available.',
      ),
    ],
    countVariances: <CountVarianceReportLine>[
      CountVarianceReportLine(
        homeId: 'home-1',
        productName: 'Rice Basmati',
        locationName: 'Pantry',
        projectedQuantity: 4,
        countedQuantity: 2,
        unit: 'bags',
        countedAt: _instant,
      ),
    ],
    prices: <PriceObservationReportLine>[
      PriceObservationReportLine(
        homeId: 'home-1',
        productName: 'Rice Basmati',
        packText: '5 kg',
        storeName: 'Local store',
        currency: 'NAD',
        netPrice: 199.99,
        observedAt: _instant,
        observationCount: 1,
        comparable: false,
      ),
    ],
    unresolved: <UnresolvedLineReportLine>[
      UnresolvedLineReportLine(
        homeId: 'home-1',
        lineId: 'line-1',
        rawDescription: 'Tea',
        sourceType: 'opening count',
        observedAt: _instant,
      ),
    ],
    suggestionFeedback: <SuggestionFeedbackReportLine>[
      SuggestionFeedbackReportLine(
        homeId: 'home-1',
        suggestionId: 'suggestion-1',
        productName: 'Rice Basmati',
        action: 'edited_quantity',
        algorithmVersion: 'deterministic-v1',
        recordedAt: _instant,
      ),
    ],
    backtest: const BacktestCoverageReport(
      homeId: 'home-1',
      algorithmVersion: 'deterministic-v1',
      totalCandidatePeriods: 8,
      evaluatedPeriods: 4,
      suggestionCount: 4,
      trueNeedCount: 3,
      missedStockOutCount: 1,
      overbuyBaseQuantity: 500,
      overrideCount: 1,
    ),
  );
}

InventoryBalanceReportLine _balance({required String homeId}) {
  return InventoryBalanceReportLine(
    homeId: homeId,
    homeProductId: 'home-product-1',
    productName: 'Rice Basmati',
    locationName: 'Pantry',
    quantity: 2,
    unit: 'bags',
    asOf: _instant,
    hasDataQualityWarning: false,
  );
}

final class _ReportRepository implements HouseholdReportRepository {
  const _ReportRepository(this.report);

  final HouseholdReport report;

  @override
  Future<HouseholdReport> load({required String homeId}) async => report;
}

final class _SwitchableReportRepository implements HouseholdReportRepository {
  @override
  Future<HouseholdReport> load({required String homeId}) async {
    return HouseholdReport(homeId: homeId, generatedAt: _instant);
  }
}

final class _DelayedReportRepository implements HouseholdReportRepository {
  final Map<String, Completer<HouseholdReport>> _completers =
      <String, Completer<HouseholdReport>>{};

  void complete(String homeId, HouseholdReport report) {
    _completers[homeId]!.complete(report);
  }

  @override
  Future<HouseholdReport> load({required String homeId}) {
    return (_completers[homeId] ??= Completer<HouseholdReport>()).future;
  }
}

final class _ThrowingRepository implements HouseholdReportRepository {
  const _ThrowingRepository(this.error);

  final Object error;

  @override
  Future<HouseholdReport> load({required String homeId}) async {
    throw error;
  }
}
