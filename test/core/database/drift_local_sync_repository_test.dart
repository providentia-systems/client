import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

void main() {
  late AppDatabase database;
  late DriftLocalSyncRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftLocalSyncRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('domain change and outbox operation commit atomically', () async {
    await repository.commitLocalMutation(_mutation());

    await expectLater(
      repository.commitLocalMutation(
        _mutation(
          entityId: 'second-record',
          payload: <String, Object?>{'n': 2},
        ),
      ),
      throwsA(anything),
    );

    final records = await database.select(database.localRecords).get();
    final operations = await database.select(database.clientOperations).get();
    expect(records, hasLength(1));
    expect(records.single.entityId, 'record-1');
    expect(operations, hasLength(1));
    expect(operations.single.operationId, 'operation-1');
  });

  test(
    'create operation keeps a nullable base revision and local revision 0',
    () async {
      await repository.commitLocalMutation(_mutation());

      final operation = await database
          .select(database.clientOperations)
          .getSingle();
      final record = await database.select(database.localRecords).getSingle();
      expect(operation.baseRevision, isNull);
      expect(record.revision, 0);
    },
  );

  test('retry classification persists safe backoff state', () async {
    await repository.commitLocalMutation(_mutation(baseRevision: 3));
    await repository.markSyncing(const <String>['operation-1']);
    final now = DateTime.utc(2026, 7, 29, 12);

    await repository.applyPushResults(
      results: <PushOperationResult>[
        PushOperationResult(
          operationId: 'operation-1',
          kind: PushResultKind.retryableFailure,
          safeMessage: 'Connection interrupted. Retrying safely.',
        ),
      ],
      now: now,
      retryPolicy: const RetryPolicy(baseDelay: Duration(seconds: 2)),
    );

    final operation = await database
        .select(database.clientOperations)
        .getSingle();
    expect(operation.state, ClientOperationState.retryWait.storageValue);
    expect(operation.retryCount, 1);
    expect(operation.nextAttemptAt, isNotNull);
    expect(operation.nextAttemptAt!.isAfter(now), isTrue);
    expect(operation.lastSafeError, contains('Retrying safely'));
  });

  test('startup recovery requeues a process-death syncing operation', () async {
    await repository.commitLocalMutation(_mutation());
    await repository.markSyncing(const <String>['operation-1']);

    await repository.recoverInterruptedOperations(
      now: DateTime.utc(2026, 7, 29, 13),
    );

    final operation = await database
        .select(database.clientOperations)
        .getSingle();
    expect(operation.state, ClientOperationState.pending.storageValue);
    expect(operation.lastSafeError, contains('interrupted'));
  });

  test(
    'pull page and cursor commit atomically on cross-home rejection',
    () async {
      final page = _page(
        changes: <RemoteChange>[_change(homeId: 'another-home', revision: 1)],
        pageCursor: 'cursor-1',
      );

      await expectLater(
        repository.applyPullPage(homeId: 'home-1', page: page),
        throwsStateError,
      );

      expect(await repository.cursorForHome('home-1'), isNull);
      expect(await database.select(database.localRecords).get(), isEmpty);
    },
  );

  test('first pull accepts the server canonical genesis cursor', () async {
    await repository.applyPullPage(
      homeId: 'home-1',
      page: _page(
        fromCursor: 'eyJzZXF1ZW5jZSI6MH0',
        changes: const <RemoteChange>[],
        pageCursor: 'eyJzZXF1ZW5jZSI6MH0',
      ),
    );

    expect(await repository.cursorForHome('home-1'), 'eyJzZXF1ZW5jZSI6MH0');
  });

  test('older upsert never resurrects a newer tombstone', () async {
    await repository.applyPullPage(
      homeId: 'home-1',
      page: _page(
        changes: <RemoteChange>[
          _change(
            kind: RemoteChangeKind.tombstone,
            revision: 5,
            cursor: 'cursor-5',
          ),
        ],
        pageCursor: 'cursor-5',
      ),
    );
    await repository.applyPullPage(
      homeId: 'home-1',
      page: _page(
        fromCursor: 'cursor-5',
        changes: <RemoteChange>[_change(revision: 4, cursor: 'cursor-6')],
        pageCursor: 'cursor-6',
      ),
    );

    expect(await database.select(database.localRecords).get(), isEmpty);
    final tombstone = await database
        .select(database.recordTombstones)
        .getSingle();
    expect(tombstone.revision, 5);
    expect(await repository.cursorForHome('home-1'), 'cursor-6');
  });

  test('duplicate tombstone replay is idempotent', () async {
    final change = _change(
      kind: RemoteChangeKind.tombstone,
      revision: 5,
      cursor: 'cursor-5',
    );
    await repository.applyPullPage(
      homeId: 'home-1',
      page: _page(changes: <RemoteChange>[change], pageCursor: 'cursor-5'),
    );
    await repository.applyPullPage(
      homeId: 'home-1',
      page: _page(
        fromCursor: 'cursor-5',
        changes: <RemoteChange>[change],
        pageCursor: 'cursor-6',
      ),
    );

    expect(
      await database.select(database.recordTombstones).get(),
      hasLength(1),
    );
    expect(await repository.cursorForHome('home-1'), 'cursor-6');
  });

  test('remote tombstone is preserved when local intent is pending', () async {
    await repository.commitLocalMutation(_mutation(baseRevision: 1));

    await repository.applyPullPage(
      homeId: 'home-1',
      page: _page(
        changes: <RemoteChange>[
          _change(
            kind: RemoteChangeKind.tombstone,
            revision: 2,
            cursor: 'cursor-2',
          ),
        ],
        pageCursor: 'cursor-2',
      ),
    );

    final operation = await database
        .select(database.clientOperations)
        .getSingle();
    final conflict = await database
        .select(database.syncConflictRecords)
        .getSingle();
    expect(operation.state, ClientOperationState.blockedConflict.storageValue);
    expect(jsonDecode(conflict.remotePayload!)['tombstone'], isTrue);
    expect(conflict.remoteRevision, 2);
  });

  test('manual retry cannot bypass validation or conflict blocks', () async {
    await repository.commitLocalMutation(_mutation());
    await repository.markSyncing(const <String>['operation-1']);
    await repository.applyPushResults(
      results: <PushOperationResult>[
        PushOperationResult(
          operationId: 'operation-1',
          kind: PushResultKind.validationError,
          safeMessage: 'Correct the value before retrying.',
        ),
      ],
      now: DateTime.utc(2026, 7, 29, 14),
      retryPolicy: const RetryPolicy(),
    );

    await repository.requeueOperation(
      operationId: 'operation-1',
      now: DateTime.utc(2026, 7, 29, 15),
    );

    final operation = await database
        .select(database.clientOperations)
        .getSingle();
    expect(
      operation.state,
      ClientOperationState.blockedValidation.storageValue,
    );
  });
}

