import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/features/homes/infrastructure/home_data_revocation.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/domain/inventory_services.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';

void main() {
  late AppDatabase database;
  late DriftHouseholdRepository repository;
  final now = DateTime.utc(2026, 7, 30, 12);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(database, clock: () => now);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'baseline import reconciles every required total and is idempotent',
    () async {
      final source = _baselineFixture();

      final report = await repository.importBaseline(
        homeId: 'home-1',
        encodedPantryData: source.$1,
        encodedProductRules: source.$2,
      );
      final replay = await repository.importBaseline(
        homeId: 'home-1',
        encodedPantryData: source.$1,
        encodedProductRules: source.$2,
      );

      expect(report.itemMasterRows, 292);
      expect(report.currentStockRows, 60);
      expect(report.currentUnits, 159);
      expect(report.recentPurchaseRows, 16);
      expect(report.historicalPurchaseRows, 452);
      expect(report.monthlyPurchaseRows, 261);
      expect(report.exactStockMatches, 32);
      expect(report.unresolvedStockRows, 28);
      expect(report.unresolvedRecentPurchaseRows, 12);
      expect(replay.alreadyImported, isTrue);

      final items = await repository.watchItems(homeId: 'home-1').first;
      final purchases = await repository
          .watchPurchaseLines(homeId: 'home-1')
          .first;
      expect(items, hasLength(320));
      expect(items.where((item) => item.isCounted), hasLength(60));
      expect(
        items.fold<double>(
          0,
          (total, item) => total + (item.currentQuantity ?? 0),
        ),
        159,
      );
      expect(
        items.where((item) => item.id.startsWith('baseline-stock-')),
        hasLength(28),
      );
      expect(
        items
            .singleWhere(
              (item) =>
                  item.id ==
                  'review-ground-coffee-jacobs-barista-classic-pack-size-pending-279',
            )
            .currentQuantity,
        2,
      );
      expect(items.where((item) => item.id == 'baseline-stock-26'), isEmpty);
      expect(purchases, hasLength(468));
      expect(await database.select(database.clientOperations).get(), isEmpty);
    },
  );

  test(
    'production projection keeps 292 catalog packs and 28 distinct private opening products',
    () async {
      final catalogItems = List<InventoryItem>.generate(292, (index) {
        final packId = _fixtureUuid(1, index + 1);
        return InventoryItem(
          id: packId,
          homeId: _homeId,
          canonicalName: 'Catalog product $index',
          packSize: '${index + 1} units',
          category: 'Baseline',
          productId: _fixtureUuid(2, index + 1),
          packId: packId,
        );
      });
      await repository.replaceCatalogItemMaster(
        homeId: _homeId,
        items: catalogItems,
      );

      for (var index = 0; index < 60; index++) {
        final linked = index < 32;
        final homeProductId = _fixtureUuid(3, index + 1);
        await _seedProjection(
          database,
          homeId: _homeId,
          entityType: 'inventory-home-product',
          entityId: homeProductId,
          revision: 1,
          payload: <String, Object?>{
            'productId': linked ? catalogItems[index].productId : null,
            'packId': linked ? catalogItems[index].packId : null,
            'privateName': linked ? null : 'Private opening product $index',
            'originalPackText': linked ? null : 'Source pack $index',
            'status': 'active',
          },
        );
        await _seedProjection(
          database,
          homeId: _homeId,
          entityType: 'inventory-balance',
          entityId: homeProductId,
          revision: 1,
          payload: <String, Object?>{
            'homeProductId': homeProductId,
            'quantity': index == 59 ? '41' : '2',
          },
        );
      }

      await repository.replaceCatalogItemMaster(
        homeId: _homeId,
        items: catalogItems,
      );
      final items = await repository.watchItems(homeId: _homeId).first;

      expect(items, hasLength(320));
      expect(
        items.map((item) => item.packId).whereType<String>().toSet(),
        hasLength(292),
      );
      expect(items.where((item) => item.isCounted), hasLength(60));
      expect(
        items.fold<double>(
          0,
          (total, item) => total + (item.currentQuantity ?? 0),
        ),
        159,
      );
      expect(
        items.where((item) => item.isHomeProduct && item.packId == null),
        hasLength(28),
      );
      expect(items.map((item) => item.canonicalName).toSet(), hasLength(320));
      expect(await database.select(database.clientOperations).get(), isEmpty);
    },
  );

  test(
    'closing a count atomically updates the balance and movement ledger',
    () async {
      final source = _baselineFixture();
      await repository.importBaseline(
        homeId: 'home-1',
        encodedPantryData: source.$1,
        encodedProductRules: source.$2,
      );
      final open = StockCountSession(
        id: 'count-1',
        homeId: 'home-1',
        locationId: 'primary',
        startedAt: now,
        lines: <StockCountLine>[
          StockCountLine(
            id: 'line-1',
            itemId: 'item-0',
            status: CountLineStatus.confirmed,
            source: CountSource.manual,
            observedQuantity: 9,
          ),
        ],
      );
      await repository.saveCountSession(open);

      await repository.saveCountSession(
        open.close(now.add(const Duration(minutes: 5))),
      );

      final items = await repository.watchItems(homeId: 'home-1').first;
      expect(
        items.singleWhere((item) => item.id == 'item-0').currentQuantity,
        9,
      );
      final movements = await (database.select(
        database.localRecords,
      )..where((row) => row.entityType.equals('phase5.stock-movement'))).get();
      expect(movements, hasLength(1));
      expect(await database.select(database.clientOperations).get(), isEmpty);
    },
  );

  test(
    'current pinned contract change-feed resources drive projections',
    () async {
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'inventory-home-product',
        entityId: _productId,
        revision: 2,
        payload: <String, Object?>{
          'privateName': 'Stone-ground flour',
          'originalPackText': '2 kg',
          'status': 'active',
        },
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'inventory-balance',
        entityId: _productId,
        revision: 4,
        payload: <String, Object?>{
          'homeProductId': _productId,
          'quantity': '3.5',
        },
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'inventory-count-session',
        entityId: _sessionId,
        revision: 1,
        payload: const <String, Object?>{
          'locationId': null,
          'notes': '',
          'scopeComplete': false,
          'reliability': 'unassessed',
          'status': 'open',
        },
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'inventory-count-line',
        entityId: _countLineId,
        revision: 1,
        payload: <String, Object?>{
          'sessionId': _sessionId,
          'homeProductId': _productId,
          'quantity': '4',
          'confidence': null,
          'source': 'manual',
          'notes': '',
          'status': 'confirmed',
        },
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'purchasing-store',
        entityId: _storeId,
        revision: 1,
        payload: const <String, Object?>{
          'name': 'Central Market',
          'location': 'Windhoek',
          'status': 'active',
        },
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'purchasing-receipt',
        entityId: _receiptId,
        revision: 2,
        payload: <String, Object?>{
          'storeId': _storeId,
          'purchaseDate': '2026-08-10',
          'currency': 'NAD',
          'totalAmount': '12.34',
          'status': 'committed',
          'source': 'manual',
          'sourceReference': null,
          'notes': '',
        },
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'purchasing-receipt-line',
        entityId: _receiptLineId,
        revision: 2,
        payload: <String, Object?>{
          'receiptId': _receiptId,
          'rawDescription': 'Flour 2kg',
          'quantity': '2',
          'originalPackText': '2 kg',
          'unitPrice': '6.17',
          'lineTotal': '12.34',
          'homeProductId': _productId,
          'approvalStatus': 'approved',
        },
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'shopping-list',
        entityId: _listId,
        revision: 2,
        payload: const <String, Object?>{
          'name': 'Weekly groceries',
          'kind': 'manual',
          'status': 'open',
        },
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'shopping-list-line',
        entityId: _shoppingLineId,
        revision: 1,
        payload: <String, Object?>{
          'listId': _listId,
          'homeProductId': _productId,
          'description': 'Stone-ground flour',
          'source': 'manual',
          'quantityToBuy': '2',
          'explanation': 'Added manually.',
          'confidence': null,
          'checkedAt': null,
          'checked': false,
        },
      );

      final items = await repository.watchItems(homeId: _homeId).first;
      final count = await repository
          .watchActiveCountSession(homeId: _homeId)
          .first;
      final purchases = await repository
          .watchPurchaseLines(homeId: _homeId)
          .first;
      final shopping = await repository.watchActiveList(homeId: _homeId).first;

      expect(items.single.canonicalName, 'Stone-ground flour');
      expect(items.single.currentQuantity, 3.5);
      expect(count?.id, _sessionId);
      expect(count?.lines.single.observedQuantity, 4);
      expect(purchases.single.storeName, 'Central Market');
      expect(purchases.single.lineTotal?.minorUnits, 1234);
      expect(shopping.id, _listId);
      expect(shopping.lines.single.homeProductId, _productId);
      // ignore: deprecated_member_use_from_same_package
      expect(shopping.lines.single.productPackId, isNull);
    },
  );

  test(
    'manual adjustment atomically updates balance and queues a closed v2 command',
    () async {
      var syncTriggers = 0;
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
        onMutationCommitted: () async {
          syncTriggers++;
        },
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'inventory-home-product',
        entityId: _productId,
        revision: 1,
        payload: const <String, Object?>{
          'privateName': 'Flour',
          'originalPackText': '2 kg',
          'status': 'active',
        },
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'inventory-balance',
        entityId: _productId,
        revision: 3,
        payload: <String, Object?>{
          'homeProductId': _productId,
          'quantity': '2',
        },
      );

      await repository.commitManualAdjustment(
        intent: ManualAdjustmentIntent(
          id: _operationId1,
          homeId: _homeId,
          itemId: _productId,
          locationId: 'primary',
          projectedQuantity: 2,
          observedQuantity: 5,
          reason: 'Physical recount',
          createdAt: now,
        ),
        movement: null,
      );

      final balance =
          await (database.select(database.localRecords)..where(
                (row) =>
                    row.homeId.equals(_homeId) &
                    row.entityType.equals('inventory-balance') &
                    row.entityId.equals(_productId),
              ))
              .getSingle();
      final operation = await database
          .select(database.clientOperations)
          .getSingle();
      expect(jsonDecode(balance.payload), containsPair('quantity', '5'));
      expect(balance.revision, 3);
      expect(operation.entityType, 'inventory-balance');
      expect(operation.operationType, 'inventory.adjustment.create');
      expect(operation.entityId, _productId);
      expect(operation.baseRevision, isNull);
      expect(jsonDecode(operation.payload), <String, Object?>{
        'quantityDelta': '3',
        'reason': 'Physical recount',
      });
      expect(syncTriggers, 1);
    },
  );

  test(
    'private product creation is atomic private and protocol allowlisted',
    () async {
      var idIndex = 0;
      var syncTriggers = 0;
      final generatedIds = <String>[_createdProductId, _operationId1];
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
        idGenerator: () => generatedIds[idIndex++],
        onMutationCommitted: () async {
          syncTriggers++;
        },
      );

      final result = await repository.createPrivateHomeProduct(
        PrivateHomeProductDraft(
          homeId: _homeId,
          privateName: '  Family spice mix  ',
          originalPackText: '  250 g jar  ',
        ),
      );

      expect(result.homeProductId, _createdProductId);
      expect(result.revision, 1);
      expect(result.awaitsServerConfirmation, isTrue);
      final record = await database.select(database.localRecords).getSingle();
      expect(record.homeId, _homeId);
      expect(record.entityType, 'inventory-home-product');
      expect(record.entityId, _createdProductId);
      expect(record.revision, 1);
      final representation = jsonDecode(record.payload) as Map<String, Object?>;
      expect(representation, <String, Object?>{
        'productId': null,
        'packId': null,
        'privateName': 'Family spice mix',
        'originalPackText': '250 g jar',
        'status': 'active',
        'id': _createdProductId,
        'revision': 1,
      });
      expect(representation.containsKey('quantity'), isFalse);
      expect(representation.containsKey('homeId'), isFalse);

      final operation = await database
          .select(database.clientOperations)
          .getSingle();
      expect(operation.operationId, _operationId1);
      expect(operation.homeId, _homeId);
      expect(operation.entityType, 'inventory-home-product');
      expect(operation.entityId, _createdProductId);
      expect(operation.operationType, 'inventory.home-product.create');
      expect(operation.baseRevision, isNull);
      final command = jsonDecode(operation.payload) as Map<String, Object?>;
      expect(command, <String, Object?>{
        'productId': null,
        'packId': null,
        'privateName': 'Family spice mix',
        'originalPackText': '250 g jar',
      });
      expect(command.keys, hasLength(4));
      expect(command.containsKey('quantity'), isFalse);
      expect(command.containsKey('homeId'), isFalse);
      final item = await repository.watchItems(homeId: _homeId).first;
      expect(item.single.canonicalName, 'Family spice mix');
      expect(item.single.currentQuantity, isNull);
      expect(syncTriggers, 1);
    },
  );

  test(
    'private product creation fails closed outside a valid synced home',
    () async {
      await expectLater(
        repository.createPrivateHomeProduct(
          PrivateHomeProductDraft(
            homeId: _homeId,
            privateName: 'Local-only product',
          ),
        ),
        throwsA(isA<InventoryProductCreationException>()),
      );
      expect(await database.select(database.localRecords).get(), isEmpty);
      expect(await database.select(database.clientOperations).get(), isEmpty);

      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
      );
      await expectLater(
        repository.createPrivateHomeProduct(
          PrivateHomeProductDraft(
            homeId: 'another-home',
            privateName: 'Foreign product',
          ),
        ),
        throwsArgumentError,
      );
      expect(await database.select(database.localRecords).get(), isEmpty);
      expect(await database.select(database.clientOperations).get(), isEmpty);
    },
  );

  test(
    'catalog item-master selection queues one typed home-product command',
    () async {
      var idIndex = 0;
      var syncTriggers = 0;
      final generatedIds = <String>[_createdProductId, _operationId1];
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
        idGenerator: () => generatedIds[idIndex++],
        onMutationCommitted: () async {
          syncTriggers++;
        },
      );
      final catalogItem = InventoryItem(
        id: _productId,
        homeId: _homeId,
        productId: _otherProductId,
        packId: _productId,
        canonicalName: 'Long-grain rice',
        packSize: '2 kg',
        category: 'Grains',
        brand: 'Harvest',
        aliases: const <String>['Rice long grain'],
      );
      await repository.replaceCatalogItemMaster(
        homeId: _homeId,
        items: <InventoryItem>[catalogItem],
      );
      expect(
        (await repository.watchItems(homeId: _homeId).first).single.id,
        _productId,
      );

      final result = await repository.createCatalogHomeProduct(
        CatalogHomeProductDraft.fromItem(catalogItem),
      );

      expect(result.homeProductId, _createdProductId);
      final operation = await database
          .select(database.clientOperations)
          .getSingle();
      expect(operation.operationType, 'inventory.home-product.create');
      expect(operation.entityId, _createdProductId);
      expect(operation.baseRevision, isNull);
      expect(jsonDecode(operation.payload), <String, Object?>{
        'productId': _otherProductId,
        'packId': _productId,
        'privateName': null,
        'originalPackText': null,
      });
      final selected = await repository.watchItems(homeId: _homeId).first;
      expect(selected, hasLength(1));
      expect(selected.single.id, _createdProductId);
      expect(selected.single.productId, _otherProductId);
      expect(selected.single.packId, _productId);
      expect(selected.single.canonicalName, 'Long-grain rice');
      expect(selected.single.aliases, <String>['Rice long grain']);
      expect(selected.single.isHomeProduct, isTrue);
      expect(syncTriggers, 1);
    },
  );

  test(
    'verified item-master cache remains searchable offline and purges by home',
    () async {
      final item = InventoryItem(
        id: _productId,
        homeId: _homeId,
        productId: _otherProductId,
        packId: _productId,
        canonicalName: 'Long-grain rice',
        packSize: '2 kg bag',
        category: 'Grains',
        brand: 'Harvest Foods',
        aliases: const <String>['Rice long grain'],
      );
      await repository.replaceCatalogItemMaster(
        homeId: _homeId,
        items: <InventoryItem>[item],
      );

      // A new repository instance has no network dependency and reads the
      // last complete home-scoped snapshot from Drift.
      repository = DriftHouseholdRepository(database, clock: () => now);
      final cached = await repository.watchItems(homeId: _homeId).first;
      expect(cached, hasLength(1));
      const search = InventoryItemSearch();
      for (final query in <String>[
        'long grain',
        'rice long grain',
        'harvest foods',
        'grains',
        '2 kg bag',
      ]) {
        expect(
          search.filter(
            cached,
            InventorySearchCriteria(
              query: query,
              view: InventoryView.itemMaster,
            ),
          ),
          hasLength(1),
        );
      }
      expect(await repository.watchItems(homeId: _otherHomeId).first, isEmpty);
      await expectLater(
        repository.replaceCatalogItemMaster(
          homeId: _homeId,
          items: <InventoryItem>[
            InventoryItem(
              id: _createdProductId,
              homeId: _otherHomeId,
              productId: _otherProductId,
              packId: _createdProductId,
              canonicalName: 'Foreign product',
              packSize: '1 unit',
              category: 'Private',
            ),
          ],
        ),
        throwsFormatException,
      );
      expect(await repository.watchItems(homeId: _homeId).first, hasLength(1));

      await RevokedHomeDataPurger(database).purge(_homeId);
      expect(await repository.watchItems(homeId: _homeId).first, isEmpty);
    },
  );

  test(
    'catalog selection rejects an uncached or foreign guessed pack',
    () async {
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
        idGenerator: () => _operationId1,
      );

      await expectLater(
        repository.createCatalogHomeProduct(
          CatalogHomeProductDraft(
            homeId: _homeId,
            productId: _otherProductId,
            packId: _productId,
            canonicalName: 'Guessed product',
            packSize: '1 unit',
            category: 'Unknown',
          ),
        ),
        throwsA(isA<InventoryProductCreationException>()),
      );
      expect(await database.select(database.localRecords).get(), isEmpty);
      expect(await database.select(database.clientOperations).get(), isEmpty);
    },
  );

  test(
    'synchronized mutation rejects guessed cross-home objects atomically',
    () async {
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
      );
      await _seedProjection(
        database,
        homeId: _otherHomeId,
        entityType: 'inventory-home-product',
        entityId: _productId,
        revision: 1,
        payload: const <String, Object?>{
          'privateName': 'Other home item',
          'originalPackText': '1 unit',
          'status': 'active',
        },
      );

      await expectLater(
        repository.commitManualAdjustment(
          intent: ManualAdjustmentIntent(
            id: _operationId1,
            homeId: _homeId,
            itemId: _productId,
            locationId: 'primary',
            projectedQuantity: 0,
            observedQuantity: 1,
            reason: 'Should fail',
            createdAt: now,
          ),
          movement: null,
        ),
        throwsStateError,
      );

      expect(await database.select(database.clientOperations).get(), isEmpty);
      expect(
        await (database.select(
          database.localRecords,
        )..where((row) => row.homeId.equals(_homeId))).get(),
        isEmpty,
      );
    },
  );

  test(
    'count workflow preserves command order revisions and UUID identities',
    () async {
      var idIndex = 0;
      final operationIds = <String>[
        _operationId4,
        _operationId3,
        _operationId2,
        _operationId1,
      ];
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
        idGenerator: () => operationIds[idIndex++],
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'inventory-home-product',
        entityId: _productId,
        revision: 1,
        payload: const <String, Object?>{
          'privateName': 'Flour',
          'originalPackText': '2 kg',
          'status': 'active',
        },
      );
      final open = StockCountSession(
        id: _sessionId,
        homeId: _homeId,
        locationId: 'primary',
        startedAt: now,
      );
      await repository.saveCountSession(open);
      final counted = open.recordLine(
        StockCountLine(
          id: _countLineId,
          itemId: _productId,
          status: CountLineStatus.confirmed,
          source: CountSource.manual,
          observedQuantity: 7,
        ),
      );
      await repository.saveCountSession(counted);
      final updated = counted.recordLine(
        StockCountLine(
          id: _countLineId,
          itemId: _productId,
          status: CountLineStatus.confirmed,
          source: CountSource.manual,
          observedQuantity: 8,
        ),
      );
      await repository.saveCountSession(updated);
      await repository.saveCountSession(
        updated.close(now.add(const Duration(minutes: 2))),
      );

      final operations =
          await (database.select(database.clientOperations)
                ..orderBy(<OrderingTerm Function(ClientOperations)>[
                  (row) => OrderingTerm.asc(row.clientTimestamp),
                  (row) => OrderingTerm.asc(row.operationId),
                ]))
              .get();
      expect(operations.map((operation) => operation.operationType), <String>[
        'inventory.count-session.create',
        'inventory.count-line.upsert',
        'inventory.count-line.upsert',
        'inventory.count-session.close',
      ]);
      expect(operations.map((operation) => operation.baseRevision), <int?>[
        null,
        0,
        1,
        3,
      ]);
      for (var index = 1; index < operations.length; index++) {
        expect(
          operations[index].clientTimestamp.isAfter(
            operations[index - 1].clientTimestamp,
          ),
          isTrue,
          reason: 'dependent commands must not be ordered by random UUIDv4',
        );
      }
      final lineCommands = operations
          .where(
            (operation) =>
                operation.operationType == 'inventory.count-line.upsert',
          )
          .toList(growable: false);
      expect(lineCommands.map((operation) => operation.entityId), <String>[
        _countLineId,
        _countLineId,
      ]);
      expect(
        lineCommands.map(
          (operation) =>
              (jsonDecode(operation.payload)
                  as Map<String, Object?>)['quantity'],
        ),
        <String>['7', '8'],
      );
      expect(
        operations.every((operation) => operation.operationId.contains('-')),
        isTrue,
      );
      final balance =
          await (database.select(database.localRecords)
                ..where((row) => row.entityType.equals('inventory-balance')))
              .getSingle();
      expect(jsonDecode(balance.payload), containsPair('quantity', '8'));
    },
  );

  test(
    'cancelling a synchronized count queues the revision-bound v2 command',
    () async {
      var idIndex = 0;
      var syncTriggers = 0;
      final operationIds = <String>[_operationId2, _operationId1];
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
        idGenerator: () => operationIds[idIndex++],
        onMutationCommitted: () async {
          syncTriggers++;
        },
      );
      final open = StockCountSession(
        id: _sessionId,
        homeId: _homeId,
        locationId: 'primary',
        startedAt: now,
      );

      await repository.saveCountSession(open);
      await repository.saveCountSession(open.cancel());

      final operations =
          await (database.select(database.clientOperations)
                ..orderBy(<OrderingTerm Function(ClientOperations)>[
                  (row) => OrderingTerm.asc(row.clientTimestamp),
                ]))
              .get();
      expect(operations.map((operation) => operation.operationType), <String>[
        'inventory.count-session.create',
        'inventory.count-session.cancel',
      ]);
      expect(operations.map((operation) => operation.baseRevision), <int?>[
        null,
        1,
      ]);
      expect(jsonDecode(operations.last.payload), isEmpty);
      final session =
          await (database.select(database.localRecords)..where(
                (row) =>
                    row.homeId.equals(_homeId) &
                    row.entityType.equals('inventory-count-session') &
                    row.entityId.equals(_sessionId),
              ))
              .getSingle();
      expect(session.revision, 2);
      expect(jsonDecode(session.payload), containsPair('status', 'cancelled'));
      expect(
        await repository.watchActiveCountSession(homeId: _homeId).first,
        isNull,
      );
      expect(
        await (database.select(database.localRecords)
              ..where((row) => row.entityType.equals('phase5.stock-movement')))
            .get(),
        isEmpty,
      );
      expect(syncTriggers, 2);
    },
  );

  test(
    'photo count queues an ordinary line and changes balance only on one close',
    () async {
      var idIndex = 0;
      final operationIds = <String>[
        _operationId4,
        _operationId3,
        _operationId2,
      ];
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
        idGenerator: () => operationIds[idIndex++],
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'inventory-home-product',
        entityId: _productId,
        revision: 1,
        payload: const <String, Object?>{
          'privateName': 'Flour',
          'originalPackText': '2 kg',
          'status': 'active',
        },
      );
      final open = StockCountSession(
        id: _sessionId,
        homeId: _homeId,
        locationId: 'primary',
        startedAt: now,
      );
      await repository.saveCountSession(open);
      final counted = open
          .attachPhoto(
            StockPhotoReference(
              id: 'proposal-1',
              localReference: 'ephemeral://review',
              addedAt: now,
            ),
          )
          .recordLine(
            StockCountLine(
              id: _countLineId,
              itemId: _productId,
              status: CountLineStatus.confirmed,
              source: CountSource.photo,
              observedQuantity: 6,
              photoId: 'proposal-1',
            ),
          );
      await repository.saveCountSession(counted);

      var operations = await database.select(database.clientOperations).get();
      expect(operations, hasLength(2));
      final linePayload = jsonDecode(operations.last.payload);
      expect(linePayload, containsPair('source', 'photo-confirmed'));
      expect(
        await (database.select(
          database.localRecords,
        )..where((row) => row.entityType.equals('inventory-balance'))).get(),
        isEmpty,
      );

      final closed = counted.close(now.add(const Duration(minutes: 2)));
      await repository.saveCountSession(closed);
      operations = await database.select(database.clientOperations).get();
      expect(
        operations.where(
          (operation) =>
              operation.operationType == 'inventory.count-session.close',
        ),
        hasLength(1),
      );
      final balance =
          await (database.select(database.localRecords)
                ..where((row) => row.entityType.equals('inventory-balance')))
              .getSingle();
      expect(jsonDecode(balance.payload), containsPair('quantity', '6'));
      await expectLater(repository.saveCountSession(closed), throwsStateError);
    },
  );

  test(
    'receipt capture queues exact ordered commands and commit retry is idempotent',
    () async {
      var idIndex = 0;
      var syncTriggers = 0;
      final generatedIds = <String>[
        _receiptId,
        _operationId4,
        _receiptLineId,
        _operationId3,
        _operationId2,
        _operationId1,
      ];
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
        idGenerator: () => generatedIds[idIndex++],
        onMutationCommitted: () async {
          syncTriggers++;
        },
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'purchasing-store',
        entityId: _storeId,
        revision: 1,
        payload: const <String, Object?>{
          'name': 'Central Market',
          'location': 'Windhoek',
          'status': 'active',
        },
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'inventory-home-product',
        entityId: _productId,
        revision: 1,
        payload: const <String, Object?>{
          'privateName': 'Flour',
          'originalPackText': '2 kg',
          'status': 'active',
        },
      );
      await _seedProjection(
        database,
        homeId: _otherHomeId,
        entityType: 'inventory-home-product',
        entityId: _otherProductId,
        revision: 1,
        payload: const <String, Object?>{
          'privateName': 'Foreign flour',
          'originalPackText': '1 kg',
          'status': 'active',
        },
      );

      final created = await repository.createReceiptDraft(
        PurchaseReceiptDraftRequest(
          homeId: _homeId,
          storeId: _storeId,
          purchaseDate: DateTime.utc(2026, 8, 11),
          currency: 'NAD',
          total: Money(minorUnits: 1234, currency: 'NAD'),
          notes: 'Private till note',
          sourceReference: 'wallet-photo-7',
        ),
      );
      final added = await repository.addReceiptLine(
        PurchaseReceiptLineRequest(
          homeId: _homeId,
          receiptId: created.entityId,
          rawDescription: '  Flour 2kg  ',
          quantity: 2,
          originalPackText: '2 kg',
          unitPrice: Money(minorUnits: 617, currency: 'NAD'),
          lineTotal: Money(minorUnits: 1234, currency: 'NAD'),
        ),
      );
      expect(
        await repository.watchPurchaseLines(homeId: _homeId).first,
        isEmpty,
        reason: 'draft lines must not appear as committed purchase history',
      );

      await expectLater(
        repository.commitReceipt(homeId: _homeId, receiptId: _receiptId),
        throwsA(isA<PurchaseCaptureException>()),
      );
      expect(
        await database.select(database.clientOperations).get(),
        hasLength(2),
      );

      final beforeForeignApproval =
          await (database.select(database.localRecords)..where(
                (row) =>
                    row.homeId.equals(_homeId) &
                    row.entityType.isIn(<String>{
                      'purchasing-receipt',
                      'purchasing-receipt-line',
                    }),
              ))
              .get();
      await expectLater(
        repository.approveReceiptLine(
          homeId: _homeId,
          receiptId: _receiptId,
          lineId: _receiptLineId,
          homeProductId: _otherProductId,
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      final afterForeignApproval =
          await (database.select(database.localRecords)..where(
                (row) =>
                    row.homeId.equals(_homeId) &
                    row.entityType.isIn(<String>{
                      'purchasing-receipt',
                      'purchasing-receipt-line',
                    }),
              ))
              .get();
      expect(
        afterForeignApproval.map(
          (row) => (row.entityId, row.revision, row.payload),
        ),
        beforeForeignApproval.map(
          (row) => (row.entityId, row.revision, row.payload),
        ),
      );

      final approved = await repository.approveReceiptLine(
        homeId: _homeId,
        receiptId: _receiptId,
        lineId: _receiptLineId,
        homeProductId: _productId,
      );
      final committed = await repository.commitReceipt(
        homeId: _homeId,
        receiptId: _receiptId,
      );
      final retry = await repository.commitReceipt(
        homeId: _homeId,
        receiptId: _receiptId,
      );

      expect(created.entityId, _receiptId);
      expect(added.entityId, _receiptLineId);
      expect(approved.revision, 2);
      expect(committed.revision, 4);
      expect(retry.disposition, PurchaseMutationDisposition.alreadyQueued);
      expect(idIndex, generatedIds.length);
      final operations =
          await (database.select(database.clientOperations)
                ..orderBy(<OrderingTerm Function(ClientOperations)>[
                  (row) => OrderingTerm.asc(row.clientTimestamp),
                  (row) => OrderingTerm.asc(row.operationId),
                ]))
              .get();
      expect(operations, hasLength(4));
      expect(operations.map((operation) => operation.operationType), <String>[
        'purchasing.receipt.create',
        'purchasing.receipt-line.create',
        'purchasing.receipt-line.approve',
        'purchasing.receipt.commit',
      ]);
      expect(operations.map((operation) => operation.entityType), <String>[
        'purchasing-receipt',
        'purchasing-receipt-line',
        'purchasing-receipt-line',
        'purchasing-receipt',
      ]);
      expect(operations.map((operation) => operation.baseRevision), <int?>[
        null,
        1,
        1,
        3,
      ]);
      for (var index = 1; index < operations.length; index++) {
        expect(
          operations[index].clientTimestamp.isAfter(
            operations[index - 1].clientTimestamp,
          ),
          isTrue,
        );
      }
      expect(jsonDecode(operations[0].payload), <String, Object?>{
        'storeId': _storeId,
        'purchaseDate': '2026-08-11',
        'currency': 'NAD',
        'totalAmount': '12.34',
        'notes': 'Private till note',
        'sourceReference': 'wallet-photo-7',
      });
      expect(jsonDecode(operations[1].payload), <String, Object?>{
        'receiptId': _receiptId,
        'rawDescription': 'Flour 2kg',
        'quantity': '2',
        'originalPackText': '2 kg',
        'unitPrice': '6.17',
        'lineTotal': '12.34',
      });
      expect(jsonDecode(operations[2].payload), <String, Object?>{
        'receiptId': _receiptId,
        'homeProductId': _productId,
      });
      expect(jsonDecode(operations[3].payload), <String, Object?>{});
      final capture = await repository
          .watchActiveReceiptCapture(homeId: _homeId)
          .first;
      expect(capture?.status, PurchaseReceiptStatus.committed);
      expect(capture?.commitAwaitingConfirmation, isTrue);
      expect(capture?.revision, 4);
      expect(capture?.lines.single.revision, 2);
      expect(capture?.lines.single.homeProductId, _productId);
      final pendingHistory = await repository
          .watchPurchaseLines(homeId: _homeId)
          .first;
      expect(pendingHistory.single.pendingSynchronization, isTrue);
      expect(syncTriggers, 5);
    },
  );

  test(
    'unresolved decision survives reload, exact retry, and commit without local effects',
    () async {
      var idIndex = 0;
      final generatedIds = <String>[_operationId1];
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
        idGenerator: () => generatedIds[idIndex++],
      );
      await _seedDraftReceiptAndLine(database);

      final unresolved = await repository.markReceiptLineUnresolved(
        homeId: _homeId,
        receiptId: _receiptId,
        lineId: _receiptLineId,
      );
      var reloadedIdCalls = 0;
      final reloaded = DriftHouseholdRepository(
        database,
        clock: () => now.add(const Duration(minutes: 1)),
        deviceId: _deviceId,
        idGenerator: () {
          reloadedIdCalls++;
          return _operationId2;
        },
      );
      final retry = await reloaded.markReceiptLineUnresolved(
        homeId: _homeId,
        receiptId: _receiptId,
        lineId: _receiptLineId,
      );

      expect(unresolved.revision, 2);
      expect(retry.revision, 2);
      expect(retry.disposition, PurchaseMutationDisposition.alreadyQueued);
      expect(reloadedIdCalls, 0);
      var operations = await database.select(database.clientOperations).get();
      expect(operations, hasLength(1));
      expect(operations.single.operationId, _operationId1);
      expect(
        operations.single.operationType,
        'purchasing.receipt-line.unresolve',
      );
      expect(operations.single.baseRevision, 1);
      expect(jsonDecode(operations.single.payload), <String, Object?>{
        'receiptId': _receiptId,
      });

      final capture = await reloaded
          .watchActiveReceiptCapture(homeId: _homeId)
          .first;
      expect(capture?.reviewComplete, isTrue);
      expect(capture?.lines.single.unresolved, isTrue);
      expect(capture?.lines.single.rawDescription, 'Unreadable till line');
      expect(capture?.lines.single.originalPackText, '500 g?');
      expect(capture?.lines.single.lineTotal?.minorUnits, 875);
      expect(capture?.lines.single.homeProductId, isNull);

      final committed = await reloaded.commitReceipt(
        homeId: _homeId,
        receiptId: _receiptId,
      );
      expect(committed.revision, 4);
      operations = await database.select(database.clientOperations).get();
      expect(operations.map((operation) => operation.operationType), <String>[
        'purchasing.receipt-line.unresolve',
        'purchasing.receipt.commit',
      ]);
      expect(operations.map((operation) => operation.baseRevision), <int?>[
        1,
        3,
      ]);
      expect(idIndex, generatedIds.length);
      expect(reloadedIdCalls, 1);
      final effectRecords =
          await (database.select(database.localRecords)..where(
                (row) => row.entityType.isIn(const <String>[
                  'phase5.stock-movement',
                  'phase8.price-observation',
                  'inventory-movement',
                  'purchasing-price-observation',
                ]),
              ))
              .get();
      expect(effectRecords, isEmpty);
    },
  );

  test(
    'unresolved decision can later be approved without losing raw data',
    () async {
      var idIndex = 0;
      final generatedIds = <String>[_operationId1, _operationId2];
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
        idGenerator: () => generatedIds[idIndex++],
      );
      await _seedDraftReceiptAndLine(database);
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'inventory-home-product',
        entityId: _productId,
        revision: 1,
        payload: const <String, Object?>{
          'privateName': 'Reviewed pantry item',
          'originalPackText': '500 g',
          'status': 'active',
        },
      );

      await repository.markReceiptLineUnresolved(
        homeId: _homeId,
        receiptId: _receiptId,
        lineId: _receiptLineId,
      );
      final approved = await repository.approveReceiptLine(
        homeId: _homeId,
        receiptId: _receiptId,
        lineId: _receiptLineId,
        homeProductId: _productId,
      );

      expect(approved.revision, 3);
      final capture = await repository
          .watchActiveReceiptCapture(homeId: _homeId)
          .first;
      expect(capture?.lines.single.approved, isTrue);
      expect(capture?.lines.single.rawDescription, 'Unreadable till line');
      expect(capture?.lines.single.originalPackText, '500 g?');
      expect(capture?.lines.single.homeProductId, _productId);
      final operations = await database.select(database.clientOperations).get();
      expect(operations.map((operation) => operation.operationType), <String>[
        'purchasing.receipt-line.unresolve',
        'purchasing.receipt-line.approve',
      ]);
      expect(operations.map((operation) => operation.baseRevision), <int?>[
        1,
        2,
      ]);
    },
  );

  test(
    'foreign-home unresolved mutation is atomic and authoritative second-device projection is readable',
    () async {
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
        idGenerator: () => _operationId1,
      );
      await _seedDraftReceiptAndLine(database, homeId: _otherHomeId);

      await expectLater(
        repository.markReceiptLineUnresolved(
          homeId: _homeId,
          receiptId: _receiptId,
          lineId: _receiptLineId,
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      expect(await database.select(database.clientOperations).get(), isEmpty);

      await DriftLocalSyncRepository(database).applyPullPage(
        homeId: _homeId,
        page: PullPage(
          protocolVersion: 1,
          fromCursor: null,
          pageCursor: 'cursor-unresolved',
          highWaterCursor: 'cursor-unresolved',
          hasMore: false,
          requestId: 'second-device-pull',
          changes: <RemoteChange>[
            RemoteChange(
              cursor: 'cursor-receipt',
              homeId: _homeId,
              entityType: 'purchasing-receipt',
              entityId: _receiptId,
              kind: RemoteChangeKind.upsert,
              revision: 3,
              serverTimestamp: now,
              payload: _draftReceiptPayload(),
            ),
            RemoteChange(
              cursor: 'cursor-unresolved',
              homeId: _homeId,
              entityType: 'purchasing-receipt-line',
              entityId: _receiptLineId,
              kind: RemoteChangeKind.upsert,
              revision: 2,
              serverTimestamp: now,
              payload: <String, Object?>{
                ..._draftLinePayload(),
                'homeProductId': null,
                'approvalStatus': 'unresolved',
              },
            ),
          ],
        ),
      );

      final secondDevice = await repository
          .watchActiveReceiptCapture(homeId: _homeId)
          .first;
      expect(secondDevice?.lines.single.unresolved, isTrue);
      expect(
        secondDevice?.lines.single.synchronizationState,
        PurchaseSynchronizationState.synchronized,
      );
      expect(secondDevice?.reviewComplete, isTrue);
    },
  );

  test(
    'approved-catalog is terminal and can be deliberately unresolved then reapproved',
    () async {
      var idIndex = 0;
      final operationIds = <String>[
        _operationId1,
        _operationId2,
        _operationId3,
      ];
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
        idGenerator: () => operationIds[idIndex++],
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'inventory-home-product',
        entityId: _productId,
        revision: 1,
        payload: const <String, Object?>{
          'privateName': 'Catalog milk',
          'status': 'active',
        },
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'purchasing-receipt',
        entityId: _receiptId,
        revision: 2,
        payload: _draftReceiptPayload(),
      );
      await _seedProjection(
        database,
        homeId: _homeId,
        entityType: 'purchasing-receipt-line',
        entityId: _receiptLineId,
        revision: 1,
        payload: <String, Object?>{
          ..._draftLinePayload(),
          'homeProductId': _productId,
          'approvalStatus': 'approved-catalog',
        },
      );

      final catalogCapture = await repository
          .watchActiveReceiptCapture(homeId: _homeId)
          .first;
      expect(
        catalogCapture?.lines.single.approvalStatus,
        PurchaseLineApprovalStatus.approvedCatalog,
      );
      expect(catalogCapture?.lines.single.approved, isTrue);
      expect(catalogCapture?.reviewComplete, isTrue);

      await repository.markReceiptLineUnresolved(
        homeId: _homeId,
        receiptId: _receiptId,
        lineId: _receiptLineId,
      );
      await repository.approveReceiptLine(
        homeId: _homeId,
        receiptId: _receiptId,
        lineId: _receiptLineId,
        homeProductId: _productId,
      );
      await repository.commitReceipt(homeId: _homeId, receiptId: _receiptId);

      final operations = await database.select(database.clientOperations).get();
      expect(operations.map((operation) => operation.operationType), <String>[
        'purchasing.receipt-line.unresolve',
        'purchasing.receipt-line.approve',
        'purchasing.receipt.commit',
      ]);
      expect(operations.map((operation) => operation.baseRevision), <int?>[
        1,
        2,
        4,
      ]);
    },
  );

  test('shopping writes only published create and checked semantics', () async {
    var idIndex = 0;
    final operationIds = <String>[_operationId1, _operationId2, _operationId3];
    repository = DriftHouseholdRepository(
      database,
      clock: () => now,
      deviceId: _deviceId,
      idGenerator: () => operationIds[idIndex++],
    );
    final empty = ShoppingList(
      id: _listId,
      homeId: _homeId,
      name: 'Shopping list',
      createdAt: now,
    );
    await repository.saveList(empty);
    final withLine = empty.add(
      ShoppingListLine(
        id: _shoppingLineId,
        homeId: _homeId,
        name: 'Flour',
        quantity: 2,
        origin: ShoppingLineOrigin.manual,
        createdAt: now,
        homeProductId: _productId,
      ),
    );
    await repository.saveList(withLine);
    await repository.saveList(withLine.toggle(_shoppingLineId));

    final beforeUnsupported = await database
        .select(database.clientOperations)
        .get();
    await expectLater(
      repository.saveList(withLine.updateQuantity(_shoppingLineId, 4)),
      throwsA(isA<UnsupportedError>()),
    );
    final operations = await database.select(database.clientOperations).get();
    expect(operations, hasLength(beforeUnsupported.length));
    expect(
      operations.map((operation) => operation.operationType),
      containsAll(<String>[
        'shopping.list.create',
        'shopping.list-line.create',
        'shopping.list-line.checked',
      ]),
    );
    final line = await (database.select(
      database.localRecords,
    )..where((row) => row.entityType.equals('shopping-list-line'))).getSingle();
    final payload = jsonDecode(line.payload) as Map<String, Object?>;
    expect(payload['quantityToBuy'], '2');
    expect(payload['checked'], isTrue);
  });

  test(
    'suggestion add keeps three identities while queuing ordinary v2 line create',
    () async {
      var idIndex = 0;
      final operationIds = <String>[_operationId1, _operationId2];
      repository = DriftHouseholdRepository(
        database,
        clock: () => now,
        deviceId: _deviceId,
        idGenerator: () => operationIds[idIndex++],
      );
      final empty = ShoppingList(
        id: _listId,
        homeId: _homeId,
        name: 'Shopping list',
        createdAt: now,
      );
      await repository.saveList(empty);
      await repository.saveList(
        empty.add(
          ShoppingListLine(
            id: _shoppingLineId,
            homeId: _homeId,
            name: 'Flour',
            quantity: 2,
            origin: ShoppingLineOrigin.suggestion,
            createdAt: now,
            suggestionId: _suggestionId,
            homeProductId: _productId,
            selectedPackId: _selectedPackId,
          ),
        ),
      );

      final projected = await repository.watchActiveList(homeId: _homeId).first;
      final line = projected.lines.single;
      expect(line.suggestionId, _suggestionId);
      expect(line.homeProductId, _productId);
      expect(line.selectedPackId, _selectedPackId);
      // ignore: deprecated_member_use_from_same_package
      expect(line.productPackId, isNull);

      final operations = await database.select(database.clientOperations).get();
      expect(operations, hasLength(2));
      final createLine = operations.singleWhere(
        (operation) => operation.operationType == 'shopping.list-line.create',
      );
      expect(jsonDecode(createLine.payload), <String, Object?>{
        'listId': _listId,
        'homeProductId': _productId,
        'description': 'Flour',
        'quantity': '2',
      });
      expect(
        operations.any(
          (operation) => operation.operationType.contains('feedback'),
        ),
        isFalse,
      );
      final link =
          await (database.select(database.localRecords)..where(
                (row) =>
                    row.entityType.equals('shopping-suggestion-line-link-v1'),
              ))
              .getSingle();
      expect(
        jsonDecode(link.payload),
        containsPair('suggestionId', _suggestionId),
      );
    },
  );
}

