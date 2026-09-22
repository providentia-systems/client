import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/session_bound_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

const account = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
LocalMutation mutation(String id, DateTime at) => LocalMutation(
  operationId: id,
  deviceId: 'device',
  homeId: 'home',
  entityType: 'item',
  entityId: id,
  operationType: 'create',
  clientTimestamp: at,
  payloadSchemaVersion: 1,
  payload: {'quantity': 1},
);
PendingClientOperation pending(String? owner) => PendingClientOperation(
  operationId: 'op',
  deviceId: 'device',
  homeId: 'home',
  originatingAccountId: owner,
  entityType: 'item',
  entityId: 'item',
  operationType: 'create',
  clientTimestamp: DateTime.utc(2026),
  payloadSchemaVersion: 1,
  payload: {},
  retryCount: 0,
);
void main() {
  test(
    'enqueue order survives equal or backwards clocks and random UUID order',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final local = DriftLocalSyncRepository(db, accountId: account);
      final now = DateTime.utc(2026, 9, 22);
      await local.commitLocalMutation(mutation('z-parent', now));
      await local.commitLocalMutation(
        mutation('a-child', now.subtract(const Duration(days: 1))),
      );
      final rows = await local.pendingOperations(homeId: 'home', now: now);
      expect(rows.map((row) => row.operationId), ['z-parent', 'a-child']);
      expect(rows.map((row) => row.enqueueSequence), [1, 2]);
      expect(rows.every((row) => row.originatingAccountId == account), isTrue);
      expect(rows.last.clientTimestamp, now.subtract(const Duration(days: 1)));
    },
  );
  test(
    'retired writer rolls back optimistic state and never consumes an order',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var checks = 0;
      final local = DriftLocalSyncRepository(
        db,
        accountId: account,
        isCurrent: () => ++checks == 1,
      );
      await expectLater(
        local.commitLocalMutation(mutation('old', DateTime.utc(2026))),
        throwsA(isA<AuthenticationSyncException>()),
      );
      expect(await db.select(db.clientOperations).get(), isEmpty);
      expect(await db.select(db.localRecords).get(), isEmpty);
      final current = DriftLocalSyncRepository(db, accountId: account);
      await current.commitLocalMutation(mutation('new', DateTime.utc(2026)));
      expect(
        (await current.pendingOperations(
          homeId: 'home',
          now: DateTime.utc(2026),
        )).single.enqueueSequence,
        1,
      );
    },
  );
  test(
    'account provenance is checked before transport or receipt recovery',
    () async {
      final gateway = SessionBoundSyncGateway(
        delegate: _NoTransport(),
        homeId: 'home',
        deviceId: 'device',
        accountId: account,
        isCurrent: () => true,
      );
      for (final entry in {
        null: 'origin_account_unknown',
        'another-account': 'account_binding_mismatch',
      }.entries) {
        expect(
          () => gateway.validateOperationBinding(pending(entry.key)),
          throwsA(
            isA<BindingSyncException>().having(
              (e) => e.code,
              'code',
              entry.value,
            ),
          ),
        );
        await expectLater(
          gateway.push(
            homeId: 'home',
            lastPulledCursor: null,
            operations: [pending(entry.key)],
          ),
          throwsA(isA<BindingSyncException>()),
        );
      }
      gateway.validateOperationBinding(pending(account));
    },
  );
}

class _NoTransport implements SyncRemoteGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No transport may be invoked by a provenance check.');
}
