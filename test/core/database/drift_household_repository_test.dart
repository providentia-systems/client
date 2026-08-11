import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
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
      expect(report.exactStockMatches, 25);
      expect(report.unresolvedStockRows, 35);
      expect(report.unresolvedRecentPurchaseRows, 12);
      expect(replay.alreadyImported, isTrue);

      final items = await repository.watchItems(homeId: 'home-1').first;
      final purchases = await repository
          .watchPurchaseLines(homeId: 'home-1')
          .first;
      expect(items, hasLength(327));
      expect(purchases, hasLength(468));
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
      expect(shopping.lines.single.productPackId, _productId);
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
        productPackId: _productId,
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
const _operationId1 = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';
const _operationId2 = '0198a0b1-c2d3-7e4f-9234-56789abcdef1';
const _operationId3 = '0198a0b1-c2d3-7e4f-9234-56789abcdef2';
const _operationId4 = '0198a0b1-c2d3-7e4f-9234-56789abcdef3';

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
  final itemMaster = List<Map<String, Object?>>.generate(
    292,
    (index) => <String, Object?>{
      'id': 'item-$index',
      'category': 'Category ${index % 12}',
      'product': 'Product $index',
      'packSize': '1 unit',
      'unit': 'units',
      'brand': '',
    },
  );
  final currentStock = List<Map<String, Object?>>.generate(
    60,
    (index) => <String, Object?>{
      'id': 'stock-$index',
      'category': 'Category ${index % 12}',
      'product': index < 25 ? 'Product $index' : 'Unmatched $index',
      'packSize': '1 unit',
      'quantity': index == 59 ? 41 : 2,
      'unit': 'units',
      'brand': '',
    },
  );
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
