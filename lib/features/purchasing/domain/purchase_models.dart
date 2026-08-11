enum PurchaseSource { recentReceipt, historicalImport }

enum PurchaseDatePrecision { exactDay, monthOnly }

enum PurchaseReceiptStatus { draft, committed }

enum PurchaseLineApprovalStatus {
  unreviewed,
  approved,
  approvedCatalog,
  unresolved,
}

/// `pending` is deliberately conservative: child commands may be acknowledged
/// while the optimistic parent receipt revision still awaits a receipt-level
/// acknowledgement or authoritative snapshot.
enum PurchaseSynchronizationState { synchronized, pending }

enum PurchaseMutationDisposition { queued, alreadyQueued, synchronized }

final class PurchaseMutationResult {
  const PurchaseMutationResult({
    required this.entityId,
    required this.revision,
    required this.disposition,
  });

  final String entityId;
  final int revision;
  final PurchaseMutationDisposition disposition;

  bool get awaitsServerConfirmation =>
      disposition != PurchaseMutationDisposition.synchronized;
}

final class PurchaseCaptureException implements Exception {
  const PurchaseCaptureException(this.safeMessage);

  final String safeMessage;

  @override
  String toString() => 'PurchaseCaptureException: $safeMessage';
}

final class Money implements Comparable<Money> {
  Money({required this.minorUnits, required this.currency}) {
    if (currency.trim().isEmpty) {
      throw ArgumentError.value(currency, 'currency', 'must not be empty');
    }
  }

  final int minorUnits;
  final String currency;

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits: minorUnits + other.minorUnits, currency: currency);
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits: minorUnits - other.minorUnits, currency: currency);
  }

  @override
  int compareTo(Money other) {
    _requireSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  void _requireSameCurrency(Money other) {
    if (currency != other.currency) {
      throw StateError('Cannot combine different currencies.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      minorUnits == other.minorUnits &&
      currency == other.currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);
}

/// A private, home-scoped item that a receipt line may be matched to.
///
/// Receipt text and match decisions deliberately remain outside the shared
/// catalog models.
enum PurchaseMatchCandidateKind {
  selectedCatalogPack,
  unselectedPublishedPack,
  privateHomeProduct,
}

enum PurchaseMatchBasis {
  exactDescriptionAndPack,
  exactDescriptionOrAlias,
  exactPack,
  partialDescription,
  metadataOverlap,
  itemMasterFallback,
}

final class PurchaseMatchCandidate {
  PurchaseMatchCandidate({
    required this.id,
    required this.homeId,
    required this.name,
    required this.packSize,
    this.kind = PurchaseMatchCandidateKind.selectedCatalogPack,
    String? homeProductId,
    this.productId,
    this.packId,
    this.brand = '',
    this.category = 'Uncategorized',
    List<String> aliases = const <String>[],
  }) : homeProductId =
           homeProductId ??
           (kind == PurchaseMatchCandidateKind.unselectedPublishedPack
               ? null
               : id),
       aliases = List<String>.unmodifiable(aliases) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(name, 'name');
    _requireText(packSize, 'packSize');
    if (kind == PurchaseMatchCandidateKind.unselectedPublishedPack &&
        (productId == null || packId == null || this.homeProductId != null)) {
      throw ArgumentError(
        'An unselected published pack requires product and pack identities.',
      );
    }
    if (kind != PurchaseMatchCandidateKind.unselectedPublishedPack &&
        this.homeProductId == null) {
      throw ArgumentError('A selected match requires a home product identity.');
    }
  }

  final String id;
  final String homeId;
  final String name;
  final String packSize;
  final PurchaseMatchCandidateKind kind;
  final String? homeProductId;
  final String? productId;
  final String? packId;
  final String brand;
  final String category;
  final List<String> aliases;

  bool get requiresHomeSelection =>
      kind == PurchaseMatchCandidateKind.unselectedPublishedPack;
}

final class RankedPurchaseMatchCandidate {
  const RankedPurchaseMatchCandidate({
    required this.candidate,
    required this.basis,
    required this.score,
  });

  final PurchaseMatchCandidate candidate;
  final PurchaseMatchBasis basis;
  final int score;
}

final class PurchaseReceiptLineCapture {
  PurchaseReceiptLineCapture({
    required this.id,
    required this.homeId,
    required this.receiptId,
    required this.rawDescription,
    required this.quantity,
    required this.revision,
    required this.approvalStatus,
    required this.synchronizationState,
    this.originalPackText,
    this.unitPrice,
    this.lineTotal,
    this.homeProductId,
  }) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(receiptId, 'receiptId');
    _requireText(rawDescription, 'rawDescription');
    _requirePositive(quantity, 'quantity');
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
    if ((approvalStatus == PurchaseLineApprovalStatus.approved ||
            approvalStatus == PurchaseLineApprovalStatus.approvedCatalog) &&
        homeProductId == null) {
      throw ArgumentError(
        'An approved purchase line requires a home product match.',
      );
    }
    if (approvalStatus == PurchaseLineApprovalStatus.unresolved &&
        homeProductId != null) {
      throw ArgumentError(
        'An unresolved purchase line cannot retain a home product match.',
      );
    }
  }

  final String id;
  final String homeId;
  final String receiptId;
  final String rawDescription;
  final double quantity;
  final String? originalPackText;
  final Money? unitPrice;
  final Money? lineTotal;
  final String? homeProductId;
  final int revision;
  final PurchaseLineApprovalStatus approvalStatus;
  final PurchaseSynchronizationState synchronizationState;

  bool get approved =>
      approvalStatus == PurchaseLineApprovalStatus.approved ||
      approvalStatus == PurchaseLineApprovalStatus.approvedCatalog;
  bool get unresolved =>
      approvalStatus == PurchaseLineApprovalStatus.unresolved;
  bool get reviewTerminal => approved || unresolved;
}

