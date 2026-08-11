import 'package:providentia/features/administration/domain/catalog_administration_models.dart';

final class CatalogContractUnavailableException implements Exception {
  const CatalogContractUnavailableException();
}

final class CatalogForbiddenException implements Exception {
  const CatalogForbiddenException();
}

final class CatalogConflictException implements Exception {
  const CatalogConflictException();
}

final class CatalogStaleRevisionException implements Exception {
  const CatalogStaleRevisionException();
}

final class CatalogValidationException implements Exception {
  const CatalogValidationException();
}

final class CatalogUnsupportedDecisionException implements Exception {
  const CatalogUnsupportedDecisionException();
}

abstract interface class CatalogModerationRepository {
  Set<CatalogCapability> get capabilities;

  Future<List<CatalogQueueItem>> loadQueue();
}

abstract interface class CatalogAuditRepository {
  Set<CatalogCapability> get capabilities;

  Future<List<CatalogAuditEvent>> loadAudit();
}

abstract interface class CatalogProposalDecisionRepository {
  Future<CatalogModerationDecisionResult> decideProposal(
    CatalogReviewDecision decision,
  );
}

abstract interface class CatalogContributionModerationRepository {
  Future<List<CatalogQueueItem>> loadContributionQueue();

  Future<void> decideContribution(CatalogReviewDecision decision);
}

abstract interface class CatalogConflictResolutionRepository {
  Future<void> keepExistingConflict({
    required String conflictId,
    required String reason,
    required int expectedRevision,
  });
}

abstract interface class CatalogIconRepository {
  Future<CatalogRevisionResult> putIcon(CatalogIconWrite icon);
}

abstract interface class CatalogMergeRepository {
  Set<CatalogCapability> get capabilities;

  Future<CatalogMergePreview> previewMerge({
    required String survivorProductId,
    required List<String> absorbedProductIds,
  });

  Future<CatalogMergePreview> previewReversal({required String mergeEventId});

  Future<CatalogMergeResult> execute({
    required CatalogMergePreview preview,
    required String idempotencyKey,
    required String reason,
  });
}

final class UnavailableCatalogAdministrationRepository
    implements
        CatalogModerationRepository,
        CatalogAuditRepository,
        CatalogMergeRepository {
  UnavailableCatalogAdministrationRepository({
    required Set<CatalogCapability> capabilities,
  }) : capabilities = Set<CatalogCapability>.unmodifiable(capabilities);

  @override
  final Set<CatalogCapability> capabilities;

  @override
  Future<CatalogMergeResult> execute({
    required CatalogMergePreview preview,
    required String idempotencyKey,
    required String reason,
  }) {
    throw const CatalogContractUnavailableException();
  }

  @override
  Future<List<CatalogAuditEvent>> loadAudit() {
    throw const CatalogContractUnavailableException();
  }

  @override
  Future<List<CatalogQueueItem>> loadQueue() {
    throw const CatalogContractUnavailableException();
  }

  @override
  Future<CatalogMergePreview> previewMerge({
    required String survivorProductId,
    required List<String> absorbedProductIds,
  }) {
    throw const CatalogContractUnavailableException();
  }

  @override
  Future<CatalogMergePreview> previewReversal({required String mergeEventId}) {
    throw const CatalogContractUnavailableException();
  }
}
