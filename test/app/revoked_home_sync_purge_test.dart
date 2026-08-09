import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/homes/infrastructure/home_data_revocation.dart';

void main() {
  test(
    'late pull quiesces before purge and cannot restore any revoked-home row',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 9, 12);
      await _seedEveryTable(database, 'revoked-home', now);
      await _seedEveryTable(database, 'other-home', now);

      final remote = _GatedPullGateway();
      final coordinator = SyncCoordinator(
        local: DriftLocalSyncRepository(database, clock: () => now),
        remote: remote,
        connectivity: const _OnlineProbe(),
        clock: () => now,
      );
      final gate = HomeSyncRevocationGate();
      final guarded = RevocationGuardedSynchronization(
        delegate: coordinator,
        gate: gate,
        homeId: 'revoked-home',
      );

      final synchronization = guarded.synchronize('revoked-home');
      await remote.pullStarted.future;
      var purgeCompleted = false;
      final purge = gate
          .revokeAndWait('revoked-home')
          .then((_) => RevokedHomeDataPurger(database).purge('revoked-home'))
          .whenComplete(() => purgeCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(purgeCompleted, isFalse);

      remote.pullResponse.complete(
        PullPage(
          protocolVersion: 1,
          fromCursor: 'cursor-revoked-home',
          changes: <RemoteChange>[
            RemoteChange(
              cursor: 'cursor-late',
              homeId: 'revoked-home',
              entityType: 'inventory-item',
              entityId: 'late-record',
              kind: RemoteChangeKind.upsert,
              revision: 2,
              serverTimestamp: now,
              payload: const <String, Object?>{'name': 'must be purged'},
            ),
          ],
          pageCursor: 'cursor-late',
          highWaterCursor: 'cursor-late',
          hasMore: false,
          requestId: 'late-response',
        ),
      );

      expect((await synchronization).status, SyncRunStatus.completed);
      await purge;
      expect(await _homeRowCounts(database, 'revoked-home'), <int>[
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(await _homeRowCounts(database, 'other-home'), <int>[
        1,
        1,
        1,
        1,
        1,
        1,
      ]);

      final blocked = await guarded.synchronize('revoked-home');
      expect(blocked.status, SyncRunStatus.authorizationFailure);
    },
  );
}

Future<void> _seedEveryTable(
  AppDatabase database,
  String homeId,
  DateTime now,
) async {
  await database
      .into(database.localRecords)
      .insert(
        LocalRecordsCompanion.insert(
          homeId: homeId,
          entityType: 'seed',
          entityId: 'record-$homeId',
          payload: '{}',
          updatedAt: now,
        ),
      );
  await database
      .into(database.clientOperations)
      .insert(
        ClientOperationsCompanion.insert(
          operationId: 'operation-$homeId',
          deviceId: 'device-1',
          homeId: homeId,
          entityType: 'seed',
          entityId: 'record-$homeId',
          operationType: 'upsert',
          clientTimestamp: now,
          payload: '{}',
          state: ClientOperationState.acknowledged.storageValue,
        ),
      );
  await database
      .into(database.localSyncCursors)
      .insert(
        LocalSyncCursorsCompanion.insert(
          homeId: homeId,
          cursor: 'cursor-$homeId',
          updatedAt: now,
        ),
      );
  await database
      .into(database.recordTombstones)
      .insert(
        RecordTombstonesCompanion.insert(
          homeId: homeId,
          entityType: 'deleted-seed',
          entityId: 'tombstone-$homeId',
          revision: 1,
          cursor: 'cursor-$homeId',
          deletedAt: now,
        ),
      );
  await database
      .into(database.localMediaMetadata)
      .insert(
        LocalMediaMetadataCompanion.insert(
          mediaId: 'media-$homeId',
          homeId: homeId,
          purpose: 'receipt',
          localReference: 'local-$homeId',
          createdAt: now,
        ),
      );
  await database
      .into(database.syncConflictRecords)
      .insert(
        SyncConflictRecordsCompanion.insert(
          conflictId: 'conflict-$homeId',
          operationId: 'operation-$homeId',
          homeId: homeId,
          entityType: 'seed',
          entityId: 'record-$homeId',
          conflictKind: 'seed',
          localPayload: '{}',
          detectedAt: now,
        ),
      );
}

Future<List<int>> _homeRowCounts(AppDatabase database, String homeId) async {
  return <int>[
    (await (database.select(
      database.localRecords,
    )..where((row) => row.homeId.equals(homeId))).get()).length,
    (await (database.select(
      database.clientOperations,
    )..where((row) => row.homeId.equals(homeId))).get()).length,
    (await (database.select(
      database.localSyncCursors,
    )..where((row) => row.homeId.equals(homeId))).get()).length,
    (await (database.select(
      database.recordTombstones,
    )..where((row) => row.homeId.equals(homeId))).get()).length,
    (await (database.select(
      database.localMediaMetadata,
    )..where((row) => row.homeId.equals(homeId))).get()).length,
    (await (database.select(
      database.syncConflictRecords,
    )..where((row) => row.homeId.equals(homeId))).get()).length,
  ];
}

final class _GatedPullGateway implements SyncRemoteGateway {
  final Completer<void> pullStarted = Completer<void>();
  final Completer<PullPage> pullResponse = Completer<PullPage>();

  @override
  Future<PullPage> bootstrap({required String homeId}) {
    throw StateError('A seeded cursor must skip bootstrap.');
  }

  @override
  Future<PullPage> pull({required String homeId, String? afterCursor}) {
    pullStarted.complete();
    return pullResponse.future;
  }

  @override
  Future<PushResponse> push({
    required String homeId,
    required String? lastPulledCursor,
    required List<PendingClientOperation> operations,
  }) async => const PushResponse(results: <PushOperationResult>[]);
}

final class _OnlineProbe implements ConnectivityProbe {
  const _OnlineProbe();

  @override
  Future<ConnectivityResult> check() async => const ConnectivityResult.online();
}