final class PurchaseReceiptCapture {
  PurchaseReceiptCapture({
    required this.id,
    required this.homeId,
    required this.purchaseDate,
    required this.currency,
    required this.notes,
    required this.revision,
    required this.status,
    required this.synchronizationState,
    required List<PurchaseReceiptLineCapture> lines,
    this.storeId,
    this.storeName,
    this.total,
    this.sourceReference,
  }) : lines = List<PurchaseReceiptLineCapture>.unmodifiable(lines) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireCurrency(currency);
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
    if (lines.any((line) => line.homeId != homeId || line.receiptId != id)) {
      throw StateError('A receipt capture cannot contain a foreign line.');
    }
  }

  final String id;
  final String homeId;
  final String? storeId;
  final String? storeName;
  final DateTime purchaseDate;
  final String currency;
  final Money? total;
  final String notes;
  final String? sourceReference;
  final int revision;
  final PurchaseReceiptStatus status;
  final PurchaseSynchronizationState synchronizationState;
  final List<PurchaseReceiptLineCapture> lines;

  bool get reviewComplete =>
      lines.isNotEmpty && lines.every((line) => line.reviewTerminal);
  bool get commitAwaitingConfirmation =>
      status == PurchaseReceiptStatus.committed &&
      synchronizationState == PurchaseSynchronizationState.pending;
}

final class PurchaseReceiptDraftRequest {
  PurchaseReceiptDraftRequest({
    required this.homeId,
    required this.purchaseDate,
    required this.currency,
    this.storeId,
    this.total,
    this.notes = '',
    this.sourceReference,
  }) {
    _requireText(homeId, 'homeId');
    _requireCurrency(currency);
    if (notes.length > 2000) {
      throw ArgumentError.value(
        notes,
        'notes',
        'must not exceed 2000 characters',
      );
    }
    if (total != null && total!.currency != currency) {
      throw ArgumentError('The receipt total must use the receipt currency.');
    }
    if (total != null && total!.minorUnits < 0) {
      throw ArgumentError('The receipt total must not be negative.');
    }
    if (sourceReference != null && sourceReference!.trim().length > 191) {
      throw ArgumentError.value(
        sourceReference,
        'sourceReference',
        'must not exceed 191 characters',
      );
    }
  }

  final String homeId;
  final String? storeId;
  final DateTime purchaseDate;
  final String currency;
  final Money? total;
  final String notes;
  final String? sourceReference;
}

final class PurchaseReceiptLineRequest {
  PurchaseReceiptLineRequest({
    required this.homeId,
    required this.receiptId,
    required this.rawDescription,
    required this.quantity,
    this.originalPackText,
    this.unitPrice,
    this.lineTotal,
  }) {
    _requireText(homeId, 'homeId');
    _requireText(receiptId, 'receiptId');
    final description = rawDescription.trim();
    if (description.isEmpty || description.length > 500) {
      throw ArgumentError.value(
        rawDescription,
        'rawDescription',
        'must contain 1 to 500 characters',
      );
    }
    _requirePositive(quantity, 'quantity');
    if (originalPackText != null && originalPackText!.trim().length > 191) {
      throw ArgumentError.value(
        originalPackText,
        'originalPackText',
        'must not exceed 191 characters',
      );
    }
    if (unitPrice == null && lineTotal == null) {
      throw ArgumentError('A unit price or line total is required.');
    }
    if (unitPrice != null &&
        lineTotal != null &&
        unitPrice!.currency != lineTotal!.currency) {
      throw ArgumentError('Receipt-line prices must use one currency.');
    }
    if ((unitPrice?.minorUnits ?? 0) < 0 || (lineTotal?.minorUnits ?? 0) < 0) {
      throw ArgumentError('Receipt-line prices must not be negative.');
    }
  }

