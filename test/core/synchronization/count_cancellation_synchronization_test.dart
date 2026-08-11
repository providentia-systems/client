import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart'
    as generated;

const String _homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const String _sessionId = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';
const String _deviceAId = '0198a0b1-c2d3-7e4f-a345-6789abcdef01';
const String _deviceBId = '0198a0b1-c2d3-7e4f-b456-789abcdef012';
const String _createOperationId = '0198a0b1-c2d3-7e4f-8567-89abcdef0123';
const String _cancelOperationId = '0198a0b1-c2d3-7e4f-9678-9abcdef01234';

void main() {
  test(
    'count cancellation uses the closed revision-bound v2 wire command',
    () async {
      late Map<String, Object?> requestBody;
      final client = generated.ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'protocolVersion': 2,
              'batchId': requestBody['batchId'],
              'requestId': 'cancel-request',
              'serverTime': '2026-08-11T08:00:00Z',
              'results': <Object?>[
                <String, Object?>{
                  'operationId': _cancelOperationId,
                  'status': 'accepted',
                  'revision': 8,
                  'changeCursor': 'cursor-8',
                },
              ],
              'highWaterCursor': 'cursor-8',
            }),
            200,
          );
        }),
      );

      final response = await GeneratedSyncGateway(client).push(
        homeId: _homeId,
        lastPulledCursor: 'cursor-7',
        operations: <PendingClientOperation>[
          PendingClientOperation(
            operationId: _cancelOperationId,
            deviceId: _deviceAId,
            homeId: _homeId,
            entityType: 'inventory-count-session',
            entityId: _sessionId,
            operationType: 'inventory.count-session.cancel',
            baseRevision: 7,
            clientTimestamp: DateTime.utc(2026, 8, 11, 8),
            payloadSchemaVersion: 1,
            payload: const <String, Object?>{},
            retryCount: 0,
          ),
        ],
      );

      final command =
          (requestBody['operations'] as List<Object?>).single
              as Map<String, Object?>;
      expect(requestBody['protocolVersion'], 2);
      expect(command['commandType'], 'inventory.count-session.cancel');
      expect(command['entityId'], _sessionId);
      expect(command['baseRevision'], 7);
      expect(command['payload'], isEmpty);
      expect(command, isNot(contains('entityType')));
      expect(response.results.single.kind, PushResultKind.acknowledged);
      expect(response.results.single.acceptedRevision, 8);
    },
  );

  test(
    'lost cancellation response reconciles once without movements',
    () async {
      var now = DateTime.utc(2026, 8, 11, 8);
      final server = _CountSyncServer(serverClock: () => now);
      final deviceA = _CountDevice.create(
        deviceId: _deviceAId,
        server: server,
        operationIds: <String>[_createOperationId, _cancelOperationId],
        clock: () => now,
      );
      final deviceB = _CountDevice.create(
        deviceId: _deviceBId,
        server: server,
        operationIds: const <String>[],
        clock: () => now,
      );
      addTearDown(() async {
        await deviceA.close();
        await deviceB.close();
      });

      await deviceA.household.saveCountSession(
        StockCountSession(
          id: _sessionId,
          homeId: _homeId,
          locationId: 'primary',
          startedAt: now,
        ),
      );
      expect((await deviceA.synchronize()).status, SyncRunStatus.completed);
      expect((await deviceB.synchronize()).status, SyncRunStatus.completed);
      expect((await deviceB.activeSession())?.status, CountSessionStatus.open);

      // The cancellation commits locally while the device is offline. It
      // removes the active session immediately but must not apply inventory.
      final open = await deviceA.activeSession();
      await deviceA.household.saveCountSession(open!.cancel());
      expect(await deviceA.activeSession(), isNull);
      expect(await deviceB.activeSession(), isNotNull);
      await _expectNoInventoryApplication(deviceA.database);

      server.loseNextCancellationResponse = true;
      final reconciled = await deviceA.synchronize();
      expect(reconciled.status, SyncRunStatus.completed);
      var cancelOperation = await deviceA.operation(_cancelOperationId);
      expect(
        cancelOperation.state,
        ClientOperationState.acknowledged.storageValue,
      );
      expect(server.cancellationApplications, 1);
      expect(server.movementApplications, 0);
      await _expectNoInventoryApplication(deviceA.database);

      now = now.add(const Duration(minutes: 5));
      final repeated = await deviceA.synchronize();
      expect(repeated.status, SyncRunStatus.completed);
      cancelOperation = await deviceA.operation(_cancelOperationId);
      expect(
        cancelOperation.state,
        ClientOperationState.acknowledged.storageValue,
      );
      expect(
        server.pushedOperationIds.where(
          (operationId) => operationId == _cancelOperationId,
        ),
        hasLength(1),
      );
      expect(server.cancellationApplications, 1);

      expect((await deviceB.synchronize()).status, SyncRunStatus.completed);
      expect(await deviceA.activeSession(), isNull);
      expect(await deviceB.activeSession(), isNull);
      expect(server.sessionStatus, 'cancelled');
      expect(server.movementApplications, 0);
      await _expectNoInventoryApplication(deviceA.database);
      await _expectNoInventoryApplication(deviceB.database);
    },
  );
}

Future<void> _expectNoInventoryApplication(AppDatabase database) async {
  final records = await database.select(database.localRecords).get();
  expect(
    records.where(
      (record) =>
          record.entityType == 'inventory-balance' ||
          record.entityType == 'inventory-movement' ||
          record.entityType == 'phase5.stock-movement',
    ),
    isEmpty,
  );
}

final class _CountDevice {
  _CountDevice._({
    required this.database,
    required this.household,
    required this.coordinator,
  });

