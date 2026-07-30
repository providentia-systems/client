import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

const String _homeId = 'home-1';
final DateTime _now = DateTime.utc(2026, 7, 30, 12);

void main() {
  test('two devices converge after editing different entities', () async {
    final server = _InMemorySyncServer();
    final deviceA = _Device.create('device-a', server);
    final deviceB = _Device.create('device-b', server);
    addTearDown(() async {
      await deviceA.close();
      await deviceB.close();
    });

    await deviceA.synchronize();
    await deviceB.synchronize();
    await deviceA.mutate(
      operationId: 'operation-a-1',
      entityId: 'record-a',
      quantity: 2,
    );
    await deviceB.mutate(
      operationId: 'operation-b-1',
      entityId: 'record-b',
      quantity: 4,
    );

    expect((await deviceA.synchronize()).completed, isTrue);
    expect((await deviceB.synchronize()).completed, isTrue);
    expect((await deviceA.synchronize()).completed, isTrue);

    expect(await deviceA.quantities(), <String, int>{
      'record-a': 2,
      'record-b': 4,
    });
    expect(await deviceB.quantities(), <String, int>{
      'record-a': 2,
      'record-b': 4,
    });
  });

  test('same-entity edits preserve both sides of a conflict', () async {
    final server = _InMemorySyncServer();
    final deviceA = _Device.create('device-a', server);
    final deviceB = _Device.create('device-b', server);
    addTearDown(() async {
      await deviceA.close();
      await deviceB.close();
    });

    await deviceA.synchronize();
    await deviceB.synchronize();
    await deviceA.mutate(
      operationId: 'operation-seed',
      entityId: 'shared-record',
      quantity: 1,
    );
    await deviceA.synchronize();
    await deviceB.synchronize();

    await deviceA.mutate(
      operationId: 'operation-a-2',
      entityId: 'shared-record',
      quantity: 2,
      baseRevision: 1,
    );
    await deviceB.mutate(
      operationId: 'operation-b-2',
      entityId: 'shared-record',
      quantity: 3,
      baseRevision: 1,
    );

    await deviceA.synchronize();
    final deviceBOutcome = await deviceB.synchronize();

    final localRecord = await deviceB.database
        .select(deviceB.database.localRecords)
        .getSingle();
    final operation = await (deviceB.database.select(
      deviceB.database.clientOperations,
    )..where((row) => row.operationId.equals('operation-b-2'))).getSingle();
    final conflict = await deviceB.database
        .select(deviceB.database.syncConflictRecords)
        .getSingle();

    expect(deviceBOutcome.completed, isTrue);
    expect(jsonDecode(localRecord.payload), <String, Object?>{'quantity': 3});
    expect(operation.state, ClientOperationState.blockedConflict.storageValue);
    expect(jsonDecode(conflict.localPayload), <String, Object?>{'quantity': 3});
    expect(jsonDecode(conflict.remotePayload!), <String, Object?>{
      'quantity': 2,
    });
    expect(conflict.remoteRevision, 2);
  });
}

final class _Device {
  _Device._(this.id, this.database, this.repository, this.coordinator);

  factory _Device.create(String id, _InMemorySyncServer server) {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = DriftLocalSyncRepository(database, clock: () => _now);
    final coordinator = SyncCoordinator(
      local: repository,
      remote: server,
      connectivity: const _OnlineProbe(),
      clock: () => _now,
    );
    return _Device._(id, database, repository, coordinator);
  }

  final String id;
  final AppDatabase database;
  final DriftLocalSyncRepository repository;
  final SyncCoordinator coordinator;

  Future<void> mutate({
    required String operationId,
    required String entityId,
    required int quantity,
    int? baseRevision,
  }) {
    return repository.commitLocalMutation(
      LocalMutation(
        operationId: operationId,
        deviceId: id,
        homeId: _homeId,
        entityType: 'inventory_balance',
        entityId: entityId,
        operationType: 'put',
        baseRevision: baseRevision,
        clientTimestamp: _now,
        payloadSchemaVersion: 1,
        payload: <String, Object?>{'quantity': quantity},
      ),
    );
  }

  Future<SyncRunOutcome> synchronize() => coordinator.synchronize(_homeId);

