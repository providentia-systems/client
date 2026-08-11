import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/reporting/application/household_report_service.dart';
import 'package:providentia/features/reporting/domain/household_report.dart';
import 'package:providentia/features/reporting/infrastructure/generated_household_report_repository.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test(
    'maps every current report envelope and fact without decimal loss',
    () async {
      final requestedPaths = <String>[];
      final repository = GeneratedHouseholdReportRepository(
        _client((request) async {
          requestedPaths.add(request.url.path);
          return _json(_reportForPath(request.url.path));
        }),
      );

      final report = await repository.load(homeId: _homeId);

      expect(requestedPaths.toSet(), <String>{
        '/api/v1/homes/$_homeId/reports/inventory',
        '/api/v1/homes/$_homeId/reports/purchases',
        '/api/v1/homes/$_homeId/reports/consumption',
        '/api/v1/homes/$_homeId/reports/suggestions',
      });
      expect(report.homeId, _homeId);
      expect(report.sourceReports, hasLength(4));
      expect(report.generatedAt, DateTime.parse('2026-08-11T12:04:00Z'));

      final inventory = report.inventoryFacts.single;
      expect(inventory.homeProductId, _homeProductId);
      expect(inventory.productName, 'Rolled oats');
      expect(inventory.packText, '1 kg');
      expect(inventory.factualQuantity, '12.12500001');
      expect(inventory.balanceRevision, 4);
      expect(inventory.lastMovementId, _movementId);
      expect(inventory.configuredMinimum, '3.5');
      expect(inventory.alwaysKeep, isTrue);
      expect(inventory.neverSuggest, isFalse);

      final purchase = report.purchaseTotals.single;
      expect(purchase.month, '2026-08');
      expect(purchase.currency, 'NAD');
      expect(purchase.storeId, _storeId);
      expect(purchase.receiptCount, 2);
      expect(purchase.total, '999999999.12345678');
      final purchaseMetadata = report.sourceReports.singleWhere(
        (metadata) => metadata.kind == HouseholdReportKind.purchases,
      );
      expect(purchaseMetadata.currencyPolicy, contains('never-combined'));
      expect(purchaseMetadata.from, DateTime.utc(2026, 8));
      expect(purchaseMetadata.through, DateTime.utc(2026, 8, 11));

      final estimate = report.consumptionEstimates.single;
      expect(estimate.id, _estimateId);
      expect(estimate.dailyRate, '0.125');
      expect(estimate.variability, '0.01');
      expect(estimate.sampleIntervals, 3);
      expect(estimate.purchaseCadenceDays, 14);
      expect(estimate.confidenceScore, '0.8125');
      expect(estimate.confidenceBand, EvidenceConfidence.high);
      expect(estimate.limitations, <String>['Counts are sparse.']);
      expect(estimate.inputWatermark, _watermark);

      final suggestion = report.shoppingSuggestions.single;
      expect(suggestion.id, _suggestionId);
      expect(suggestion.expectedDemand, '2.25');
      expect(suggestion.factualStock, '1');
      expect(suggestion.selectedPackId, _packId);
      expect(suggestion.packCount, 2);
      expect(suggestion.status, 'active');
      expect(suggestion.modelVersion, 'suggestion-v1');

      final comparison = report.suggestionPriceComparisons.single;
      expect(comparison.suggestionId, _suggestionId);
      expect(comparison.storeId, _storeId);
      expect(comparison.currency, 'NAD');
      expect(comparison.effectiveTotal, '42.75');
      expect(comparison.excessQuantity, '0.75');
      expect(comparison.selected, isTrue);
      expect(comparison.reason, 'lowest comparable total');

      expect(
        report.allScopedLines.every((line) => line.homeId == _homeId),
        isTrue,
      );
    },
  );

  test('rejects a cross-home ID at any nested response depth', () async {
    final repository = GeneratedHouseholdReportRepository(
      _client((request) async {
        final body = _reportForPath(request.url.path);
        if (request.url.path.endsWith('/reports/consumption')) {
          final data = body['data']! as List<Object?>;
          final first = data.single! as Map<String, Object?>;
          first['opaqueFutureField'] = <String, Object?>{
            'items': <Object?>[
              <String, Object?>{'homeId': _otherHomeId},
            ],
          };
        }
        return _json(body);
      }),
    );

    await expectLater(
      repository.load(homeId: _homeId),
      throwsA(
        isA<ReportRepositoryException>().having(
          (error) => error.kind,
          'kind',
          ReportRepositoryFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test('normalizes HTTP problems without leaking backend detail', () async {
    const privateDetail = 'PRIVATE support diagnostic and household fact';
    final repository = GeneratedHouseholdReportRepository(
      _client(
        (_) async => _json(<String, Object?>{
          'type': 'https://example.test/problems/forbidden',
          'title': 'Forbidden',
          'status': 403,
          'requestId': _requestId,
          'detail': privateDetail,
        }, status: 403),
      ),
    );

    try {
      await repository.load(homeId: _homeId);
      fail('Expected a normalized repository failure.');
    } on ReportRepositoryException catch (error) {
      expect(error.kind, ReportRepositoryFailureKind.forbidden);
      expect(error.toString(), isNot(contains(privateDetail)));
    }
  });
}

Map<String, Object?> _reportForPath(String path) {
  if (path.endsWith('/reports/inventory')) {
    return <String, Object?>{
      'type': 'inventory',
      'asOf': '2026-08-11T12:01:00Z',
      'quantitySemantics': 'factual-ledger-balance',
      'data': <Object?>[
        <String, Object?>{
          'homeProductId': _homeProductId,
          'productName': 'Rolled oats',
          'packText': '1 kg',
          'factualQuantity': '12.12500001',
          'balanceRevision': '4',
          'lastMovementId': _movementId,
          'balanceUpdatedAt': '2026-08-11T11:00:00Z',
          'configuredMinimum': '3.5',
          'alwaysKeep': '1',
          'neverSuggest': 0,
        },
      ],
    };
  }
  if (path.endsWith('/reports/purchases')) {
    return <String, Object?>{
      'type': 'purchases',
      'asOf': '2026-08-11T12:02:00Z',
      'from': '2026-08-01',
      'through': '2026-08-11',
      'currencyPolicy': 'totals-are-never-combined-across-currencies',
      'data': <Object?>[
        <String, Object?>{
          'month': '2026-08',
          'currency': 'NAD',
          'storeId': _storeId,
          'storeName': 'Market',
          'receiptCount': '2',
          'total': '999999999.12345678',
        },
      ],
    };
  }
  if (path.endsWith('/reports/consumption')) {
    return <String, Object?>{
      'type': 'consumption',
      'asOf': '2026-08-11T12:03:00Z',
      'quantitySemantics': 'estimated-from-complete-reliable-count-intervals',
      'data': <Object?>[
        <String, Object?>{
          'id': _estimateId,
          'homeProductId': _homeProductId,
          'productName': 'Rolled oats',
          'method': 'count_intervals',
          'dailyRate': '0.125',
          'variability': '0.01',
          'sampleIntervals': '3',
          'coverageDays': 91,
          'purchaseSamples': 4,
          'purchaseCadenceDays': '14',
          'nextExpectedShoppingAt': '2026-08-20T00:00:00Z',
          'confidenceScore': '0.8125',
          'confidenceBand': 'high',
          'evidenceFrom': '2026-05-01T00:00:00Z',
          'evidenceTo': '2026-08-01T00:00:00Z',
          'limitations': <Object?>['Counts are sparse.'],
          'asOf': '2026-08-11T12:03:00Z',
          'inputWatermark': _watermark,
        },
      ],
    };
  }
  if (path.endsWith('/reports/suggestions')) {
    return <String, Object?>{
      'type': 'suggestions',
      'asOf': '2026-08-11T12:04:00Z',
      'quantitySemantics': 'forecast-not-ledger-fact',
      'data': <Object?>[
        <String, Object?>{
          'id': _suggestionId,
          'homeProductId': _homeProductId,
          'productName': 'Rolled oats',
          'packText': '1 kg',
          'expectedDemand': '2.25',
          'safetyStock': '0.5',
          'factualStock': '1',
          'usableStock': '1',
          'requiredQuantity': '1.75',
          'selectedPackId': _packId,
          'packCount': '2',
          'confidenceScore': '0.75',
          'confidenceBand': 'medium',
          'status': 'active',
          'expiresAt': '2026-08-18T12:04:00Z',
          'modelVersion': 'suggestion-v1',
          'asOf': '2026-08-11T12:04:00Z',
          'inputWatermark': _watermark,
        },
      ],
      'priceComparisons': <Object?>[
        <String, Object?>{
          'suggestionId': _suggestionId,
          'homeProductId': _homeProductId,
          'productName': 'Rolled oats',
          'packId': _packId,
          'packText': '1 kg',
          'storeId': _storeId,
          'storeName': 'Market',
          'currency': 'NAD',
          'packCount': '2',
          'effectiveTotal': '42.75',
          'excessQuantity': '0.75',
          'priceObservedAt': '2026-08-10T09:00:00Z',
          'selected': '1',
          'reason': 'lowest comparable total',
        },
      ],
    };
  }
  throw StateError('Unexpected report path: $path');
}

ProvidentiaApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => ProvidentiaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(handler),
);

http.Response _json(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{'content-type': 'application/json'},
);

const String _homeId = '01912345-6789-7abc-8def-0123456789ab';
const String _otherHomeId = '01912345-6789-7abc-8def-1123456789ab';
const String _homeProductId = '01912345-6789-7abc-8def-2123456789ab';
const String _movementId = '01912345-6789-7abc-8def-3123456789ab';
const String _storeId = '01912345-6789-7abc-8def-4123456789ab';
const String _estimateId = '01912345-6789-7abc-8def-5123456789ab';
const String _suggestionId = '01912345-6789-7abc-8def-6123456789ab';
const String _packId = '01912345-6789-7abc-8def-7123456789ab';
const String _requestId = '01912345-6789-7abc-8def-8123456789ab';
const String _watermark =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
