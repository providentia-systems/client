import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';

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
