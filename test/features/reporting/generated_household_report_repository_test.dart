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

  test(
    'preserves explicit unknown, recorded zero and signed uncertain stock',
    () async {
      final repository = GeneratedHouseholdReportRepository(
        _client((request) async {
          final body = _reportForPath(request.url.path);
          if (request.url.path.endsWith('/inventory')) {
            body['data'] = <Object?>[
              <String, Object?>{
                'homeProductId': _homeProductId,
                'productName': 'Unknown stock',
                'packText': '',
                'stockUnit': 'kg',
                'factualQuantity': null,
                'quantityState': 'unknown',
                'uncertain': false,
                'pendingQuantity': null,
                'limitations': <String>['No stock balance has been recorded.'],
                'checkpointId': null,
              },
              <String, Object?>{
                'homeProductId': _homeProductId,
                'productName': 'Recorded zero',
                'packText': '',
                'stockUnit': 'each',
                'factualQuantity': '0',
                'quantityState': 'recorded',
                'uncertain': false,
                'pendingQuantity': '0',
                'limitations': <String>[],
                'checkpointId': _movementId,
              },
              <String, Object?>{
                'homeProductId': _homeProductId,
                'productName': 'Uncertain balance',
                'packText': 'Private pack',
                'stockUnit': 'kg',
                'factualQuantity': '-2.12500001',
                'quantityState': 'uncertain',
                'uncertain': true,
                'pendingQuantity': '1.00000001',
                'limitations': <String>[
                  'A date-only purchase requires review.',
                ],
                'checkpointId': _movementId,
                'balanceRevision': 7,
                'balanceUpdatedAt': '2026-08-11T11:00:00Z',
              },
            ];
          }
          return _json(body);
        }),
      );

      final report = await repository.load(homeId: _homeId);
      expect(report.inventoryFacts, hasLength(3));
      final unknown = report.inventoryFacts[0];
      expect(unknown.factualQuantity, isNull);
      expect(unknown.quantityState, InventoryReportQuantityState.unknown);
      expect(unknown.pendingQuantity, isNull);
      expect(unknown.limitations, <String>[
        'No stock balance has been recorded.',
      ]);
      final zero = report.inventoryFacts[1];
      expect(zero.factualQuantity, '0');
      expect(zero.quantityState, InventoryReportQuantityState.recorded);
      expect(zero.uncertain, isFalse);
      expect(zero.stockUnit, 'each');
      final uncertain = report.inventoryFacts[2];
      expect(uncertain.factualQuantity, '-2.12500001');
      expect(uncertain.quantityState, InventoryReportQuantityState.uncertain);
      expect(uncertain.uncertain, isTrue);
      expect(uncertain.pendingQuantity, '1.00000001');
      expect(uncertain.checkpointId, _movementId);
      expect(uncertain.limitations, <String>[
        'A date-only purchase requires review.',
      ]);
      expect(uncertain.balanceRevision, 7);
      expect(uncertain.balanceUpdatedAt, DateTime.utc(2026, 8, 11, 11));
    },
  );

  test(
    'older responses retain quantities with evidence explicitly unavailable',
    () async {
      final repository = GeneratedHouseholdReportRepository(
        _client((request) async => _json(_reportForPath(request.url.path))),
      );
      final row = (await repository.load(
        homeId: _homeId,
      )).inventoryFacts.single;
      expect(row.factualQuantity, '12.12500001');
      expect(row.quantityState, InventoryReportQuantityState.unavailable);
      expect(row.stockUnit, isNull);
      expect(row.uncertain, isNull);
      expect(row.pendingQuantity, isNull);
      expect(row.checkpointId, isNull);
    },
  );

  test(
    'incomplete quantity evidence does not turn absence into zero',
    () async {
      final repository = GeneratedHouseholdReportRepository(
        _client((request) async {
          final body = _reportForPath(request.url.path);
          if (request.url.path.endsWith('/inventory')) {
            final rows = body['data']! as List<Object?>;
            final row = rows.single! as Map<String, Object?>;
            row.remove('factualQuantity');
            row.remove('productName');
            row.remove('packText');
            row['stockUnit'] = '';
          }
          return _json(body);
        }),
      );
      final row = (await repository.load(
        homeId: _homeId,
      )).inventoryFacts.single;
      expect(row.factualQuantity, isNull);
      expect(row.quantityState, InventoryReportQuantityState.unavailable);
      expect(row.productName, 'Product name unavailable');
      expect(row.packText, '');
      expect(row.stockUnit, isNull);
    },
  );

  for (final contradictory in <Map<String, Object?>>[
    <String, Object?>{'quantityState': 'unknown', 'factualQuantity': '0'},
    <String, Object?>{'quantityState': 'recorded', 'factualQuantity': null},
    <String, Object?>{'quantityState': 'recorded', 'uncertain': true},
    <String, Object?>{'quantityState': 'uncertain', 'uncertain': false},
  ]) {
    test('rejects contradictory inventory evidence $contradictory', () async {
      final repository = GeneratedHouseholdReportRepository(
        _client((request) async {
          final body = _reportForPath(request.url.path);
          if (request.url.path.endsWith('/inventory')) {
            final rows = body['data']! as List<Object?>;
            (rows.single! as Map<String, Object?>).addAll(contradictory);
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
  }

  test(
    'preserves complete, partial and wholly unknown receipt spend by currency',
    () async {
      final repository = GeneratedHouseholdReportRepository(
        _client((request) async {
          final body = _reportForPath(request.url.path);
          if (request.url.path.endsWith('/purchases')) {
            body['data'] = <Object?>[
              <String, Object?>{
                'month': '2026-08',
                'currency': 'NAD',
                'receiptCount': 2,
                'total': '0',
                'knownSubtotal': '0',
                'pricingComplete': true,
                'amountSource': 'declared',
                'completeReceiptCount': 2,
                'partialReceiptCount': 0,
                'unknownReceiptCount': 0,
                'declaredReceiptCount': 2,
                'derivedReceiptCount': 0,
              },
              <String, Object?>{
                'month': '2026-08',
                'currency': 'USD',
                'receiptCount': 3,
                'total': null,
                'knownSubtotal': '12.12500001',
                'pricingComplete': false,
                'amountSource': 'partial',
                'completeReceiptCount': 1,
                'partialReceiptCount': 1,
                'unknownReceiptCount': 1,
                'declaredReceiptCount': 0,
                'derivedReceiptCount': 1,
              },
              <String, Object?>{
                'month': '2026-08',
                'currency': 'EUR',
                'receiptCount': 1,
                'total': null,
                'knownSubtotal': null,
                'pricingComplete': false,
                'amountSource': 'unknown',
                'completeReceiptCount': 0,
                'partialReceiptCount': 0,
                'unknownReceiptCount': 1,
                'declaredReceiptCount': 0,
                'derivedReceiptCount': 0,
              },
            ];
          }
          return _json(body);
        }),
      );
      final rows = (await repository.load(homeId: _homeId)).purchaseTotals;
      expect(rows.map((row) => row.currency), <String>['NAD', 'USD', 'EUR']);
      expect(rows[0].total, '0');
      expect(rows[0].pricingComplete, isTrue);
      expect(rows[0].amountSource, PurchaseReportAmountSource.declared);
      expect(rows[0].completeReceiptCount, 2);
      expect(rows[0].declaredReceiptCount, 2);
      expect(rows[1].total, isNull);
      expect(rows[1].knownSubtotal, '12.12500001');
      expect(rows[1].pricingComplete, isFalse);
      expect(rows[1].amountSource, PurchaseReportAmountSource.partial);
      expect(rows[1].completeReceiptCount, 1);
      expect(rows[1].partialReceiptCount, 1);
      expect(rows[1].unknownReceiptCount, 1);
      expect(rows[1].derivedReceiptCount, 1);
      expect(rows[2].total, isNull);
      expect(rows[2].knownSubtotal, isNull);
      expect(rows[2].amountSource, PurchaseReportAmountSource.unknown);
    },
  );

  test(
    'legacy purchase totals disclose absent completeness rather than certify',
    () async {
      final repository = GeneratedHouseholdReportRepository(
        _client((request) async => _json(_reportForPath(request.url.path))),
      );
      final row = (await repository.load(
        homeId: _homeId,
      )).purchaseTotals.single;
      expect(row.total, '999999999.12345678');
      expect(row.pricingComplete, isNull);
      expect(row.knownSubtotal, isNull);
      expect(row.amountSource, PurchaseReportAmountSource.unavailable);
    },
  );

  test(
    'future evidence metadata remains readable without certifying unknown meanings',
    () async {
      final repository = GeneratedHouseholdReportRepository(
        _client((request) async {
          final body = _reportForPath(request.url.path);
          if (request.url.path.endsWith('/inventory')) {
            final rows = body['data']! as List<Object?>;
            (rows.single! as Map<String, Object?>).addAll(<String, Object?>{
              'productName': null,
              'quantityState': 'future-evidence-kind',
              'factualQuantity': '-1234567890.123456789',
              'uncertain': true,
              'futureMetadata': <String, Object?>{
                'homeId': _homeId,
                'reviewed': false,
              },
            });
          }
          if (request.url.path.endsWith('/purchases')) {
            final rows = body['data']! as List<Object?>;
            (rows.single! as Map<String, Object?>).addAll(<String, Object?>{
              'amountSource': 'future-pricing-kind',
              'total': '1234567890.123456789',
            });
          }
          return _json(body);
        }),
      );
      final report = await repository.load(homeId: _homeId);
      final stock = report.inventoryFacts.single;
      expect(stock.productName, 'Product name unavailable');
      expect(stock.factualQuantity, '-1234567890.123456789');
      expect(stock.quantityState, InventoryReportQuantityState.unavailable);
      expect(stock.uncertain, isTrue);
      expect(report.purchaseTotals.single.total, '1234567890.123456789');
      expect(
        report.purchaseTotals.single.amountSource,
        PurchaseReportAmountSource.unavailable,
      );
      expect(report.purchaseTotals.single.pricingComplete, isNull);
    },
  );

  for (final instant in <String, String>{
    '2026-08-01 00:00:00': '2026-08-01T00:00:00Z',
    '2026-03-08 01:59:59': '2026-03-08T01:59:59Z',
    '2026-11-01 01:30:00': '2026-11-01T01:30:00Z',
    '2026-09-15 23:59:59.123456': '2026-09-15T23:59:59.123456Z',
    '2026-08-01T00:00:00+02:00': '2026-07-31T22:00:00Z',
    '2026-08-01T00:00:00-07:00': '2026-08-01T07:00:00Z',
  }.entries) {
    test('report instant ${instant.key} preserves the UTC instant', () async {
      final repository = GeneratedHouseholdReportRepository(
        _client((request) async {
          final body = _reportForPath(request.url.path);
          if (request.url.path.endsWith('/inventory')) {
            final rows = body['data']! as List<Object?>;
            (rows.single! as Map<String, Object?>)['balanceUpdatedAt'] =
                instant.key;
          }
          return _json(body);
        }),
      );
      final report = await repository.load(homeId: _homeId);
      expect(
        report.inventoryFacts.single.balanceUpdatedAt,
        DateTime.parse(instant.value),
      );
      expect(report.purchaseTotals.single.month, '2026-08');
    });
  }

  test('null report instants remain absent rather than becoming now', () async {
    final repository = GeneratedHouseholdReportRepository(
      _client((request) async {
        final body = _reportForPath(request.url.path);
        if (request.url.path.endsWith('/inventory')) {
          final rows = body['data']! as List<Object?>;
          (rows.single! as Map<String, Object?>)['balanceUpdatedAt'] = null;
        }
        return _json(body);
      }),
    );
    final report = await repository.load(homeId: _homeId);
    expect(report.inventoryFacts.single.balanceUpdatedAt, isNull);
  });

  for (final invalid in <Object?>[
    '2026-02-30 00:00:00',
    '2026-08-01T00:00:00',
    'tomorrow',
    42,
  ]) {
    test(
      'invalid or ambiguous report instant $invalid is not accepted',
      () async {
        final repository = GeneratedHouseholdReportRepository(
          _client((request) async {
            final body = _reportForPath(request.url.path);
            if (request.url.path.endsWith('/inventory')) {
              final rows = body['data']! as List<Object?>;
              (rows.single! as Map<String, Object?>)['balanceUpdatedAt'] =
                  invalid;
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
      },
    );
  }

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
