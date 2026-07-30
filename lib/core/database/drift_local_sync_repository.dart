import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

final class DriftLocalSyncRepository implements LocalSyncRepository {
  DriftLocalSyncRepository(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static final List<String> _unacknowledgedOperationStates =
      <ClientOperationState>[
        ClientOperationState.pending,
        ClientOperationState.syncing,
        ClientOperationState.retryWait,
        ClientOperationState.blockedConflict,
        ClientOperationState.blockedValidation,
        ClientOperationState.blockedAuthorization,
      ].map((state) => state.storageValue).toList(growable: false);

  final AppDatabase _database;
  final DateTime Function() _clock;

  @override
  Stream<SyncSummary> watchSummary({required String homeId}) {
    final query = _database.select(_database.clientOperations)
      ..where((row) => row.homeId.equals(homeId));
    return query.watch().map((rows) {
      int count(ClientOperationState state) =>
          rows.where((row) => row.state == state.storageValue).length;
      final safeErrors = rows
          .where((row) => row.lastSafeError != null)
          .map((row) => row.lastSafeError)
          .toList(growable: false);

      return SyncSummary(
        pending: count(ClientOperationState.pending),
        syncing: count(ClientOperationState.syncing),
        retryWaiting: count(ClientOperationState.retryWait),
        blockedConflicts: count(ClientOperationState.blockedConflict),
        blockedValidation: count(ClientOperationState.blockedValidation),
        blockedAuthorization: count(ClientOperationState.blockedAuthorization),
        acknowledged: count(ClientOperationState.acknowledged),
        availability: SyncAvailability.checking,
        isSynchronizing: count(ClientOperationState.syncing) > 0,
        lastSafeError: safeErrors.isEmpty ? null : safeErrors.first,
      );
    });
  }

  @override
  Future<void> commitLocalMutation(LocalMutation mutation) {
    return _database.transaction(() async {
      await _database
          .into(_database.localRecords)
          .insertOnConflictUpdate(
            LocalRecordsCompanion.insert(
              homeId: mutation.homeId,
              entityType: mutation.entityType,
              entityId: mutation.entityId,
              payload: mutation.encodedPayload,
              revision: Value<int>(mutation.baseRevision ?? 0),
              updatedAt: mutation.clientTimestamp.toUtc(),
            ),
          );
      await _database
          .into(_database.clientOperations)
          .insert(
            ClientOperationsCompanion.insert(
              operationId: mutation.operationId,
              deviceId: mutation.deviceId,
              homeId: mutation.homeId,
              entityType: mutation.entityType,
              entityId: mutation.entityId,
              operationType: mutation.operationType,
              baseRevision: Value<int?>(mutation.baseRevision),
              clientTimestamp: mutation.clientTimestamp.toUtc(),
              payloadSchemaVersion: Value<int>(mutation.payloadSchemaVersion),
              payload: mutation.encodedPayload,
              state: ClientOperationState.pending.storageValue,
            ),
            mode: InsertMode.insertOrAbort,
          );
    });
  }

  @override
  Future<List<PendingClientOperation>> pendingOperations({
    required String homeId,
    required DateTime now,
    int limit = 100,
  }) async {
    final query = _database.select(_database.clientOperations)
      ..where(
        (row) =>
            row.homeId.equals(homeId) &
            (row.state.equals(ClientOperationState.pending.storageValue) |
                (row.state.equals(ClientOperationState.retryWait.storageValue) &
                    (row.nextAttemptAt.isNull() |
                        row.nextAttemptAt.isSmallerOrEqualValue(now.toUtc())))),
      )
      ..orderBy(<OrderingTerm Function(ClientOperations)>[
        (row) => OrderingTerm.asc(row.clientTimestamp),
        (row) => OrderingTerm.asc(row.operationId),
      ])
      ..limit(limit);

    final rows = await query.get();
    return rows
        .map(
          (row) => PendingClientOperation(
            operationId: row.operationId,
            deviceId: row.deviceId,
            homeId: row.homeId,
            entityType: row.entityType,
            entityId: row.entityId,
            operationType: row.operationType,
            baseRevision: row.baseRevision,
            clientTimestamp: row.clientTimestamp,
            payloadSchemaVersion: row.payloadSchemaVersion,
            payload: _decodePayload(row.payload),
            retryCount: row.retryCount,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> markSyncing(List<String> operationIds) async {
    if (operationIds.isEmpty) {
      return;
    }
    await (_database.update(
      _database.clientOperations,
    )..where((row) => row.operationId.isIn(operationIds))).write(
      ClientOperationsCompanion(
        state: Value<String>(ClientOperationState.syncing.storageValue),
        lastSafeError: const Value<String?>(null),
      ),
    );
  }

  @override
  Future<void> recoverInterruptedOperations({required DateTime now}) async {
    await (_database.update(_database.clientOperations)..where(
          (row) => row.state.equals(ClientOperationState.syncing.storageValue),
        ))
        .write(
          ClientOperationsCompanion(
            state: Value<String>(ClientOperationState.pending.storageValue),
            nextAttemptAt: Value<DateTime>(now.toUtc()),
            lastSafeError: const Value<String>(
              'Synchronization was interrupted and will resume safely.',
            ),
          ),
        );
  }

  @override
  Future<void> applyPushResults({
    required List<PushOperationResult> results,
    required DateTime now,
    required RetryPolicy retryPolicy,
  }) {
    return _database.transaction(() async {
      for (final result in results) {
        final operation =
            await (_database.select(_database.clientOperations)
                  ..where((row) => row.operationId.equals(result.operationId)))
                .getSingle();
        final nextState = _stateFor(result.kind);
        final nextRetryCount = result.kind == PushResultKind.retryableFailure
            ? operation.retryCount + 1
            : operation.retryCount;
        final nextAttemptAt = result.kind == PushResultKind.retryableFailure
            ? now.toUtc().add(
                retryPolicy.delayFor(
                  operationId: operation.operationId,
                  retryCount: operation.retryCount,
                ),
              )
            : null;

        await (_database.update(
          _database.clientOperations,
        )..where((row) => row.operationId.equals(result.operationId))).write(
          ClientOperationsCompanion(
            state: Value<String>(nextState.storageValue),
            retryCount: Value<int>(nextRetryCount),
            nextAttemptAt: Value<DateTime?>(nextAttemptAt),
            lastSafeError: Value<String?>(result.safeMessage),
            serverCursor: Value<String?>(result.changeCursor),
            acknowledgedAt: Value<DateTime?>(
              result.kind == PushResultKind.acknowledged ? now.toUtc() : null,
            ),
          ),
        );

        if (result.kind == PushResultKind.acknowledged &&
            result.acceptedRevision != null) {
          await (_database.update(_database.localRecords)..where(
                (row) =>
                    row.homeId.equals(operation.homeId) &
                    row.entityType.equals(operation.entityType) &
                    row.entityId.equals(operation.entityId),
              ))
              .write(
                LocalRecordsCompanion(
                  revision: Value<int>(result.acceptedRevision!),
                  synchronizedAt: Value<DateTime>(now.toUtc()),
                ),
              );
        }

        if (result.kind == PushResultKind.conflict) {
          await _database
              .into(_database.syncConflictRecords)
              .insertOnConflictUpdate(
                SyncConflictRecordsCompanion.insert(
                  conflictId: 'conflict:${operation.operationId}',
                  operationId: operation.operationId,
                  homeId: operation.homeId,
                  entityType: operation.entityType,
                  entityId: operation.entityId,
                  conflictKind: 'revision_mismatch',
                  localPayload: operation.payload,
                  remotePayload: Value<String?>(
                    result.remotePayload == null
                        ? null
                        : jsonEncode(result.remotePayload),
                  ),
                  remoteRevision: Value<int?>(result.acceptedRevision),
                  detectedAt: now.toUtc(),
                ),
              );
        }
      }
    });
  }

  @override
  Future<String?> cursorForHome(String homeId) async {
    final query = _database.select(_database.localSyncCursors)
      ..where(
        (row) =>
            row.homeId.equals(homeId) &
            row.feed.equals('home_changes') &
            row.protocolVersion.equals(1) &
            row.schemaGeneration.equals(2),
      );
    return (await query.getSingleOrNull())?.cursor;
  }

  @override
  Future<void> applyPullPage({required String homeId, required PullPage page}) {
    return _database.transaction(() async {
      if (page.protocolVersion != 1) {
        throw StateError(
          'Unsupported sync protocol version ${page.protocolVersion}.',
        );
      }
      final currentCursor = await cursorForHome(homeId);
      // The first request has no client cursor, while the backend returns a
      // canonical encoded genesis cursor in `fromCursor`. Once a cursor has
      // been committed, every following page must echo it exactly.
      if (currentCursor != null && page.fromCursor != currentCursor) {
        throw StateError(
          'Pull page cursor mismatch: expected $currentCursor, '
          'received ${page.fromCursor}.',
        );
      }
      for (final change in page.changes) {
        if (change.homeId != homeId) {
          throw StateError(
            'Cross-home change rejected for ${change.entityType}/'
            '${change.entityId}.',
          );
        }
        final localIntent =
            await (_database.select(_database.clientOperations)..where(
                  (row) =>
                      row.homeId.equals(homeId) &
                      row.entityType.equals(change.entityType) &
                      row.entityId.equals(change.entityId) &
                      row.state.isIn(_unacknowledgedOperationStates),
                ))
                .get();

        if (localIntent.isNotEmpty) {
          final remoteRepresentation = change.kind == RemoteChangeKind.upsert
              ? jsonEncode(change.payload)
              : jsonEncode(<String, Object?>{
                  'tombstone': true,
                  'revision': change.revision,
                  'cursor': change.cursor,
                  'deletedAt': change.serverTimestamp.toUtc().toIso8601String(),
                });
          for (final operation in localIntent) {
            await _database
                .into(_database.syncConflictRecords)
                .insertOnConflictUpdate(
                  SyncConflictRecordsCompanion.insert(
                    conflictId: 'conflict:${operation.operationId}',
                    operationId: operation.operationId,
                    homeId: homeId,
                    entityType: change.entityType,
                    entityId: change.entityId,
                    conflictKind: 'remote_change_with_pending_local_operation',
                    localPayload: operation.payload,
                    remotePayload: Value<String?>(remoteRepresentation),
                    remoteRevision: Value<int>(change.revision),
                    detectedAt: change.serverTimestamp.toUtc(),
                  ),
                );
            await (_database.update(_database.clientOperations)..where(
                  (row) => row.operationId.equals(operation.operationId),
                ))
                .write(
                  ClientOperationsCompanion(
                    state: Value<String>(
                      ClientOperationState.blockedConflict.storageValue,
                    ),
                    lastSafeError: const Value<String>(
                      'A newer server revision needs review.',
                    ),
                  ),
                );
          }
          continue;
        }

        final existingRecord =
            await (_database.select(_database.localRecords)..where(
                  (row) =>
                      row.homeId.equals(homeId) &
                      row.entityType.equals(change.entityType) &
                      row.entityId.equals(change.entityId),
                ))
                .getSingleOrNull();
        final existingTombstone =
            await (_database.select(_database.recordTombstones)..where(
                  (row) =>
                      row.homeId.equals(homeId) &
                      row.entityType.equals(change.entityType) &
                      row.entityId.equals(change.entityId),
                ))
                .getSingleOrNull();
        final newestRevision =
            <int>[
              if (existingRecord != null) existingRecord.revision,
              if (existingTombstone != null) existingTombstone.revision,
            ].fold<int>(-1, (highest, revision) {
              return revision > highest ? revision : highest;
            });
        if (change.revision <= newestRevision) {
          // Duplicate and out-of-order replay is idempotent. In particular, an
          // older upsert can never resurrect a newer tombstone.
          continue;
        }

        if (change.kind == RemoteChangeKind.tombstone) {
          await (_database.delete(_database.localRecords)..where(
                (row) =>
                    row.homeId.equals(homeId) &
                    row.entityType.equals(change.entityType) &
                    row.entityId.equals(change.entityId),
              ))
              .go();
          await _database
              .into(_database.recordTombstones)
              .insertOnConflictUpdate(
                RecordTombstonesCompanion.insert(
                  homeId: homeId,
                  entityType: change.entityType,
                  entityId: change.entityId,
                  revision: change.revision,
                  cursor: change.cursor,
                  deletedAt: change.serverTimestamp.toUtc(),
                ),
              );
        } else {
          await _database
              .into(_database.localRecords)
              .insertOnConflictUpdate(
                LocalRecordsCompanion.insert(
                  homeId: homeId,
                  entityType: change.entityType,
                  entityId: change.entityId,
                  payload: jsonEncode(change.payload),
                  revision: Value<int>(change.revision),
                  updatedAt: change.serverTimestamp.toUtc(),
                  synchronizedAt: Value<DateTime>(
                    change.serverTimestamp.toUtc(),
                  ),
                ),
              );
          await (_database.delete(_database.recordTombstones)..where(
                (row) =>
                    row.homeId.equals(homeId) &
                    row.entityType.equals(change.entityType) &
                    row.entityId.equals(change.entityId),
              ))
              .go();
        }
      }

      // Advancing the page cursor in the same transaction prevents a process
      // death from skipping changes that were not committed.
      await _database
          .into(_database.localSyncCursors)
          .insertOnConflictUpdate(
            LocalSyncCursorsCompanion.insert(
              homeId: homeId,
              feed: const Value<String>('home_changes'),
              protocolVersion: const Value<int>(1),
              schemaGeneration: const Value<int>(2),
              cursor: page.pageCursor,
              updatedAt: _clock().toUtc(),
            ),
          );
    });
  }

  @override
  Future<void> replaceWithBootstrap({
    required String homeId,
    required PullPage page,
  }) {
    return _database.transaction(() async {
      if (page.protocolVersion != 1 || page.hasMore) {
        throw StateError('Invalid synchronization bootstrap page.');
      }
      for (final change in page.changes) {
        if (change.homeId != homeId || change.kind != RemoteChangeKind.upsert) {
          throw StateError(
            'Bootstrap contains an invalid or cross-home record.',
          );
        }
      }

      final localIntent =
          (await (_database.select(_database.clientOperations)
                    ..where((row) => row.homeId.equals(homeId))
                    ..orderBy(<OrderingTerm Function(ClientOperations)>[
                      (row) => OrderingTerm.asc(row.clientTimestamp),
                      (row) => OrderingTerm.asc(row.operationId),
                    ]))
                  .get())
              .where(
                (operation) =>
                    operation.state !=
                    ClientOperationState.acknowledged.storageValue,
              );

      await (_database.delete(
        _database.localRecords,
      )..where((row) => row.homeId.equals(homeId))).go();
      await (_database.delete(
        _database.recordTombstones,
      )..where((row) => row.homeId.equals(homeId))).go();
      await (_database.delete(
        _database.localSyncCursors,
      )..where((row) => row.homeId.equals(homeId))).go();

      for (final change in page.changes) {
        await _database
            .into(_database.localRecords)
            .insert(
              LocalRecordsCompanion.insert(
                homeId: homeId,
                entityType: change.entityType,
                entityId: change.entityId,
                payload: jsonEncode(change.payload),
                revision: Value<int>(change.revision),
                updatedAt: change.serverTimestamp.toUtc(),
                synchronizedAt: Value<DateTime>(change.serverTimestamp.toUtc()),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }

      // A server snapshot replaces synchronized cache state, never durable
      // local intent. Reapply every unacknowledged operation over the snapshot
      // before committing its captured cursor.
      for (final operation in localIntent) {
        if (operation.operationType == 'delete') {
          await (_database.delete(_database.localRecords)..where(
                (row) =>
                    row.homeId.equals(homeId) &
                    row.entityType.equals(operation.entityType) &
                    row.entityId.equals(operation.entityId),
              ))
              .go();
          await _database
              .into(_database.recordTombstones)
              .insertOnConflictUpdate(
                RecordTombstonesCompanion.insert(
                  homeId: homeId,
                  entityType: operation.entityType,
                  entityId: operation.entityId,
                  revision: operation.baseRevision ?? 0,
                  cursor: page.pageCursor,
                  deletedAt: operation.clientTimestamp.toUtc(),
                ),
              );
        } else {
          await _database
              .into(_database.localRecords)
              .insertOnConflictUpdate(
                LocalRecordsCompanion.insert(
                  homeId: homeId,
                  entityType: operation.entityType,
                  entityId: operation.entityId,
                  payload: operation.payload,
                  revision: Value<int>(operation.baseRevision ?? 0),
                  updatedAt: operation.clientTimestamp.toUtc(),
                  synchronizedAt: const Value<DateTime?>(null),
                ),
              );
          await (_database.delete(_database.recordTombstones)..where(
                (row) =>
                    row.homeId.equals(homeId) &
                    row.entityType.equals(operation.entityType) &
                    row.entityId.equals(operation.entityId),
              ))
              .go();
        }
      }

      await _database
          .into(_database.localSyncCursors)
          .insert(
            LocalSyncCursorsCompanion.insert(
              homeId: homeId,
              feed: const Value<String>('home_changes'),
              protocolVersion: const Value<int>(1),
              schemaGeneration: const Value<int>(2),
              cursor: page.pageCursor,
              updatedAt: _clock().toUtc(),
            ),
          );
    });
  }

  @override
  Future<void> requeueRetryableOperations({
    required String homeId,
    required DateTime now,
  }) async {
    await (_database.update(_database.clientOperations)..where(
          (row) =>
              row.homeId.equals(homeId) &
              row.state.equals(ClientOperationState.retryWait.storageValue) &
              (row.nextAttemptAt.isNull() |
                  row.nextAttemptAt.isSmallerOrEqualValue(now.toUtc())),
        ))
        .write(
          ClientOperationsCompanion(
            state: Value<String>(ClientOperationState.pending.storageValue),
            nextAttemptAt: const Value<DateTime?>(null),
          ),
        );
  }

  @override
  Future<void> requeueOperation({
    required String homeId,
    required String operationId,
    required DateTime now,
  }) async {
    await (_database.update(_database.clientOperations)..where(
          (row) =>
              row.homeId.equals(homeId) &
              row.operationId.equals(operationId) &
              row.state.equals(ClientOperationState.retryWait.storageValue),
        ))
        .write(
          ClientOperationsCompanion(
            state: Value<String>(ClientOperationState.pending.storageValue),
            nextAttemptAt: Value<DateTime>(now.toUtc()),
            lastSafeError: const Value<String?>(null),
          ),
        );
  }

  ClientOperationState _stateFor(PushResultKind kind) {
    return switch (kind) {
      PushResultKind.acknowledged => ClientOperationState.acknowledged,
      PushResultKind.conflict => ClientOperationState.blockedConflict,
      PushResultKind.validationError => ClientOperationState.blockedValidation,
      PushResultKind.authorizationFailure =>
        ClientOperationState.blockedAuthorization,
      PushResultKind.retryableFailure => ClientOperationState.retryWait,
    };
  }

  Map<String, Object?> _decodePayload(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Operation payload must be a JSON object.');
    }
    return decoded;
  }
}
