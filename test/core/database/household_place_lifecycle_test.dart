import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';

const _home = '01912345-6789-7abc-8def-0123456789ab';
const _otherHome = '01912345-6789-7abc-8def-1123456789ab';
const _device = '01912345-6789-7abc-8def-2123456789ab';
String _id(int index) =>
    '01912345-6789-7abc-8def-${index.toString().padLeft(12, '0')}';

void main() {
  late AppDatabase database;
  late DriftHouseholdRepository repository;
  final at = DateTime.utc(2026, 9, 12);
  var nextId = 1;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(
      database,
      deviceId: _device,
      idGenerator: () => _id(nextId++),
      clock: () => at,
    );
  });
  tearDown(() => database.close());

  test(
    'metadata lifecycle survives adapter restart and retains revision-bound ordered commands',
    () async {
      await repository.saveHomeLocation(
        homeId: _home,
        name: 'Pantry',
        kind: 'pantry',
        archived: false,
      );
      final location =
          (await repository.watchHomeLocations(_home).first).single;
      await repository.saveHomeLocation(
        homeId: _home,
        locationId: location.id,
        name: 'Cupboard',
        kind: 'shelf',
        archived: true,
        expectedRevision: location.revision,
      );
      await repository.savePurchaseStore(
        homeId: _home,
        name: 'Grocer',
        location: 'Town',
        archived: false,
      );
      final store = (await repository.watchPurchaseStores(_home).first).single;
      await repository.savePurchaseStore(
        homeId: _home,
        storeId: store.id,
        name: 'Market',
        location: 'City',
        archived: true,
        expectedRevision: store.revision,
      );
      final restarted = DriftHouseholdRepository(
        database,
        deviceId: _device,
        clock: () => at,
      );
      final removed = (await restarted.watchHomeLocations(_home).first).single;
      expect(removed.name, 'Cupboard');
      expect(removed.kind, 'shelf');
      expect(removed.archived, isTrue);
      expect(removed.revision, 2);
      final removedStore =
          (await restarted.watchPurchaseStores(_home).first).single;
      expect(removedStore.location, 'City');
      expect(removedStore.archived, isTrue);
      await restarted.saveHomeLocation(
        homeId: _home,
        locationId: removed.id,
        name: removed.name,
        kind: removed.kind,
        archived: false,
        expectedRevision: 2,
      );
      await restarted.savePurchaseStore(
        homeId: _home,
        storeId: removedStore.id,
        name: removedStore.name,
        location: removedStore.location,
        archived: false,
        expectedRevision: 2,
      );
      expect(
        (await restarted.watchHomeLocations(_home).first).single.revision,
        3,
      );
      expect(
        (await restarted.watchPurchaseStores(_home).first).single.revision,
        3,
      );
      expect(await restarted.watchHomeLocations(_otherHome).first, isEmpty);
      expect(await restarted.watchPurchaseStores(_otherHome).first, isEmpty);
      final operations = await database.select(database.clientOperations).get();
      expect(operations.map((operation) => operation.operationType), [
        'inventory.location.create',
        'inventory.location.update',
        'purchasing.store.create',
        'purchasing.store.update',
        'inventory.location.update',
        'purchasing.store.update',
      ]);
      expect(operations.map((operation) => operation.baseRevision), [
        null,
        1,
        null,
        1,
        2,
        2,
      ]);
      for (final operation in operations) {
        expect(operation.homeId, _home);
      }
      await expectLater(
        repository.saveHomeLocation(
          homeId: _home,
          locationId: removed.id,
          name: 'Stale',
          kind: 'pantry',
          archived: false,
          expectedRevision: 1,
        ),
        throwsStateError,
      );
      await expectLater(
        repository.savePurchaseStore(
          homeId: _otherHome,
          storeId: removedStore.id,
          name: 'Wrong home',
          location: '',
          archived: false,
          expectedRevision: 3,
        ),
        throwsStateError,
      );
      expect(
        await database.select(database.clientOperations).get(),
        hasLength(6),
      );
    },
  );

  test(
    'open workflows prevent archive and references use the selected durable IDs',
    () async {
      await repository.saveHomeLocation(
        homeId: _home,
        name: 'Freezer',
        kind: 'freezer',
        archived: false,
      );
      final location =
          (await repository.watchHomeLocations(_home).first).single;
      final session = StockCountSession(
        id: _id(800),
        homeId: _home,
        locationId: location.id,
        startedAt: at,
      );
      await repository.saveCountSession(session);
      await expectLater(
        repository.saveHomeLocation(
          homeId: _home,
          locationId: location.id,
          name: location.name,
          kind: location.kind,
          archived: true,
          expectedRevision: 1,
        ),
        throwsStateError,
      );
      expect(
        (await repository.watchHomeLocations(_home).first).single.archived,
        isFalse,
      );
      await repository.saveCountSession(session.cancel());
      await repository.saveHomeLocation(
        homeId: _home,
        locationId: location.id,
        name: location.name,
        kind: location.kind,
        archived: true,
        expectedRevision: 1,
      );
      await expectLater(
        repository.saveCountSession(
          StockCountSession(
            id: _id(801),
            homeId: _home,
            locationId: location.id,
            startedAt: at,
          ),
        ),
        throwsStateError,
      );

      await repository.savePurchaseStore(
        homeId: _home,
        name: 'Grocer',
        location: 'Town',
        archived: false,
      );
      final store = (await repository.watchPurchaseStores(_home).first).single;
      await repository.createReceiptDraft(
        PurchaseReceiptDraftRequest(
          homeId: _home,
          storeId: store.id,
          purchaseDate: at,
          currency: 'NAD',
        ),
      );
      await expectLater(
        repository.savePurchaseStore(
          homeId: _home,
          storeId: store.id,
          name: store.name,
          location: store.location,
          archived: true,
          expectedRevision: 1,
        ),
        throwsStateError,
      );
      final operations = await database.select(database.clientOperations).get();
      final count = operations.singleWhere(
        (operation) =>
            operation.operationType == 'inventory.count-session.create',
      );
      final receipt = operations.singleWhere(
        (operation) => operation.operationType == 'purchasing.receipt.create',
      );
      expect(
        (jsonDecode(count.payload) as Map<String, Object?>)['locationId'],
        location.id,
      );
      expect(
        (jsonDecode(receipt.payload) as Map<String, Object?>)['storeId'],
        store.id,
      );
      expect(
        (await repository.watchPurchaseStores(_home).first).single.archived,
        isFalse,
      );
    },
  );
}
