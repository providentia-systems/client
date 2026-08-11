import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/app_controller.dart';
import 'package:providentia/app/providentia_app.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/sync_conflicts/application/sync_conflict_repository.dart';
import 'package:providentia/features/sync_conflicts/infrastructure/drift_sync_conflict_repository.dart';
import 'package:providentia/features/sync_conflicts/presentation/sync_conflict_controller.dart';

const String _homeOne = 'home-1';
const String _homeTwo = 'home-2';
const String _operationOne = '0198a0b1-c2d3-4e4f-8567-89abcdef0123';
const String _operationTwo = '0198a0b1-c2d3-4e4f-9678-9abcdef01234';
const String _freshOperation = '0198a0b1-c2d3-4e4f-a789-abcdef012345';
final DateTime _now = DateTime.utc(2026, 8, 11, 13);

void main() {
  late AppDatabase database;
  late DriftLocalSyncRepository local;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    local = DriftLocalSyncRepository(database, clock: () => _now);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'accept remote applies projection and supersedes without acknowledging',
    () async {
      await _seedPushConflict(local);
      await local.commitLocalMutation(
        _mutation(
          operationId: _operationTwo,
          entityId: 'later-record',
          at: _now.add(const Duration(seconds: 2)),
          payload: const <String, Object?>{'quantity': 9},
        ),
      );
      final repository = _scoped(local);

      final evidence = (await repository.unresolved()).single;
      expect(evidence.homeId, _homeOne);
      expect(evidence.local.commandPayload, <String, Object?>{'quantity': 3});
      expect(evidence.local.representation, <String, Object?>{'quantity': 3});
      expect(evidence.remote.kind, SyncConflictRemoteKind.upsert);
      expect(evidence.remote.representation, <String, Object?>{'quantity': 2});

      await repository.acceptRemote(evidence.id);

      final original = await _operation(database, _operationOne);
      expect(original.state, ClientOperationState.superseded.storageValue);
      expect(original.acknowledgedAt, isNull);
      final record = await _record(database, 'record-1');
      expect(jsonDecode(record.payload), <String, Object?>{'quantity': 2});
      expect(record.revision, 2);
      expect(record.synchronizedAt, isNotNull);
      final conflict = await database
          .select(database.syncConflictRecords)
          .getSingle();
      expect(conflict.resolution, 'accept_remote');
      expect(conflict.resolvedAt, isNotNull);
      expect(await repository.unresolved(), isEmpty);

      final executable = await local.pendingOperations(
        homeId: _homeOne,
        now: _now.add(const Duration(minutes: 1)),
      );
      expect(executable.map((operation) => operation.operationId), <String>[
        _operationTwo,
      ]);
    },
  );

  test(
    'reapply local creates a fresh revision-bound operation before dependents',
    () async {
      await _seedPushConflict(local);
      await local.commitLocalMutation(
        _mutation(
          operationId: _operationTwo,
          entityId: 'later-record',
          at: _now.add(const Duration(seconds: 2)),
          payload: const <String, Object?>{'quantity': 9},
        ),
      );
      final repository = _scoped(
        local,
        operationIdGenerator: () => _freshOperation,
      );

      await repository.reapplyLocal('conflict:$_operationOne');

      final original = await _operation(database, _operationOne);
      final replacement = await _operation(database, _freshOperation);
      expect(original.state, ClientOperationState.superseded.storageValue);
      expect(original.acknowledgedAt, isNull);
      expect(replacement.state, ClientOperationState.pending.storageValue);
      expect(replacement.baseRevision, 2);
      expect(replacement.payload, jsonEncode(<String, Object?>{'quantity': 3}));
      expect(replacement.clientTimestamp, original.clientTimestamp);
      final record = await _record(database, 'record-1');
      expect(jsonDecode(record.payload), <String, Object?>{'quantity': 3});
      expect(record.revision, 3);
      expect(record.synchronizedAt, isNull);
      final conflict = await database
          .select(database.syncConflictRecords)
          .getSingle();
      expect(conflict.resolution, 'reapply_local');

      final executable = await local.pendingOperations(
        homeId: _homeOne,
        now: _now.add(const Duration(minutes: 1)),
      );
      expect(executable.map((operation) => operation.operationId), <String>[
        _freshOperation,
        _operationTwo,
      ]);
    },
  );

  test('accept remote deletion commits a tombstone atomically', () async {
    await local.commitLocalMutation(_mutation(baseRevision: 1));
    await local.applyPullPage(
      homeId: _homeOne,
      page: PullPage(
        protocolVersion: 1,
        fromCursor: null,
        changes: <RemoteChange>[
          RemoteChange(
            cursor: 'cursor-2',
            homeId: _homeOne,
            entityType: 'inventory-balance',
            entityId: 'record-1',
            kind: RemoteChangeKind.tombstone,
            revision: 2,
            serverTimestamp: _now,
          ),
        ],
        pageCursor: 'cursor-2',
        highWaterCursor: 'cursor-2',
        hasMore: false,
        requestId: 'delete-conflict',
      ),
    );
    final repository = _scoped(local);
    final evidence = (await repository.unresolved()).single;
    expect(evidence.remote.kind, SyncConflictRemoteKind.tombstone);
    expect(evidence.remote.revision, 2);

    await repository.acceptRemote(evidence.id);

    expect(await database.select(database.localRecords).get(), isEmpty);
    final tombstone = await database
        .select(database.recordTombstones)
        .getSingle();
    expect(tombstone.revision, 2);
    expect(tombstone.cursor, 'cursor-2');
    expect(
      (await _operation(database, _operationOne)).state,
      ClientOperationState.superseded.storageValue,
    );
  });

  test('count conflicts refuse both generic last-writer choices', () async {
    await _seedPushConflict(
      local,
      entityType: 'inventory-count-session',
      operationType: 'inventory.count-session.cancel',
      localPayload: const <String, Object?>{},
      remotePayload: const <String, Object?>{'status': 'open'},
    );
    final repository = _scoped(
      local,
      operationIdGenerator: () => _freshOperation,
    );
    final evidence = (await repository.unresolved()).single;
    expect(evidence.requiresCountReconciliation, isTrue);
    expect(evidence.canAcceptRemote, isFalse);
    expect(evidence.canReapplyLocal, isFalse);

    await expectLater(
      repository.acceptRemote(evidence.id),
      throwsA(
        isA<SyncConflictResolutionException>().having(
          (error) => error.safeMessage,
          'safeMessage',
          contains('count reconciliation'),
        ),
      ),
    );
    await expectLater(
      repository.reapplyLocal(evidence.id),
      throwsA(isA<SyncConflictResolutionException>()),
    );

    final operation = await _operation(database, _operationOne);
    final conflict = await database
        .select(database.syncConflictRecords)
        .getSingle();
    expect(operation.state, ClientOperationState.blockedConflict.storageValue);
    expect(conflict.resolvedAt, isNull);
  });

  test(
    'count reconciliation accepts server evidence without creating a command',
    () async {
      await _seedPushConflict(
        local,
        entityType: 'inventory-count-session',
        operationType: 'inventory.count-session.cancel',
        localPayload: const <String, Object?>{},
        remotePayload: const <String, Object?>{'status': 'open', 'revision': 2},
      );
      final repository = _scoped(local);

      await repository.reconcileCount('conflict:$_operationOne');

      final operation = await _operation(database, _operationOne);
      final conflict = await database
          .select(database.syncConflictRecords)
          .getSingle();
      final record = await _record(database, 'record-1');
      expect(operation.state, ClientOperationState.superseded.storageValue);
      expect(conflict.resolution, 'reconcile_count');
      expect(conflict.resolvedAt, isNotNull);
      expect(jsonDecode(record.payload), <String, Object?>{
        'status': 'open',
        'revision': 2,
      });
      expect(
        await database.select(database.clientOperations).get(),
        hasLength(1),
      );
      expect(await repository.unresolved(), isEmpty);
    },
  );

  test(
    'failed fresh-operation insert rolls the whole resolution back',
    () async {
      await _seedPushConflict(local);
      await local.commitLocalMutation(
        _mutation(
          operationId: _operationTwo,
          entityId: 'another-record',
          at: _now.add(const Duration(seconds: 2)),
        ),
      );
      final repository = _scoped(
        local,
        operationIdGenerator: () => _operationTwo,
      );

      await expectLater(
        repository.reapplyLocal('conflict:$_operationOne'),
        throwsA(anything),
      );

      final operation = await _operation(database, _operationOne);
      final conflict = await database
          .select(database.syncConflictRecords)
          .getSingle();
      final record = await _record(database, 'record-1');
      expect(
        operation.state,
        ClientOperationState.blockedConflict.storageValue,
      );
      expect(conflict.resolvedAt, isNull);
      expect(record.revision, 1);
      expect(jsonDecode(record.payload), <String, Object?>{'quantity': 3});
      expect(
        await database.select(database.clientOperations).get(),
        hasLength(2),
      );
    },
  );

  test('active-home and live authorization boundaries fail closed', () async {
    await _seedPushConflict(local, homeId: _homeTwo);
    final homeOneRepository = _scoped(local);

    expect(await homeOneRepository.unresolved(), isEmpty);
    await expectLater(
      homeOneRepository.acceptRemote('conflict:$_operationOne'),
      throwsA(
        isA<SyncConflictResolutionException>().having(
          (error) => error.safeMessage,
          'safeMessage',
          contains('current home'),
        ),
      ),
    );
    expect(
      (await _operation(database, _operationOne)).state,
      ClientOperationState.blockedConflict.storageValue,
    );

    final denied = DriftSyncConflictRepository(
      conflictStore: local,
      homeId: _homeTwo,
      accessResolver: (_) => SyncConflictAccess.denied,
    );
    await expectLater(
      denied.unresolved(),
      throwsA(
        isA<SyncConflictResolutionException>().having(
          (error) => error.safeMessage,
          'safeMessage',
          contains('role'),
        ),
      ),
    );
  });

  testWidgets('status entry routes count evidence only to reconciliation', (
    tester,
  ) async {
    final conflict = SyncConflict(
      id: 'count-conflict',
      homeId: _homeOne,
      entityType: 'inventory-count-session',
      entityId: 'count-1',
      kind: 'revision_mismatch',
      detectedAt: _now,
      local: SyncConflictLocalEvidence(
        operationId: _operationOne,
        operationType: 'inventory.count-session.close',
        commandPayload: const <String, Object?>{'secret': 'not-rendered'},
        representation: const <String, Object?>{'status': 'closed'},
        isDeletion: false,
      ),
      remote: SyncConflictRemoteEvidence(
        kind: SyncConflictRemoteKind.upsert,
        revision: 2,
        representation: const <String, Object?>{'status': 'open'},
      ),
    );
    final conflictController = SyncConflictController(
      repository: _FakeConflictRepository(conflict),
    );
    var reconciliationCalls = 0;
    const summary = SyncSummary(
      pending: 0,
      syncing: 0,
      retryWaiting: 0,
      blockedConflicts: 1,
      blockedValidation: 0,
      blockedAuthorization: 0,
      acknowledged: 0,
      availability: SyncAvailability.online,
      isSynchronizing: false,
    );

    await tester.pumpWidget(
      ProvidentiaApp(
        controller: AppController.preview(summary: summary),
        syncConflictController: conflictController,
        onCountReconciliation: (_) => reconciliationCalls++,
      ),
    );
    expect(find.byKey(const Key('review-sync-conflicts')), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-sync-conflicts')));
    await tester.pumpAndSettle();

    expect(find.text('Synchronization review'), findsOneWidget);
    expect(
      find.byKey(const Key('reconcile-count-count-conflict')),
      findsOneWidget,
    );
    expect(find.text('Use server version'), findsNothing);
    expect(find.text('Reapply device change'), findsNothing);
    expect(find.textContaining('not-rendered'), findsNothing);
    await tester.tap(find.byKey(const Key('reconcile-count-count-conflict')));
    await tester.pump();
    expect(find.text('Use the server count?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-count-reconciliation')));
    await tester.pumpAndSettle();
    expect(reconciliationCalls, 1);
  });
}

