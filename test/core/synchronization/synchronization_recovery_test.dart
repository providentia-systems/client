import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/generated_sync_recovery_gateway.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/core/synchronization/synchronization_recovery.dart';
import 'package:providentia/features/homes/infrastructure/home_data_revocation.dart';
import 'package:providentia_api_client/providentia_api_client.dart'
    as generated;

void main() {
  test(
    'protected recovery preserves pending identities, order and blocker across restart',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'providentia-recovery-test-',
      );
      final file = File('${temporary.path}/synthetic.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      var local = DriftLocalSyncRepository(database);
      await local.commitLocalMutation(_mutation('operation-1'));
      await local.commitLocalMutation(_mutation('operation-2'));
      await local.applyPushResults(
        results: [
          PushOperationResult(
            operationId: 'operation-1',
            kind: PushResultKind.authorizationFailure,
            code: 'device_binding_mismatch',
          ),
        ],
        now: DateTime.utc(2026),
        retryPolicy: RetryPolicy(),
      );
      final before = await database.select(database.clientOperations).get();
      await local.replaceWithRecoveryBootstrap(
        homeId: 'home-1',
        page: _snapshot(),
      );
      expect(await database.select(database.clientOperations).get(), before);
      await database.close();
      database = AppDatabase(NativeDatabase(file));
      local = DriftLocalSyncRepository(database);
      final preserved = await local.recoveryOperations(homeId: 'home-1');
      expect(preserved.map((item) => item.operation.operationId), [
        'operation-1',
        'operation-2',
      ]);
      expect(preserved.first.blockedCode, 'device_binding_mismatch');
      expect(preserved.first.state, ClientOperationState.blockedAuthorization);
      expect(preserved.first.operation.originatingAccountId, 'account-1');
      expect(preserved.first.operation.deviceId, 'device-1');
      expect(preserved.first.operation.payload, {'name': 'Synthetic product'});
      expect((await local.watchSummary(homeId: 'home-1').first).unresolved, 2);
      await database.close();
      await temporary.delete(recursive: true);
    },
  );

  test(
    'cross-account or device recovery preserves inaccessible queue without rebuilding',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final local = DriftLocalSyncRepository(database);
      await local.commitLocalMutation(_mutation('operation-1'));
      final before = await database.select(database.localRecords).get();
      await expectLater(
        local.requireOriginalRecoveryBinding(
          homeId: 'home-1',
          accountId: 'other-account',
          deviceId: 'device-1',
        ),
        throwsA(isA<BindingSyncException>()),
      );
      await expectLater(
        local.requireOriginalRecoveryBinding(
          homeId: 'home-1',
          accountId: 'account-1',
          deviceId: 'other-device',
        ),
        throwsA(isA<BindingSyncException>()),
      );
      expect(await database.select(database.localRecords).get(), before);
      expect(
        (await local.recoveryOperations(
          homeId: 'home-1',
        )).single.operation.operationId,
        'operation-1',
      );
      await database.close();
    },
  );

  test(
    'malformed bootstrap rolls back without losing saved work or cursor',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final local = DriftLocalSyncRepository(database);
      await local.commitLocalMutation(_mutation('operation-1'));
      final before = await database.select(database.localRecords).get();
      await expectLater(
        local.replaceWithRecoveryBootstrap(
          homeId: 'home-1',
          page: _snapshot(homeId: 'other-home'),
        ),
        throwsStateError,
      );
      expect(await database.select(database.localRecords).get(), before);
      expect(
        (await local.recoveryOperations(
          homeId: 'home-1',
        )).single.operation.operationId,
        'operation-1',
      );
      expect(await local.cursorForHome('home-1'), isNull);
      await database.close();
    },
  );

  test(
    'revalidation requeues only original eligible predecessor and never executes',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final local = DriftLocalSyncRepository(database);
      await local.commitLocalMutation(_mutation('operation-1'));
      await local.commitLocalMutation(_mutation('operation-2'));
      await local.applyPushResults(
        results: [
          PushOperationResult(
            operationId: 'operation-1',
            kind: PushResultKind.authorizationFailure,
            code: 'device_binding_mismatch',
          ),
        ],
        now: DateTime.utc(2026),
        retryPolicy: RetryPolicy(),
      );
      final before = (await local.recoveryOperations(
        homeId: 'home-1',
      )).first.operation;
      final remote = _SyncGateway();
      final recovery = _RecoveryGateway();
      final coordinator = SyncCoordinator(
        local: local,
        remote: remote,
        recoveryGateway: recovery,
        connectivity: const _Online(),
      );
      final result = await coordinator.revalidateSavedOperations('home-1');
      expect(result.recovered, 1);
      expect(result.needsReview, 1);
      expect(remote.pushes, 0);
      final after = (await local.recoveryOperations(homeId: 'home-1')).first;
      expect(after.state, ClientOperationState.pending);
      expect(after.operation.operationId, before.operationId);
      expect(after.operation.payload, before.payload);
      expect(after.operation.deviceId, before.deviceId);
      expect(after.operation.enqueueSequence, before.enqueueSequence);
      expect(after.operation.retryCount, before.retryCount + 1);
      await database.close();
    },
  );

  test(
    'verified revocation waits for admitted recovery and blocks all subsequent recovery',
    () async {
      final gate = HomeSyncRevocationGate();
      final completed = Completer<void>();
      final running = gate.runRecovery('home-1', () => completed.future);
      var quiesced = false;
      final revoked = gate.revokeAndWait('home-1').then((_) => quiesced = true);
      await Future<void>.delayed(Duration.zero);
      expect(quiesced, isFalse);
      await expectLater(
        gate.runRecovery('home-1', () async {}),
        throwsA(isA<AuthenticationSyncException>()),
      );
      completed.complete();
      await running;
      await revoked;
      expect(quiesced, isTrue);
    },
  );

  test(
    'production recovery adapter preserves exact command and fails closed on foreign binding',
    () async {
      final requests = <http.Request>[];
      var foreign = false;
      final api = generated.ProvidentiaApiClient(
        baseUri: Uri.parse('https://synthetic.example'),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'protocolVersion': 2,
              'accountId': foreign ? 'other-account' : 'account-1',
              'deviceId': 'device-1',
              'homeId': 'home-1',
              if (request.url.path.endsWith('/diagnostics'))
                'deployment': {
                  'contractHash': 'synthetic-hash',
                  'buildRevision': 'synthetic-build',
                  'migrationStatus': 'current',
                  'contractMatchesLock': true,
                },
              if (request.url.path.endsWith('/revalidate'))
                'operations': [
                  {
                    'operationId': 'operation-1',
                    'action': 'retry_same_operation',
                    'code': 'unknown_under_original_binding',
                  },
                ],
            }),
            200,
          );
        }),
      );
      final gateway = GeneratedSyncRecoveryGateway(
        client: api,
        accountId: 'account-1',
        deviceId: 'device-1',
        homeId: 'home-1',
        isCurrent: () => true,
      );
      expect(
        (await gateway.diagnostics(homeId: 'home-1')).contractHash,
        'synthetic-hash',
      );
      final operation = SyncRecoveryOperation(
        operation: _pending(),
        state: ClientOperationState.blockedAuthorization,
        blockedCode: 'device_binding_mismatch',
      );
      final decisions = await gateway.revalidate(
        homeId: 'home-1',
        operations: [operation],
      );
      expect(decisions.single.action, SyncRecoveryAction.retrySameOperation);
      final encoded = jsonDecode(requests.last.body) as Map<String, Object?>;
      final saved =
          (encoded['operations']! as List<Object?>).single
              as Map<String, Object?>;
      expect(
        (saved['command']! as Map<String, Object?>)['payload'],
        operation.operation.payload,
      );
      expect(
        (saved['command']! as Map<String, Object?>)['operationId'],
        'operation-1',
      );
      foreign = true;
      await expectLater(
        gateway.diagnostics(homeId: 'home-1'),
        throwsA(isA<BindingSyncException>()),
      );
    },
  );
}

