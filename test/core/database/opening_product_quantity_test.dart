import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/client_local_record_types.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/domain/inventory_services.dart';

const _home = '10000000-0000-4000-8000-000000000001';
const _device = '10000000-0000-4000-8000-000000000002';
const _identity = '10000000-0000-4000-8000-000000000003';
const _product = '10000000-0000-4000-8000-000000000004';
const _pack = '10000000-0000-4000-8000-000000000005';

void main() {
  late AppDatabase db;
  late DriftHouseholdRepository repository;
  final now = DateTime.utc(2026, 10, 26, 12);
  var nextId = 100;
  String next() =>
      '10000000-0000-4000-8000-${(nextId++).toString().padLeft(12, '0')}';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(
      db,
      deviceId: _device,
      idGenerator: next,
      clock: () => now,
    );
  });
  tearDown(() => db.close());

  Future<InventoryProductCreationResult> create(
    bool catalog,
    double? quantity,
  ) async {
    if (!catalog) {
      return repository.createPrivateHomeProduct(
        PrivateHomeProductDraft(
          homeId: _home,
          privateName: 'Rice',
          unit: 'kg',
          clientProductId: _identity,
          openingQuantity: quantity,
          openingObservedAt: quantity == null ? null : now,
          openingCountConfirmed: quantity != null,
        ),
      );
    }
    return repository.createCatalogHomeProduct(
      CatalogHomeProductDraft(
        homeId: _home,
        productId: _product,
        packId: _pack,
        canonicalName: 'Rice',
        packSize: '1 kg',
        category: 'Food',
        clientProductId: _identity,
        openingQuantity: quantity,
        openingObservedAt: quantity == null ? null : now,
        openingCountConfirmed: quantity != null,
      ),
    );
  }

  for (final catalog in [false, true]) {
    for (final quantity in <double?>[null, 0, 2.5]) {
      test(
        '${catalog ? 'catalog' : 'private'} quantity $quantity queues once in dependency order across restart',
        () async {
          if (catalog) {
            await repository.replaceCatalogItemMaster(
              homeId: _home,
              items: [
                InventoryItem(
                  id: _pack,
                  homeId: _home,
                  canonicalName: 'Rice',
                  packSize: '1 kg',
                  category: 'Food',
                  productId: _product,
                  packId: _pack,
                ),
              ],
            );
          }
          final first = await create(catalog, quantity);
          var operations = await (db.select(
            db.clientOperations,
          )..orderBy([(row) => OrderingTerm.asc(row.enqueueSequence)])).get();
          expect(
            operations.map((op) => op.operationType),
            quantity == null
                ? ['inventory.home-product.create']
                : [
                    'inventory.home-product.create',
                    'inventory.count-session.create',
                    'inventory.count-line.upsert',
                    'inventory.count-session.close',
                  ],
          );
          final originalIds = operations.map((op) => op.operationId).toList();
          if (quantity != null) {
            final line =
                jsonDecode(operations[2].payload) as Map<String, Object?>;
            expect(line['homeProductId'], _identity);
            expect(line['quantity'], quantity == 0 ? '0' : '2.5');
            final session =
                jsonDecode(operations[1].payload) as Map<String, Object?>;
            expect(session['scopeComplete'], isFalse);
            expect(session['reliability'], 'partial');
            expect(session['locationId'], isNull);
            expect(session['observedAt'], now.toIso8601String());
          }
          // No fabricated factual balance: actual quantities arrive via count readback.
          final item = (await repository.watchItems(homeId: _home).first)
              .singleWhere((item) => item.isHomeProduct);
          expect(item.currentQuantity, isNull);
          expect(item.isCounted, isFalse);
          expect(
            const InventoryItemSearch().filter([
              item,
            ], const InventorySearchCriteria()),
            quantity == null ? isEmpty : hasLength(1),
          );
          expect(
            item.pendingOpeningQuantity,
            quantity == null
                ? isNull
                : quantity == 0
                ? '0'
                : '2.5',
          );
          repository = DriftHouseholdRepository(
            db,
            deviceId: _device,
            idGenerator: next,
            clock: () => now,
          );
          final repeated = await create(catalog, quantity);
          expect(repeated.homeProductId, first.homeProductId);
          operations = await (db.select(
            db.clientOperations,
          )..orderBy([(row) => OrderingTerm.asc(row.enqueueSequence)])).get();
          expect(operations.map((op) => op.operationId), originalIds);
          expect(
            await (db.select(db.localRecords)..where(
                  (row) => row.entityType.equals('inventory-home-product'),
                ))
                .get(),
            hasLength(1),
          );
          expect(
            await repository
                .watchItems(homeId: '10000000-0000-4000-8000-000000000009')
                .first,
            isEmpty,
          );
          // Rebuild preserves exact queued creation/count commands and pending values.
          final local = DriftLocalSyncRepository(db);
          await local.replaceWithBootstrap(
            homeId: _home,
            page: PullPage(
              protocolVersion: 1,
              fromCursor: 'synthetic',
              changes: [],
              pageCursor: 'synthetic',
              highWaterCursor: 'synthetic',
              hasMore: false,
              requestId: 'synthetic-request',
            ),
          );
          expect(
            await (db.select(db.localRecords)..where(
                  (row) => row.entityType.equals(
                    ClientLocalRecordTypes.inventoryCreation,
                  ),
                ))
                .get(),
            hasLength(1),
          );
          final restored = (await repository.watchItems(homeId: _home).first)
              .singleWhere((item) => item.isHomeProduct);
          expect(restored.pendingOpeningQuantity, item.pendingOpeningQuantity);
        },
      );
    }
  }

  test(
    'one-product opening observation never certifies or zeros other home stock',
    () async {
      const otherProduct = '10000000-0000-4000-8000-000000000009';
      await db
          .into(db.localRecords)
          .insert(
            LocalRecordsCompanion.insert(
              homeId: _home,
              entityType: 'inventory-home-product',
              entityId: otherProduct,
              payload: jsonEncode({
                'id': otherProduct,
                'privateName': 'Other stock',
                'unit': 'units',
                'status': 'active',
              }),
              updatedAt: now,
              synchronizedAt: Value(now),
            ),
          );
      await db
          .into(db.localRecords)
          .insert(
            LocalRecordsCompanion.insert(
              homeId: _home,
              entityType: 'inventory-balance',
              entityId: otherProduct,
              payload: jsonEncode({
                'homeProductId': otherProduct,
                'quantity': '8',
              }),
              updatedAt: now,
              synchronizedAt: Value(now),
            ),
          );
      await create(false, 2.5);
      final operations = await (db.select(
        db.clientOperations,
      )..orderBy([(row) => OrderingTerm.asc(row.enqueueSequence)])).get();
      final start = jsonDecode(operations[1].payload) as Map<String, Object?>;
      final close = jsonDecode(operations[3].payload) as Map<String, Object?>;
      expect(start['scopeComplete'], isFalse);
      expect(start['reliability'], 'partial');
      expect(close['scopeComplete'], isFalse);
      expect(close['reliability'], 'partial');
      final lines = await (db.select(
        db.localRecords,
      )..where((row) => row.entityType.equals('inventory-count-line'))).get();
      expect(lines, hasLength(1));
      expect(
        jsonDecode(lines.single.payload),
        containsPair('homeProductId', _identity),
      );
      final balances = await (db.select(
        db.localRecords,
      )..where((row) => row.entityType.equals('inventory-balance'))).get();
      expect(balances, hasLength(1));
      expect(
        jsonDecode(balances.single.payload),
        containsPair('quantity', '8'),
      );
      final items = await repository.watchItems(homeId: _home).first;
      expect(
        items.singleWhere((item) => item.id == otherProduct).currentQuantity,
        8,
      );
      expect(
        items.singleWhere((item) => item.id == _identity).currentQuantity,
        isNull,
      );
    },
  );

  test(
    'partial count acknowledgement keeps the opening observation visible until assessed stock readback',
    () async {
      await create(false, 0);
      await (db.update(db.localRecords)
            ..where((row) => row.entityType.equals('inventory-count-session')))
          .write(LocalRecordsCompanion(synchronizedAt: Value(now)));
      var item = (await repository.watchItems(homeId: _home).first).single;
      expect(item.pendingOpeningQuantity, '0');
      expect(item.isCounted, isFalse);
      await db
          .into(db.localRecords)
          .insert(
            LocalRecordsCompanion.insert(
              homeId: _home,
              entityType: 'inventory-balance',
              entityId: _identity,
              payload: jsonEncode({
                'homeProductId': _identity,
                'quantity': '0',
                'uncertain': false,
              }),
              updatedAt: now,
              synchronizedAt: Value(now),
            ),
          );
      item = (await repository.watchItems(homeId: _home).first).single;
      expect(item.currentQuantity, 0);
      expect(item.pendingOpeningQuantity, isNull);
    },
  );

  test(
    'invalid or unconfirmed opening values cannot create a product',
    () async {
      for (final quantity in [-1.0, double.nan, double.infinity]) {
        expect(
          () => PrivateHomeProductDraft(
            homeId: _home,
            privateName: 'Rice',
            openingQuantity: quantity,
            openingObservedAt: now,
            openingCountConfirmed: true,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => PrivateHomeProductDraft(
          homeId: _home,
          privateName: 'Rice',
          openingQuantity: 0,
          openingObservedAt: now,
        ),
        throwsArgumentError,
      );
      expect(await db.select(db.localRecords).get(), isEmpty);
      expect(await db.select(db.clientOperations).get(), isEmpty);
    },
  );

  test(
    'dependent count failure rolls back product and permits exact request retry',
    () async {
      var calls = 0;
      repository = DriftHouseholdRepository(
        db,
        deviceId: _device,
        clock: () => now,
        idGenerator: () => ++calls == 3 ? 'invalid-id' : next(),
      );
      await expectLater(create(false, 0), throwsArgumentError);
      expect(await db.select(db.localRecords).get(), isEmpty);
      expect(await db.select(db.clientOperations).get(), isEmpty);
      repository = DriftHouseholdRepository(
        db,
        deviceId: _device,
        clock: () => now,
        idGenerator: next,
      );
      await create(false, 0);
      expect(await db.select(db.clientOperations).get(), hasLength(4));
    },
  );
}
