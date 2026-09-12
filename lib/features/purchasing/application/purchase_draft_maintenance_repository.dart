import 'package:providentia/features/purchasing/domain/purchase_models.dart';

/// Revision-bound maintenance for uncommitted receipts in the durable outbox.
abstract interface class PurchaseDraftMaintenanceRepository {
  Future<PurchaseMutationResult> updateReceiptDraft({
    required String receiptId,
    required int expectedRevision,
    required PurchaseReceiptDraftRequest draft,
  });

  Future<PurchaseMutationResult> updateReceiptDraftLine({
    required String lineId,
    required int expectedRevision,
    required PurchaseReceiptLineRequest line,
  });

  Future<PurchaseMutationResult> removeReceiptDraftLine({
    required String homeId,
    required String receiptId,
    required String lineId,
    required int expectedRevision,
  });

  Future<PurchaseMutationResult> cancelReceiptDraft({
    required String homeId,
    required String receiptId,
    required int expectedRevision,
  });
}
