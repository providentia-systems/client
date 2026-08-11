import 'package:providentia/features/inventory/domain/inventory_models.dart';

abstract interface class InventoryRepository {
  /// Emits only records visible to [homeId].
  Stream<List<InventoryItem>> watchItems({required String homeId});

  Stream<StockCountSession?> watchActiveCountSession({required String homeId});

  Future<void> saveCountSession(StockCountSession session);

  /// Persists the intent and optional ledger movement atomically.
  ///
  /// Connected adapters project the optimistic balance and queue the pinned
  /// `inventory.adjustment.create` command in the same transaction.
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  });
}

/// Narrow protocol-v2 capability for creating a home-private product identity.
abstract interface class InventoryProductCreationRepository
    implements InventoryRepository {
  bool get supportsPrivateHomeProductCreation;
  bool get supportsCatalogHomeProductCreation;

  Future<InventoryProductCreationResult> createPrivateHomeProduct(
    PrivateHomeProductDraft draft,
  );

  Future<InventoryProductCreationResult> createCatalogHomeProduct(
    CatalogHomeProductDraft draft,
  );
}
