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

  test(
    'HTTP 403 blocks each pushed operation as authorization failure',
    () async {
      final client = generated.ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'type': 'about:blank',
              'title': 'Forbidden',
              'status': 403,
              'detail': 'Membership was revoked.',
              'requestId': 'request-3',
            }),
            403,
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

      expect(response.results.single.kind, PushResultKind.authorizationFailure);
      expect(response.results.single.safeMessage, 'Membership was revoked.');
    },
  );

  for (final method in <String>['bootstrap', 'pull']) {
    test(
      '$method HTTP 403 is authorization, not expired authentication',
      () async {
        final client = generated.ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient((_) async {
            return http.Response(
              jsonEncode(<String, Object?>{
                'type': 'about:blank',
                'title': 'Forbidden',
                'status': 403,
                'detail': 'Home membership no longer permits synchronization.',
                'requestId': 'request-403',
              }),
              403,
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

  test('push rejects cross-home and mixed-device batches before HTTP', () async {
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
  });

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
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains('omitted'),
      )),
    );

    final duplicateResult = <String, Object?>{
      'operationId': operationId,
      'status': 'accepted',
      'revision': 2,
      'changeCursor': 'cursor-2',
    };
    final duplicateGateway = _gatewayWithPushResults(
      <Object?>[duplicateResult, duplicateResult],
    );
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
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains('twice'),
      )),
    );

    final unknownGateway = _gatewayWithPushResults(
      const <Object?>[
        <String, Object?>{
          'operationId': '0198a0b1-c2d3-7e4f-9234-56789abcdef9',
          'status': 'accepted',
          'revision': 2,
          'changeCursor': 'cursor-2',
        },
      ],
    );
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
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains('unknown operation'),
      )),
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