  Future<Map<String, int>> quantities() async {
    final rows = await database.select(database.localRecords).get();
    return <String, int>{
      for (final row in rows)
        row.entityId:
            (jsonDecode(row.payload) as Map<String, Object?>)['quantity']!
                as int,
    };
  }

  Future<void> close() => database.close();
}

final class _OnlineProbe implements ConnectivityProbe {
  const _OnlineProbe();

  @override
  Future<ConnectivityResult> check() async {
    return const ConnectivityResult.online();
  }
}

final class _InMemorySyncServer implements SyncRemoteGateway {
  final Map<String, _ServerRecord> _records = <String, _ServerRecord>{};
  final List<RemoteChange> _changes = <RemoteChange>[];
  final Map<String, PushOperationResult> _operationResults =
      <String, PushOperationResult>{};
  int _sequence = 0;

  @override
  Future<PullPage> bootstrap({required String homeId}) async {
    return PullPage(
      protocolVersion: 1,
      fromCursor: _cursor,
      changes: _records.values
          .map(
            (record) => RemoteChange(
              cursor: _cursor,
              homeId: homeId,
              entityType: record.entityType,
              entityId: record.entityId,
              kind: RemoteChangeKind.upsert,
              revision: record.revision,
              serverTimestamp: _now,
              payload: record.payload,
            ),
          )
          .toList(growable: false),
      pageCursor: _cursor,
      highWaterCursor: _cursor,
      hasMore: false,
      requestId: 'bootstrap-$_sequence',
    );
  }

  @override
  Future<PullPage> pull({required String homeId, String? afterCursor}) async {
    final fromSequence = _parseCursor(afterCursor);
    final changes = _changes
        .where((change) => _parseCursor(change.cursor) > fromSequence)
        .toList(growable: false);
    return PullPage(
      protocolVersion: 1,
      fromCursor: afterCursor,
      changes: changes,
      pageCursor: changes.isEmpty
          ? afterCursor ?? _cursor
          : changes.last.cursor,
      highWaterCursor: _cursor,
      hasMore: false,
      requestId: 'pull-$_sequence',
    );
  }

  @override
  Future<PushResponse> push({
    required String homeId,
    required String? lastPulledCursor,
    required List<PendingClientOperation> operations,
  }) async {
    final results = <PushOperationResult>[];
    for (final operation in operations) {
      final previous = _operationResults[operation.operationId];
      if (previous != null) {
        results.add(previous);
        continue;
      }

      final key = '${operation.entityType}\u0000${operation.entityId}';
      final current = _records[key];
      final revisionMatches = current == null
          ? operation.baseRevision == null
          : operation.baseRevision == current.revision;
      late final PushOperationResult result;
      if (!revisionMatches) {
        result = PushOperationResult(
          operationId: operation.operationId,
          kind: PushResultKind.conflict,
          acceptedRevision: current?.revision,
          changeCursor: _cursor,
          safeMessage: 'The server record changed on another device.',
          remotePayload: current?.payload,
        );
      } else {
        final revision = (current?.revision ?? 0) + 1;
        _sequence++;
        final record = _ServerRecord(
          entityType: operation.entityType,
          entityId: operation.entityId,
          revision: revision,
          payload: operation.payload,
        );
        _records[key] = record;
        _changes.add(
          RemoteChange(
            cursor: _cursor,
            homeId: homeId,
            entityType: operation.entityType,
            entityId: operation.entityId,
            kind: RemoteChangeKind.upsert,
            revision: revision,
            serverTimestamp: _now,
            payload: operation.payload,
          ),
        );
        result = PushOperationResult(
          operationId: operation.operationId,
          kind: PushResultKind.acknowledged,
          acceptedRevision: revision,
          changeCursor: _cursor,
          remotePayload: operation.payload,
        );
      }
      _operationResults[operation.operationId] = result;
      results.add(result);
    }
    return PushResponse(results: results);
  }

  String get _cursor => 'cursor-$_sequence';

  int _parseCursor(String? cursor) {
    if (cursor == null) {
      return 0;
    }
    return int.parse(cursor.substring('cursor-'.length));
  }
}

final class _ServerRecord {
  _ServerRecord({
    required this.entityType,
    required this.entityId,
    required this.revision,
    required Map<String, Object?> payload,
  }) : payload = Map<String, Object?>.unmodifiable(payload);

  final String entityType;
  final String entityId;
  final int revision;
  final Map<String, Object?> payload;
}
