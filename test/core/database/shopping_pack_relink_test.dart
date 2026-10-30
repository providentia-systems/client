import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';

const _home = '10000000-0000-4000-8000-000000000001';
const _device = '10000000-0000-4000-8000-000000000002';
const _product = '10000000-0000-4000-8000-000000000003';
const _family = '10000000-0000-4000-8000-000000000004';
const _basePack = '10000000-0000-4000-8000-000000000005';
const _alternate = '10000000-0000-4000-8000-000000000006';
const _badPack = '10000000-0000-4000-8000-000000000007';
const _list = '10000000-0000-4000-8000-000000000008';
const _line = '10000000-0000-4000-8000-000000000009';
final _now = DateTime.utc(2026, 10, 26);

void main() {
  late AppDatabase db;
  late DriftHouseholdRepository repository;
  var next = 100;
  DriftHouseholdRepository createRepository() => DriftHouseholdRepository(
    db,
    deviceId: _device,
    clock: () => _now,
    idGenerator: () => '10000000-0000-4000-8000-${next++}'.padRight(36, '0'),
  );
  Future<void> seed(String type, String id, Map<String, Object?> data) => db
      .into(db.localRecords)
      .insert(
        LocalRecordsCompanion.insert(
          homeId: _home,
          entityType: type,
          entityId: id,
          payload: jsonEncode({'id': id, 'homeId': _home, ...data}),
          revision: const Value(1),
          updatedAt: _now,
          synchronizedAt: Value(_now),
        ),
      );
  Future<void> fixtures() async {
    await seed('inventory-home-product', _product, {
      'productId': _family,
      'packId': _basePack,
      'privateName': 'Rice',
      'unit': 'kg',
      'status': 'active',
    });
    await seed('inventory-balance', _product, {
      'homeProductId': _product,
      'quantity': '-2.5',
    });
    await seed('shopping-list', _list, {'name': 'Groceries', 'status': 'open'});
    await repository.replaceCatalogItemMaster(
      homeId: _home,
      items: [
        for (final (id, amount, unit) in [
          (_basePack, '1000', 'g'),
          (_alternate, '500', 'g'),
          (_badPack, '1000', 'ml'),
        ])
          InventoryItem(
            id: id,
            homeId: _home,
            canonicalName: 'Rice',
            packSize: '$amount $unit',
            category: 'Groceries',
            productId: _family,
            packId: id,
            normalizedBaseAmount: amount,
            normalizedBaseUnit: unit,
            packStatus: 'published',
          ),
      ],
    );
  }

  Future<ShoppingList> list() async =>
      (await repository.watchLists(homeId: _home).first).single;
  Future<void> add({String? pack = _alternate}) async {
    final saved = await list();
    await repository.saveList(
      saved.add(
        ShoppingListLine(
          id: _line,
          homeId: _home,
          name: 'Buy sealed bags',
          quantity: 2,
          origin: ShoppingLineOrigin.manual,
          createdAt: _now,
          homeProductId: _product,
          selectedPackId: pack,
        ),
      ),
    );
  }

  Future<String> stock() async =>
      (await (db.select(db.localRecords)
                ..where((row) => row.entityType.equals('inventory-balance')))
              .getSingle())
          .payload;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = createRepository();
  });
  tearDown(() => db.close());

  test(
    'buying pack and instructions persist without changing signed stock',
    () async {
      await fixtures();
      final before = await stock();
      await add();
      final saved = (await list()).lines.single;
      expect(saved.selectedPackId, _alternate);
      expect(saved.quantityBasis, 'pack-count');
      expect(saved.stockUnit, 'kg');
      expect(saved.quantity, 2);
      expect(saved.name, 'Buy sealed bags');
      expect(saved.pending, isTrue);
      final operation = await db.select(db.clientOperations).getSingle();
      expect(
        jsonDecode(operation.payload),
        containsPair('selectedPackId', _alternate),
      );
      expect(await stock(), before);
      repository = createRepository();
      expect((await list()).lines.single.selectedPackId, _alternate);
      expect(
        (await db.select(db.clientOperations).getSingle()).operationId,
        operation.operationId,
      );
    },
  );

  test(
    'incompatible pack is rejected before projection or queue changes',
    () async {
      await fixtures();
      await expectLater(add(pack: _badPack), throwsStateError);
      expect((await list()).lines, isEmpty);
      expect(await db.select(db.clientOperations).get(), isEmpty);
    },
  );

  test(
    'relink is revision checked, explicit and preserves quantity/instructions',
    () async {
      await fixtures();
      await add();
      final before = await stock();
      await repository.relinkShoppingLine(
        homeId: _home,
        listId: _list,
        lineId: _line,
        expectedRevision: 1,
        homeProductId: _product,
        selectedPackId: _basePack,
        reason: 'Choose the larger buying pack',
      );
      final line = (await list()).lines.single;
      expect(line.name, 'Buy sealed bags');
      expect(line.quantity, 2);
      expect(line.selectedPackId, _basePack);
      expect(line.revision, 2);
      final operations = await db.select(db.clientOperations).get();
      expect(operations, hasLength(2));
      final correction = operations.last;
      expect(correction.operationType, 'shopping.list-line.relink');
      expect(correction.baseRevision, 1);
      expect(jsonDecode(correction.payload), {
        'listId': _list,
        'homeProductId': _product,
        'selectedPackId': _basePack,
        'reason': 'Choose the larger buying pack',
      });
      await expectLater(
        repository.relinkShoppingLine(
          homeId: _home,
          listId: _list,
          lineId: _line,
          expectedRevision: 1,
          homeProductId: null,
          selectedPackId: null,
          reason: 'A stale choice',
        ),
        throwsStateError,
      );
      expect(await db.select(db.clientOperations).get(), hasLength(2));
      expect(await stock(), before);
      await expectLater(
        repository.saveList(
          (await list()).copyWith(
            lines: [
              ShoppingListLine(
                id: _line,
                homeId: _home,
                name: 'Changed',
                quantity: 2,
                origin: ShoppingLineOrigin.manual,
                createdAt: _now,
                revision: 2,
                homeProductId: _product,
                selectedPackId: _alternate,
              ),
            ],
          ),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'relink to custom explicitly clears suggestion and pack metadata',
    () async {
      await fixtures();
      await seed('shopping-list-line', _line, {
        'listId': _list,
        'homeProductId': _product,
        'selectedPackId': _alternate,
        'suggestionId': _family,
        'description': 'Rice for visitors',
        'quantityToBuy': '2',
        'source': 'suggestion',
        'checked': false,
      });
      await repository.relinkShoppingLine(
        homeId: _home,
        listId: _list,
        lineId: _line,
        expectedRevision: 1,
        homeProductId: null,
        selectedPackId: null,
        reason: 'Keep this as a custom instruction',
      );
      final saved = (await list()).lines.single;
      expect(saved.homeProductId, isNull);
      expect(saved.selectedPackId, isNull);
      expect(saved.suggestionId, isNull);
      expect(saved.origin, ShoppingLineOrigin.manual);
      expect(saved.quantityBasis, 'stock-unit');
      expect(saved.name, 'Rice for visitors');
    },
  );

  test(
    'another device reads product and pack without creating stock or an outbox operation',
    () async {
      await fixtures();
      final before = await stock();
      await DriftLocalSyncRepository(db).applyPullPage(
        homeId: _home,
        page: PullPage(
          protocolVersion: 1,
          fromCursor: null,
          pageCursor: 'other-device',
          highWaterCursor: 'other-device',
          hasMore: false,
          requestId: 'synthetic-device-readback',
          changes: [
            RemoteChange(
              cursor: 'other-device',
              homeId: _home,
              entityType: 'shopping-list-line',
              entityId: _line,
              kind: RemoteChangeKind.upsert,
              revision: 4,
              serverTimestamp: _now,
              payload: {
                'listId': _list,
                'homeProductId': _product,
                'productId': _family,
                'selectedPackId': _alternate,
                'quantityBasis': 'pack-count',
                'stockUnit': 'kg',
                'description': 'Sealed packs for visitors',
                'quantityToBuy': '3',
                'source': 'manual',
                'checked': false,
              },
            ),
          ],
        ),
      );
      final line = (await list()).lines.single;
      expect(line.homeProductId, _product);
      expect(line.selectedPackId, _alternate);
      expect(line.quantityBasis, 'pack-count');
      expect(line.quantity, 3);
      expect(line.name, 'Sealed packs for visitors');
      expect(line.pending, isFalse);
      expect(await stock(), before);
      expect(await db.select(db.clientOperations).get(), isEmpty);
    },
  );

  test(
    'selection eligibility retains buying-pack semantics for units and measurements',
    () {
      expect(
        shoppingPackIsCompatible(
          stockUnit: 'units',
          selectedAmount: null,
          selectedUnit: null,
          hasBasePack: true,
          selectedIsBasePack: true,
        ),
        isTrue,
      );
      expect(
        shoppingPackIsCompatible(
          stockUnit: 'units',
          selectedAmount: '1',
          selectedUnit: 'g',
          hasBasePack: true,
          selectedIsBasePack: false,
          baseAmount: '3',
          baseUnit: 'g',
        ),
        isTrue,
      );
      expect(
        shoppingPackIsCompatible(
          stockUnit: 'units',
          selectedAmount: '500',
          selectedUnit: 'g',
          hasBasePack: false,
          selectedIsBasePack: false,
        ),
        isFalse,
      );
      expect(
        shoppingPackIsCompatible(
          stockUnit: 'kg',
          selectedAmount: '500',
          selectedUnit: 'ml',
          hasBasePack: false,
          selectedIsBasePack: false,
        ),
        isFalse,
      );
    },
  );

  test(
    'saved file restart and authoritative acknowledgement retain one relink',
    () async {
      await db.close();
      final directory = await Directory.systemTemp.createTemp('shopping-pack-');
      final file = File('${directory.path}/saved.sqlite');
      db = AppDatabase(NativeDatabase(file));
      repository = createRepository();
      try {
        await fixtures();
        await add();
        await repository.relinkShoppingLine(
          homeId: _home,
          listId: _list,
          lineId: _line,
          expectedRevision: 1,
          homeProductId: _product,
          selectedPackId: _basePack,
          reason: 'Reviewed pack choice',
        );
        final operations = await db.select(db.clientOperations).get();
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        repository = createRepository();
        expect((await list()).lines.single.selectedPackId, _basePack);
        expect(
          (await db.select(db.clientOperations).get()).map(
            (row) => row.operationId,
          ),
          operations.map((row) => row.operationId),
        );
        final sync = DriftLocalSyncRepository(db);
        await sync.applyPushResults(
          results: [
            for (var index = 0; index < operations.length; index++)
              PushOperationResult(
                operationId: operations[index].operationId,
                kind: PushResultKind.acknowledged,
                acceptedRevision: index + 1,
              ),
          ],
          now: _now,
          retryPolicy: RetryPolicy(),
        );
        await sync.applyPullPage(
          homeId: _home,
          page: PullPage(
            protocolVersion: 1,
            fromCursor: null,
            pageCursor: 'readback',
            highWaterCursor: 'readback',
            hasMore: false,
            requestId: 'synthetic',
            changes: [
              RemoteChange(
                cursor: 'readback',
                homeId: _home,
                entityType: 'shopping-list-line',
                entityId: _line,
                kind: RemoteChangeKind.upsert,
                revision: 2,
                serverTimestamp: _now,
                payload: {
                  'listId': _list,
                  'homeProductId': _product,
                  'productId': _family,
                  'selectedPackId': _basePack,
                  'stockUnit': 'kg',
                  'quantityBasis': 'pack-count',
                  'description': 'Buy sealed bags',
                  'quantityToBuy': '2',
                  'source': 'manual',
                  'checked': false,
                },
              ),
            ],
          ),
        );
        expect((await list()).lines.single.selectedPackId, _basePack);
        expect((await list()).lines.single.quantity, 2);
        expect(await db.select(db.clientOperations).get(), hasLength(2));
      } finally {
        await db.close();
        await directory.delete(recursive: true);
        db = AppDatabase(NativeDatabase.memory());
      }
    },
  );
}
