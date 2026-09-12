import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/inventory/application/stock_preference_repository.dart';
import 'package:providentia/features/inventory/domain/stock_preference.dart';

const _home = '00000000-0000-4000-8000-000000000001';
const _product = '00000000-0000-4000-8000-000000000002';
const _device = '00000000-0000-4000-8000-000000000003';

void main() {
  late AppDatabase database;
  late _Reader reader;
  late DriftHouseholdRepository repository;
  final at = DateTime.utc(2026, 9, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    reader = _Reader();
    repository = DriftHouseholdRepository(
      database,
      deviceId: _device,
      stockPreferenceReader: reader,
    );
    for (final entry in <String, Map<String, Object?>>{
      'inventory-home-product': {'status': 'active', 'privateName': 'Rice'},
      'inventory-balance': {'quantity': '8', 'lastMovementId': 'retained'},
    }.entries) {
      await database
          .into(database.localRecords)
          .insert(
            LocalRecordsCompanion.insert(
              homeId: _home,
              entityType: entry.key,
              entityId: _product,
              payload: jsonEncode(entry.value),
              revision: const Value(1),
              updatedAt: at,
            ),
          );
    }
  });
  tearDown(() => database.close());

  test(
    'server revision and exact minimum survive pending restart without changing stock',
    () async {
      final loaded = await repository.loadStockPreference(
        homeId: _home,
        productId: _product,
      );
      expect(loaded.revision, 7);
      await repository.saveStockPreference(
        _policy(loaded.revision, minimum: '4.00000001'),
      );
      final operations = await database.select(database.clientOperations).get();
      expect(operations, hasLength(1));
      expect(operations.single.baseRevision, 7);
      expect(operations.single.operationType, 'shopping.preference.put');
      expect(
        (jsonDecode(operations.single.payload)
            as Map<String, Object?>)['minimumQuantity'],
        '4.00000001',
      );
      final restarted = DriftHouseholdRepository(
        database,
        deviceId: _device,
        stockPreferenceReader: reader,
      );
      final pending = await restarted.loadStockPreference(
        homeId: _home,
        productId: _product,
      );
      expect(pending.minimumQuantity, '4.00000001');
      expect(pending.revision, 8);
      expect(reader.calls, 1);
      final balance = await (database.select(
        database.localRecords,
      )..where((r) => r.entityType.equals('inventory-balance'))).getSingle();
      expect(
        (jsonDecode(balance.payload) as Map<String, Object?>)['quantity'],
        '8',
      );
      expect(
        (jsonDecode(balance.payload) as Map<String, Object?>)['lastMovementId'],
        'retained',
      );
      await expectLater(
        restarted.saveStockPreference(loaded),
        throwsStateError,
      );
      expect(
        await database.select(database.clientOperations).get(),
        hasLength(1),
      );
    },
  );

  test('in-flight read cannot overwrite a newer durable edit', () async {
    final loaded = await repository.loadStockPreference(
      homeId: _home,
      productId: _product,
    );
    final waiting = Completer<StockPreference>();
    reader.next = () => waiting.future;
    final refresh = repository.loadStockPreference(
      homeId: _home,
      productId: _product,
    );
    await Future<void>.delayed(Duration.zero);
    await repository.saveStockPreference(
      _policy(loaded.revision, minimum: '12'),
    );
    waiting.complete(loaded);
    expect((await refresh).minimumQuantity, '12');
  });

  test(
    'offline fallback uses verified policy and never hides authorization failure',
    () async {
      await repository.loadStockPreference(homeId: _home, productId: _product);
      reader.next = () => throw const StockPreferenceUnavailable();
      expect(
        (await repository.loadStockPreference(
          homeId: _home,
          productId: _product,
        )).revision,
        7,
      );
      reader.next = () => throw StateError('Authorization revoked');
      await expectLater(
        repository.loadStockPreference(homeId: _home, productId: _product),
        throwsStateError,
      );
      expect(await database.select(database.clientOperations).get(), isEmpty);
    },
  );

  test(
    'unknown offline preference is not replaced by invented defaults',
    () async {
      reader.next = () => throw const StockPreferenceUnavailable();
      await expectLater(
        repository.loadStockPreference(homeId: _home, productId: _product),
        throwsA(isA<StockPreferenceUnavailable>()),
      );
      expect(await database.select(database.clientOperations).get(), isEmpty);
    },
  );

  test(
    'cross-home response is rejected without caching or writing intent',
    () async {
      reader.next = () async => StockPreference(
        homeId: _device,
        homeProductId: _product,
        revision: 7,
      );
      await expectLater(
        repository.loadStockPreference(homeId: _home, productId: _product),
        throwsStateError,
      );
      final preferences = await (database.select(
        database.localRecords,
      )..where((r) => r.entityType.equals('shopping-stock-preference'))).get();
      expect(preferences, isEmpty);
      expect(await database.select(database.clientOperations).get(), isEmpty);
    },
  );
  test('a late response cannot recreate data after home revocation', () async {
    final waiting = Completer<StockPreference>();
    reader.next = () => waiting.future;
    final loading = repository.loadStockPreference(
      homeId: _home,
      productId: _product,
    );
    await Future<void>.delayed(Duration.zero);
    await (database.delete(
      database.localRecords,
    )..where((row) => row.homeId.equals(_home))).go();
    waiting.complete(_policy(7));
    await expectLater(loading, throwsStateError);
    expect(await database.select(database.localRecords).get(), isEmpty);
  });
}

StockPreference _policy(int revision, {String minimum = '5'}) =>
    StockPreference(
      homeId: _home,
      homeProductId: _product,
      revision: revision,
      minimumQuantity: minimum,
      alwaysKeep: true,
      leadTimeDays: 2,
      targetCoverageDays: 14,
    );

final class _Reader implements StockPreferenceReader {
  int calls = 0;
  Future<StockPreference> Function()? next;
  @override
  Future<StockPreference> read({
    required String homeId,
    required String productId,
  }) {
    calls++;
    return next?.call() ?? Future.value(_policy(7));
  }
}
