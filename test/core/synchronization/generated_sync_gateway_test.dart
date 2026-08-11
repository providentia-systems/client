import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart'
    as generated;

void main() {
  const homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
  const operationId = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';
  const deviceId = '0198a0b1-c2d3-7e4f-a345-6789abcdef01';

  test('push sends the route-scoped contract and maps accepted', () async {
    late http.Request captured;
    final client = generated.ProvidentiaApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      httpClient: MockClient((request) async {
        captured = request;
        final requestBody = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode(<String, Object?>{
            'protocolVersion': 1,
            'batchId': requestBody['batchId'],
            'requestId': 'request-1',
            'serverTime': '2026-07-30T12:00:00Z',
            'results': <Object?>[
              <String, Object?>{
                'operationId': operationId,
                'status': 'accepted',
                'revision': 2,
                'changeCursor': 'cursor-2',
                'representation': <String, Object?>{'theme': 'fresh'},
              },
            ],
            'highWaterCursor': 'cursor-2',
          }),
          200,
        );
      }),
    );
    final gateway = GeneratedSyncGateway(client);

    final response = await gateway.push(
      homeId: homeId,
      lastPulledCursor: null,
      operations: <PendingClientOperation>[
        PendingClientOperation(
          operationId: operationId,
          deviceId: deviceId,
          homeId: homeId,
          entityType: 'home-preference',
          entityId: '0198a0b1-c2d3-7e4f-b456-789abcdef012',
          operationType: 'put',
          baseRevision: null,
          clientTimestamp: DateTime.utc(2026, 7, 30, 11),
          payloadSchemaVersion: 1,
          payload: const <String, Object?>{'theme': 'fresh'},
          retryCount: 0,
        ),
      ],
    );

    final body = jsonDecode(captured.body) as Map<String, Object?>;
    final operation =
        (body['operations'] as List<Object?>).single as Map<String, Object?>;
    expect(captured.url.path, '/api/v1/homes/$homeId/sync/push');
    expect(captured.headers['Idempotency-Key'], body['batchId']);
    expect(
      body['batchId'],
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(body['deviceId'], deviceId);
    expect(body, containsPair('lastPulledCursor', null));
    expect(operation, isNot(contains('homeId')));
    expect(response.results.single.kind, PushResultKind.acknowledged);
    expect(response.results.single.acceptedRevision, 2);
  });

  test(
    'protocol 2 sends the revisioned unresolved receipt decision exactly',
    () async {
      late Map<String, Object?> requestBody;
      final client = generated.ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': 2,
              'batchId': requestBody['batchId'],
              'requestId': 'unresolved-push',
              'serverTime': '2026-08-11T12:00:00Z',
              'results': <Object?>[
                <String, Object?>{
                  'operationId': operationId,
                  'status': 'accepted',
                  'revision': 3,
                  'changeCursor': 'cursor-unresolved',
                  'result': <String, Object?>{
                    'id': '0198a0b1-c2d3-7e4f-b456-789abcdef012',
                    'revision': 3,
                    'approvalStatus': 'unresolved',
                  },
                },
              ],
              'highWaterCursor': 'cursor-unresolved',
            }),
            200,
          );
        }),
      );

      final response = await GeneratedSyncGateway(client).push(
        homeId: homeId,
        lastPulledCursor: null,
        operations: <PendingClientOperation>[
          PendingClientOperation(
            operationId: operationId,
            deviceId: deviceId,
            homeId: homeId,
            entityType: 'purchasing-receipt-line',
            entityId: '0198a0b1-c2d3-7e4f-b456-789abcdef012',
            operationType: 'purchasing.receipt-line.unresolve',
            baseRevision: 2,
            clientTimestamp: DateTime.utc(2026, 8, 11, 11),
            payloadSchemaVersion: 1,
            payload: const <String, Object?>{
              'receiptId': '0198a0b1-c2d3-7e4f-b456-789abcdef013',
            },
            retryCount: 0,
          ),
        ],
      );

      final command =
          (requestBody['operations'] as List<Object?>).single
              as Map<String, Object?>;
      expect(command['commandType'], 'purchasing.receipt-line.unresolve');
      expect(command['baseRevision'], 2);
      expect(command['payload'], <String, Object?>{
        'receiptId': '0198a0b1-c2d3-7e4f-b456-789abcdef013',
      });
      expect(response.results.single.kind, PushResultKind.acknowledged);
      expect(response.results.single.acceptedRevision, 3);
    },
  );

  test(
    'operation status preserves request order and mixed known/unknown results',
    () async {
      const unknownOperationId = '0198a0b1-c2d3-7e4f-9234-56789abcdef1';
      late http.Request captured;
      final client = generated.ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': 2,
              // Deliberately return the valid set in a different order. The
              // gateway restores caller order before exposing the response.
              'operations': <Object?>[
                <String, Object?>{
                  'operationId': unknownOperationId,
                  'known': false,
                },
                <String, Object?>{
                  'operationId': operationId,
                  'known': true,
                  'result': <String, Object?>{
                    'operationId': operationId,
                    'status': 'accepted',
                    'commandType': 'inventory.location.create',
                    'entityId': '0198a0b1-c2d3-7e4f-b456-789abcdef012',
                    'result': <String, Object?>{
                      'id': '0198a0b1-c2d3-7e4f-b456-789abcdef012',
                      'revision': 4,
                    },
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final response = await GeneratedSyncGateway(client).operationStatuses(
        homeId: homeId,
        deviceId: deviceId,
        operationIds: const <String>[operationId, unknownOperationId],
      );

      expect(captured.url.path, '/api/v1/homes/$homeId/sync/operation-status');
      expect(captured.method, 'POST');
      expect(jsonDecode(captured.body), <String, Object?>{
        'deviceId': deviceId,
        'operationIds': <Object?>[operationId, unknownOperationId],
      });
      expect(
        response.operations.map((item) => item.operationId),
        const <String>[operationId, unknownOperationId],
      );
      expect(response.operations.first.isKnown, isTrue);
      expect(
        response.operations.first.result!.kind,
        PushResultKind.acknowledged,
      );
      expect(response.operations.first.result!.acceptedRevision, 4);
      expect(response.operations.last.isKnown, isFalse);
    },
  );

  for (final statusCode in <int>[403, 404]) {
    test(
      'operation status HTTP $statusCode is authorization failure',
      () async {
        final client = generated.ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode(<String, Object?>{
                'type': 'about:blank',
                'title': statusCode == 403 ? 'Forbidden' : 'Not Found',
                'status': statusCode,
                'detail': 'Home access is unavailable.',
                'requestId': 'status-$statusCode',
              }),
              statusCode,
            ),
          ),
        );

        await expectLater(
          GeneratedSyncGateway(client).operationStatuses(
            homeId: homeId,
            deviceId: deviceId,
            operationIds: const <String>[operationId],
          ),
          throwsA(isA<AuthorizationSyncException>()),
        );
      },
    );
  }

  test(
    'operation status rejects malformed or cross-boundary response fields',
    () async {
      for (final operations in <List<Object?>>[
        <Object?>[
          <String, Object?>{
            'operationId': operationId,
            'known': false,
            'result': null,
          },
        ],
        <Object?>[
          <String, Object?>{
            'operationId': operationId,
            'known': false,
            'homeId': homeId,
          },
        ],
        <Object?>[
          <String, Object?>{
            'operationId': operationId,
            'known': true,
            'result': <String, Object?>{
              'operationId': operationId,
              'status': 'accepted',
              'deviceId': deviceId,
            },
          },
        ],
      ]) {
        final client = generated.ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': 2,
                'operations': operations,
              }),
              200,
            ),
          ),
        );

        await expectLater(
          GeneratedSyncGateway(client).operationStatuses(
            homeId: homeId,
            deviceId: deviceId,
            operationIds: const <String>[operationId],
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'operation status rejects malformed request identities before HTTP',
    () async {
      final gateway = GeneratedSyncGateway(
        generated.ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient((_) async {
            fail('Malformed status identities must not perform HTTP.');
          }),
        ),
      );

      await expectLater(
        gateway.operationStatuses(
          homeId: homeId,
          deviceId: 'device-from-another-boundary',
          operationIds: const <String>[operationId],
        ),
        throwsFormatException,
      );
      await expectLater(
        gateway.operationStatuses(
          homeId: homeId,
          deviceId: deviceId,
          operationIds: const <String>[operationId, operationId],
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'initial pull omits cursor and preserves canonical genesis cursor',
    () async {
      late http.Request captured;
      final client = generated.ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': 1,
              'requestId': 'request-2',
              'fromCursor': 'eyJzZXF1ZW5jZSI6MH0',
              'pageCursor': 'cursor-1',
              'highWaterCursor': 'cursor-1',
              'hasMore': false,
              'changes': <Object?>[
                <String, Object?>{
                  'cursor': 'cursor-1',
                  'entityType': 'private-note',
                  'entityId': '0198a0b1-c2d3-7e4f-b456-789abcdef012',
                  'operation': 'delete',
                  'revision': 4,
                  'serverTimestamp': '2026-07-30T12:00:00Z',
                  'representationSchemaVersion': 1,
                  'tombstone': <String, Object?>{
                    'deletedAt': '2026-07-30T12:00:00Z',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final page = await GeneratedSyncGateway(client).pull(homeId: homeId);

      expect(captured.url.queryParameters, <String, String>{'limit': '250'});
      expect(page.fromCursor, 'eyJzZXF1ZW5jZSI6MH0');
      expect(page.changes.single.homeId, homeId);
      expect(page.changes.single.kind, RemoteChangeKind.tombstone);
    },
  );

  test(
    'bootstrap maps an authorized snapshot to an atomic local page',
    () async {
      final client = generated.ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/homes/$homeId/sync/bootstrap');
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': 1,
              'requestId': 'request-bootstrap',
              'snapshotCursor': 'snapshot-cursor',
              'pageCursor': null,
              'highWaterCursor': 'snapshot-cursor',
              'hasMore': false,
              'records': <Object?>[
                <String, Object?>{
                  'entityType': 'home-preference',
                  'entityId': '0198a0b1-c2d3-7e4f-b456-789abcdef012',
                  'revision': 3,
                  'representationSchemaVersion': 1,
                  'representation': <String, Object?>{'theme': 'fresh'},
                  'serverTimestamp': '2026-07-30T12:00:00Z',
                },
              ],
            }),
            200,
          );
        }),
      );

      final page = await GeneratedSyncGateway(client).bootstrap(homeId: homeId);

      expect(page.pageCursor, 'snapshot-cursor');
      expect(page.changes.single.revision, 3);
      expect(page.changes.single.payload['theme'], 'fresh');
    },
  );

  test('bootstrap consumes every page at one high-water boundary', () async {
    var calls = 0;
    final client = generated.ProvidentiaApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      httpClient: MockClient((request) async {
        calls++;
        if (calls == 1) {
          expect(request.url.queryParameters, <String, String>{'limit': '250'});
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': 1,
              'requestId': 'bootstrap-page-1',
              'snapshotCursor': null,
              'pageCursor': 'next-page',
              'highWaterCursor': 'snapshot-cursor',
              'hasMore': true,
              'records': <Object?>[_bootstrapRecord('entity-1', revision: 1)],
            }),
            200,
          );
        }
        expect(request.url.queryParameters['cursor'], 'next-page');
        return http.Response(
          jsonEncode(<String, Object?>{
            'protocolVersion': 1,
            'requestId': 'bootstrap-page-2',
            'snapshotCursor': 'snapshot-cursor',
            'pageCursor': null,
            'highWaterCursor': 'snapshot-cursor',
            'hasMore': false,
            'records': <Object?>[_bootstrapRecord('entity-2', revision: 2)],
          }),
          200,
        );
      }),
    );

    final page = await GeneratedSyncGateway(client).bootstrap(homeId: homeId);

    expect(calls, 2);
    expect(page.changes.map((change) => change.entityId), <String>[
      'entity-1',
      'entity-2',
    ]);
    expect(page.pageCursor, 'snapshot-cursor');
  });

  test('pantry command batches use sync push protocol 2', () async {
    late Map<String, Object?> requestBody;
    final client = generated.ProvidentiaApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      httpClient: MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, Object?>;
        final command =
            (requestBody['operations'] as List<Object?>).single
                as Map<String, Object?>;
        return http.Response(
          jsonEncode(<String, Object?>{
            'protocolVersion': 2,
            'batchId': requestBody['batchId'],
            'requestId': 'pantry-push',
            'serverTime': '2026-08-09T12:00:00Z',
            'results': <Object?>[
              <String, Object?>{
                'operationId': command['operationId'],
                'status': 'accepted',
                'revision': 1,
                'changeCursor': 'cursor-1',
              },
            ],
            'highWaterCursor': 'cursor-1',
          }),
          200,
        );
      }),
    );

    final response = await GeneratedSyncGateway(client).push(
      homeId: homeId,
      lastPulledCursor: null,
      operations: <PendingClientOperation>[
        PendingClientOperation(
          operationId: operationId,
          deviceId: deviceId,
          homeId: homeId,
          entityType: 'inventory-balance',
          entityId: '0198a0b1-c2d3-7e4f-b456-789abcdef012',
          operationType: 'inventory.adjustment.create',
          clientTimestamp: DateTime.utc(2026, 8, 9, 12),
          payloadSchemaVersion: 1,
          payload: const <String, Object?>{
            'quantityDelta': '1',
            'reason': 'Physical recount',
          },
          retryCount: 0,
        ),
      ],
    );

    final command =
        (requestBody['operations'] as List<Object?>).single
            as Map<String, Object?>;
    expect(requestBody['protocolVersion'], 2);
    expect(command['commandType'], 'inventory.adjustment.create');
    expect(command, isNot(contains('entityType')));
    expect(response.results.single.kind, PushResultKind.acknowledged);
  });

  test(
    'protocol 2 rejects a command projected onto the wrong resource',
    () async {
      final client = generated.ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((_) async {
          fail('A mismatched command must be rejected before HTTP.');
        }),
      );

      await expectLater(
        GeneratedSyncGateway(client).push(
          homeId: homeId,
          lastPulledCursor: null,
          operations: <PendingClientOperation>[
            PendingClientOperation(
              operationId: operationId,
              deviceId: deviceId,
              homeId: homeId,
              entityType: 'inventory-home-product',
              entityId: '0198a0b1-c2d3-7e4f-b456-789abcdef012',
              operationType: 'inventory.adjustment.create',
              clientTimestamp: DateTime.utc(2026, 8, 9, 12),
              payloadSchemaVersion: 1,
              payload: const <String, Object?>{
                'quantityDelta': '1',
                'reason': 'Physical recount',
              },
              retryCount: 0,
            ),
          ],
        ),
        throwsFormatException,
      );
    },
  );

  for (final statusCode in <int>[403, 404]) {
    test(
      'HTTP $statusCode blocks each pushed operation as authorization failure',
      () async {
        final client = generated.ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient((_) async {
            return http.Response(
              jsonEncode(<String, Object?>{
                'type': 'about:blank',
                'title': statusCode == 403 ? 'Forbidden' : 'Not Found',
                'status': statusCode,
                'detail': 'Home access is unavailable.',
                'requestId': 'request-3',
              }),
              statusCode,
            );
          }),
        );
        final operation = PendingClientOperation(
          operationId: operationId,
          deviceId: deviceId,
          homeId: homeId,
          entityType: 'home-preference',
          entityId: '0198a0b1-c2d3-7e4f-b456-789abcdef012',
          operationType: 'put',
          clientTimestamp: DateTime.utc(2026, 7, 30, 11),
          payloadSchemaVersion: 1,
          payload: const <String, Object?>{'theme': 'fresh'},
          retryCount: 0,
        );

        final response = await GeneratedSyncGateway(client).push(
          homeId: homeId,
          lastPulledCursor: 'cursor-1',
          operations: <PendingClientOperation>[operation],
        );

        expect(
          response.results.single.kind,
          PushResultKind.authorizationFailure,
        );
        expect(
          response.results.single.safeMessage,
          'Home access is unavailable.',
        );
      },
    );
  }

  for (final method in <String>['bootstrap', 'pull']) {
    for (final statusCode in <int>[403, 404]) {
      test(
        '$method HTTP $statusCode is authorization, not authentication',
        () async {
          final client = generated.ProvidentiaApiClient(
            baseUri: Uri.parse('https://api.example.test'),
            httpClient: MockClient((_) async {
              return http.Response(
                jsonEncode(<String, Object?>{
                  'type': 'about:blank',
                  'title': statusCode == 403 ? 'Forbidden' : 'Not Found',
                  'status': statusCode,
                  'detail': 'Home membership is unavailable.',
                  'requestId': 'request-$statusCode',
                }),
                statusCode,
              );
            }),
          );
          final gateway = GeneratedSyncGateway(client);

          final request = method == 'bootstrap'
              ? gateway.bootstrap(homeId: homeId)
              : gateway.pull(homeId: homeId, afterCursor: 'cursor-1');

          await expectLater(
            request,
            throwsA(
              isA<AuthorizationSyncException>().having(
                (error) => error.safeMessage,
                'safe message',
                contains('membership'),
              ),
            ),
          );
        },
      );
    }
  }

  test('pull maps the exact HTTP 410 problem to resync required', () async {
    final client = generated.ProvidentiaApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      httpClient: MockClient((_) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'type': 'https://providentia.invalid/problems/sync_resync_required',
            'title': 'Synchronization bootstrap required',
            'status': 410,
            'detail': 'The cursor is no longer available.',
            'requestId': 'request-410',
          }),
          410,
        );
      }),
    );

    await expectLater(
      GeneratedSyncGateway(
        client,
      ).pull(homeId: homeId, afterCursor: 'expired-cursor'),
      throwsA(
        isA<ResyncRequiredSyncException>().having(
          (error) => error.safeMessage,
          'safe message',
          contains('cursor'),
        ),
      ),
    );
  });

  test('empty push is a transport-free no-op', () async {
    final client = generated.ProvidentiaApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      httpClient: MockClient((_) async {
        fail('An empty synchronization batch must not perform HTTP.');
      }),
    );

    final response = await GeneratedSyncGateway(client).push(
      homeId: homeId,
      lastPulledCursor: null,
      operations: const <PendingClientOperation>[],
    );

    expect(response.results, isEmpty);
  });

  test(
    'push rejects cross-home and mixed-device batches before HTTP',
    () async {
      final client = generated.ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((_) async {
          fail('An invalid synchronization batch must not perform HTTP.');
        }),
      );
      final gateway = GeneratedSyncGateway(client);

      await expectLater(
        gateway.push(
          homeId: homeId,
          lastPulledCursor: null,
          operations: <PendingClientOperation>[
            _operation(
              operationId: operationId,
              homeId: '0198a0b1-c2d3-7e4f-8123-456789abcdee',
              deviceId: deviceId,
            ),
          ],
        ),
        throwsFormatException,
      );
      await expectLater(
        gateway.push(
          homeId: homeId,
          lastPulledCursor: null,
          operations: <PendingClientOperation>[
            _operation(
              operationId: operationId,
              homeId: homeId,
              deviceId: deviceId,
            ),
            _operation(
              operationId: '0198a0b1-c2d3-7e4f-9234-56789abcdef1',
              homeId: homeId,
              deviceId: '0198a0b1-c2d3-7e4f-a345-6789abcdef02',
            ),
          ],
        ),
        throwsFormatException,
      );
    },
  );

  test('push requires exactly one result for every operation', () async {
    final missingGateway = _gatewayWithPushResults(const <Object?>[]);
    await expectLater(
      missingGateway.push(
        homeId: homeId,
        lastPulledCursor: null,
        operations: <PendingClientOperation>[
          _operation(
            operationId: operationId,
            homeId: homeId,
            deviceId: deviceId,
          ),
        ],
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('omitted'),
        ),
      ),
    );

    final duplicateResult = <String, Object?>{
      'operationId': operationId,
      'status': 'accepted',
      'revision': 2,
      'changeCursor': 'cursor-2',
    };
    final duplicateGateway = _gatewayWithPushResults(<Object?>[
      duplicateResult,
      duplicateResult,
    ]);
    await expectLater(
      duplicateGateway.push(
        homeId: homeId,
        lastPulledCursor: null,
        operations: <PendingClientOperation>[
          _operation(
            operationId: operationId,
            homeId: homeId,
            deviceId: deviceId,
          ),
        ],
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('twice'),
        ),
      ),
    );

    final unknownGateway = _gatewayWithPushResults(const <Object?>[
      <String, Object?>{
        'operationId': '0198a0b1-c2d3-7e4f-9234-56789abcdef9',
        'status': 'accepted',
        'revision': 2,
        'changeCursor': 'cursor-2',
      },
    ]);
    await expectLater(
      unknownGateway.push(
        homeId: homeId,
        lastPulledCursor: null,
        operations: <PendingClientOperation>[
          _operation(
            operationId: operationId,
            homeId: homeId,
            deviceId: deviceId,
          ),
        ],
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('unknown operation'),
        ),
      ),
    );
  });
}

