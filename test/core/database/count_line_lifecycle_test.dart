import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';

void main() {
  test(
    'removal and recount preserve count identity and revision across restart',
    () async {
      const home = '01912345-6789-7abc-8def-0123456789ab';
      const device = '01912345-6789-7abc-8def-1123456789ab';
      String id(int value) =>
          '01912345-6789-7abc-8def-${value.toString().padLeft(12, '0')}';
      var next = 1;
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = DriftHouseholdRepository(
        database,
        deviceId: device,
        idGenerator: () => id(next++),
      );
      final item = await repository.createPrivateHomeProduct(
        PrivateHomeProductDraft(homeId: home, privateName: 'Rice'),
      );
      final open = StockCountSession(
        id: id(800),
        homeId: home,
        locationId: 'primary',
        startedAt: DateTime.utc(2026, 9, 12),
      );
      await repository.saveCountSession(open);
      final counted = open.recordLine(
        StockCountLine(
          id: id(801),
          itemId: item.homeProductId,
          observedQuantity: 5,
          source: CountSource.manual,
          status: CountLineStatus.confirmed,
        ),
      );
      await repository.saveCountSession(counted);
      await repository.saveCountSession(counted.removeLine(id(801)));
      final restarted = DriftHouseholdRepository(database, deviceId: device);
      final removed = await restarted
          .watchActiveCountSession(homeId: home)
          .first;
      expect(removed!.lines, isEmpty);
      expect(
        (await restarted.watchItems(homeId: home).first).single.currentQuantity,
        isNull,
      );
      var rows = await database.select(database.localRecords).get();
      final retained = rows.singleWhere(
        (row) => row.entityType == 'inventory-count-line',
      );
      expect(retained.entityId, id(801));
      expect(retained.revision, 2);
      expect(
        (jsonDecode(retained.payload) as Map<String, Object?>)['status'],
        'removed',
      );
      final recounted = removed.recordLine(
        StockCountLine(
          id: id(999),
          itemId: item.homeProductId,
          observedQuantity: 3,
          source: CountSource.manual,
          status: CountLineStatus.confirmed,
        ),
      );
      await restarted.saveCountSession(recounted);
      final current = await restarted
          .watchActiveCountSession(homeId: home)
          .first;
      expect(current!.lines.single.id, id(801));
      expect(current.lines.single.observedQuantity, 3);
      rows = await database.select(database.localRecords).get();
      expect(
        rows.where((row) => row.entityType == 'inventory-count-line'),
        hasLength(1),
      );
      final operations = await database.select(database.clientOperations).get();
      expect(operations.map((operation) => operation.operationType), [
        'inventory.home-product.create',
        'inventory.count-session.create',
        'inventory.count-line.upsert',
        'inventory.count-line.remove',
        'inventory.count-line.upsert',
      ]);
      expect(operations[3].baseRevision, 1);
      expect(operations[4].baseRevision, 2);
      expect(operations[3].entityId, operations[4].entityId);
      await restarted.saveCountSession(current.cancel());
      await expectLater(
        restarted.saveCountSession(current.removeLine(id(801))),
        throwsStateError,
      );
    },
  );
}
