import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/infrastructure/generated_home_item_master_source.dart';
import 'package:providentia/features/inventory/infrastructure/item_master_refreshing_synchronization.dart';

const String _homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const String _otherHomeId = '0198a0b1-c2d3-7e4f-8123-456789abcdee';
const String _productId = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';
const String _packId = '0198a0b1-c2d3-7e4f-a345-6789abcdef01';
const String _privateProductId = '0198a0b1-c2d3-7e4f-b456-789abcdef012';
const String _staleSelectionId = '0198a0b1-c2d3-7e4f-9567-89abcdef0123';
const String _globalCategoryId = '0198a0b1-c2d3-7e4f-a678-9abcdef01234';
const String _homeCategoryId = '0198a0b1-c2d3-7e4f-b789-abcdef012345';

void main() {
  test('refreshes the verified cache after every completed sync run', () async {
    final item = InventoryItem(
      id: '0198a0b1-c2d3-7e4f-9234-56789abcdef0',
      homeId: _homeId,
      productId: '0198a0b1-c2d3-7e4f-a345-6789abcdef01',
      packId: '0198a0b1-c2d3-7e4f-9234-56789abcdef0',
      canonicalName: 'Rice',
      packSize: '2 kg',
      category: 'Grains',
    );
    final source = _Source(<InventoryItem>[item]);
    final delegate = _Synchronization(
      const SyncRunOutcome(status: SyncRunStatus.completed),
    );
    var replacements = 0;
    final synchronization = ItemMasterRefreshingSynchronization(
      delegate: delegate,
      source: source,
      replaceCache: ({required homeId, required items}) async {
        expect(homeId, _homeId);
        expect(items, same(source.items));
        replacements++;
      },
      homeId: _homeId,
    );

    expect((await synchronization.synchronize(_homeId)).completed, isTrue);
    expect((await synchronization.synchronize(_homeId)).completed, isTrue);
    expect(source.loads, 2);
    expect(replacements, 2);
  });

  test('preserves the prior cache on offline or malformed refreshes', () async {
    var replacements = 0;
    final offlineSource = _Source(const <InventoryItem>[]);
    final offline = ItemMasterRefreshingSynchronization(
      delegate: _Synchronization(
        const SyncRunOutcome(status: SyncRunStatus.offline),
      ),
      source: offlineSource,
      replaceCache: ({required homeId, required items}) async {
        replacements++;
      },
      homeId: _homeId,
    );
    expect((await offline.synchronize(_homeId)).status, SyncRunStatus.offline);
    expect(offlineSource.loads, 0);

    final malformed = ItemMasterRefreshingSynchronization(
      delegate: _Synchronization(
        const SyncRunOutcome(status: SyncRunStatus.completed),
      ),
      source: _Source.failure(const FormatException('partial page')),
      replaceCache: ({required homeId, required items}) async {
        replacements++;
      },
      homeId: _homeId,
    );
    final outcome = await malformed.synchronize(_homeId);
    expect(outcome.status, SyncRunStatus.retryableFailure);
    expect(outcome.safeMessage, contains('catalog could not be refreshed'));
    expect(replacements, 0);
  });

  test(
    'maps item-master authorization loss and rejects a foreign home',
    () async {
      final synchronization = ItemMasterRefreshingSynchronization(
        delegate: _Synchronization(
          const SyncRunOutcome(status: SyncRunStatus.completed),
        ),
        source: _Source.failure(
          const HomeItemMasterSourceException(
            HomeItemMasterSourceFailure.authorizationDenied,
          ),
        ),
        replaceCache: ({required homeId, required items}) async {},
        homeId: _homeId,
      );

      expect(
        (await synchronization.synchronize(_homeId)).status,
        SyncRunStatus.authorizationFailure,
      );
      await expectLater(
        synchronization.synchronize(_otherHomeId),
        throwsArgumentError,
      );
    },
  );

  test(
    'real Drift composition keeps sync authoritative across stale and failed refreshes',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final gateway = _AuthoritativeGateway();
      final local = DriftLocalSyncRepository(
        database,
        clock: () => DateTime.utc(2026, 9, 10, 8),
      );
      final household = DriftHouseholdRepository(
        database,
        clock: () => DateTime.utc(2026, 9, 10, 8),
      );
      final itemMaster = <InventoryItem>[
        InventoryItem(
          id: _staleSelectionId,
          homeId: _homeId,
          canonicalName: 'Long-grain rice',
          packSize: '2 kg bag',
          category: 'Global grains',
          brand: 'Harvest',
          aliases: const <String>['Rice long grain'],
          currentQuantity: 9,
          isHomeProduct: true,
          productId: _productId,
          packId: _packId,
          categoryId: _globalCategoryId,
          categorySource: InventoryCategorySource.global,
        ),
        InventoryItem(
          id: _privateProductId,
          homeId: _homeId,
          canonicalName: 'Family chilli blend',
          packSize: '250 g jar',
          category: 'Family spices',
          currentQuantity: 4,
          isHomeProduct: true,
          homeCategoryId: _homeCategoryId,
          categorySource: InventoryCategorySource.home,
        ),
      ];
      final source = _QueuedSource(<Object>[
        itemMaster,
        const FormatException('refresh interrupted'),
        itemMaster,
      ]);
      final coordinator = SyncCoordinator(
        local: local,
        remote: gateway,
        connectivity: const _OnlineProbe(),
        clock: () => DateTime.utc(2026, 9, 10, 8),
      );
      final synchronization = ItemMasterRefreshingSynchronization(
        delegate: coordinator,
        source: source,
        replaceCache: household.replaceCatalogItemMaster,
        homeId: _homeId,
      );

      expect((await synchronization.synchronize(_homeId)).completed, isTrue);
      var items = await household.watchItems(homeId: _homeId).first;
      expect(items, hasLength(2));
      final privateItem = items.singleWhere(
        (item) => item.id == _privateProductId,
      );
      final catalogItem = items.singleWhere(
        (item) => item.id == _staleSelectionId,
      );
      expect(privateItem.category, 'Family spices');
      expect(privateItem.homeCategoryId, _homeCategoryId);
      expect(privateItem.categorySource, InventoryCategorySource.home);
      expect(privateItem.currentQuantity, 4);
      expect(catalogItem.isHomeProduct, isTrue);
      expect(catalogItem.currentQuantity, 9);
      expect(catalogItem.categoryId, _globalCategoryId);
      expect(await household.watchItems(homeId: _otherHomeId).first, isEmpty);

      final cached = await database.select(database.localRecords).get();
      final cacheRows = cached
          .where((row) => row.entityType == 'inventory-item-master-product')
          .toList(growable: false);
      expect(cacheRows, hasLength(1));
      expect(cacheRows.single.entityId, _packId);

      gateway.deleteProducts();
      // A failed refresh cannot preserve the deleted private projection via
      // item-master data from the previous successful run.
      expect(
        (await synchronization.synchronize(_homeId)).status,
        SyncRunStatus.retryableFailure,
      );
      items = await household.watchItems(homeId: _homeId).first;
      expect(items, hasLength(1));
      expect(items.single.id, _packId);
      expect(items.single.isHomeProduct, isFalse);

      // A later stale server item-master response is validated, but its
      // private and selected state remains non-authoritative and cannot undo
      // the synchronization tombstone.
      expect((await synchronization.synchronize(_homeId)).completed, isTrue);
      items = await household.watchItems(homeId: _homeId).first;
      expect(items, hasLength(1));
      expect(items.single.id, _packId);
      expect(items.single.isHomeProduct, isFalse);
      expect(source.loads, 3);
    },
  );
}

