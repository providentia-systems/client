import 'package:providentia/features/inventory/presentation/inventory_controller.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/shopping/presentation/shopping_controller.dart';

/// Constructor-injected Phase 5 household feature composition.
///
/// Keeping this bundle separate from [AppController] prevents navigation and
/// synchronization state from becoming a service locator for feature data.
final class HouseholdFeatures {
  const HouseholdFeatures({
    required this.inventory,
    required this.purchasing,
    required this.shopping,
  });

  final InventoryController inventory;
  final PurchasingController purchasing;
  final ShoppingController shopping;

  void start() {
    inventory.start();
    purchasing.start();
    shopping.start();
  }

  void dispose() {
    inventory.dispose();
    purchasing.dispose();
    shopping.dispose();
  }
}