  factory _CountDevice.create({
    required String deviceId,
    required _CountSyncServer server,
    required List<String> operationIds,
    required DateTime Function() clock,
  }) {
    final database = AppDatabase(NativeDatabase.memory());
    var operationIndex = 0;
    final household = DriftHouseholdRepository(
      database,
      deviceId: deviceId,
      clock: clock,
      idGenerator: () => operationIds[operationIndex++],
    );
    final coordinator = SyncCoordinator(
      local: DriftLocalSyncRepository(database, clock: clock),
      remote: server,
      connectivity: const _OnlineProbe(),
      retryPolicy: RetryPolicy(baseDelay: const Duration(seconds: 1)),
      clock: clock,
    );
    return _CountDevice._(
      database: database,
      household: household,
      coordinator: coordinator,
    );
  }

  final AppDatabase database;
  final DriftHouseholdRepository household;
  final SyncCoordinator coordinator;

  Future<SyncRunOutcome> synchronize() => coordinator.synchronize(_homeId);

  Future<StockCountSession?> activeSession() =>
      household.watchActiveCountSession(homeId: _homeId).first;

  Future<ClientOperation> operation(String operationId) => (database.select(
    database.clientOperations,
  )..where((row) => row.operationId.equals(operationId))).getSingle();

  Future<void> close() => database.close();
}

final class _OnlineProbe implements ConnectivityProbe {
  const _OnlineProbe();

  @override
  Future<ConnectivityResult> check() async => const ConnectivityResult.online();
}

final class _CountSyncServer implements SyncRemoteGateway {
  _CountSyncServer({required DateTime Function() serverClock})
    : _clock = serverClock;

  final DateTime Function() _clock;
  final List<RemoteChange> _changes = <RemoteChange>[];
  final Map<String, PushOperationResult> _operationResults =
      <String, PushOperationResult>{};
  final List<String> pushedOperationIds = <String>[];
  Map<String, Object?>? _session;
  int _revision = 0;
  int _sequence = 0;
  int cancellationApplications = 0;
  int movementApplications = 0;
  bool loseNextCancellationResponse = false;

  String? get sessionStatus => _session?['status'] as String?;

  @override
  Future<OperationStatusResponse> operationStatuses({
    required String homeId,
    required String deviceId,
    required List<String> operationIds,
  }) async => OperationStatusResponse(
    operations: operationIds
        .map(
          (operationId) => OperationStatusItem(
            operationId: operationId,
            result: _operationResults[operationId],
          ),
        )
        .toList(growable: false),
  );

  @override
  Future<PullPage> bootstrap({required String homeId}) async {
    final session = _session;
    return PullPage(
      protocolVersion: 1,
      fromCursor: _cursor,
      changes: session == null
          ? const <RemoteChange>[]
          : <RemoteChange>[
              RemoteChange(
                cursor: _cursor,
                homeId: homeId,
                entityType: 'inventory-count-session',
                entityId: _sessionId,
                kind: RemoteChangeKind.upsert,
                revision: _revision,
                serverTimestamp: _clock().toUtc(),
                payload: session,
              ),
            ],
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
    final operation = operations.single;
    pushedOperationIds.add(operation.operationId);
    final previous = _operationResults[operation.operationId];
    if (previous != null) {
      return PushResponse(results: <PushOperationResult>[previous]);
    }

    if (operation.homeId != homeId ||
        operation.entityType != 'inventory-count-session' ||
        operation.entityId != _sessionId) {
      throw const FormatException('Unexpected count synchronization scope.');
    }
    final nextSession = switch (operation.operationType) {
      'inventory.count-session.create' => _openSession(operation),
      'inventory.count-session.cancel' => _cancelSession(operation),
      _ => throw FormatException(
        'Unexpected count command ${operation.operationType}.',
      ),
    };
    _revision++;
    _sequence++;
    _session = nextSession;
    final change = RemoteChange(
      cursor: _cursor,
      homeId: homeId,
      entityType: 'inventory-count-session',
      entityId: _sessionId,
      kind: RemoteChangeKind.upsert,
      revision: _revision,
      serverTimestamp: _clock().toUtc(),
      payload: nextSession,
    );
    _changes.add(change);
    final result = PushOperationResult(
      operationId: operation.operationId,
      kind: PushResultKind.acknowledged,
      acceptedRevision: _revision,
      changeCursor: _cursor,
      remotePayload: nextSession,
    );
    _operationResults[operation.operationId] = result;

    if (operation.operationType == 'inventory.count-session.cancel' &&
        loseNextCancellationResponse) {
      loseNextCancellationResponse = false;
      throw const RetryableSyncException('Response was lost after commit.');
    }
    return PushResponse(results: <PushOperationResult>[result]);
  }

  Map<String, Object?> _openSession(PendingClientOperation operation) {
    if (_session != null || operation.baseRevision != null) {
      throw const FormatException('Count creation revision is invalid.');
    }
    return <String, Object?>{
      ...operation.payload,
      'status': 'open',
      '_clientStartedAt': operation.clientTimestamp.toUtc().toIso8601String(),
      '_clientClosedAt': null,
    };
  }

  Map<String, Object?> _cancelSession(PendingClientOperation operation) {
    if (_session?['status'] != 'open' ||
        operation.baseRevision != _revision ||
        operation.payload.isNotEmpty) {
      throw const FormatException('Count cancellation revision is invalid.');
    }
    cancellationApplications++;
    return <String, Object?>{..._session!, 'status': 'cancelled'};
  }

  String get _cursor => 'cursor-$_sequence';

  int _parseCursor(String? cursor) {
    if (cursor == null) return 0;
    return int.parse(cursor.substring('cursor-'.length));
  }
}
