import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart'
    as generated;

void main() {
  const home = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
  const device = '0198a0b1-c2d3-7e4f-a345-6789abcdef01';
  const operation = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';
  const entity = '0198a0b1-c2d3-7e4f-b456-789abcdef012';
  const commands = <String, String>{
    'purchasing.receipt-line.correct': 'purchasing-receipt-line',
    'purchasing.receipt.correct-date': 'purchasing-receipt',
    'inventory.count-session.review': 'inventory-count-session',
    'shopping.list-line.relink': 'shopping-list-line',
  };
  for (final command in commands.entries) {
    test(
      '${command.key} retains immutable revisioned protocol 2 payload',
      () async {
        final payload = <String, Object?>{
          'reason': 'Synthetic correction',
          'purchaseDate': '2026-10-25',
        };
        final calls = <Map<String, Object?>>[];
        final client = generated.ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            calls.add(body);
            expect(body['protocolVersion'], 2);
            expect(body['deviceId'], device);
            final saved =
                (body['operations']! as List<Object?>).single!
                    as Map<String, Object?>;
            expect(saved['operationId'], operation);
            expect(saved['entityId'], entity);
            expect(saved['commandType'], command.key);
            expect(saved['baseRevision'], 4);
            expect(saved['payload'], payload);
            return http.Response(
              jsonEncode(<String, Object?>{
                'protocolVersion': 2,
                'batchId': body['batchId'],
                'requestId': 'synthetic-contract-command',
                'serverTime': '2026-10-26T12:00:00Z',
                'results': <Object?>[
                  <String, Object?>{
                    'operationId': operation,
                    'status': 'accepted',
                    'revision': 5,
                    'changeCursor': 'cursor-5',
                    'result': <String, Object?>{
                      'id': entity,
                      'revision': 5,
                      'receiptRevision': 6,
                    },
                  },
                ],
                'highWaterCursor': 'cursor-5',
              }),
              200,
            );
          }),
        );
        final gateway = GeneratedSyncGateway(client);
        final pending = PendingClientOperation(
          operationId: operation,
          deviceId: device,
          homeId: home,
          entityType: command.value,
          entityId: entity,
          operationType: command.key,
          baseRevision: 4,
          clientTimestamp: DateTime.utc(2026, 10, 26),
          payloadSchemaVersion: 1,
          payload: payload,
          retryCount: 0,
        );
        for (var retry = 0; retry < 2; retry++) {
          final result = await gateway.push(
            homeId: home,
            lastPulledCursor: null,
            operations: [pending],
          );
          expect(result.results.single.kind, PushResultKind.acknowledged);
          expect(result.results.single.remotePayload?['receiptRevision'], 6);
        }
        expect(calls.first, calls.last);
      },
    );

    test(
      '${command.key} rejects a missing revision before transport',
      () async {
        final client = generated.ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient(
            (_) async => throw StateError('Transport must not run'),
          ),
        );
        await expectLater(
          GeneratedSyncGateway(client).push(
            homeId: home,
            lastPulledCursor: null,
            operations: [
              PendingClientOperation(
                operationId: operation,
                deviceId: device,
                homeId: home,
                entityType: command.value,
                entityId: entity,
                operationType: command.key,
                baseRevision: null,
                clientTimestamp: DateTime.utc(2026, 10, 26),
                payloadSchemaVersion: 1,
                payload: const {},
                retryCount: 0,
              ),
            ],
          ),
          throwsFormatException,
        );
      },
    );
  }
}
