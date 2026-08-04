import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/household_sync/application/household_api17_ports.dart';
import 'package:providentia/features/household_sync/infrastructure/api17_online_household_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';

void main() {
  test(
    'authoritative home stock maps into the Phase 5 item projection',
    () async {
      final gateway = _FakeGateway(<Api17HomeStockRecord>[
        _stock(quantity: 4.5),
      ]);
      final repository = Api17OnlineHouseholdRepository(gateway);
      addTearDown(repository.dispose);

      final items = await repository.watchItems(homeId: 'home-1').first;

      expect(items, hasLength(1));
      expect(items.single.id, 'home-product-1');
      expect(items.single.canonicalName, 'Rice');
      expect(items.single.currentQuantity, 4.5);
      expect(items.single.isHomeProduct, isFalse);
    },
  );

  test('explicit refresh publishes a new authoritative snapshot', () async {
    final gateway = _FakeGateway(<Api17HomeStockRecord>[_stock(quantity: 1)]);
    final repository = Api17OnlineHouseholdRepository(gateway);
    addTearDown(repository.dispose);
    final snapshots = repository.watchItems(homeId: 'home-1').take(2).toList();
    await Future<void>.delayed(Duration.zero);

    gateway.records = <Api17HomeStockRecord>[_stock(quantity: 7)];
    await repository.refreshItems('home-1');

    final values = await snapshots;
    expect(values[0].single.currentQuantity, 1);
    expect(values[1].single.currentQuantity, 7);
  });

  test('cross-home response data is rejected', () async {
    final gateway = _FakeGateway(<Api17HomeStockRecord>[
      _stock(homeId: 'other-home', quantity: 1),
    ]);
    final repository = Api17OnlineHouseholdRepository(gateway);
    addTearDown(repository.dispose);

    await expectLater(
      repository.refreshItems('home-1'),
      throwsA(
        isA<HouseholdApiException>().having(
          (error) => error.kind,
          'kind',
          HouseholdApiFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test('location-scoped adjustment is explicitly unsupported', () async {
    final repository = Api17OnlineHouseholdRepository(
      _FakeGateway(<Api17HomeStockRecord>[]),
    );
    addTearDown(repository.dispose);
    final intent = ManualAdjustmentIntent(
      id: 'operation-1',
      homeId: 'home-1',
      itemId: 'home-product-1',
      locationId: 'pantry-1',
      projectedQuantity: 2,
      observedQuantity: 3,
      reason: 'Count correction',
      createdAt: DateTime.utc(2026, 8, 4),
    );

    await expectLater(
      repository.commitManualAdjustment(
        intent: intent,
        movement: intent.toMovement('movement-1'),
      ),
      throwsA(
        isA<HouseholdContractUnsupportedException>().having(
          (error) => error.operation,
          'operation',
          'commitManualAdjustment',
        ),
      ),
    );
  });
}

Api17HomeStockRecord _stock({
  String homeId = 'home-1',
  required double quantity,
}) {
  return Api17HomeStockRecord(
    id: 'home-product-1',
    homeId: homeId,
    productId: 'product-1',
    packId: 'pack-1',
    productName: 'Rice',
    originalPackText: '1 kg',
    categoryId: 'category-1',
    quantity: quantity,
    revision: 1,
  );
}

final class _FakeGateway implements HouseholdApi17Gateway {
  _FakeGateway(this.records);

  List<Api17HomeStockRecord> records;

  @override
  Future<Api17StockMovementReceipt> createHomeLevelStockAdjustment(
    Api17HomeLevelStockAdjustment adjustment,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<Api17HomeStockRecord>> listHomeStock(String homeId) async =>
      List<Api17HomeStockRecord>.of(records);
}
