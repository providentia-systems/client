import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia_api_client/providentia_api_client.dart'
    as generated;

const _home = '10000000-0000-4000-8000-000000000001';
const _device = '10000000-0000-4000-8000-000000000002';
const _account = '10000000-0000-4000-8000-000000000003';
const _operation = '10000000-0000-4000-8000-000000000004';
const _entity = '10000000-0000-4000-8000-000000000005';
final _now = DateTime.utc(2026, 10, 26);

void main() {
  for (final code in <String>[
    'unsupported_operation',
    'unsupported_command',
    'unsupported_payload_schema',
    'unsupported_schema_version',
    'unsupported_protocol_version',
  ]) {
    test(
      '$code push and response-loss readback expose supported-server guidance',
      () async {
        final client = generated.ProvidentiaApiClient(
          baseUri: Uri.parse('https://synthetic.example.test'),
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            final result = <String, Object?>{
              'operationId': _operation,
              'status': 'validation_error',
              'code': code,
              'detail':
                  'Untrusted backend details are not capability guidance.',
            };
            if (request.url.path.endsWith('/sync/push')) {
              return _json(<String, Object?>{
                'protocolVersion': 2,
                'batchId': body['batchId'],
                'requestId': 'synthetic-capability',
                'serverTime': _now.toIso8601String(),
                'highWaterCursor': 'synthetic-cursor',
                'results': <Object?>[result],
              });
            }
            return _json(<String, Object?>{
              'protocolVersion': 2,
              'operations': <Object?>[
                <String, Object?>{
                  'operationId': _operation,
                  'known': true,
                  'result': result,
                },
              ],
            });
          }),
        );
        final gateway = GeneratedSyncGateway(client);
        final pushed = (await gateway.push(
          homeId: _home,
          lastPulledCursor: null,
          operations: <PendingClientOperation>[_pending()],
        )).results.single;
        final recovered = (await gateway.operationStatuses(
          homeId: _home,
          deviceId: _device,
          operationIds: <String>[_operation],
        )).operations.single.result!;
        for (final result in <PushOperationResult>[pushed, recovered]) {
          expect(result.kind, PushResultKind.validationError);
          expect(result.code, code);
          expect(result.safeMessage, contains('API 2.4.0'));
          expect(result.safeMessage, contains('queue'));
          expect(result.safeMessage, isNot(contains('Untrusted')));
          expect(
            syncFailureHeading(result.code),
            'Verify the supported backend',
          );
        }
      },
    );
  }

  for (final declaredCode in <String?>[null, 'unsupported_payload_schema']) {
    test(
      'HTTP 422 ${declaredCode ?? 'legacy untyped'} preserves original blocked queue',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final local = DriftLocalSyncRepository(database);
        await local.commitLocalMutation(
          LocalMutation(
            operationId: _operation,
            homeId: _home,
            deviceId: _device,
            originatingAccountId: _account,
            entityType: 'inventory-count-session',
            entityId: _entity,
            operationType: 'inventory.count-session.review',
            baseRevision: 4,
            clientTimestamp: _now,
            payloadSchemaVersion: 1,
            payload: const <String, Object?>{'reason': 'Synthetic review'},
          ),
        );
        final before =
            (await database.select(database.clientOperations).get()).single;
        final gateway = GeneratedSyncGateway(
          generated.ProvidentiaApiClient(
            baseUri: Uri.parse('https://synthetic.example.test'),
            httpClient: MockClient(
              (_) async => _json(<String, Object?>{
                'type': 'about:blank',
                'title': 'Invalid command',
                'status': 422,
                'detail': 'commandType is not enabled for synchronization.',
                'requestId': 'synthetic-validation',
                'code': ?declaredCode,
              }, 422),
            ),
          ),
        );
        final response = await gateway.push(
          homeId: _home,
          lastPulledCursor: null,
          operations: await local.pendingOperations(homeId: _home, now: _now),
        );
        final result = response.results.single;
        expect(result.kind, PushResultKind.validationError);
        expect(result.code, declaredCode ?? 'invalid_command');
        expect(result.safeMessage, contains('API 2.4.0'));
        if (declaredCode == null) {
          expect(
            result.safeMessage,
            contains('does not identify the installed version'),
          );
        }
        await local.applyPushResults(
          results: response.results,
          now: _now,
          retryPolicy: RetryPolicy(),
        );
        final after =
            (await database.select(database.clientOperations).get()).single;
        expect(
          after.state,
          ClientOperationState.blockedValidation.storageValue,
        );
        expect(after.safeFailureCode, declaredCode ?? 'invalid_command');
        expect(after.operationId, before.operationId);
        expect(after.payload, before.payload);
        expect(after.enqueueSequence, before.enqueueSequence);
        expect(after.deviceId, before.deviceId);
        expect(after.originatingAccountId, before.originatingAccountId);
        expect(after.baseRevision, before.baseRevision);
        expect(after.nextAttemptAt, isNull);
        expect(
          (await local.watchSummary(homeId: _home).first).failureCode,
          declaredCode ?? 'invalid_command',
        );
      },
    );
  }
}

PendingClientOperation _pending() => PendingClientOperation(
  operationId: _operation,
  homeId: _home,
  deviceId: _device,
  originatingAccountId: _account,
  entityType: 'inventory-count-session',
  entityId: _entity,
  operationType: 'inventory.count-session.review',
  baseRevision: 4,
  clientTimestamp: _now,
  payloadSchemaVersion: 1,
  payload: const <String, Object?>{'reason': 'Synthetic review'},
  retryCount: 0,
);
http.Response _json(Map<String, Object?> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );
