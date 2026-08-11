import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/app/app_controller.dart';
import 'package:providentia/app/production_bootstrap_app.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/client_local_record_types.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/homes/infrastructure/home_data_revocation.dart';
import 'package:providentia/features/shopping/application/online_shopping_suggestion_repository.dart';
import 'package:providentia/features/shopping/application/shopping_interaction_capabilities.dart';
import 'package:providentia/features/shopping/application/shopping_repository.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';
import 'package:providentia/features/shopping/infrastructure/drift_shopping_suggestion_cache.dart';
import 'package:providentia/features/shopping/infrastructure/generated_online_shopping_suggestion_repository.dart';
import 'package:providentia/features/shopping/presentation/shopping_controller.dart';
import 'package:providentia_api_client/providentia_api_client.dart'
    as generated;

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

  test(
    'real HTTP 404 quiesces production sync, purges caches, and routes away',
    () async {
      const homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 11, 14);
      await _seedEveryTable(database, homeId, now);
      await _seedProtectedLocalOnlyRecords(database, homeId, now);

      var transportRequests = 0;
      final client = generated.ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((_) async {
          transportRequests++;
          return http.Response(
            jsonEncode(<String, Object?>{
              'type': 'about:blank',
              'title': 'Not Found',
              'status': 404,
              'detail': 'The requested resource was not found.',
              'requestId': 'request-revoked-home',
            }),
            404,
            headers: const <String, String>{
              'content-type': 'application/problem+json',
            },
          );
        }),
      );
      addTearDown(client.close);
      final syncGate = HomeSyncRevocationGate();
      final guarded = RevocationGuardedSynchronization(
        delegate: SyncCoordinator(
          local: DriftLocalSyncRepository(database, clock: () => now),
          remote: GeneratedSyncGateway(client),
          connectivity: const _OnlineProbe(),
          clock: () => now,
        ),
        gate: syncGate,
        homeId: homeId,
      );
      final app = AppController(
        synchronization: guarded,
        activeHomeId: homeId,
        clock: () => now,
      );
      addTearDown(app.dispose);
      final resumeGate = ProductionResumeSyncGate(refresh: app.refresh)
        ..markReady();
      addTearDown(resumeGate.dispose);
      var routedAway = false;
      List<int>? countsWhenRouted;
      final boundary = ProductionHomeRevocationBoundary(
        purge: (revokedHomeId) async {
          await syncGate.revokeAndWait(revokedHomeId);
          await RevokedHomeDataPurger(database).purge(revokedHomeId);
          return true;
        },
      );
      Future<bool>? revocation;
      app.addListener(() {
        if (revocation != null ||
            app.syncSummary.availability !=
                SyncAvailability.authorizationDenied) {
          return;
        }
        revocation = boundary.revokePurgeAndRoute(
          homeId: homeId,
          resumeSyncGate: resumeGate,
          routeAway: () async {
            countsWhenRouted = await _homeRowCounts(database, homeId);
            routedAway = true;
          },
        );
      });

      await app.start();
      expect(await revocation, isTrue);

      expect(
        app.syncSummary.availability,
        SyncAvailability.authorizationDenied,
      );
      expect(routedAway, isTrue);
      expect(countsWhenRouted, <int>[0, 0, 0, 0, 0, 0]);
      expect(await _homeRowCounts(database, homeId), <int>[0, 0, 0, 0, 0, 0]);
      final protectedRows =
          await (database.select(database.localRecords)
                ..where((row) => row.homeId.equals(homeId))
                ..where(
                  (row) => row.entityType.isIn(
                    ClientLocalRecordTypes.synchronizationProtected.toList(),
                  ),
                ))
              .get();
      expect(protectedRows, isEmpty);

      expect(transportRequests, 1);
      resumeGate.resume();
      await resumeGate.settle();
      expect(transportRequests, 1);
      expect(
        (await guarded.synchronize(homeId)).status,
        SyncRunStatus.authorizationFailure,
      );
      expect(transportRequests, 1);
    },
  );

  for (final statusCode in <int>[403, 404]) {
    test(
      'shopping HTTP $statusCode revokes once, quiesces sync, and purges the home',
      () async {
        const homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final now = DateTime.utc(2026, 8, 11, 16);
        await _seedEveryTable(database, homeId, now);
        await _seedProtectedLocalOnlyRecords(database, homeId, now);

        var transportRequests = 0;
        final client = generated.ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient((_) async {
            transportRequests++;
            return http.Response(
              jsonEncode(<String, Object?>{
                'type': 'about:blank',
                'title': statusCode == 403 ? 'Forbidden' : 'Not Found',
                'status': statusCode,
                'detail': 'The requested resource is unavailable.',
                'requestId': 'request-shopping-revoked',
              }),
              statusCode,
              headers: const <String, String>{
                'content-type': 'application/problem+json',
              },
            );
          }),
        );
        addTearDown(client.close);
        final syncGate = HomeSyncRevocationGate();
        final guarded = RevocationGuardedSynchronization(
          delegate: SyncCoordinator(
            local: DriftLocalSyncRepository(database, clock: () => now),
            remote: GeneratedSyncGateway(client),
            connectivity: const _OnlineProbe(),
            clock: () => now,
          ),
          gate: syncGate,
          homeId: homeId,
        );
        var resumeRefreshes = 0;
        final resumeGate = ProductionResumeSyncGate(
          refresh: () async {
            resumeRefreshes++;
            await guarded.synchronize(homeId);
          },
        )..markReady();
        addTearDown(resumeGate.dispose);
        var routeAwayCalls = 0;
        final boundary = ProductionHomeRevocationBoundary(
          purge: (revokedHomeId) async {
            await syncGate.revokeAndWait(revokedHomeId);
            await RevokedHomeDataPurger(database).purge(revokedHomeId);
            return true;
          },
        );
        final revoked = Completer<void>();
        var denialCallbacks = 0;
        final controller = ShoppingController(
          repository: _ReadOnlyShoppingRepository(
            ShoppingList(
              id: 'list',
              homeId: homeId,
              name: 'Current',
              createdAt: now,
            ),
          ),
          homeId: homeId,
          suggestionRepository: CachedOnlineShoppingSuggestionRepository(
            remote: GeneratedOnlineShoppingSuggestionRepository(client),
            cache: DriftShoppingSuggestionCache(database),
          ),
          capabilities:
              ShoppingInteractionCapabilities.onlineEvidenceSuggestions,
          onAuthorizationDenied: () async {
            denialCallbacks++;
            await boundary.revokePurgeAndRoute(
              homeId: homeId,
              resumeSyncGate: resumeGate,
              routeAway: () async {
                routeAwayCalls++;
              },
            );
            if (!revoked.isCompleted) revoked.complete();
          },
        );
        addTearDown(controller.dispose);

        controller.start();
        await revoked.future;
        await controller.refreshSuggestions();

        expect(controller.state.suggestionsAccessDenied, isTrue);
        expect(denialCallbacks, 1);
        expect(routeAwayCalls, 1);
        expect(await _homeRowCounts(database, homeId), <int>[0, 0, 0, 0, 0, 0]);
        expect(
          await (database.select(
            database.localRecords,
          )..where((row) => row.homeId.equals(homeId))).get(),
          isEmpty,
        );
        expect(
          (await guarded.synchronize(homeId)).status,
          SyncRunStatus.authorizationFailure,
        );
        resumeGate.resume();
        await resumeGate.settle();
        expect(resumeRefreshes, 0);
        expect(transportRequests, 1);
      },
    );
  }
}