LocalMutation _mutation({
  String entityId = 'record-1',
  int? baseRevision,
  Map<String, Object?> payload = const <String, Object?>{'quantity': 1},
}) {
  return LocalMutation(
    operationId: 'operation-1',
    deviceId: 'device-1',
    homeId: 'home-1',
    entityType: 'inventory_balance',
    entityId: entityId,
    operationType: 'set_count',
    baseRevision: baseRevision,
    clientTimestamp: DateTime.utc(2026, 7, 29, 12),
    payloadSchemaVersion: 1,
    payload: payload,
  );
}

RemoteChange _change({
  String homeId = 'home-1',
  RemoteChangeKind kind = RemoteChangeKind.upsert,
  int revision = 1,
  String cursor = 'cursor-1',
}) {
  return RemoteChange(
    cursor: cursor,
    homeId: homeId,
    entityType: 'inventory_balance',
    entityId: 'record-1',
    kind: kind,
    revision: revision,
    serverTimestamp: DateTime.utc(2026, 7, 29, 12),
    payload: <String, Object?>{'quantity': revision},
  );
}

PullPage _page({
  String? fromCursor,
  required List<RemoteChange> changes,
  required String pageCursor,
  bool hasMore = false,
}) {
  return PullPage(
    protocolVersion: 1,
    fromCursor: fromCursor,
    changes: changes,
    pageCursor: pageCursor,
    highWaterCursor: pageCursor,
    hasMore: hasMore,
    requestId: 'request-1',
  );
}
