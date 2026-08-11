import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/client_local_record_types.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

void main() {
  late AppDatabase database;
  late DriftLocalSyncRepository repository;
  late DateTime clock;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    clock = DateTime.utc(2026, 7, 30, 12);
    repository = DriftLocalSyncRepository(database, clock: () => clock);
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
      retryPolicy: RetryPolicy(baseDelay: Duration(seconds: 2)),
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

  test('an earlier retry delay is a queue barrier until it is due', () async {
    final firstAt = DateTime.utc(2026, 7, 29, 12);
    await repository.commitLocalMutation(_mutation(clientTimestamp: firstAt));
    await repository.commitLocalMutation(
      _mutation(
        operationId: 'operation-2',
        entityId: 'record-2',
        clientTimestamp: firstAt.add(const Duration(seconds: 1)),
      ),
    );
    await repository.commitLocalMutation(
      _mutation(
        operationId: 'operation-3',
        entityId: 'record-3',
        clientTimestamp: firstAt.add(const Duration(seconds: 2)),
      ),
    );
    await repository.markSyncing(const <String>['operation-1']);
    await repository.applyPushResults(
      results: <PushOperationResult>[
        PushOperationResult(
          operationId: 'operation-1',
          kind: PushResultKind.acknowledged,
        ),
      ],
      now: firstAt,
      retryPolicy: RetryPolicy(),
    );
    await repository.markSyncing(const <String>['operation-2']);
    await repository.applyPushResults(
      results: <PushOperationResult>[
        PushOperationResult(
          operationId: 'operation-2',
          kind: PushResultKind.retryableFailure,
          safeMessage: 'Retry in order.',
        ),
      ],
      now: firstAt,
      retryPolicy: RetryPolicy(baseDelay: const Duration(seconds: 2)),
    );

    expect(
      await repository.pendingOperations(
        homeId: 'home-1',
        now: firstAt.add(const Duration(seconds: 1)),
      ),
      isEmpty,
    );

    final due = await repository.pendingOperations(
      homeId: 'home-1',
      now: firstAt.add(const Duration(seconds: 3)),
    );
    expect(due.map((operation) => operation.operationId), <String>[
      'operation-2',
      'operation-3',
    ]);
  });

  test(
    'earlier acknowledgement cannot roll back a dependent optimistic revision',
    () async {
      await repository.commitLocalMutation(
        _mutation(
          entityType: 'purchasing-receipt',
          baseRevision: 1,
          operationType: 'purchasing.receipt.create',
        ),
      );
      await database
          .update(database.localRecords)
          .write(
            const LocalRecordsCompanion(
              revision: Value<int>(3),
              synchronizedAt: Value<DateTime?>(null),
            ),
          );
      await repository.markSyncing(const <String>['operation-1']);

      await repository.applyPushResults(
        results: <PushOperationResult>[
          PushOperationResult(
            operationId: 'operation-1',
            kind: PushResultKind.acknowledged,
            acceptedRevision: 1,
          ),
        ],
        now: DateTime.utc(2026, 7, 29, 13),
        retryPolicy: RetryPolicy(),
      );

      final record = await database.select(database.localRecords).getSingle();
      expect(record.revision, 3);
      expect(record.synchronizedAt, isNull);
      final operation = await database
          .select(database.clientOperations)
          .getSingle();
      expect(operation.state, ClientOperationState.acknowledged.storageValue);
    },
  );

  test('startup recovery requeues a process-death syncing operation', () async {
    await repository.commitLocalMutation(_mutation());
    await repository.commitLocalMutation(
      _mutation(operationId: 'operation-2', homeId: 'home-2'),
    );
    await repository.markSyncing(const <String>['operation-1', 'operation-2']);

    final recovered = await repository.recoverInterruptedOperations(
      homeId: 'home-1',
      now: DateTime.utc(2026, 7, 29, 13),
    );

    expect(recovered, const <String>['operation-1']);
    final operations = await database.select(database.clientOperations).get();
    final operation = operations.singleWhere(
      (row) => row.operationId == 'operation-1',
    );
    expect(operation.state, ClientOperationState.pending.storageValue);
    expect(operation.lastSafeError, contains('interrupted'));
    expect(
      operations.singleWhere((row) => row.operationId == 'operation-2').state,
      ClientOperationState.syncing.storageValue,
    );
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

  test(
    'equal authoritative upsert confirms protocol-v2 optimistic projection',
    () async {
      await repository.commitLocalMutation(
        _mutation(
          entityType: 'purchasing-receipt',
          entityId: 'receipt-1',
          operationType: 'purchasing.receipt.create',
          payload: const <String, Object?>{'status': 'draft-local'},
        ),
      );
      await database
          .update(database.localRecords)
          .write(
            const LocalRecordsCompanion(
              revision: Value<int>(1),
              synchronizedAt: Value<DateTime?>(null),
            ),
          );
      await repository.markSyncing(const <String>['operation-1']);
      await repository.applyPushResults(
        results: <PushOperationResult>[
          PushOperationResult(
            operationId: 'operation-1',
            kind: PushResultKind.acknowledged,
          ),
        ],
        now: DateTime.utc(2026, 7, 29, 13),
        retryPolicy: RetryPolicy(),
      );
      final serverAt = DateTime.utc(2026, 7, 29, 13, 1);

      await repository.applyPullPage(
        homeId: 'home-1',
        page: _page(
          changes: <RemoteChange>[
            _change(
              entityType: 'purchasing-receipt',
              entityId: 'receipt-1',
              revision: 1,
              cursor: 'cursor-1',
              serverTimestamp: serverAt,
              payload: const <String, Object?>{'status': 'draft-server'},
            ),
          ],
          pageCursor: 'cursor-1',
        ),
      );

      final record = await database.select(database.localRecords).getSingle();
      expect(jsonDecode(record.payload), <String, Object?>{
        'status': 'draft-server',
      });
      expect(record.revision, 1);
      expect(record.updatedAt.toUtc(), serverAt);
      expect(record.synchronizedAt?.toUtc(), serverAt);
      expect(
        (await database.select(database.clientOperations).getSingle()).state,
        ClientOperationState.acknowledged.storageValue,
      );
    },
  );

  test('equal cross-kind tombstone cannot delete an upsert', () async {
    await repository.applyPullPage(
      homeId: 'home-1',
      page: _page(
        changes: <RemoteChange>[_change(revision: 2, cursor: 'cursor-2')],
        pageCursor: 'cursor-2',
      ),
    );

    await repository.applyPullPage(
      homeId: 'home-1',
      page: _page(
        fromCursor: 'cursor-2',
        changes: <RemoteChange>[
          _change(
            kind: RemoteChangeKind.tombstone,
            revision: 2,
            cursor: 'cursor-3',
          ),
        ],
        pageCursor: 'cursor-3',
      ),
    );

    expect(await database.select(database.localRecords).get(), hasLength(1));
    expect(await database.select(database.recordTombstones).get(), isEmpty);
    expect(await repository.cursorForHome('home-1'), 'cursor-3');
  });

  test('equal duplicate upsert cannot rewrite synchronized state', () async {
    await repository.applyPullPage(
      homeId: 'home-1',
      page: _page(
        changes: <RemoteChange>[_change(revision: 2, cursor: 'cursor-2')],
        pageCursor: 'cursor-2',
      ),
    );

    await repository.applyPullPage(
      homeId: 'home-1',
      page: _page(
        fromCursor: 'cursor-2',
        changes: <RemoteChange>[
          _change(
            revision: 2,
            cursor: 'cursor-3',
            payload: const <String, Object?>{'quantity': 999},
          ),
        ],
        pageCursor: 'cursor-3',
      ),
    );

    final record = await database.select(database.localRecords).getSingle();
    expect(jsonDecode(record.payload), <String, Object?>{'quantity': 2});
    expect(await repository.cursorForHome('home-1'), 'cursor-3');
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
    final remotePayload =
        jsonDecode(conflict.remotePayload!) as Map<String, Object?>;
    expect(operation.state, ClientOperationState.blockedConflict.storageValue);
    expect(remotePayload['tombstone'], isTrue);
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
      retryPolicy: RetryPolicy(),
    );

    await repository.requeueOperation(
      homeId: 'home-1',
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

  test('manual retry cannot cross a home boundary', () async {
    await repository.commitLocalMutation(_mutation(homeId: 'home-2'));
    await repository.markSyncing(const <String>['operation-1']);
    await repository.applyPushResults(
      results: <PushOperationResult>[
        PushOperationResult(
          operationId: 'operation-1',
          kind: PushResultKind.retryableFailure,
          safeMessage: 'Retry later.',
        ),
      ],
      now: DateTime.utc(2026, 7, 29, 14),
      retryPolicy: RetryPolicy(),
    );

    await repository.requeueOperation(
      homeId: 'home-1',
      operationId: 'operation-1',
      now: DateTime.utc(2026, 7, 29, 15),
    );

    final operation = await database
        .select(database.clientOperations)
        .getSingle();
    expect(operation.homeId, 'home-2');
    expect(operation.state, ClientOperationState.retryWait.storageValue);
  });

  test(
    'resync atomically replaces cache and reapplies unacknowledged intent',
    () async {
      await repository.applyPullPage(
        homeId: 'home-1',
        page: _page(
          changes: <RemoteChange>[
            _change(entityId: 'stale-record', revision: 1),
          ],
          pageCursor: 'expired-cursor',
        ),
      );
      await repository.commitLocalMutation(_mutation());

      await repository.replaceWithBootstrap(
        homeId: 'home-1',
        page: _page(
          fromCursor: 'snapshot-cursor',
          changes: <RemoteChange>[
            _change(
              entityId: 'server-record',
              revision: 7,
              cursor: 'snapshot-cursor',
            ),
          ],
          pageCursor: 'snapshot-cursor',
        ),
      );

      final records = await database.select(database.localRecords).get();
      expect(
        records.map((record) => record.entityId),
        containsAll(<String>['record-1', 'server-record']),
      );
      expect(
        records.map((record) => record.entityId),
        isNot(contains('stale-record')),
      );
      expect(
        jsonDecode(
          records
              .singleWhere((record) => record.entityId == 'record-1')
              .payload,
        ),
        <String, Object?>{'quantity': 1},
      );
      expect(await repository.cursorForHome('home-1'), 'snapshot-cursor');
      expect(
        await database.select(database.clientOperations).get(),
        hasLength(1),
      );
    },
  );

  test(
    'bootstrap retains separately verified shopping cache and line links',
    () async {
      for (final (type, id) in <(String, String)>[
        ('shopping-suggestion-cache-v1', 'verified-feed'),
        ('shopping-suggestion-line-link-v1', 'line-1'),
      ]) {
        await database
            .into(database.localRecords)
            .insert(
              LocalRecordsCompanion.insert(
                homeId: 'home-1',
                entityType: type,
                entityId: id,
                payload: '{}',
                updatedAt: clock,
              ),
            );
      }
      await database
          .into(database.localRecords)
          .insert(
            LocalRecordsCompanion.insert(
              homeId: 'home-1',
              entityType: 'stale-server-projection',
              entityId: 'stale',
              payload: '{}',
              updatedAt: clock,
            ),
          );

      await repository.replaceWithBootstrap(
        homeId: 'home-1',
        page: _page(
          fromCursor: 'snapshot-cursor',
          changes: const <RemoteChange>[],
          pageCursor: 'snapshot-cursor',
        ),
      );

      final records = await database.select(database.localRecords).get();
      expect(
        records.map((record) => record.entityType),
        containsAll(<String>[
          'shopping-suggestion-cache-v1',
          'shopping-suggestion-line-link-v1',
        ]),
      );
      expect(
        records.map((record) => record.entityType),
        isNot(contains('stale-server-projection')),
      );
    },
  );

  test('resync replays multiple intents in deterministic order', () async {
    await repository.commitLocalMutation(
      _mutation(
        operationId: 'operation-z',
        clientTimestamp: DateTime.utc(2026, 7, 29, 13),
        payload: const <String, Object?>{'quantity': 13},
      ),
    );
    await repository.commitLocalMutation(
      _mutation(
        operationId: 'operation-a',
        clientTimestamp: DateTime.utc(2026, 7, 29, 12),
        payload: const <String, Object?>{'quantity': 12},
      ),
    );

    await repository.replaceWithBootstrap(
      homeId: 'home-1',
      page: _page(
        fromCursor: 'snapshot-cursor',
        changes: const <RemoteChange>[],
        pageCursor: 'snapshot-cursor',
      ),
    );

    final record = await database.select(database.localRecords).getSingle();
    expect(jsonDecode(record.payload), <String, Object?>{'quantity': 13});
    expect(
      (await database.select(database.clientOperations).get()).map(
        (operation) => operation.operationId,
      ),
      containsAll(<String>['operation-a', 'operation-z']),
    );
  });

  test(
    'bootstrap replaces an acknowledged v2 projection with server truth',
    () async {
      await repository.commitLocalMutation(
        _mutation(
          entityType: 'inventory-home-product',
          entityId: 'product-1',
          operationType: 'inventory.home-product.create',
          payload: const <String, Object?>{'privateName': 'Optimistic name'},
        ),
      );
      await repository.markSyncing(const <String>['operation-1']);
      await repository.applyPushResults(
        results: <PushOperationResult>[
          PushOperationResult(
            operationId: 'operation-1',
            kind: PushResultKind.acknowledged,
          ),
        ],
        now: DateTime.utc(2026, 7, 29, 13),
        retryPolicy: RetryPolicy(),
      );

      await repository.replaceWithBootstrap(
        homeId: 'home-1',
        page: _page(
          fromCursor: 'snapshot-cursor',
          changes: <RemoteChange>[
            _change(
              entityType: 'inventory-home-product',
              entityId: 'product-1',
              revision: 1,
              cursor: 'snapshot-cursor',
              payload: const <String, Object?>{
                'id': 'product-1',
                'revision': 1,
                'privateName': 'Server name',
              },
            ),
          ],
          pageCursor: 'snapshot-cursor',
        ),
      );

      final record = await database.select(database.localRecords).getSingle();
      expect(jsonDecode(record.payload), <String, Object?>{
        'id': 'product-1',
        'revision': 1,
        'privateName': 'Server name',
      });
      expect(record.synchronizedAt, isNotNull);
    },
  );

  test(
    'bootstrap preserves a pending v2 child and its optimistic parent',
    () async {
      await repository.commitLocalMutation(
        _mutation(
          entityType: 'purchasing-receipt-line',
          entityId: 'line-1',
          operationType: 'purchasing.receipt-line.create',
          baseRevision: 1,
          payload: const <String, Object?>{'receiptId': 'receipt-1'},
        ),
      );
      await database
          .into(database.localRecords)
          .insertOnConflictUpdate(
            LocalRecordsCompanion.insert(
              homeId: 'home-1',
              entityType: 'purchasing-receipt',
              entityId: 'receipt-1',
              payload: jsonEncode(const <String, Object?>{
                'status': 'draft-optimistic',
              }),
              revision: const Value<int>(2),
              updatedAt: DateTime.utc(2026, 7, 29, 13),
              synchronizedAt: const Value<DateTime?>(null),
            ),
          );

      await repository.replaceWithBootstrap(
        homeId: 'home-1',
        page: _page(
          fromCursor: 'snapshot-cursor',
          changes: <RemoteChange>[
            _change(
              entityType: 'purchasing-receipt',
              entityId: 'receipt-1',
              revision: 1,
              cursor: 'snapshot-cursor',
              payload: const <String, Object?>{'status': 'draft-server'},
            ),
          ],
          pageCursor: 'snapshot-cursor',
        ),
      );

      final records = await database.select(database.localRecords).get();
      final parent = records.singleWhere(
        (record) => record.entityType == 'purchasing-receipt',
      );
      expect(jsonDecode(parent.payload), <String, Object?>{
        'status': 'draft-optimistic',
      });
      expect(parent.revision, 2);
      expect(parent.synchronizedAt, isNull);
      expect(
        records.any((record) => record.entityType == 'purchasing-receipt-line'),
        isTrue,
      );
    },
  );

  test(
    'bootstrap preserves pending unresolved decision and optimistic receipt parent',
    () async {
      await repository.commitLocalMutation(
        _mutation(
          entityType: 'purchasing-receipt-line',
          entityId: 'line-unresolved',
          operationType: 'purchasing.receipt-line.unresolve',
          baseRevision: 2,
          payload: const <String, Object?>{'receiptId': 'receipt-unresolved'},
        ),
      );
      await database
          .into(database.localRecords)
          .insertOnConflictUpdate(
            LocalRecordsCompanion.insert(
              homeId: 'home-1',
              entityType: 'purchasing-receipt',
              entityId: 'receipt-unresolved',
              payload: jsonEncode(const <String, Object?>{
                'status': 'draft-optimistic',
              }),
              revision: const Value<int>(4),
              updatedAt: DateTime.utc(2026, 7, 29, 13),
              synchronizedAt: const Value<DateTime?>(null),
            ),
          );

      await repository.replaceWithBootstrap(
        homeId: 'home-1',
        page: _page(
          fromCursor: 'snapshot-cursor',
          changes: <RemoteChange>[
            _change(
              entityType: 'purchasing-receipt',
              entityId: 'receipt-unresolved',
              revision: 3,
              cursor: 'snapshot-cursor',
              payload: const <String, Object?>{'status': 'draft-server'},
            ),
          ],
          pageCursor: 'snapshot-cursor',
        ),
      );

      final records = await database.select(database.localRecords).get();
      final parent = records.singleWhere(
        (record) => record.entityType == 'purchasing-receipt',
      );
      expect(jsonDecode(parent.payload), <String, Object?>{
        'status': 'draft-optimistic',
      });
      expect(parent.revision, 4);
      expect(parent.synchronizedAt, isNull);
      expect(
        records.any(
          (record) =>
              record.entityType == 'purchasing-receipt-line' &&
              record.entityId == 'line-unresolved',
        ),
        isTrue,
      );
    },
  );

  test('summary stream is isolated to its requested home', () async {
    await repository.commitLocalMutation(_mutation());
    await repository.commitLocalMutation(
      _mutation(
        operationId: 'operation-2',
        homeId: 'home-2',
        entityId: 'record-2',
      ),
    );
    await repository.markSyncing(const <String>['operation-2']);

    final homeOne = await repository.watchSummary(homeId: 'home-1').first;
    final homeTwo = await repository.watchSummary(homeId: 'home-2').first;

    expect(homeOne.pending, 1);
    expect(homeOne.syncing, 0);
    expect(homeTwo.pending, 0);
    expect(homeTwo.syncing, 1);
  });

  test('later remote changes preserve already-blocked local intent', () async {
    await repository.commitLocalMutation(_mutation(baseRevision: 1));
    await repository.applyPullPage(
      homeId: 'home-1',
      page: _page(
        changes: <RemoteChange>[_change(revision: 2, cursor: 'cursor-2')],
        pageCursor: 'cursor-2',
      ),
    );
    await repository.applyPullPage(
      homeId: 'home-1',
      page: _page(
        fromCursor: 'cursor-2',
        changes: <RemoteChange>[_change(revision: 3, cursor: 'cursor-3')],
        pageCursor: 'cursor-3',
      ),
    );

    final record = await database.select(database.localRecords).getSingle();
    final operation = await database
        .select(database.clientOperations)
        .getSingle();
    final conflict = await database
        .select(database.syncConflictRecords)
        .getSingle();

    expect(jsonDecode(record.payload), <String, Object?>{'quantity': 1});
    expect(operation.state, ClientOperationState.blockedConflict.storageValue);
    expect(conflict.remoteRevision, 3);
    expect(jsonDecode(conflict.remotePayload!), <String, Object?>{
      'quantity': 3,
    });
    expect(await repository.cursorForHome('home-1'), 'cursor-3');
  });

  test('cursor audit timestamps use the injected clock', () async {
    await repository.applyPullPage(
      homeId: 'home-1',
      page: _page(changes: const <RemoteChange>[], pageCursor: 'cursor-1'),
    );

    final cursor = await database.select(database.localSyncCursors).getSingle();
    expect(
      cursor.updatedAt.microsecondsSinceEpoch,
      clock.microsecondsSinceEpoch,
    );

    clock = clock.add(const Duration(minutes: 5));
    await repository.replaceWithBootstrap(
      homeId: 'home-1',
      page: _page(
        fromCursor: 'snapshot-cursor',
        changes: const <RemoteChange>[],
        pageCursor: 'snapshot-cursor',
      ),
    );

    final replaced = await database
        .select(database.localSyncCursors)
        .getSingle();
    expect(
      replaced.updatedAt.microsecondsSinceEpoch,
      clock.microsecondsSinceEpoch,
    );
  });

  test(
    'bootstrap preserves local AI settings and rejects server injection',
    () async {
      for (final (type, id) in <(String, String)>[
        (ClientLocalRecordTypes.strictLocalAiConfiguration, 'profile-1'),
        (ClientLocalRecordTypes.strictLocalAiSelection, 'active'),
      ]) {
        await database
            .into(database.localRecords)
            .insert(
              LocalRecordsCompanion.insert(
                homeId: 'home-1',
                entityType: type,
                entityId: id,
                payload: jsonEncode(<String, Object?>{'id': id}),
                updatedAt: clock,
              ),
            );
      }

      await repository.replaceWithBootstrap(
        homeId: 'home-1',
        page: _page(
          fromCursor: 'snapshot-cursor',
          changes: const <RemoteChange>[],
          pageCursor: 'snapshot-cursor',
        ),
      );
      expect(await database.select(database.localRecords).get(), hasLength(2));

      for (final type in <String>{
        ClientLocalRecordTypes.strictLocalAiConfiguration,
        ClientLocalRecordTypes.strictLocalAiSelection,
      }) {
        await expectLater(
          repository.replaceWithBootstrap(
            homeId: 'home-1',
            page: _page(
              fromCursor: 'snapshot-cursor-2',
              changes: <RemoteChange>[
                _change(
                  entityType: type,
                  entityId: 'server-injected',
                  cursor: 'snapshot-cursor-2',
                ),
              ],
              pageCursor: 'snapshot-cursor-2',
            ),
          ),
          throwsStateError,
        );
      }

      await expectLater(
        repository.applyPullPage(
          homeId: 'home-1',
          page: _page(
            fromCursor: 'snapshot-cursor',
            changes: <RemoteChange>[
              _change(
                entityType: ClientLocalRecordTypes.strictLocalAiConfiguration,
                entityId: 'server-injected',
                cursor: 'cursor-remote-injection',
              ),
            ],
            pageCursor: 'cursor-remote-injection',
          ),
        ),
        throwsStateError,
      );
    },
  );
}

LocalMutation _mutation({
  String operationId = 'operation-1',
  String homeId = 'home-1',
  String entityType = 'inventory_balance',
  String entityId = 'record-1',
  String operationType = 'set_count',
  int? baseRevision,
  DateTime? clientTimestamp,
  Map<String, Object?> payload = const <String, Object?>{'quantity': 1},
}) {
  return LocalMutation(
    operationId: operationId,
    deviceId: 'device-1',
    homeId: homeId,
    entityType: entityType,
    entityId: entityId,
    operationType: operationType,
    baseRevision: baseRevision,
    clientTimestamp: clientTimestamp ?? DateTime.utc(2026, 7, 29, 12),
    payloadSchemaVersion: 1,
    payload: payload,
  );
}

RemoteChange _change({
  String homeId = 'home-1',
  String entityType = 'inventory_balance',
  String entityId = 'record-1',
  RemoteChangeKind kind = RemoteChangeKind.upsert,
  int revision = 1,
  String cursor = 'cursor-1',
  DateTime? serverTimestamp,
  Map<String, Object?>? payload,
}) {
  return RemoteChange(
    cursor: cursor,
    homeId: homeId,
    entityType: entityType,
    entityId: entityId,
    kind: kind,
    revision: revision,
    serverTimestamp: serverTimestamp ?? DateTime.utc(2026, 7, 29, 12),
    payload: payload ?? <String, Object?>{'quantity': revision},
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