DriftSyncConflictRepository _scoped(
  DriftLocalSyncRepository local, {
  String Function()? operationIdGenerator,
}) => DriftSyncConflictRepository(
  conflictStore: local,
  homeId: _homeOne,
  accessResolver: (_) =>
      const SyncConflictAccess(mayReview: true, mayResolve: true),
  clock: () => _now.add(const Duration(minutes: 1)),
  operationIdGenerator: operationIdGenerator,
);

Future<void> _seedPushConflict(
  DriftLocalSyncRepository local, {
  String homeId = _homeOne,
  String entityType = 'inventory-balance',
  String operationType = 'put',
  Map<String, Object?> localPayload = const <String, Object?>{'quantity': 3},
  Map<String, Object?> remotePayload = const <String, Object?>{'quantity': 2},
}) async {
  await local.commitLocalMutation(
    _mutation(
      homeId: homeId,
      entityType: entityType,
      operationType: operationType,
      baseRevision: 1,
      payload: localPayload,
    ),
  );
  await local.markSyncing(const <String>[_operationOne]);
  await local.applyPushResults(
    results: <PushOperationResult>[
      PushOperationResult(
        operationId: _operationOne,
        kind: PushResultKind.conflict,
        acceptedRevision: 2,
        remotePayload: remotePayload,
        safeMessage: 'A newer server revision needs review.',
      ),
    ],
    now: _now,
    retryPolicy: RetryPolicy(),
  );
}

