import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/session_bound_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart'
    as generated;

const _home = '01912345-6789-7abc-8def-0123456789ab';
const _otherHome = '01912345-6789-7abc-8def-1123456789ab';
const _device = '01912345-6789-7abc-8def-2123456789ab';
const _product = '01912345-6789-7abc-8def-3123456789ab';
const _receipt = '01912345-6789-7abc-8def-4123456789ab';
const _line = '01912345-6789-7abc-8def-5123456789ab';
final _at = DateTime.utc(2026, 10, 3);

void main() {
  test(
    'accepted receipt survives malformed response, readback and disk restart without recommit',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'receipt-recovery-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/receipt.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      addTearDown(() => database.close());
      var local = DriftLocalSyncRepository(database);
      await local.applyPullPage(homeId: _home, page: _emptyPage());
      await database
          .into(database.localRecords)
          .insert(
            LocalRecordsCompanion.insert(
              homeId: _home,
              entityType: 'inventory-home-product',
              entityId: _product,
              payload: jsonEncode({
                'id': _product,
                'revision': 1,
                'privateName': 'Flour',
                'status': 'active',
              }),
              revision: const Value(1),
              updatedAt: _at,
              synchronizedAt: Value(_at),
            ),
          );
      var sequence = 0;
      var repository = DriftHouseholdRepository(
        database,
        deviceId: _device,
        clock: () => _at,
        idGenerator: () =>
            '01912345-6789-7abc-8def-${(++sequence).toString().padLeft(12, '0')}',
      );
      await repository.createReceiptDraft(
        PurchaseReceiptDraftRequest(
          homeId: _home,
          clientReceiptId: _receipt,
          purchaseDate: _at,
          currency: 'NAD',
          total: Money(minorUnits: 2500, currency: 'NAD'),
        ),
      );
      await repository.addReceiptLine(
        PurchaseReceiptLineRequest(
          homeId: _home,
          receiptId: _receipt,
          clientLineId: _line,
          rawDescription: 'Flour',
          quantity: 1,
          lineTotal: Money(minorUnits: 2500, currency: 'NAD'),
        ),
      );
      await repository.approveReceiptLine(
        homeId: _home,
        receiptId: _receipt,
        lineId: _line,
        homeProductId: _product,
      );
      await repository.commitReceipt(homeId: _home, receiptId: _receipt);
      final original = await database.select(database.clientOperations).get();
      final savedIntents = original
          .map((row) => (row.operationId, row.payload, row.deviceId))
          .toList();
      final receipts = <String, Map<String, Object?>>{};
      var commitEffects = 0;
      var pushes = 0;
      var statusLookups = 0;
      var malformedReadback = true;
      final gateway = GeneratedSyncGateway(
        generated.ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/sync/push')) {
              pushes++;
              final body = jsonDecode(request.body) as Map<String, Object?>;
              final command =
                  (body['operations'] as List).single as Map<String, Object?>;
              final operationId = command['operationId']! as String;
              final isCommit =
                  command['commandType'] == 'purchasing.receipt.commit';
              if (isCommit && !receipts.containsKey(operationId)) {
                commitEffects++;
              }
              receipts.putIfAbsent(
                operationId,
                () => {
                  'operationId': operationId,
                  'status': 'accepted',
                  'commandType': command['commandType'],
                  'entityId': command['entityId'],
                  'result': isCommit
                      ? {'receiptId': _receipt, 'movements': 1}
                      : {'id': command['entityId']},
                },
              );
              return _json({
                'protocolVersion': 2,
                'batchId': body['batchId'],
                'requestId': _device,
                'serverTime': _at.toIso8601String(),
                'highWaterCursor': 'cursor-4',
                // Domain commit succeeded, but successful HTTP bytes cannot decode.
                'results': isCommit
                    ? 'malformed-success-response'
                    : [receipts[operationId]],
              });
            }
            if (request.url.path.endsWith('/sync/operation-status')) {
              statusLookups++;
              final body = jsonDecode(request.body) as Map<String, Object?>;
              expect(body['deviceId'], _device);
              final id = (body['operationIds'] as List).single as String;
              return _json({
                'protocolVersion': 2,
                'operations': [
                  {'operationId': id, 'known': true, 'result': receipts[id]},
                ],
              });
            }
            expect(request.url.path, '/api/v1/homes/$_home/sync/pull');
            expect(request.url.queryParameters['cursor'], 'cursor-0');
            return _json(
              _pullBody(
                lineOverride: malformedReadback ? {'lineTotal': 25} : {},
              ),
            );
          }),
        ),
      );
      SyncCoordinator coordinator() => SyncCoordinator(
        local: local,
        remote: SessionBoundSyncGateway(
          delegate: gateway,
          homeId: _home,
          deviceId: _device,
          isCurrent: () => true,
        ),
        connectivity: const _Online(),
        clock: () => _at,
      );
      final first = await coordinator().synchronize(_home);
      expect(first.status, SyncRunStatus.retryableFailure);
      expect(first.acknowledgedCount, 4);
      expect(commitEffects, 1);
      expect(pushes, 4);
      expect(statusLookups, 1);
      expect(await local.cursorForHome(_home), 'cursor-0');
      final pending = (await repository
          .watchActiveReceiptCapture(homeId: _home)
          .first)!;
      expect(pending.commitConfirmed, isTrue);
      expect(pending.commitAwaitingConfirmation, isFalse);
      expect(pending.commitAwaitingReadback, isTrue);
      expect(
        (await repository.commitReceipt(
          homeId: _home,
          receiptId: _receipt,
        )).disposition,
        PurchaseMutationDisposition.confirmedAwaitingReadback,
      );
      expect(
        await repository.watchActiveReceiptCapture(homeId: _otherHome).first,
        isNull,
      );
      expect(
        (await repository.watchPurchaseLines(homeId: _home).first)
            .single
            .pendingSynchronization,
        isTrue,
      );

      await database.close();
      database = AppDatabase(NativeDatabase(file));
      local = DriftLocalSyncRepository(database);
      repository = DriftHouseholdRepository(database, deviceId: _device);
      expect(
        (await repository.watchActiveReceiptCapture(homeId: _home).first)!
            .commitConfirmed,
        isTrue,
      );
      malformedReadback = false;
      final recovered = await coordinator().synchronize(_home);
      expect(recovered.status, SyncRunStatus.completed);
      expect(pushes, 4);
      expect(commitEffects, 1);
      expect(statusLookups, 1);
      expect(await local.cursorForHome(_home), 'cursor-4');
      expect(
        await repository.watchActiveReceiptCapture(homeId: _home).first,
        isNull,
      );
      final history = await repository.watchPurchaseLines(homeId: _home).first;
      expect(history, hasLength(1));
      expect(history.single.pendingSynchronization, isFalse);
      expect(history.single.lineTotal!.minorUnits, 2500);
      expect(history.single.quantity, 1);
      expect(
        (await repository.commitReceipt(
          homeId: _home,
          receiptId: _receipt,
        )).disposition,
        PurchaseMutationDisposition.synchronized,
      );
      final restored = await database.select(database.clientOperations).get();
      expect(
        restored
            .map((row) => (row.operationId, row.payload, row.deviceId))
            .toList(),
        savedIntents,
      );
      expect(
        restored.every(
          (row) => row.state == ClientOperationState.acknowledged.storageValue,
        ),
        isTrue,
      );

      await local.applyPushResults(
        results: [
          PushOperationResult(
            operationId: restored.last.operationId,
            kind: PushResultKind.retryableFailure,
          ),
        ],
        now: _at,
        retryPolicy: RetryPolicy(),
      );
      expect(
        (await database.select(database.clientOperations).get()).last.state,
        ClientOperationState.acknowledged.storageValue,
      );
    },
  );

  for (final invalid in <Map<String, Object?>>[
    {'homeId': _otherHome},
    {'id': _receipt},
    {'revision': 100},
    {'quantity': 1},
    {'quantity': 'NaN'},
    {'quantity': '0'},
    {'lineTotal': 25},
    {'approvalStatus': 'approved', 'homeProductId': null},
  ]) {
    test(
      'receipt feed rejects malformed or foreign line ${invalid.keys.join(', ')} $invalid',
      () async {
        final gateway = GeneratedSyncGateway(
          generated.ProvidentiaApiClient(
            baseUri: Uri.parse('https://api.example.test'),
            httpClient: MockClient(
              (_) async => _json(_pullBody(lineOverride: invalid)),
            ),
          ),
        );
        await expectLater(
          gateway.pull(homeId: _home, afterCursor: 'cursor-0'),
          throwsFormatException,
        );
      },
    );
  }

  test(
    'foreign receipt tombstone is rejected before deleting the local record',
    () async {
      final gateway = GeneratedSyncGateway(
        generated.ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient(
            (_) async => _json({
              ..._pullBody(),
              'changes': [
                {
                  ..._changes().first,
                  'operation': 'delete',
                  'representation': null,
                  'tombstone': {'homeId': _otherHome},
                },
              ],
            }),
          ),
        ),
      );
      await expectLater(
        gateway.pull(homeId: _home, afterCursor: 'cursor-0'),
        throwsFormatException,
      );
    },
  );

  test(
    'receipt header confirmation cannot hide still-pending line readback',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      for (final change in _changes()) {
        await database
            .into(database.localRecords)
            .insert(
              LocalRecordsCompanion.insert(
                homeId: _home,
                entityType: change['entityType']! as String,
                entityId: change['entityId']! as String,
                payload: jsonEncode(change['representation']),
                revision: Value(change['revision']! as int),
                updatedAt: _at,
                synchronizedAt: Value(
                  change['entityId'] == _receipt ? _at : null,
                ),
              ),
            );
      }
      final repository = DriftHouseholdRepository(database, deviceId: _device);
      expect(
        (await repository.watchActiveReceiptCapture(homeId: _home).first)!
            .commitAwaitingReadback,
        isTrue,
      );
      await (database.update(database.localRecords)
            ..where((row) => row.entityId.equals(_line)))
          .write(LocalRecordsCompanion(synchronizedAt: Value(_at)));
      expect(
        await repository.watchActiveReceiptCapture(homeId: _home).first,
        isNull,
      );
    },
  );

  test(
    'minimal local tombstones do not create capture or trigger cache repair',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      for (final type in [
        'purchasing-receipt',
        'purchasing-receipt-line',
        'purchasing-store',
      ]) {
        await database
            .into(database.localRecords)
            .insert(
              LocalRecordsCompanion.insert(
                homeId: _home,
                entityType: type,
                entityId: _receipt,
                payload: '{}',
                revision: const Value(2),
                isTombstone: const Value(true),
                updatedAt: _at,
                synchronizedAt: Value(_at),
              ),
            );
      }
      expect(
        await DriftHouseholdRepository(
          database,
          deviceId: _device,
        ).watchActiveReceiptCapture(homeId: _home).first,
        isNull,
      );
      expect(
        await DriftLocalSyncRepository(
          database,
        ).requiresReceiptReadbackRecovery(homeId: _home),
        isFalse,
      );
    },
  );

  test(
    'old poisoned synchronized receipt cache requests home-scoped snapshot repair',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final local = DriftLocalSyncRepository(database);
      await local.applyPullPage(homeId: _home, page: _emptyPage());
      await database
          .into(database.localRecords)
          .insert(
            LocalRecordsCompanion.insert(
              homeId: _home,
              entityType: 'purchasing-receipt-line',
              entityId: _line,
              revision: const Value(2),
              updatedAt: _at,
              synchronizedAt: Value(_at),
              payload: jsonEncode({..._linePayload(), 'quantity': 1}),
            ),
          );
      expect(
        await local.requiresReceiptReadbackRecovery(homeId: _home),
        isTrue,
      );
      expect(
        await local.requiresReceiptReadbackRecovery(homeId: _otherHome),
        isFalse,
      );
      var bootstraps = 0;
      final gateway = GeneratedSyncGateway(
        generated.ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/sync/bootstrap')) {
              bootstraps++;
              return _json({
                'protocolVersion': 1,
                'highWaterCursor': 'cursor-4',
                'snapshotCursor': 'cursor-4',
                'pageCursor': null,
                'hasMore': false,
                'requestId': _device,
                'records': _changes()
                    .map(
                      (change) => {
                        ...change,
                        'representation': change['representation'],
                      },
                    )
                    .toList(),
              });
            }
            return _json({
              ..._pullBody(),
              'fromCursor': 'cursor-4',
              'changes': [],
            });
          }),
        ),
      );
      expect(
        (await SyncCoordinator(
          local: local,
          remote: gateway,
          connectivity: const _Online(),
        ).synchronize(_home)).status,
        SyncRunStatus.completed,
      );
      expect(bootstraps, 1);
      expect(
        await local.requiresReceiptReadbackRecovery(homeId: _home),
        isFalse,
      );
      expect(await local.cursorForHome(_home), 'cursor-4');
    },
  );
}

