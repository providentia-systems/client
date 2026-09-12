final class PurchaseStore {
  const PurchaseStore({
    required this.id,
    required this.name,
    required this.location,
    required this.revision,
    required this.archived,
  });

  final String id;
  final String name;
  final String location;
  final int revision;
  final bool archived;
}

/// Store metadata and receipt references share the durable sync outbox.
abstract interface class PurchaseStoreRepository {
  bool get supportsPurchaseStores;
  Stream<List<PurchaseStore>> watchPurchaseStores(String homeId);
  Future<void> savePurchaseStore({
    required String homeId,
    String? storeId,
    required String name,
    required String location,
    required bool archived,
    int? expectedRevision,
  });
}