const _homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const _otherHomeId = '0198a0b1-c2d3-7e4f-8123-456789abcdee';
const _deviceId = '0198a0b1-c2d3-7e4f-a345-6789abcdef01';
const _productId = '0198a0b1-c2d3-7e4f-b456-789abcdef012';
const _createdProductId = '0198a0b1-c2d3-7e4f-b456-789abcdef013';
const _otherProductId = '0198a0b1-c2d3-7e4f-b456-789abcdef099';
const _sessionId = '0198a0b1-c2d3-7e4f-a567-89abcdef0123';
const _countLineId = '0198a0b1-c2d3-7e4f-9678-9abcdef01234';
const _storeId = '0198a0b1-c2d3-7e4f-a678-9abcdef01234';
const _receiptId = '0198a0b1-c2d3-7e4f-b789-abcdef012345';
const _receiptLineId = '0198a0b1-c2d3-7e4f-8789-abcdef012346';
const _listId = '0198a0b1-c2d3-7e4f-8567-89abcdef0123';
const _shoppingLineId = '0198a0b1-c2d3-7e4f-9567-89abcdef0123';
const _suggestionId = '0198a0b1-c2d3-7e4f-a567-89abcdef0124';
const _selectedPackId = '0198a0b1-c2d3-7e4f-b567-89abcdef0125';
const _operationId1 = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';
const _operationId2 = '0198a0b1-c2d3-7e4f-9234-56789abcdef1';
const _operationId3 = '0198a0b1-c2d3-7e4f-9234-56789abcdef2';
const _operationId4 = '0198a0b1-c2d3-7e4f-9234-56789abcdef3';