  final String homeId;
  final String receiptId;
  final String rawDescription;
  final double quantity;
  final String? originalPackText;
  final Money? unitPrice;
  final Money? lineTotal;
}

final class PurchaseLine {
  PurchaseLine({
    required this.id,
    required this.homeId,
    required this.purchasedAt,
    required this.datePrecision,
    required this.storeName,
    required this.rawDescription,
    required this.packSize,
    required this.quantity,
    required this.source,
    this.receiptId,
    this.canonicalItemId,
    this.canonicalName,
    this.lineTotal,
    this.pendingSynchronization = false,
  }) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(storeName, 'storeName');
    _requireText(rawDescription, 'rawDescription');
    _requireText(packSize, 'packSize');
    _requirePositive(quantity, 'quantity');
  }

  final String id;
  final String homeId;
  final DateTime purchasedAt;
  final PurchaseDatePrecision datePrecision;
  final String storeName;
  final String rawDescription;
  final String packSize;
  final double quantity;
  final PurchaseSource source;
  final String? receiptId;
  final String? canonicalItemId;
  final String? canonicalName;
  final Money? lineTotal;
  final bool pendingSynchronization;

  String get displayName => canonicalName?.trim().isNotEmpty == true
      ? canonicalName!
      : rawDescription;
}

final class PurchaseGroup {
  PurchaseGroup({
    required this.id,
    required this.purchasedAt,
    required this.storeName,
    required List<PurchaseLine> lines,
    required this.inferred,
  }) : lines = List<PurchaseLine>.unmodifiable(lines);

  final String id;
  final DateTime purchasedAt;
  final String storeName;
  final List<PurchaseLine> lines;

  /// True when legacy data had no receipt identity and date/store grouping was
  /// used only for display parity.
  final bool inferred;

  bool get pendingSynchronization =>
      lines.any((line) => line.pendingSynchronization);

  Money? get total {
    final priced = lines.where((line) => line.lineTotal != null).toList();
    if (priced.isEmpty || priced.length != lines.length) {
      return null;
    }
    return priced
        .map((line) => line.lineTotal!)
        .reduce((left, right) => left + right);
  }
}

final class MonthlyPurchaseSummary {
  const MonthlyPurchaseSummary({
    required this.month,
    required this.lineCount,
    required this.quantity,
  });

  final DateTime month;
  final int lineCount;
  final double quantity;
}

final class PriceObservation {
  PriceObservation({
    required this.id,
    required this.homeId,
    required this.productPackId,
    required this.storeName,
    required this.observedAt,
    required this.quantity,
    required this.total,
    this.baseUnitsPerPurchasedUnit = 1,
    this.isSale = false,
  }) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(productPackId, 'productPackId');
    _requireText(storeName, 'storeName');
    _requirePositive(quantity, 'quantity');
    _requirePositive(baseUnitsPerPurchasedUnit, 'baseUnitsPerPurchasedUnit');
    if (total.minorUnits < 0) {
      throw ArgumentError.value(
        total.minorUnits,
        'total',
        'must not be negative',
      );
    }
  }

  final String id;
  final String homeId;
  final String productPackId;
  final String storeName;
  final DateTime observedAt;
  final double quantity;
  final double baseUnitsPerPurchasedUnit;
  final Money total;
  final bool isSale;

  double get minorUnitsPerBaseUnit =>
      total.minorUnits / (quantity * baseUnitsPerPurchasedUnit);
}

final class PriceStatistics {
  const PriceStatistics({
    required this.homeId,
    required this.productPackId,
    required this.currency,
    required this.observationCount,
    required this.averageMinorUnitsPerBaseUnit,
    required this.lowest,
    required this.highest,
    required this.latest,
  });

  final String homeId;
  final String productPackId;
  final String currency;
  final int observationCount;
  final double averageMinorUnitsPerBaseUnit;
  final PriceObservation lowest;
  final PriceObservation highest;
  final PriceObservation latest;
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

void _requireCurrency(String value) {
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'currency',
      'must be a three-letter uppercase ISO 4217 code',
    );
  }
}

void _requirePositive(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive and finite');
  }
}
