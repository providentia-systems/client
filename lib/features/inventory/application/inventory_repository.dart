import 'package:providentia/features/inventory/domain/inventory_models.dart';

abstract interface class InventoryRepository {
  /// Emits only records visible to [homeId].
  Stream<List<InventoryItem>> watchItems({required String homeId});

  Stream<StockCountSession?> watchActiveCountSession({required String homeId});

  Future<void> saveCountSession(StockCountSession session);

  /// Persists the intent and optional ledger movement atomically.
  ///
  /// The adapter must not queue an unsupported synchronization entity until
  /// the pinned backend contract publishes that entity type.
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  });
}