String _fixtureUuid(int namespace, int index) =>
    '0198a0b1-c2d3-7e4f-8${namespace.toRadixString(16).padLeft(3, '0')}-'
    '${index.toRadixString(16).padLeft(12, '0')}';

Map<String, Object?> _draftReceiptPayload() => <String, Object?>{
  'storeId': null,
  'purchaseDate': '2026-08-11',
  'currency': 'NAD',
  'totalAmount': '8.75',
  'status': 'draft',
  'source': 'manual',
  'sourceReference': 'private-receipt-photo',
  'notes': 'Retain raw unresolved evidence',
};

Map<String, Object?> _draftLinePayload() => <String, Object?>{
  'receiptId': _receiptId,
  'rawDescription': 'Unreadable till line',
  'quantity': '1',
  'originalPackText': '500 g?',
  'unitPrice': '8.75',
  'lineTotal': '8.75',
  'homeProductId': null,
  'approvalStatus': 'unreviewed',
};

Future<void> _seedDraftReceiptAndLine(
  AppDatabase database, {
  String homeId = _homeId,
}) async {
  await _seedProjection(
    database,
    homeId: homeId,
    entityType: 'purchasing-receipt',
    entityId: _receiptId,
    revision: 2,
    payload: _draftReceiptPayload(),
  );
  await _seedProjection(
    database,
    homeId: homeId,
    entityType: 'purchasing-receipt-line',
    entityId: _receiptLineId,
    revision: 1,
    payload: _draftLinePayload(),
  );
}