final class _Source implements HomeItemMasterSource {
  _Source(this.items) : failure = null;

  _Source.failure(this.failure) : items = const <InventoryItem>[];

  final List<InventoryItem> items;
  final Object? failure;
  int loads = 0;

  @override
  Future<List<InventoryItem>> loadAll({required String homeId}) async {
    loads++;
    if (homeId != _homeId) throw StateError('foreign home');
    final error = failure;
    if (error != null) throw error;
    return items;
  }
}

final class _Synchronization implements AppSynchronization {
  const _Synchronization(this.outcome);

  final SyncRunOutcome outcome;

  @override
  Future<ConnectivityResult> connectivity() async =>
      const ConnectivityResult.online();

  @override
  Future<SyncRunOutcome> synchronize(String homeId) async => outcome;

  @override
  Stream<SyncSummary> watchSummary({required String homeId}) =>
      Stream<SyncSummary>.value(const SyncSummary.initial());
}

final class _QueuedSource implements HomeItemMasterSource {
  _QueuedSource(this._responses);

  final List<Object> _responses;
  int loads = 0;

  @override
  Future<List<InventoryItem>> loadAll({required String homeId}) async {
    if (homeId != _homeId) throw StateError('foreign home');
    final response = _responses[loads++];
    if (response is Exception) throw response;
    return response as List<InventoryItem>;
  }
}

