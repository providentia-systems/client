import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';

const String _homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const String _deviceAId = '0198a0b1-c2d3-7e4f-a345-6789abcdef01';
const String _deviceBId = '0198a0b1-c2d3-7e4f-b456-789abcdef012';
const String _productId = '0198a0b1-c2d3-7e4f-8567-89abcdef0123';
const String _packId = '0198a0b1-c2d3-7e4f-9678-9abcdef01234';
const String _homeProductId = '0198a0b1-c2d3-7e4f-a678-9abcdef01234';
const String _operationId = '0198a0b1-c2d3-7e4f-b789-abcdef012345';

void main() {
  test(
    'lost catalog-add response reconciles one operation and converges',
    () async {
      var now = DateTime.utc(2026, 8, 11, 8);
      final server = _ItemMasterSyncServer(serverClock: () => now);
      final deviceA = _Device.create(
        deviceId: _deviceAId,
        operationIds: <String>[_homeProductId, _operationId],
        server: server,
        clock: () => now,
      );
      final deviceB = _Device.create(
        deviceId: _deviceBId,
        operationIds: const <String>[],
        server: server,
        clock: () => now,
      );
      addTearDown(() async {
        await deviceA.close();
        await deviceB.close();
      });
      final cachedPack = InventoryItem(
        id: _packId,
        homeId: _homeId,
        productId: _productId,
        packId: _packId,
        canonicalName: 'Long-grain rice',
        packSize: '2 kg bag',
        category: 'Grains',
        brand: 'Harvest Foods',
        aliases: const <String>['Rice long grain'],
      );
      await deviceA.household.replaceCatalogItemMaster(
        homeId: _homeId,
        items: <InventoryItem>[cachedPack],
      );
      await deviceB.household.replaceCatalogItemMaster(
        homeId: _homeId,
        items: <InventoryItem>[cachedPack],
      );

      // The selection is usable offline immediately and queues one immutable
      // UUID-backed protocol-v2 command.
      await deviceA.household.createCatalogHomeProduct(
        CatalogHomeProductDraft.fromItem(cachedPack),
      );
      final local = await deviceA.items();
      expect(local, hasLength(1));
      expect(local.single.id, _homeProductId);
      expect(local.single.canonicalName, 'Long-grain rice');
      final queued = await deviceA.operation(_operationId);
      expect(queued.operationType, 'inventory.home-product.create');
      expect(jsonDecode(queued.payload), <String, Object?>{
        'productId': _productId,
        'packId': _packId,
        'privateName': null,
        'originalPackText': null,
      });

      server.loseNextResponse = true;
      expect((await deviceA.synchronize()).status, SyncRunStatus.completed);
      expect(server.applications, 1);
      expect(
        (await deviceA.operation(_operationId)).state,
        ClientOperationState.acknowledged.storageValue,
      );

      now = now.add(const Duration(minutes: 5));
      expect((await deviceA.synchronize()).completed, isTrue);
      expect((await deviceB.synchronize()).completed, isTrue);

      expect(server.applications, 1);
      expect(
        server.pushedOperationIds.where((id) => id == _operationId),
        hasLength(1),
      );
      for (final device in <_Device>[deviceA, deviceB]) {
        final items = await device.items();
        expect(items, hasLength(1));
        expect(items.single.id, _homeProductId);
        expect(items.single.productId, _productId);
        expect(items.single.packId, _packId);
        expect(items.single.canonicalName, 'Long-grain rice');
        expect(items.single.aliases, <String>['Rice long grain']);
        expect(items.single.isHomeProduct, isTrue);
      }
    },
  );
}

final class _Device {
  _Device._(this.database, this.household, this.coordinator);

  factory _Device.create({
    required String deviceId,
    required List<String> operationIds,
    required _ItemMasterSyncServer server,
    required DateTime Function() clock,
  }) {
    final database = AppDatabase(NativeDatabase.memory());
    var operationIndex = 0;
    final household = DriftHouseholdRepository(
      database,
      deviceId: deviceId,
      idGenerator: () => operationIds[operationIndex++],
      clock: clock,
    );
    final coordinator = SyncCoordinator(
      local: DriftLocalSyncRepository(database, clock: clock),
      remote: server,
      connectivity: const _OnlineProbe(),
      retryPolicy: RetryPolicy(baseDelay: const Duration(seconds: 1)),
      clock: clock,
    );
    return _Device._(database, household, coordinator);
  }

  final AppDatabase database;
  final DriftHouseholdRepository household;
  final SyncCoordinator coordinator;

  Future<SyncRunOutcome> synchronize() => coordinator.synchronize(_homeId);

  Future<List<InventoryItem>> items() =>
      household.watchItems(homeId: _homeId).first;

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

final class _ItemMasterSyncServer implements SyncRemoteGateway {
  _ItemMasterSyncServer({required DateTime Function() serverClock})
    : _clock = serverClock;

  final DateTime Function() _clock;
  final Map<String, PushOperationResult> _receipts =
      <String, PushOperationResult>{};
  final List<RemoteChange> _changes = <RemoteChange>[];
  final List<String> pushedOperationIds = <String>[];
  Map<String, Object?>? _homeProduct;
  int _sequence = 0;
  int applications = 0;
  bool loseNextResponse = false;

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
            result: _receipts[operationId],
          ),
        )
        .toList(growable: false),
  );

  @override
  Future<PullPage> bootstrap({required String homeId}) async => PullPage(
    protocolVersion: 1,
    fromCursor: _cursor,
    changes: _homeProduct == null
        ? const <RemoteChange>[]
        : <RemoteChange>[_change(homeId)],
    pageCursor: _cursor,
    highWaterCursor: _cursor,
    hasMore: false,
    requestId: 'bootstrap-$_sequence',
  );

  @override
  Future<PullPage> pull({required String homeId, String? afterCursor}) async {
    final from = _parseCursor(afterCursor);
    final changes = _changes
        .where((change) => _parseCursor(change.cursor) > from)
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
    final receipt = _receipts[operation.operationId];
    if (receipt != null) {
      return PushResponse(results: <PushOperationResult>[receipt]);
    }
    if (homeId != _homeId ||
        operation.homeId != _homeId ||
        operation.entityType != 'inventory-home-product' ||
        operation.entityId != _homeProductId ||
        operation.operationType != 'inventory.home-product.create' ||
        operation.baseRevision != null ||
        operation.payload['productId'] != _productId ||
        operation.payload['packId'] != _packId) {
      throw const FormatException('Unexpected item-master create command.');
    }
    applications++;
    _sequence++;
    _homeProduct = <String, Object?>{...operation.payload, 'status': 'active'};
    final change = _change(homeId);
    _changes.add(change);
    final result = PushOperationResult(
      operationId: operation.operationId,
      kind: PushResultKind.acknowledged,
      acceptedRevision: 1,
      changeCursor: _cursor,
      remotePayload: _homeProduct,
    );
    _receipts[operation.operationId] = result;
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const RetryableSyncException('Response lost after commit.');
    }
    return PushResponse(results: <PushOperationResult>[result]);
  }

  RemoteChange _change(String homeId) => RemoteChange(
    cursor: _cursor,
    homeId: homeId,
    entityType: 'inventory-home-product',
    entityId: _homeProductId,
    kind: RemoteChangeKind.upsert,
    revision: 1,
    serverTimestamp: _clock().toUtc(),
    payload: _homeProduct!,
  );

  String get _cursor => 'cursor-$_sequence';

  int _parseCursor(String? cursor) =>
      cursor == null ? 0 : int.parse(cursor.substring('cursor-'.length));
}
