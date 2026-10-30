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

/// Metadata edits share the same atomic projection/outbox boundary as stock.
abstract interface class InventoryMetadataRepository {
  bool get supportsInventoryMetadata;
  Stream<List<HomeInventoryCategory>> watchHomeCategories(String homeId);
  Stream<List<PublishedInventoryCategory>> watchPublishedCategories(
    String homeId,
  );
  Stream<List<InventoryItem>> watchArchivedHomeProducts(String homeId);
  Future<void> saveHomeCategory({
    required String homeId,
    String? categoryId,
    required String name,
    required bool archived,
    int? expectedRevision,
  });
  Future<void> updateHomeProduct({
    required String homeId,
    required String productId,
    required String? privateName,
    String? originalPackText,
    String? homeCategoryId,
    String? globalCategoryId,
    String? unit,
    required bool archived,
    int? expectedRevision,
  });
}

/// Local evidence can prohibit a unit change, but cannot certify the absence of
/// server history. The server always makes the final revision-checked decision.
abstract interface class InventoryUnitChangeRepository {
  Future<InventoryUnitChangeEligibility> unitChangeEligibility({
    required String homeId,
    required String productId,
  });
}

/// The server AI target must be accepted before a cloud extraction uses its ID.
abstract interface class InventoryCountAcknowledgementRepository {
  Future<bool> ensureCountSessionAcknowledged({
    required String homeId,
    required String sessionId,
  });
}

/// Review accepted evidence through the existing audited synchronization command.
abstract interface class InventoryCountReviewRepository {
  Stream<List<StockCountSession>> watchCountSessions({required String homeId});
  Future<void> reviewCountSession({
    required StockCountSession session,
    required StockCountEvidence evidence,
    required String reason,
    required List<StockCountLineCorrection> corrections,
  });
}
