import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/client_local_record_types.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';

const home = '10000000-0000-4000-8000-000000000001';
const otherHome = '10000000-0000-4000-8000-000000000002';
const device = '10000000-0000-4000-8000-000000000003';
const product = '10000000-0000-4000-8000-000000000004';
const pack = '10000000-0000-4000-8000-000000000005';
const homeProduct = '10000000-0000-4000-8000-000000000006';
const globalCategory = '10000000-0000-4000-8000-000000000007';
const localCategory = '10000000-0000-4000-8000-000000000008';

void main() {
  late AppDatabase db;
  late DriftHouseholdRepository repository;
  var nextId = 100;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(
      db,
      deviceId: device,
      idGenerator: () =>
          '10000000-0000-4000-8000-${(nextId++).toString().padLeft(12, '0')}',
    );
  });
  tearDown(() async => db.close());

  test(
    'private product edits keep identity and stock, queue fields and survive repository reopen',
    () async {
      await repository.replaceCatalogItemMaster(
        homeId: home,
        items: [],
        categories: [
          PublishedInventoryCategory(
            id: globalCategory,
            name: 'Produce',
            revision: 2,
          ),
        ],
      );
      expect(await repository.watchHomeCategories(home).first, isEmpty);
      final created = await repository.createPrivateHomeProduct(
        PrivateHomeProductDraft(
          homeId: home,
          privateName: 'Aple',
          globalCategoryId: globalCategory,
          unit: 'kg',
        ),
      );
      await _seed(db, 'inventory-balance', created.homeProductId, {
        'quantity': '3.5',
      });
      var item = (await repository.watchItems(homeId: home).first).single;
      expect(item.category, 'Produce');
      expect(item.unit, 'kg');
      await repository.updateHomeProduct(
        homeId: home,
        productId: item.id,
        privateName: 'Apple',
        originalPackText: 'Crate',
        unit: 'units',
        globalCategoryId: globalCategory,
        archived: false,
        expectedRevision: item.revision,
      );
      final reopened = DriftHouseholdRepository(db, deviceId: device);
      item = (await reopened.watchItems(homeId: home).first).single;
      expect(item.id, created.homeProductId);
      expect(item.canonicalName, 'Apple');
      expect(item.packSize, 'Crate');
      expect(item.unit, 'units');
      expect(item.currentQuantity, 3.5);
      expect(item.globalCategoryId, globalCategory);
      final operations = await db.select(db.clientOperations).get();
      expect(operations, hasLength(2));
      final payloads = operations
          .map((op) => jsonDecode(op.payload) as Map<String, dynamic>)
          .toList();
      expect(payloads.any((p) => jsonEncode(p).contains('Apple')), isTrue);
      expect(
        payloads.every((p) => jsonEncode(p).contains('globalCategoryId')),
        isTrue,
      );
      await expectLater(
        repository.updateHomeProduct(
          homeId: home,
          productId: item.id,
          privateName: 'Stale',
          archived: false,
          expectedRevision: 1,
        ),
        throwsStateError,
      );
      expect(await db.select(db.clientOperations).get(), hasLength(2));
      expect(await repository.watchItems(homeId: otherHome).first, isEmpty);
    },
  );

  for (final family in [false, true]) {
    test(
      'linked ${family ? 'family' : 'pack'} overrides do not contaminate canonical cache',
      () async {
        await _seed(db, 'inventory-home-product', homeProduct, {
          'productId': product,
          'packId': family ? null : pack,
          'privateName': 'My apple',
          'originalPackText': 'Home crate',
          'homeCategoryId': localCategory,
          'unit': 'kg',
          'status': 'active',
        });
        await _seed(db, 'inventory-home-category', localCategory, {
          'name': 'Local fruit',
          'status': 'active',
        });
        await _seed(db, 'inventory-balance', homeProduct, {'quantity': '3.5'});
        await repository.replaceCatalogItemMaster(
          homeId: home,
          items: [
            InventoryItem(
              id: homeProduct,
              homeId: home,
              canonicalName: 'My apple',
              packSize: 'Home crate',
              category: 'Local fruit',
              categorySource: InventoryCategorySource.home,
              homeCategoryId: localCategory,
              productId: product,
              packId: family ? null : pack,
              isHomeProduct: true,
              currentQuantity: 3.5,
              catalogName: 'Apple',
              catalogPackText: '',
              catalogCategoryId: globalCategory,
              catalogCategoryName: 'Produce',
            ),
          ],
          categories: [
            PublishedInventoryCategory(
              id: globalCategory,
              name: 'Produce',
              revision: 1,
            ),
          ],
        );
        var item = (await repository.watchItems(homeId: home).first).single;
        expect(item.canonicalName, 'My apple');
        expect(item.catalogName, 'Apple');
        expect(item.catalogCategoryName, 'Produce');
        expect(item.packSize, 'Home crate');
        await repository.updateHomeProduct(
          homeId: home,
          productId: homeProduct,
          privateName: null,
          originalPackText: null,
          archived: false,
          expectedRevision: 1,
        );
        item = (await repository.watchItems(homeId: home).first).single;
        expect(item.canonicalName, 'Apple');
        expect(item.packSize, 'Unspecified pack');
        expect(item.category, 'Produce');
        expect(item.currentQuantity, 3.5);
        expect(item.unit, 'kg');
        expect(item.productId, product);
        expect(item.packId, family ? isNull : pack);
        final cache =
            await (db.select(db.localRecords)..where(
                  (r) => r.entityType.equals(
                    ClientLocalRecordTypes.itemMasterCache,
                  ),
                ))
                .get();
        expect(cache, hasLength(family ? 0 : 1));
        expect(
          cache.any(
            (r) =>
                r.payload.contains('My apple') ||
                r.payload.contains('Home crate'),
          ),
          isFalse,
        );
      },
    );
  }
  test(
    'duplicate category snapshot fails atomically and retains existing offline categories',
    () async {
      final category = PublishedInventoryCategory(
        id: globalCategory,
        name: 'Produce',
        revision: 1,
      );
      await repository.replaceCatalogItemMaster(
        homeId: home,
        items: [],
        categories: [category],
      );
      await expectLater(
        repository.replaceCatalogItemMaster(
          homeId: home,
          items: [],
          categories: [category, category],
        ),
        throwsFormatException,
      );
      expect(
        (await repository.watchPublishedCategories(home).first).single.name,
        'Produce',
      );
      expect(
        await repository.watchPublishedCategories(otherHome).first,
        isEmpty,
      );
      expect(
        ClientLocalRecordTypes.synchronizationProtected,
        containsAll([
          ClientLocalRecordTypes.publishedCategoryCache,
          ClientLocalRecordTypes.catalogProductBase,
        ]),
      );
    },
  );
}

Future<void> _seed(
  AppDatabase db,
  String type,
  String id,
  Map<String, Object?> data,
) => db
    .into(db.localRecords)
    .insert(
      LocalRecordsCompanion.insert(
        homeId: home,
        entityType: type,
        entityId: id,
        payload: jsonEncode({
          ...data,
          if (type == 'inventory-balance') 'homeProductId': id,
          'id': id,
          'revision': 1,
        }),
        revision: const Value(1),
        updatedAt: DateTime.utc(2026, 9, 22),
      ),
    );
