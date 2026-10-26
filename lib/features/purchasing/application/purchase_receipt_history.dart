import 'package:providentia/features/purchasing/domain/purchase_models.dart';

final class PurchaseReceiptHistorySnapshot {
  const PurchaseReceiptHistorySnapshot({
    required this.homeId,
    required this.receiptId,
    required this.entries,
    this.createdAt,
  });
  final String homeId;
  final String receiptId;
  final DateTime? createdAt;
  final List<PurchaseReceiptAuditEntry> entries;
}

final class PurchaseReceiptHistoryException implements Exception {
  const PurchaseReceiptHistoryException(this.safeMessage);
  final String safeMessage;
}

abstract interface class PurchaseReceiptHistoryReader {
  Future<PurchaseReceiptHistorySnapshot> load({
    required String homeId,
    required String receiptId,
  });
}

abstract interface class PurchaseReceiptHistoryRepository {
  bool get supportsReceiptHistoryRefresh;
  Future<void> refreshReceiptHistory({
    required String homeId,
    required String receiptId,
  });
}