Future<void> _seedProjection(
  AppDatabase database, {
  required String homeId,
  required String entityType,
  required String entityId,
  required int revision,
  required Map<String, Object?> payload,
}) {
  return database
      .into(database.localRecords)
      .insert(
        LocalRecordsCompanion.insert(
          homeId: homeId,
          entityType: entityType,
          entityId: entityId,
          payload: jsonEncode(<String, Object?>{
            ...payload,
            'id': entityId,
            'revision': revision,
          }),
          revision: Value<int>(revision),
          updatedAt: DateTime.utc(2026, 8, 11, 8),
          synchronizedAt: Value<DateTime>(DateTime.utc(2026, 8, 11, 8)),
        ),
      );
}

(String, String) _baselineFixture() {
  const reviewedLinks = <int, String>{
    26: 'review-ground-coffee-jacobs-barista-classic-pack-size-pending-279',
    30: 'review-tomato-sauce-all-gold-pack-size-pending-282',
    31: 'review-tomato-sauce-pack-size-pending-283',
    32: 'review-sweet-chilli-sauce-pack-size-pending-284',
    46: 'review-oxi-laundry-stain-remover-pack-size-pending-287',
    50: 'review-thin-bleach-pack-size-pending-288',
    55: 'review-insecticide-repellent-tabard-pack-size-pending-289',
    56: 'review-air-freshener-pack-size-pending-290',
    59: 'review-steel-wool-scrubbies-pack-size-pending-292',
  };
  final reviewedStockNumbers = reviewedLinks.keys.toList(growable: false);
  final itemMaster = List<Map<String, Object?>>.generate(292, (index) {
    final reviewedIndex = index - 23;
    final reviewedStockNumber =
        reviewedIndex >= 0 && reviewedIndex < reviewedStockNumbers.length
        ? reviewedStockNumbers[reviewedIndex]
        : null;
    return <String, Object?>{
      'id': reviewedStockNumber == null
          ? 'item-$index'
          : reviewedLinks[reviewedStockNumber]!,
      'category': 'Category ${index % 12}',
      'product': reviewedStockNumber == null
          ? 'Product $index'
          : 'Reviewed product $reviewedStockNumber',
      'packSize': reviewedStockNumber == null ? '1 unit' : 'Pack size pending',
      'unit': 'units',
      'brand': reviewedStockNumber == null
          ? ''
          : 'Reviewed brand $reviewedStockNumber',
    };
  });
  final currentStock = List<Map<String, Object?>>.generate(60, (index) {
    final stockNumber = index + 1;
    final reviewed = reviewedLinks.containsKey(stockNumber);
    return <String, Object?>{
      'id': 'stock-$stockNumber',
      'category': 'Category ${index % 12}',
      'product': stockNumber <= 23
          ? 'Product $index'
          : reviewed
          ? 'Reviewed product $stockNumber'
          : 'Private product $stockNumber',
      'packSize': reviewed ? '' : '1 unit',
      'quantity': index == 59 ? 41 : 2,
      'unit': 'units',
      'brand': reviewed ? 'Reviewed brand $stockNumber' : '',
    };
  });
  final purchases = List<Map<String, Object?>>.generate(
    16,
    (index) => <String, Object?>{
      'id': 'purchase-$index',
      'date': '2026-07-${(index + 1).toString().padLeft(2, '0')}',
      'product': 'Raw purchase $index',
      'packSize': '1 unit',
      'quantity': 1,
      'totalCost': 10,
      'store': 'Fixture Store',
      'canonicalItem': index < 4 ? 'Product $index' : '',
      'canonicalPackSize': index < 4 ? '1 unit' : '',
    },
  );
  final history = List<Map<String, Object?>>.generate(
    452,
    (index) => <String, Object?>{
      'id': 'history-$index',
      'date': '2026-04-01',
      'fullName': 'Historical product ${index % 292} - 1 unit',
      'quantity': 1,
      'size': '1 unit',
      'canonicalItem': 'Product ${index % 292}',
      'canonicalPackSize': '1 unit',
    },
  );
  final monthly = List<Map<String, Object?>>.generate(
    261,
    (index) => <String, Object?>{
      'category': 'Category ${index % 12}',
      'product': 'Product $index',
      'packSize': '1 unit',
      'quantities': <String, Object?>{'2026-04': 1},
    },
  );
  final aliases = <String, Object?>{
    for (var index = 0; index < 13; index++)
      'Product $index': <String>[
        'Alias $index',
        if (index < 6) 'Alternate $index',
      ],
  };
  final rules = <String, Object?>{
    'aliases': aliases,
    'identityRules': List<Map<String, Object?>>.generate(
      19,
      (index) => <String, Object?>{
        'family': 'Family $index',
        'distinguishBy': <String>['Variant'],
      },
    ),
    'unresolvedCurrentStock': List<String>.generate(
      8,
      (index) => 'Unresolved $index',
    ),
  };
  return (
    jsonEncode(<String, Object?>{
      'itemMaster': itemMaster,
      'currentStock': currentStock,
      'purchases': purchases,
      'history': history,
      'monthlyPurchases': monthly,
    }),
    jsonEncode(rules),
  );
}
