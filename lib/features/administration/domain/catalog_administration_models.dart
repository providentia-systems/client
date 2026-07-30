enum CatalogCapability {
  review,
  curate,
  manageIcons,
  previewMerges,
  executeMerges,
  reverseMerges,
  readAudit,
}

enum CatalogQueueKind {
  proposal,
  duplicate,
  alias,
  barcode,
  pack,
  category,
  icon,
}

enum CatalogReviewStatus { pending, inReview, approved, rejected }

enum CatalogReviewDecisionKind { recommend, approve, reject }

enum CatalogMergePlanKind { merge, reversal }

final class CatalogQueueItem {
  const CatalogQueueItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.summary,
    required this.status,
    required this.revision,
  });

  final String id;
  final CatalogQueueKind kind;
  final String title;
  final String summary;
  final CatalogReviewStatus status;
  final int revision;
}

final class CatalogModerationProposal {
  const CatalogModerationProposal({
    required this.id,
    required this.canonicalName,
    required this.locale,
    required this.status,
    required this.revision,
    this.brand,
    this.variant,
    this.packText,
    this.categoryId,
    this.barcode,
  });

  final String id;
  final String canonicalName;
  final String locale;
  final CatalogReviewStatus status;
  final int revision;
  final String? brand;
  final String? variant;
  final String? packText;
  final String? categoryId;
  final String? barcode;
}

final class CatalogReviewDecision {
  const CatalogReviewDecision({
    required this.proposalId,
    required this.decision,
    required this.reason,
    required this.expectedRevision,
  });

  final String proposalId;
  final CatalogReviewDecisionKind decision;
  final String reason;
  final int expectedRevision;
}

final class DuplicateSignal {
  const DuplicateSignal({
    required this.dimension,
    required this.leftValue,
    required this.rightValue,
    required this.score,
    required this.identityRuleConflict,
  });

  final String dimension;
  final String? leftValue;
  final String? rightValue;
  final double score;
  final bool identityRuleConflict;
}

final class DuplicateCandidate {
  const DuplicateCandidate({
    required this.id,
    required this.leftProductId,
    required this.rightProductId,
    required this.signals,
    required this.revision,
  });

  final String id;
  final String leftProductId;
  final String rightProductId;
  final List<DuplicateSignal> signals;
  final int revision;

  bool get hasIdentityRuleConflict {
    return signals.any((signal) => signal.identityRuleConflict);
  }
}

final class AliasReview {
  const AliasReview({
    required this.id,
    required this.alias,
    required this.locale,
    required this.candidateProductIds,
    required this.revision,
  });

  final String id;
  final String alias;
  final String locale;
  final List<String> candidateProductIds;
  final int revision;
}

final class BarcodeConflict {
  const BarcodeConflict({
    required this.id,
    required this.normalizedBarcode,
    required this.productIds,
    required this.revision,
  });

  final String id;
  final String normalizedBarcode;
  final List<String> productIds;
  final int revision;

  bool get requiresHumanDecision => productIds.length > 1;
}

final class PackNormalizationReview {
  const PackNormalizationReview({
    required this.id,
    required this.originalPackText,
    required this.amount,
    required this.unitCode,
    required this.baseAmount,
    required this.baseUnitCode,
    required this.revision,
  });

  final String id;
  final String originalPackText;
  final double amount;
  final String unitCode;
  final double baseAmount;
  final String baseUnitCode;
  final int revision;
}

final class CategoryReview {
  const CategoryReview({
    required this.id,
    required this.productId,
    required this.currentCategoryId,
    required this.proposedCategoryId,
    required this.revision,
  });

  final String id;
  final String productId;
  final String currentCategoryId;
  final String proposedCategoryId;
  final int revision;
}

final class CatalogIconReview {
  const CatalogIconReview({
    required this.id,
    required this.targetId,
    required this.mimeType,
    required this.sha256,
    required this.width,
    required this.height,
    required this.accessibilityLabel,
    required this.provenance,
    required this.licence,
    required this.revision,
  });

  final String id;
  final String targetId;
  final String mimeType;
  final String sha256;
  final int width;
  final int height;
  final String accessibilityLabel;
  final String provenance;
  final String licence;
  final int revision;
}

final class CatalogMergeImpact {
  const CatalogMergeImpact({
    required this.globalAliasCount,
    required this.globalPackCount,
    required this.globalBarcodeCount,
    required this.hasPrivateReferences,
  });

  final int globalAliasCount;
  final int globalPackCount;
  final int globalBarcodeCount;

  /// Deliberately opaque: no home count, identity, price, or stock is exposed.
  final bool hasPrivateReferences;
}

final class CatalogMergePreview {
  CatalogMergePreview({
    required this.previewId,
    required this.kind,
    required this.survivorProductId,
    required List<String> absorbedProductIds,
    required Map<String, int> expectedRevisions,
    required this.impact,
    required this.createdAt,
  }) : absorbedProductIds = List<String>.unmodifiable(absorbedProductIds),
       expectedRevisions = Map<String, int>.unmodifiable(expectedRevisions);

  final String previewId;
  final CatalogMergePlanKind kind;
  final String survivorProductId;
  final List<String> absorbedProductIds;
  final Map<String, int> expectedRevisions;
  final CatalogMergeImpact impact;
  final DateTime createdAt;
}

final class CatalogMergeResult {
  const CatalogMergeResult({
    required this.eventId,
    required this.idempotencyKey,
    required this.completedAt,
    required this.reversed,
  });

  final String eventId;
  final String idempotencyKey;
  final DateTime completedAt;
  final bool reversed;
}

final class CatalogAuditEvent {
  const CatalogAuditEvent({
    required this.id,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.occurredAt,
    required this.requestId,
  });

  final String id;
  final String action;
  final String targetType;
  final String targetId;
  final String reason;
  final DateTime occurredAt;
  final String requestId;
}