Future<void> _seedProtectedLocalOnlyRecords(
  AppDatabase database,
  String homeId,
  DateTime now,
) async {
  var index = 0;
  for (final entityType in ClientLocalRecordTypes.synchronizationProtected) {
    await database
        .into(database.localRecords)
        .insert(
          LocalRecordsCompanion.insert(
            homeId: homeId,
            entityType: entityType,
            entityId: 'protected-${index++}',
            payload: jsonEncode(<String, Object?>{'private': true}),
            updatedAt: now,
          ),
        );
  }
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
  Future<OperationStatusResponse> operationStatuses({
    required String homeId,
    required String deviceId,
    required List<String> operationIds,
  }) async => OperationStatusResponse(
    operations: operationIds
        .map((operationId) => OperationStatusItem(operationId: operationId))
        .toList(growable: false),
  );

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

final class _ReadOnlyShoppingRepository implements ShoppingRepository {
  const _ReadOnlyShoppingRepository(this.list);

  final ShoppingList list;

  @override
  Stream<ShoppingList> watchActiveList({required String homeId}) =>
      Stream<ShoppingList>.value(list);

  @override
  Future<void> saveList(ShoppingList list) =>
      throw UnsupportedError('read-only');

  @override
  Future<void> recordFeedback(SuggestionFeedback feedback) =>
      throw UnsupportedError('read-only');
}