Map<String, Object?> _linePayload() => {
  'id': _line,
  'receiptId': _receipt,
  'revision': 2,
  'rawDescription': 'Flour',
  'quantity': '1.0000',
  'lineTotal': '25.0000',
  'homeProductId': _product,
  'approvalStatus': 'approved',
};
List<Map<String, Object?>> _changes({
  Map<String, Object?> lineOverride = const {},
}) => [
  {
    'cursor': 'cursor-3',
    'entityType': 'purchasing-receipt',
    'entityId': _receipt,
    'operation': 'upsert',
    'representationSchemaVersion': 1,
    'revision': 4,
    'serverTimestamp': _at.toIso8601String(),
    'representation': {
      'id': _receipt,
      'homeId': _home,
      'revision': 4,
      'status': 'committed',
      'purchaseDate': '2026-10-03',
      'currency': 'NAD',
      'totalAmount': '25.0000',
      'notes': '',
    },
  },
  {
    'cursor': 'cursor-4',
    'entityType': 'purchasing-receipt-line',
    'entityId': _line,
    'operation': 'upsert',
    'representationSchemaVersion': 1,
    'revision': 2,
    'serverTimestamp': _at.toIso8601String(),
    'representation': {..._linePayload(), ...lineOverride},
  },
];
Map<String, Object?> _pullBody({
  Map<String, Object?> lineOverride = const {},
}) => {
  'protocolVersion': 1,
  'fromCursor': 'cursor-0',
  'pageCursor': 'cursor-4',
  'highWaterCursor': 'cursor-4',
  'hasMore': false,
  'requestId': _device,
  'changes': _changes(lineOverride: lineOverride),
};
http.Response _json(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
PullPage _emptyPage() => PullPage(
  protocolVersion: 1,
  fromCursor: null,
  pageCursor: 'cursor-0',
  highWaterCursor: 'cursor-0',
  hasMore: false,
  requestId: _device,
  changes: const [],
);

final class _Online implements ConnectivityProbe {
  const _Online();
  @override
  Future<ConnectivityResult> check() async => const ConnectivityResult.online();
}
