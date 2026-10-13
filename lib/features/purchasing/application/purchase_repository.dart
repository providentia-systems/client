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

  Future<PurchaseMutationResult> markReceiptLineUnresolved({
    required String homeId,
    required String receiptId,
    required String lineId,
  });

  Future<PurchaseMutationResult> commitReceipt({
    required String homeId,
    required String receiptId,
  });
}

/// A home-scoped durable intake marker projected from ordinary receipts. A
/// completed or cancelled receipt must not become another draft after restart.
final class PurchaseIntakeReceipt {
  const PurchaseIntakeReceipt({required this.id, required this.status});
  final String id;
  final String status;
}

abstract interface class PurchaseIntakeRecoveryRepository {
  Future<PurchaseIntakeReceipt?> findIntakeReceipt({
    required String homeId,
    required String sourceReference,
  });
}

/// Atomic manual confirmation and stock application, with the ordinary receipt
/// left open so the next purchase belongs to the same receipt.
abstract interface class PurchaseQuickEntryRepository {
  Future<PurchaseMutationResult> addPurchasedReceiptLine({
    required PurchaseReceiptLineRequest line,
    required String homeProductId,
    String? packId,
  });
}

/// Several independent drafts and submitted receipts may coexist in one home.
abstract interface class PurchaseReceiptSelectionRepository {
  Stream<List<PurchaseReceiptCapture>> watchReceiptCaptures({
    required String homeId,
  });
}
