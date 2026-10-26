import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

void main() {
  late AppDatabase database;
  late DriftLocalSyncRepository repository;
  final now = DateTime.utc(2026, 10, 13, 8);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftLocalSyncRepository(database, clock: () => now);
  });
  tearDown(() => database.close());

  Future<void> seed(String command) async {
    final parentCommand =
        command == 'purchasing.receipt.cancel' ||
        command == 'purchasing.receipt.commit';
    await database
        .into(database.localRecords)
        .insert(
          LocalRecordsCompanion.insert(
            homeId: 'home-1',
            entityType: 'purchasing-receipt-line',
            entityId: 'line-1',
            payload: jsonEncode(<String, Object?>{
              'receiptId': 'receipt-1',
              'homeProductId': 'product-1',
              'quantity': '5',
              'stockQuantity': '5',
              'approvalStatus': command == 'purchasing.receipt-line.remove'
                  ? 'removed'
                  : 'approved',
            }),
            revision: const Value(1),
            updatedAt: now,
          ),
        );
    await database
        .into(database.localRecords)
        .insert(
          LocalRecordsCompanion.insert(
            homeId: 'home-1',
            entityType: 'purchasing-receipt',
            entityId: 'receipt-1',
            payload: jsonEncode(<String, Object?>{
              'status': command == 'purchasing.receipt.cancel'
                  ? 'cancelled'
                  : 'draft',
            }),
            revision: const Value(3),
            updatedAt: now,
          ),
        );
    await database
        .into(database.localRecords)
        .insert(
          LocalRecordsCompanion.insert(
            homeId: 'home-1',
            entityType: 'inventory-balance',
            entityId: 'product-1',
            payload: jsonEncode(<String, Object?>{'quantity': '7'}),
            revision: const Value(3),
            updatedAt: now,
          ),
        );
    await database
        .into(database.clientOperations)
        .insert(
          ClientOperationsCompanion.insert(
            operationId: 'purchase-operation-1',
            deviceId: 'device-1',
            homeId: 'home-1',
            entityType: parentCommand
                ? 'purchasing-receipt'
                : 'purchasing-receipt-line',
            entityId: parentCommand ? 'receipt-1' : 'line-1',
            operationType: command,
            baseRevision: const Value(2),
            clientTimestamp: now,
            payload: jsonEncode(<String, Object?>{
              if (!parentCommand) 'receiptId': 'receipt-1',
              if (command == 'purchasing.receipt-line.purchase' ||
                  command == 'purchasing.receipt-line.correct')
                'homeProductId': 'product-1',
            }),
            state: ClientOperationState.pending.storageValue,
          ),
        );
  }

  PullPage page({String cursor = 'cursor-1', int revision = 2}) => PullPage(
    protocolVersion: 1,
    fromCursor: cursor == 'cursor-1' ? null : 'cursor-1',
    pageCursor: cursor,
    highWaterCursor: cursor,
    hasMore: false,
    requestId: 'purchase-readback',
    changes: <RemoteChange>[
      RemoteChange(
        cursor: cursor,
        homeId: 'home-1',
        entityType: 'inventory-balance',
        entityId: 'product-1',
        kind: RemoteChangeKind.upsert,
        revision: revision,
        serverTimestamp: now,
        payload: <String, Object?>{'quantity': revision == 2 ? '4' : '8'},
      ),
      RemoteChange(
        cursor: cursor,
        homeId: 'home-1',
        entityType: 'purchasing-receipt',
        entityId: 'receipt-1',
        kind: RemoteChangeKind.upsert,
        revision: revision,
        serverTimestamp: now,
        payload: const <String, Object?>{'status': 'draft'},
      ),
    ],
  );

  Future<LocalRecord> balance() =>
      (database.select(database.localRecords)..where(
            (row) =>
                row.homeId.equals('home-1') &
                row.entityType.equals('inventory-balance'),
          ))
          .getSingle();

  for (final command in <String>[
    'purchasing.receipt-line.purchase',
    'purchasing.receipt-line.correct',
    'purchasing.receipt-line.update',
    'purchasing.receipt-line.remove',
    'purchasing.receipt.cancel',
    'purchasing.receipt.commit',
  ]) {
    test(
      'bootstrap retains stock intent and operation identity for $command',
      () async {
        await seed(command);
        await repository.replaceWithBootstrap(homeId: 'home-1', page: page());
        final savedBalance = await balance();
        expect(jsonDecode(savedBalance.payload), <String, Object?>{
          'quantity': '7',
        });
        expect(savedBalance.synchronizedAt, isNull);
        final savedLine =
            await (database.select(database.localRecords)..where(
                  (row) =>
                      row.homeId.equals('home-1') &
                      row.entityType.equals('purchasing-receipt-line'),
                ))
                .getSingle();
        expect(
          (jsonDecode(savedLine.payload)
              as Map<String, Object?>)['stockQuantity'],
          '5',
        );
        expect(savedLine.synchronizedAt, isNull);
        final operation = await database
            .select(database.clientOperations)
            .getSingle();
        expect(operation.operationId, 'purchase-operation-1');
        expect(operation.deviceId, 'device-1');
        expect(operation.state, ClientOperationState.pending.storageValue);
      },
    );
  }

  test(
    'partial readback preserves pending purchase then replaces server balance',
    () async {
      await seed('purchasing.receipt-line.purchase');
      await repository.applyPullPage(homeId: 'home-1', page: page());
      expect(jsonDecode((await balance()).payload), <String, Object?>{
        'quantity': '7',
      });
      expect(await repository.cursorForHome('home-1'), 'cursor-1');
      final receipt =
          await (database.select(database.localRecords)
                ..where((row) => row.entityType.equals('purchasing-receipt')))
              .getSingle();
      expect(receipt.revision, 3);
      expect(receipt.synchronizedAt, isNull);
      expect(
        await database.select(database.syncConflictRecords).get(),
        isEmpty,
      );

      await repository.applyPushResults(
        results: <PushOperationResult>[
          PushOperationResult(
            operationId: 'purchase-operation-1',
            kind: PushResultKind.acknowledged,
            acceptedRevision: 1,
          ),
        ],
        now: now,
        retryPolicy: RetryPolicy(),
      );
      // Another device has added 1 kg. The authoritative absolute 8 kg replaces
      // the optimistic 7 kg; the local 5 kg purchase is never added again.
      await repository.applyPullPage(
        homeId: 'home-1',
        page: page(cursor: 'cursor-2', revision: 4),
      );
      expect(jsonDecode((await balance()).payload), <String, Object?>{
        'quantity': '8',
      });
      expect((await balance()).synchronizedAt, isNotNull);
    },
  );
}