final class _OnlineProbe implements ConnectivityProbe {
  const _OnlineProbe();

  @override
  Future<ConnectivityResult> check() async => const ConnectivityResult.online();
}

final class _AuthoritativeGateway implements SyncRemoteGateway {
  _AuthoritativeGateway() {
    _append(
      entityType: 'inventory-home-category',
      entityId: _homeCategoryId,
      revision: 1,
      payload: const <String, Object?>{
        'name': 'Family spices',
        'status': 'active',
      },
    );
    _append(
      entityType: 'inventory-home-product',
      entityId: _privateProductId,
      revision: 1,
      payload: const <String, Object?>{
        'productId': null,
        'packId': null,
        'privateName': 'Family chilli blend',
        'originalPackText': '250 g jar',
        'homeCategoryId': _homeCategoryId,
        'status': 'active',
      },
    );
    _append(
      entityType: 'inventory-balance',
      entityId: _privateProductId,
      revision: 1,
      payload: const <String, Object?>{
        'homeProductId': _privateProductId,
        'quantity': '4',
        'lastMovementId': null,
      },
    );
    _append(
      entityType: 'inventory-home-product',
      entityId: _staleSelectionId,
      revision: 1,
      payload: const <String, Object?>{
        'productId': _productId,
        'packId': _packId,
        'privateName': null,
        'originalPackText': null,
        'homeCategoryId': null,
        'status': 'active',
      },
    );
    _append(
      entityType: 'inventory-balance',
      entityId: _staleSelectionId,
      revision: 1,
      payload: const <String, Object?>{
        'homeProductId': _staleSelectionId,
        'quantity': '9',
        'lastMovementId': null,
      },
    );
  }

  final List<RemoteChange> _changes = <RemoteChange>[];
  var _sequence = 0;

  void deleteProducts() {
    _append(
      entityType: 'inventory-home-product',
      entityId: _privateProductId,
      revision: 2,
      kind: RemoteChangeKind.tombstone,
    );
    _append(
      entityType: 'inventory-balance',
      entityId: _privateProductId,
      revision: 2,
      kind: RemoteChangeKind.tombstone,
    );
    _append(
      entityType: 'inventory-home-product',
      entityId: _staleSelectionId,
      revision: 2,
      kind: RemoteChangeKind.tombstone,
    );
    _append(
      entityType: 'inventory-balance',
      entityId: _staleSelectionId,
      revision: 2,
      kind: RemoteChangeKind.tombstone,
    );
  }

  @override
  Future<PullPage> bootstrap({required String homeId}) async => PullPage(
    protocolVersion: 1,
    fromCursor: 'cursor-0',
    changes: _changes.take(5).toList(growable: false),
    pageCursor: 'cursor-5',
    highWaterCursor: _cursor,
    hasMore: false,
    requestId: 'bootstrap-1',
  );

  @override
  Future<PullPage> pull({required String homeId, String? afterCursor}) async {
    final after = _parseCursor(afterCursor);
    final changes = _changes
        .where((change) => _parseCursor(change.cursor) > after)
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
  }) async => throw StateError('No commands are expected in this composition.');

  @override
  Future<OperationStatusResponse> operationStatuses({
    required String homeId,
    required String deviceId,
    required List<String> operationIds,
  }) async =>
      OperationStatusResponse(operations: const <OperationStatusItem>[]);

  void _append({
    required String entityType,
    required String entityId,
    required int revision,
    RemoteChangeKind kind = RemoteChangeKind.upsert,
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    _sequence++;
    _changes.add(
      RemoteChange(
        cursor: _cursor,
        homeId: _homeId,
        entityType: entityType,
        entityId: entityId,
        kind: kind,
        revision: revision,
        serverTimestamp: DateTime.utc(2026, 9, 10, 8, _sequence),
        payload: payload,
      ),
    );
  }

  String get _cursor => 'cursor-$_sequence';

  int _parseCursor(String? cursor) =>
      cursor == null ? 0 : int.parse(cursor.substring('cursor-'.length));
}
