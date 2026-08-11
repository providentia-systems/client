import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/client_local_record_types.dart';
import 'package:providentia/core/security/uuid_v4.dart';
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

  static const Map<String, String> _protocolTwoProjectionByCommand =
      <String, String>{
        'inventory.location.create': 'inventory-location',
        'inventory.home-product.create': 'inventory-home-product',
        'inventory.adjustment.create': 'inventory-balance',
        'inventory.count-session.create': 'inventory-count-session',
        'inventory.count-line.upsert': 'inventory-count-line',
        'inventory.count-session.close': 'inventory-count-session',
        'inventory.count-session.cancel': 'inventory-count-session',
        'purchasing.store.create': 'purchasing-store',
        'purchasing.receipt.create': 'purchasing-receipt',
        'purchasing.receipt-line.create': 'purchasing-receipt-line',
        'purchasing.receipt-line.approve': 'purchasing-receipt-line',
        'purchasing.receipt-line.unresolve': 'purchasing-receipt-line',
        'purchasing.receipt.commit': 'purchasing-receipt',
        'shopping.list.create': 'shopping-list',
        'shopping.list-line.create': 'shopping-list-line',
        'shopping.list-line.checked': 'shopping-list-line',
      };

  static const Set<String> _localOnlyRecordTypes =
      ClientLocalRecordTypes.synchronizationProtected;

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
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    final query = _database.select(_database.clientOperations)
      ..where((row) => row.homeId.equals(homeId))
      ..orderBy(<OrderingTerm Function(ClientOperations)>[
        (row) => OrderingTerm.asc(row.clientTimestamp),
        (row) => OrderingTerm.asc(row.operationId),
      ]);

    final rows = await query.get();
    final executable = <PendingClientOperation>[];
    final cutoff = now.toUtc();
    for (final row in rows) {
      final state = ClientOperationState.fromStorage(row.state);
      if (state == ClientOperationState.acknowledged ||
          state == ClientOperationState.superseded) {
        continue;
      }
      final isDueRetry =
          state == ClientOperationState.retryWait &&
          (row.nextAttemptAt == null || !row.nextAttemptAt!.isAfter(cutoff));
      if (state != ClientOperationState.pending && !isDueRetry) {
        // Every later operation may depend on this unresolved predecessor.
        // A blocked, in-flight, or not-yet-due operation is therefore a
        // conservative home-queue barrier, not a row to skip around.
        break;
      }
      executable.add(
        PendingClientOperation(
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
      );
      if (executable.length == limit) {
        break;
      }
    }
    return List<PendingClientOperation>.unmodifiable(executable);
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
  Future<List<String>> recoverInterruptedOperations({
    required String homeId,
    required DateTime now,
  }) {
    return _database.transaction(() async {
      final interrupted =
          await (_database.select(_database.clientOperations)..where(
                (row) =>
                    row.homeId.equals(homeId) &
                    row.state.equals(ClientOperationState.syncing.storageValue),
              ))
              .get();
      if (interrupted.isEmpty) {
        return const <String>[];
      }
      final operationIds = interrupted
          .map((operation) => operation.operationId)
          .toList(growable: false);
      await (_database.update(_database.clientOperations)..where(
            (row) =>
                row.homeId.equals(homeId) &
                row.operationId.isIn(operationIds) &
                row.state.equals(ClientOperationState.syncing.storageValue),
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
      return List<String>.unmodifiable(operationIds);
    });
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
                    row.entityId.equals(operation.entityId) &
                    row.revision.isSmallerOrEqualValue(
                      result.acceptedRevision!,
                    ),
              ))
              .write(
                LocalRecordsCompanion(
                  // A parent projection can already include later dependent
                  // commands (for example receipt line creation/approval).
                  // Never let an earlier acknowledgement roll that revision
                  // back or falsely mark the later optimistic state synced.
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
        if (_localOnlyRecordTypes.contains(change.entityType)) {
          throw StateError(
            'Server change targeted a reserved local-only record type.',
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
        if (change.revision < newestRevision) {
          // Out-of-order replay is idempotent. In particular, an older upsert
          // can never resurrect a newer tombstone.
          continue;
        }
        if (change.revision == newestRevision) {
          if (change.kind == RemoteChangeKind.upsert &&
              existingRecord != null &&
              existingRecord.revision == change.revision &&
              existingRecord.synchronizedAt == null &&
              existingTombstone == null) {
            // Protocol-v2 command acknowledgements do not necessarily carry a
            // resource revision. Once the same-entity intent is acknowledged,
            // the equal authoritative feed event is what confirms and
            // reconciles the optimistic projection.
            await (_database.update(_database.localRecords)..where(
                  (row) =>
                      row.homeId.equals(homeId) &
                      row.entityType.equals(change.entityType) &
                      row.entityId.equals(change.entityId) &
                      row.revision.equals(change.revision),
                ))
                .write(
                  LocalRecordsCompanion(
                    payload: Value<String>(jsonEncode(change.payload)),
                    updatedAt: Value<DateTime>(change.serverTimestamp.toUtc()),
                    synchronizedAt: Value<DateTime>(
                      change.serverTimestamp.toUtc(),
                    ),
                  ),
                );
          }
          // Equal tombstones and cross-kind replays remain idempotent. They
          // cannot delete or resurrect an already materialized equal revision.
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
        if (change.homeId != homeId ||
            change.kind != RemoteChangeKind.upsert ||
            _localOnlyRecordTypes.contains(change.entityType)) {
          throw StateError(
            'Bootstrap contains an invalid or cross-home record.',
          );
        }
      }

      // Separately verified client caches and suggestion/list identity links
      // are not server-feed projections. Bootstrap replacement must retain
      // them until their own scoped refresh or purge replaces them.
      final localOnlyRecords =
          await (_database.select(_database.localRecords)..where(
                (row) =>
                    row.homeId.equals(homeId) &
                    row.entityType.isIn(_localOnlyRecordTypes),
              ))
              .get();

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
                        ClientOperationState.acknowledged.storageValue &&
                    operation.state !=
                        ClientOperationState.superseded.storageValue,
              )
              .toList(growable: false);
      final protocolTwoIntent = localIntent
          .where(
            (operation) => _protocolTwoProjectionByCommand.containsKey(
              operation.operationType,
            ),
          )
          .toList(growable: false);
      final intentKeys = protocolTwoIntent
          .map(
            (operation) => '${operation.entityType}\u0000${operation.entityId}',
          )
          .toSet();
      for (final operation in protocolTwoIntent) {
        final payload = _decodePayload(operation.payload);
        final auxiliary = switch (operation.operationType) {
          'inventory.count-line.upsert' => (
            entityType: 'inventory-count-session',
            entityId: payload['sessionId'],
          ),
          'purchasing.receipt-line.create' ||
          'purchasing.receipt-line.approve' ||
          'purchasing.receipt-line.unresolve' => (
            entityType: 'purchasing-receipt',
            entityId: payload['receiptId'],
          ),
          'shopping.list-line.create' => (
            entityType: 'shopping-list',
            entityId: payload['listId'],
          ),
          _ => null,
        };
        if (auxiliary != null && auxiliary.entityId is String) {
          intentKeys.add(
            '${auxiliary.entityType}\u0000${auxiliary.entityId as String}',
          );
        }
        if (operation.operationType == 'inventory.count-session.close') {
          final countLines =
              await (_database.select(_database.localRecords)..where(
                    (row) =>
                        row.homeId.equals(homeId) &
                        row.entityType.equals('inventory-count-line'),
                  ))
                  .get();
          for (final line in countLines) {
            final linePayload = _decodePayload(line.payload);
            final homeProductId = linePayload['homeProductId'];
            if (linePayload['sessionId'] == operation.entityId &&
                homeProductId is String) {
              intentKeys.add('inventory-balance\u0000$homeProductId');
            }
          }
        }
      }
      final optimisticRecords =
          (await (_database.select(_database.localRecords)..where(
                    (row) =>
                        row.homeId.equals(homeId) & row.synchronizedAt.isNull(),
                  ))
                  .get())
              .where(
                (record) => intentKeys.contains(
                  '${record.entityType}\u0000${record.entityId}',
                ),
              )
              .toList(growable: false);

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

      for (final record in localOnlyRecords) {
        await _database
            .into(_database.localRecords)
            .insert(
              LocalRecordsCompanion.insert(
                homeId: record.homeId,
                entityType: record.entityType,
                entityId: record.entityId,
                payload: record.payload,
                revision: Value<int>(record.revision),
                isTombstone: Value<bool>(record.isTombstone),
                updatedAt: record.updatedAt,
                synchronizedAt: Value<DateTime?>(record.synchronizedAt),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }

      // A server snapshot replaces synchronized cache state, never durable
      // local intent. Protocol-v2 operations carry command payloads rather
      // than materialized resource representations, so replay the exact
      // unsynchronized projection rows captured before replacement.
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
        } else if (!_protocolTwoProjectionByCommand.containsKey(
          operation.operationType,
        )) {
          // Legacy protocol-v1 operations still use their projection as the
          // operation payload and therefore remain directly replayable.
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

      for (final record in optimisticRecords) {
        await _database
            .into(_database.localRecords)
            .insertOnConflictUpdate(
              LocalRecordsCompanion.insert(
                homeId: homeId,
                entityType: record.entityType,
                entityId: record.entityId,
                payload: record.payload,
                revision: Value<int>(record.revision),
                isTombstone: Value<bool>(record.isTombstone),
                updatedAt: record.updatedAt,
                synchronizedAt: const Value<DateTime?>(null),
              ),
            );
        await (_database.delete(_database.recordTombstones)..where(
              (row) =>
                  row.homeId.equals(homeId) &
                  row.entityType.equals(record.entityType) &
                  row.entityId.equals(record.entityId),
            ))
            .go();
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

  @override
  Stream<List<SyncConflict>> watchUnresolvedConflicts({
    required String homeId,
  }) {
    final query = _database.select(_database.syncConflictRecords)
      ..where((row) => row.homeId.equals(homeId) & row.resolvedAt.isNull())
      ..orderBy(<OrderingTerm Function(SyncConflictRecords)>[
        (row) => OrderingTerm.asc(row.detectedAt),
        (row) => OrderingTerm.asc(row.conflictId),
      ]);
    return query.watch().asyncMap(
      (rows) => _mapConflicts(homeId: homeId, rows: rows),
    );
  }

  @override
  Future<List<SyncConflict>> unresolvedConflicts({
    required String homeId,
  }) async {
    final query = _database.select(_database.syncConflictRecords)
      ..where((row) => row.homeId.equals(homeId) & row.resolvedAt.isNull())
      ..orderBy(<OrderingTerm Function(SyncConflictRecords)>[
        (row) => OrderingTerm.asc(row.detectedAt),
        (row) => OrderingTerm.asc(row.conflictId),
      ]);
    return _mapConflicts(homeId: homeId, rows: await query.get());
  }

  @override
  Future<void> acceptRemoteConflict({
    required String homeId,
    required String conflictId,
    required DateTime resolvedAt,
  }) {
    return _database.transaction(() async {
      final context = await _resolutionContext(
        homeId: homeId,
        conflictId: conflictId,
      );
      _rejectGenericCountResolution(context);
      final revision = _requiredRemoteRevision(context.conflict);
      final remote = _decodeRemoteEvidence(context.conflict);
      if (remote.kind == SyncConflictRemoteKind.unavailable) {
        throw const SyncConflictResolutionException(
          'The server version is not available yet. Synchronize before choosing it.',
        );
      }
      final at = resolvedAt.toUtc();
      await _applyAuthoritativeConflictEvidence(
        homeId: homeId,
        conflictId: conflictId,
        context: context,
        remote: remote,
        revision: revision,
        at: at,
      );

      await _supersedeOperation(context.operation.operationId);
      await _resolveConflict(
        conflictId: conflictId,
        resolution: SyncConflictResolutionChoice.acceptRemote,
        resolvedAt: at,
      );
    });
  }

  @override
  Future<void> reconcileCountConflict({
    required String homeId,
    required String conflictId,
    required DateTime resolvedAt,
  }) {
    return _database.transaction(() async {
      final context = await _resolutionContext(
        homeId: homeId,
        conflictId: conflictId,
      );
      if (!_isCountConflict(context)) {
        throw const SyncConflictResolutionException(
          'Only count conflicts can use the count reconciliation workflow.',
        );
      }
      final revision = _requiredRemoteRevision(context.conflict);
      final remote = _decodeRemoteEvidence(context.conflict);
      if (remote.kind == SyncConflictRemoteKind.unavailable) {
        throw const SyncConflictResolutionException(
          'The server count is not available yet. Synchronize before reconciling it.',
        );
      }
      final at = resolvedAt.toUtc();
      await _applyAuthoritativeConflictEvidence(
        homeId: homeId,
        conflictId: conflictId,
        context: context,
        remote: remote,
        revision: revision,
        at: at,
      );

      // Count movements remain server-owned. This resolution only accepts the
      // authoritative count projection and supersedes the stale command; a
      // fresh count is an explicit, separately synchronized operation.
      await _supersedeOperation(context.operation.operationId);
      await _resolveConflict(
        conflictId: conflictId,
        resolution: SyncConflictResolutionChoice.reconcileCount,
        resolvedAt: at,
      );
    });
  }

  @override
  Future<void> reapplyLocalConflict({
    required String homeId,
    required String conflictId,
    required String newOperationId,
    required DateTime resolvedAt,
  }) {
    return _database.transaction(() async {
      if (!isUuid(newOperationId)) {
        throw ArgumentError.value(
          newOperationId,
          'newOperationId',
          'must be a UUID',
        );
      }
      final context = await _resolutionContext(
        homeId: homeId,
        conflictId: conflictId,
      );
      if (newOperationId == context.operation.operationId) {
        throw const SyncConflictResolutionException(
          'Reapplying requires a fresh operation identifier.',
        );
      }
      _rejectGenericCountResolution(context);
      final revision = _requiredRemoteRevision(context.conflict);
      final payload = _decodePayload(context.operation.payload);
      _validateReapplicationIntent(context.operation);
      final at = resolvedAt.toUtc();

      // Preserve the original logical position so dependent operations remain
      // behind the fresh replacement in the durable home queue.
      await _supersedeOperation(context.operation.operationId);
      await _database
          .into(_database.clientOperations)
          .insert(
            ClientOperationsCompanion.insert(
              operationId: newOperationId,
              deviceId: context.operation.deviceId,
              homeId: homeId,
              entityType: context.operation.entityType,
              entityId: context.operation.entityId,
              operationType: context.operation.operationType,
              baseRevision: Value<int>(revision),
              clientTimestamp: context.operation.clientTimestamp,
              payloadSchemaVersion: Value<int>(
                context.operation.payloadSchemaVersion,
              ),
              payload: jsonEncode(payload),
              state: ClientOperationState.pending.storageValue,
            ),
            mode: InsertMode.insertOrAbort,
          );

      if (context.operation.operationType == 'delete') {
        await (_database.delete(_database.localRecords)..where(
              (row) =>
                  row.homeId.equals(homeId) &
                  row.entityType.equals(context.operation.entityType) &
                  row.entityId.equals(context.operation.entityId),
            ))
            .go();
        await _database
            .into(_database.recordTombstones)
            .insertOnConflictUpdate(
              RecordTombstonesCompanion.insert(
                homeId: homeId,
                entityType: context.operation.entityType,
                entityId: context.operation.entityId,
                revision: revision + 1,
                cursor: 'conflict-reapply:$conflictId',
                deletedAt: at,
              ),
            );
      } else {
        final currentRecord =
            await (_database.select(_database.localRecords)..where(
                  (row) =>
                      row.homeId.equals(homeId) &
                      row.entityType.equals(context.operation.entityType) &
                      row.entityId.equals(context.operation.entityId),
                ))
                .getSingleOrNull();
        if (currentRecord == null &&
            _protocolTwoProjectionByCommand.containsKey(
              context.operation.operationType,
            )) {
          throw const SyncConflictResolutionException(
            'The local projection is unavailable. Review the item again before reapplying.',
          );
        }
        await _database
            .into(_database.localRecords)
            .insertOnConflictUpdate(
              LocalRecordsCompanion.insert(
                homeId: homeId,
                entityType: context.operation.entityType,
                entityId: context.operation.entityId,
                payload: currentRecord?.payload ?? jsonEncode(payload),
                revision: Value<int>(revision + 1),
                updatedAt: at,
                synchronizedAt: const Value<DateTime?>(null),
              ),
            );
        await (_database.delete(_database.recordTombstones)..where(
              (row) =>
                  row.homeId.equals(homeId) &
                  row.entityType.equals(context.operation.entityType) &
                  row.entityId.equals(context.operation.entityId),
            ))
            .go();
      }

      await _resolveConflict(
        conflictId: conflictId,
        resolution: SyncConflictResolutionChoice.reapplyLocal,
        resolvedAt: at,
      );
    });
  }

  Future<List<SyncConflict>> _mapConflicts({
    required String homeId,
    required List<SyncConflictRecord> rows,
  }) async {
    final conflicts = <SyncConflict>[];
    for (final row in rows) {
      final operation =
          await (_database.select(_database.clientOperations)..where(
                (candidate) =>
                    candidate.operationId.equals(row.operationId) &
                    candidate.homeId.equals(homeId),
              ))
              .getSingleOrNull();
      if (operation == null) continue;
      final record =
          await (_database.select(_database.localRecords)..where(
                (candidate) =>
                    candidate.homeId.equals(homeId) &
                    candidate.entityType.equals(row.entityType) &
                    candidate.entityId.equals(row.entityId),
              ))
              .getSingleOrNull();
      final tombstone =
          await (_database.select(_database.recordTombstones)..where(
                (candidate) =>
                    candidate.homeId.equals(homeId) &
                    candidate.entityType.equals(row.entityType) &
                    candidate.entityId.equals(row.entityId),
              ))
              .getSingleOrNull();
      final remote = _decodeRemoteEvidence(row);
      conflicts.add(
        SyncConflict(
          id: row.conflictId,
          homeId: row.homeId,
          entityType: row.entityType,
          entityId: row.entityId,
          kind: row.conflictKind,
          detectedAt: row.detectedAt,
          local: SyncConflictLocalEvidence(
            operationId: operation.operationId,
            operationType: operation.operationType,
            commandPayload: _decodePayload(row.localPayload),
            representation: record == null
                ? null
                : _decodePayload(record.payload),
            isDeletion:
                operation.operationType == 'delete' || tombstone != null,
          ),
          remote: SyncConflictRemoteEvidence(
            kind: remote.kind,
            revision: row.remoteRevision,
            representation: remote.representation,
            deletedAt: remote.deletedAt,
          ),
        ),
      );
    }
    return List<SyncConflict>.unmodifiable(conflicts);
  }

  Future<({SyncConflictRecord conflict, ClientOperation operation})>
  _resolutionContext({
    required String homeId,
    required String conflictId,
  }) async {
    final conflict =
        await (_database.select(_database.syncConflictRecords)..where(
              (row) =>
                  row.conflictId.equals(conflictId) &
                  row.homeId.equals(homeId) &
                  row.resolvedAt.isNull(),
            ))
            .getSingleOrNull();
    if (conflict == null) {
      throw const SyncConflictResolutionException(
        'This conflict is not available in the current home.',
      );
    }
    final operation =
        await (_database.select(_database.clientOperations)..where(
              (row) =>
                  row.operationId.equals(conflict.operationId) &
                  row.homeId.equals(homeId) &
                  row.entityType.equals(conflict.entityType) &
                  row.entityId.equals(conflict.entityId),
            ))
            .getSingleOrNull();
    if (operation == null ||
        operation.state != ClientOperationState.blockedConflict.storageValue) {
      throw const SyncConflictResolutionException(
        'The blocked local change is no longer available for review.',
      );
    }
    return (conflict: conflict, operation: operation);
  }

  void _rejectGenericCountResolution(
    ({SyncConflictRecord conflict, ClientOperation operation}) context,
  ) {
    if (_isCountConflict(context)) {
      throw const SyncConflictResolutionException(
        'Count conflicts require the dedicated count reconciliation workflow.',
      );
    }
  }

  bool _isCountConflict(
    ({SyncConflictRecord conflict, ClientOperation operation}) context,
  ) =>
      context.conflict.entityType == 'inventory-count-session' ||
      context.conflict.entityType == 'inventory-count-line' ||
      context.operation.operationType.startsWith('inventory.count-');

  Future<void> _applyAuthoritativeConflictEvidence({
    required String homeId,
    required String conflictId,
    required ({SyncConflictRecord conflict, ClientOperation operation}) context,
    required ({
      SyncConflictRemoteKind kind,
      Map<String, Object?>? representation,
      Map<String, Object?> metadata,
      DateTime? deletedAt,
    })
    remote,
    required int revision,
    required DateTime at,
  }) async {
    if (remote.kind == SyncConflictRemoteKind.tombstone) {
      await (_database.delete(_database.localRecords)..where(
            (row) =>
                row.homeId.equals(homeId) &
                row.entityType.equals(context.conflict.entityType) &
                row.entityId.equals(context.conflict.entityId),
          ))
          .go();
      await _database
          .into(_database.recordTombstones)
          .insertOnConflictUpdate(
            RecordTombstonesCompanion.insert(
              homeId: homeId,
              entityType: context.conflict.entityType,
              entityId: context.conflict.entityId,
              revision: revision,
              cursor:
                  _optionalString(remote.metadata, 'cursor') ??
                  context.operation.serverCursor ??
                  'conflict:$conflictId',
              deletedAt: remote.deletedAt ?? at,
            ),
          );
      return;
    }
    final representation = remote.representation;
    if (representation == null) {
      throw const SyncConflictResolutionException(
        'The server version is incomplete. Synchronize before choosing it.',
      );
    }
    await _database
        .into(_database.localRecords)
        .insertOnConflictUpdate(
          LocalRecordsCompanion.insert(
            homeId: homeId,
            entityType: context.conflict.entityType,
            entityId: context.conflict.entityId,
            payload: jsonEncode(representation),
            revision: Value<int>(revision),
            updatedAt: at,
            synchronizedAt: Value<DateTime>(at),
          ),
        );
    await (_database.delete(_database.recordTombstones)..where(
          (row) =>
              row.homeId.equals(homeId) &
              row.entityType.equals(context.conflict.entityType) &
              row.entityId.equals(context.conflict.entityId),
        ))
        .go();
  }

  int _requiredRemoteRevision(SyncConflictRecord conflict) {
    final revision = conflict.remoteRevision;
    if (revision == null || revision < 0) {
      throw const SyncConflictResolutionException(
        'The authoritative revision is unavailable. Synchronize before resolving this conflict.',
      );
    }
    return revision;
  }

  void _validateReapplicationIntent(ClientOperation operation) {
    if (operation.operationType.trim().isEmpty ||
        operation.payloadSchemaVersion < 1) {
      throw const SyncConflictResolutionException(
        'The local intent is invalid and cannot be reapplied.',
      );
    }
    final expectedProjection =
        _protocolTwoProjectionByCommand[operation.operationType];
    if (expectedProjection != null &&
        (operation.entityType != expectedProjection ||
            operation.payloadSchemaVersion != 1)) {
      throw const SyncConflictResolutionException(
        'The local intent does not match the published synchronization command.',
      );
    }
    _decodePayload(operation.payload);
  }

  Future<void> _supersedeOperation(String operationId) async {
    await (_database.update(
      _database.clientOperations,
    )..where((row) => row.operationId.equals(operationId))).write(
      ClientOperationsCompanion(
        state: Value<String>(ClientOperationState.superseded.storageValue),
        nextAttemptAt: const Value<DateTime?>(null),
        lastSafeError: const Value<String?>(null),
        acknowledgedAt: const Value<DateTime?>(null),
      ),
    );
  }

  Future<void> _resolveConflict({
    required String conflictId,
    required SyncConflictResolutionChoice resolution,
    required DateTime resolvedAt,
  }) async {
    await (_database.update(
      _database.syncConflictRecords,
    )..where((row) => row.conflictId.equals(conflictId))).write(
      SyncConflictRecordsCompanion(
        resolvedAt: Value<DateTime>(resolvedAt),
        resolution: Value<String>(resolution.storageValue),
      ),
    );
  }

  ({
    SyncConflictRemoteKind kind,
    Map<String, Object?>? representation,
    Map<String, Object?> metadata,
    DateTime? deletedAt,
  })
  _decodeRemoteEvidence(SyncConflictRecord conflict) {
    final source = conflict.remotePayload;
    if (source == null) {
      return (
        kind: SyncConflictRemoteKind.unavailable,
        representation: null,
        metadata: const <String, Object?>{},
        deletedAt: null,
      );
    }
    final payload = _decodePayload(source);
    if (payload['tombstone'] == true) {
      final deletedAtSource = payload['deletedAt'];
      return (
        kind: SyncConflictRemoteKind.tombstone,
        representation: null,
        metadata: payload,
        deletedAt: deletedAtSource is String
            ? DateTime.tryParse(deletedAtSource)?.toUtc()
            : null,
      );
    }
    return (
      kind: SyncConflictRemoteKind.upsert,
      representation: payload,
      metadata: payload,
      deletedAt: null,
    );
  }

  String? _optionalString(Map<String, Object?> payload, String key) {
    final value = payload[key];
    return value is String && value.trim().isNotEmpty ? value : null;
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