LocalMutation _mutation(String id) => LocalMutation(
  operationId: id,
  deviceId: 'device-1',
  originatingAccountId: 'account-1',
  homeId: 'home-1',
  entityType: 'inventory-home-product',
  entityId: id,
  operationType: 'inventory.home-product.create',
  clientTimestamp: DateTime.utc(2026),
  payloadSchemaVersion: 1,
  payload: {'name': 'Synthetic product'},
);
PendingClientOperation _pending() => PendingClientOperation(
  operationId: 'operation-1',
  deviceId: 'device-1',
  originatingAccountId: 'account-1',
  homeId: 'home-1',
  entityType: 'inventory-home-product',
  entityId: 'product-1',
  operationType: 'inventory.home-product.create',
  clientTimestamp: DateTime.utc(2026),
  payloadSchemaVersion: 1,
  payload: {'name': 'Synthetic product'},
  retryCount: 0,
);
PullPage _snapshot({String homeId = 'home-1'}) => PullPage(
  requestId: 'synthetic-request',
  protocolVersion: 1,
  fromCursor: null,
  changes: [
    RemoteChange(
      cursor: 'snapshot-1',
      homeId: homeId,
      entityType: 'inventory-home-product',
      entityId: 'server-product',
      kind: RemoteChangeKind.upsert,
      revision: 1,
      serverTimestamp: DateTime.utc(2026),
      payload: {'id': 'server-product', 'name': 'Server product'},
    ),
  ],
  pageCursor: 'snapshot-1',
  highWaterCursor: 'snapshot-1',
  hasMore: false,
);

final class _Online implements ConnectivityProbe {
  const _Online();
  @override
  Future<ConnectivityResult> check() async => const ConnectivityResult.online();
}

final class _RecoveryGateway implements SyncRecoveryGateway {
  @override
  Future<SyncRecoveryDiagnostics> diagnostics({required String homeId}) async =>
      SyncRecoveryDiagnostics(
        accountId: 'account-1',
        deviceId: 'device-1',
        homeId: homeId,
        contractHash: 'synthetic',
        buildRevision: 'synthetic',
        migrationStatus: 'current',
        contractMatchesLock: true,
      );
  @override
  Future<List<SyncRecoveryDecision>> revalidate({
    required String homeId,
    required List<SyncRecoveryOperation> operations,
  }) async => [
    for (var index = 0; index < operations.length; index++)
      SyncRecoveryDecision(
        operationId: operations[index].operation.operationId,
        action: index == 0
            ? SyncRecoveryAction.retrySameOperation
            : SyncRecoveryAction.awaitPredecessor,
      ),
  ];
}

final class _SyncGateway implements SyncRemoteGateway {
  int pushes = 0;
  @override
  Future<PullPage> bootstrap({required String homeId}) async =>
      _snapshot(homeId: homeId);
  @override
  Future<OperationStatusResponse> operationStatuses({
    required String homeId,
    required String deviceId,
    required List<String> operationIds,
  }) async => OperationStatusResponse(operations: []);
  @override
  Future<PullPage> pull({required String homeId, String? afterCursor}) async =>
      _snapshot(homeId: homeId);
  @override
  Future<PushResponse> push({
    required String homeId,
    required String? lastPulledCursor,
    required List<PendingClientOperation> operations,
  }) async {
    pushes++;
    return const PushResponse(results: []);
  }
}
