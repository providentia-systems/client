import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';

void main() {
  InventoryItem item(double? quantity) => InventoryItem(
    id: 'item',
    homeId: 'home',
    canonicalName: 'Synthetic rice',
    packSize: '1 kg',
    category: 'Uncategorized',
    currentQuantity: quantity,
  );

  test('signed ledger balances remain readable without inventing evidence', () {
    for (final quantity in <double>[-3.125, 0, 2.5]) {
      expect(item(quantity).currentQuantity, quantity);
      expect(item(quantity).copyWith().currentQuantity, quantity);
    }
    expect(item(null).currentQuantity, isNull);
    expect(() => item(double.nan), throwsArgumentError);
    expect(() => item(double.infinity), throwsArgumentError);
  });

  test(
    'physical observations remain nonnegative for counts and adjustments',
    () {
      expect(
        () => StockCountLine(
          id: 'count',
          itemId: 'item',
          status: CountLineStatus.confirmed,
          source: CountSource.manual,
          observedQuantity: -1,
        ),
        throwsArgumentError,
      );
      ManualAdjustmentIntent adjustment(double observed) =>
          ManualAdjustmentIntent(
            id: 'adjustment',
            homeId: 'home',
            itemId: 'item',
            locationId: 'pantry',
            projectedQuantity: -3.125,
            observedQuantity: observed,
            reason: 'Physical observation',
            createdAt: DateTime.utc(2026, 10, 26),
          );
      expect(adjustment(0).delta, 3.125);
      expect(() => adjustment(-1), throwsArgumentError);
    },
  );
}
