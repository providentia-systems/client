import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/reporting/application/household_report_service.dart';
import 'package:providentia/features/reporting/application/reporting_controller.dart';
import 'package:providentia/features/reporting/infrastructure/generated_household_report_repository.dart';
import 'package:providentia/features/reporting/presentation/household_reports_page.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  testWidgets(
    'current adapter facts and currency-isolated totals are visible',
    (tester) async {
      final requested = <String>[];
      final controller = _controller((request) async {
        requested.add(request.url.path);
        return _json(_body(request.url.path));
      });
      addTearDown(controller.dispose);
      await controller.load();
      await _show(tester, controller);

      expect(requested, hasLength(4));
      expect(controller.status, ReportingStatus.ready);
      expect(find.text('Rice'), findsOneWidget);
      expect(find.textContaining('Quantity 5.25'), findsOneWidget);
      expect(find.text('2026-10 · NAD 25'), findsOneWidget);
      expect(find.text('2026-10 · USD 10'), findsOneWidget);
      expect(find.textContaining('1 receipt · Market'), findsOneWidget);
      expect(find.text('Oats · high'), findsOneWidget);
      expect(
        find.textContaining('Estimated quantity/day 0.125'),
        findsOneWidget,
      );
      expect(find.textContaining('Counts are sparse.'), findsOneWidget);
      expect(find.text('Soap'), findsOneWidget);
      expect(find.textContaining('Suggested quantity 1.75'), findsOneWidget);
      expect(find.textContaining('NAD 42.75 · 2 packs'), findsOneWidget);
      expect(find.text('Balances by location'), findsNothing);
      expect(find.text('Movement ledger'), findsNothing);
      expect(find.textContaining('NAD 35'), findsNothing);
      expect(tester.takeException(), isNull);

      controller.switchHome(_otherHome);
      await tester.pumpAndSettle();
      expect(find.text('Rice'), findsNothing);
      expect(find.text('2026-10 · NAD 25'), findsNothing);
      expect(find.text('Load reports'), findsOneWidget);
    },
  );

  testWidgets('empty current reports do not fall back to legacy collections', (
    tester,
  ) async {
    final controller = _controller((request) async {
      final body = _body(request.url.path);
      body['data'] = <Object?>[];
      body.remove('priceComparisons');
      return _json(body);
    });
    addTearDown(controller.dispose);
    await controller.load();
    await _show(tester, controller);

    expect(controller.status, ReportingStatus.ready);
    expect(find.text('No inventory facts are available.'), findsOneWidget);
    expect(
      find.text('No committed purchase totals are available.'),
      findsOneWidget,
    );
    expect(
      find.text('No consumption estimates are available.'),
      findsOneWidget,
    );
    expect(find.text('No shopping suggestions are available.'), findsOneWidget);
    expect(find.text('Balances by location'), findsNothing);
    expect(find.text('Reports are temporarily unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid current payload is an error, never an empty report', (
    tester,
  ) async {
    final controller = _controller((request) async {
      final body = _body(request.url.path);
      if (request.url.path.endsWith('/inventory')) {
        body['data'] = <Object?>[
          <String, Object?>{'homeId': _otherHome},
        ];
      }
      return _json(body);
    });
    addTearDown(controller.dispose);
    await controller.load();
    await _show(tester, controller);

    expect(controller.status, ReportingStatus.contractUnavailable);
    expect(find.text('Reports are temporarily unavailable'), findsOneWidget);
    expect(find.text('No inventory facts are available.'), findsNothing);
    expect(find.text('Rice'), findsNothing);
  });
}

Future<void> _show(WidgetTester tester, ReportingController controller) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: HouseholdReportsPage(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

ReportingController _controller(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = MockClient(handler);
  addTearDown(client.close);
  return ReportingController(
    service: HouseholdReportService(
      GeneratedHouseholdReportRepository(
        ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: client,
        ),
      ),
    ),
    activeHomeId: _home,
  );
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const <String, String>{'content-type': 'application/json'},
);

Map<String, Object?> _body(String path) {
  final kind = path.split('/').last;
  return <String, Object?>{
    'type': kind,
    'asOf': '2026-10-03T12:00:00Z',
    if (kind == 'purchases')
      'currencyPolicy': 'totals-are-never-combined-across-currencies',
    'data': switch (kind) {
      'inventory' => <Object?>[
        <String, Object?>{
          'homeProductId': _product,
          'productName': 'Rice',
          'packText': '1 kg',
          'factualQuantity': '5.25',
        },
      ],
      'purchases' => <Object?>[
        <String, Object?>{
          'month': '2026-10',
          'currency': 'NAD',
          'storeName': 'Market',
          'receiptCount': 1,
          'total': '25',
        },
        <String, Object?>{
          'month': '2026-10',
          'currency': 'USD',
          'receiptCount': 1,
          'total': '10',
        },
      ],
      'consumption' => <Object?>[
        <String, Object?>{
          'id': _estimate,
          'homeProductId': _product,
          'productName': 'Oats',
          'method': 'count_intervals',
          'dailyRate': '0.125',
          'variability': '0.01',
          'sampleIntervals': 3,
          'coverageDays': 91,
          'purchaseSamples': 4,
          'confidenceScore': '0.8125',
          'confidenceBand': 'high',
          'limitations': <String>['Counts are sparse.'],
          'asOf': '2026-10-03T12:00:00Z',
          'inputWatermark': _watermark,
        },
      ],
      'suggestions' => <Object?>[
        <String, Object?>{
          'id': _suggestion,
          'homeProductId': _product,
          'productName': 'Soap',
          'packText': '1 pack',
          'expectedDemand': '2.25',
          'safetyStock': '0.5',
          'factualStock': '1',
          'usableStock': '1',
          'requiredQuantity': '1.75',
          'confidenceScore': '0.75',
          'confidenceBand': 'medium',
          'status': 'active',
          'expiresAt': '2026-10-10T12:00:00Z',
          'modelVersion': 'suggestion-v1',
          'asOf': '2026-10-03T12:00:00Z',
          'inputWatermark': _watermark,
        },
      ],
      _ => throw StateError('Unexpected request: $path'),
    },
    if (kind == 'suggestions')
      'priceComparisons': <Object?>[
        <String, Object?>{
          'packId': _pack,
          'productName': 'Compared soap',
          'currency': 'NAD',
          'packCount': 2,
          'effectiveTotal': '42.75',
          'excessQuantity': '0.75',
          'priceObservedAt': '2026-10-02T09:00:00Z',
          'selected': true,
          'reason': 'lowest comparable total',
        },
      ],
  };
}

const _home = '01912345-6789-7abc-8def-0123456789ab';
const _otherHome = '01912345-6789-7abc-8def-1123456789ab';
const _product = '01912345-6789-7abc-8def-2123456789ab';
const _estimate = '01912345-6789-7abc-8def-5123456789ab';
const _suggestion = '01912345-6789-7abc-8def-6123456789ab';
const _pack = '01912345-6789-7abc-8def-7123456789ab';
const _watermark =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