LocalMutation _mutation({
  String operationId = _operationOne,
  String homeId = _homeOne,
  String entityType = 'inventory-balance',
  String entityId = 'record-1',
  String operationType = 'put',
  int? baseRevision,
  DateTime? at,
  Map<String, Object?> payload = const <String, Object?>{'quantity': 3},
}) => LocalMutation(
  operationId: operationId,
  deviceId: 'device-1',
  homeId: homeId,
  entityType: entityType,
  entityId: entityId,
  operationType: operationType,
  baseRevision: baseRevision,
  clientTimestamp: at ?? _now,
  payloadSchemaVersion: 1,
  payload: payload,
);

Future<ClientOperation> _operation(AppDatabase database, String operationId) =>
    (database.select(
      database.clientOperations,
    )..where((row) => row.operationId.equals(operationId))).getSingle();

Future<LocalRecord> _record(AppDatabase database, String entityId) =>
    (database.select(
      database.localRecords,
    )..where((row) => row.entityId.equals(entityId))).getSingle();

final class _FakeConflictRepository implements SyncConflictRepository {
  _FakeConflictRepository(this.conflict);

  final SyncConflict conflict;

  @override
  SyncConflictAccess get access =>
      const SyncConflictAccess(mayReview: true, mayResolve: true);

  @override
  String get homeId => _homeOne;

  @override
  Future<void> acceptRemote(String conflictId) async {}

  @override
  Future<void> reapplyLocal(String conflictId) async {}

  @override
  Future<void> reconcileCount(String conflictId) async {}

  @override
  bool canResolve(SyncConflict conflict) => conflict.homeId == homeId;

  @override
  Future<List<SyncConflict>> unresolved() async => <SyncConflict>[conflict];

  @override
  Stream<List<SyncConflict>> watchUnresolved() =>
      Stream<List<SyncConflict>>.value(<SyncConflict>[conflict]);
}
