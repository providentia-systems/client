import 'package:providentia/features/purchasing/domain/purchase_models.dart';

abstract interface class PurchaseRepository {
  Stream<List<PurchaseLine>> watchPurchaseLines({required String homeId});

  Stream<List<PriceObservation>> watchPriceObservations({
    required String homeId,
    String? productPackId,
  });
}

/// Mutating, local-first purchasing capability exposed only by repositories
/// that can persist protocol-v2 commands and their optimistic projections.
abstract interface class PurchaseCaptureRepository
    implements PurchaseRepository {
  Stream<PurchaseReceiptCapture?> watchActiveReceiptCapture({
    required String homeId,
  });

  Stream<List<PurchaseMatchCandidate>> watchPurchaseMatchCandidates({
    required String homeId,
  });

  Future<PurchaseMutationResult> createReceiptDraft(
    PurchaseReceiptDraftRequest request,
  );

  Future<PurchaseMutationResult> addReceiptLine(
    PurchaseReceiptLineRequest request,
  );

  Future<PurchaseMutationResult> approveReceiptLine({
    required String homeId,
    required String receiptId,
    required String lineId,
    required String homeProductId,
  });

  Future<PurchaseMutationResult> commitReceipt({
    required String homeId,
    required String receiptId,
  });
}