GeneratedSyncGateway _gatewayWithPushResults(List<Object?> results) {
  return GeneratedSyncGateway(
    generated.ProvidentiaApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode(<String, Object?>{
            'protocolVersion': 1,
            'batchId': body['batchId'],
            'requestId': 'result-integrity',
            'serverTime': '2026-07-30T12:00:00Z',
            'results': results,
            'highWaterCursor': 'cursor-2',
          }),
          200,
        );
      }),
    ),
  );
}

PendingClientOperation _operation({
  required String operationId,
  required String homeId,
  required String deviceId,
}) {
  return PendingClientOperation(
    operationId: operationId,
    deviceId: deviceId,
    homeId: homeId,
    entityType: 'home-preference',
    entityId: '0198a0b1-c2d3-7e4f-b456-789abcdef012',
    operationType: 'put',
    clientTimestamp: DateTime.utc(2026, 7, 30, 11),
    payloadSchemaVersion: 1,
    payload: const <String, Object?>{'theme': 'fresh'},
    retryCount: 0,
  );
}

Map<String, Object?> _bootstrapRecord(
  String entityId, {
  required int revision,
}) => <String, Object?>{
  'entityType': 'home-preference',
  'entityId': entityId,
  'revision': revision,
  'representationSchemaVersion': 1,
  'representation': <String, Object?>{'revision': revision},
  'serverTimestamp': '2026-08-09T12:00:00Z',
};
