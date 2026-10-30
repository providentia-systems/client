import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';

void main() {
  const home = '10000000-0000-4000-8000-000000000001';
  const device = '10000000-0000-4000-8000-000000000002';
  const product = '10000000-0000-4000-8000-000000000003';
  const session = '10000000-0000-4000-8000-000000000004';
  const line = '10000000-0000-4000-8000-000000000005';
  const listId = '10000000-0000-4000-8000-000000000006';
  const pack = '10000000-0000-4000-8000-000000000007';
  var next = 100;
  late AppDatabase db;
  late DriftHouseholdRepository repository;
  final observed = DateTime.utc(2026, 10, 25, 12);
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(
      db,
      deviceId: device,
      idGenerator: () => '10000000-0000-4000-8000-${next++}'.padRight(36, '0'),
    );
  });
  tearDown(() => db.close());

  Future<void> seed(String type, String id, Map<String, Object?> value) async {
    await db
        .into(db.localRecords)
        .insert(
          LocalRecordsCompanion.insert(
            homeId: home,
            entityType: type,
            entityId: id,
            payload: jsonEncode(<String, Object?>{
              'id': id,
              'homeId': home,
              ...value,
            }),
            revision: const Value(1),
            updatedAt: observed,
            synchronizedAt: Value(observed),
          ),
        );
  }

  test(
    'count evidence survives local restart and closing preserves signed stock',
    () async {
      await seed('inventory-home-product', product, <String, Object?>{
        'privateName': 'Synthetic rice',
        'originalPackText': '1 kg',
        'unit': 'kg',
        'status': 'active',
      });
      await seed('inventory-balance', product, <String, Object?>{
        'homeProductId': product,
        'quantity': '-2.5',
        'uncertain': true,
        'pendingQuantity': '1.25',
        'limitations': <String>['unassessed-unit'],
      });
      final open = StockCountSession(
        id: session,
        homeId: home,
        locationId: 'primary',
        startedAt: observed,
        scopeComplete: false,
        reliability: 'partial',
        observedAt: observed,
        observedTimezone: 'Africa/Windhoek',
      );
      await repository.saveCountSession(open);
      await repository.saveCountSession(
        open.recordLine(
          StockCountLine(
            id: line,
            itemId: product,
            status: CountLineStatus.confirmed,
            source: CountSource.manual,
            observedQuantity: 8,
            unit: 'kg',
          ),
        ),
      );
      repository = DriftHouseholdRepository(db, deviceId: device);
      final restored = (await repository
          .watchActiveCountSession(homeId: home)
          .first)!;
      expect(restored.scopeComplete, isFalse);
      expect(restored.reliability, 'partial');
      expect(restored.observedAt, observed);
      expect(restored.observedTimezone, 'Africa/Windhoek');
      expect(restored.lines.single.unit, 'kg');
      final item = (await repository.watchItems(homeId: home).first).single;
      expect(item.currentQuantity, -2.5);
      expect(item.stockUncertain, isTrue);
      expect(item.pendingStockQuantity, '1.25');
      expect(item.stockLimitations, <String>['unassessed-unit']);
      await repository.saveCountSession(
        restored.close(observed.add(const Duration(hours: 1))),
      );
      final balance = await (db.select(
        db.localRecords,
      )..where((r) => r.entityType.equals('inventory-balance'))).getSingle();
      expect(jsonDecode(balance.payload), containsPair('quantity', '-2.5'));
      expect(
        jsonDecode(balance.payload),
        containsPair('pendingQuantity', '1.25'),
      );
      final operations = await db.select(db.clientOperations).get();
      final close = operations.singleWhere(
        (r) => r.operationType == 'inventory.count-session.close',
      );
      expect(jsonDecode(close.payload), containsPair('scopeComplete', false));
      expect(jsonDecode(close.payload), containsPair('reliability', 'partial'));
    },
  );

  test(
    'shopping readback retains pack identity and basis across mutation and restart',
    () async {
      await seed('shopping-list', listId, <String, Object?>{
        'name': 'Synthetic list',
        'status': 'open',
      });
      await seed('shopping-list-line', line, <String, Object?>{
        'listId': listId,
        'description': 'Rice',
        'quantityToBuy': '2',
        'source': 'manual',
        'checked': false,
        'homeProductId': product,
        'selectedPackId': pack,
        'productId': product,
        'stockUnit': 'kg',
        'quantityBasis': 'pack-count',
      });
      var list = (await repository.watchLists(homeId: home).first).single;
      final original = list.lines.single;
      expect(original.selectedPackId, pack);
      expect(original.productId, product);
      expect(original.stockUnit, 'kg');
      expect(original.quantityBasis, 'pack-count');
      await repository.saveList(list.toggle(line));
      repository = DriftHouseholdRepository(db, deviceId: device);
      list = (await repository.watchLists(homeId: home).first).single;
      expect(list.lines.single.checked, isTrue);
      expect(list.lines.single.quantityBasis, 'pack-count');
      expect(list.lines.single.productId, product);
      expect(list.lines.single.selectedPackId, pack);
    },
  );
}
