import 'package:providentia/features/ai_integration/domain/ai_models.dart';

enum AiGatewayRoute { serverProxyCloud, directStrictLocal }

enum AiGatewayReadinessState {
  ready,
  missingBackendContract,
  missingCapability,
  unavailable,
}

final class AiGatewayReadiness {
  const AiGatewayReadiness({required this.state, required this.safeMessage});

  const AiGatewayReadiness.ready()
    : state = AiGatewayReadinessState.ready,
      safeMessage = null;

  final AiGatewayReadinessState state;
  final String? safeMessage;

  bool get isReady => state == AiGatewayReadinessState.ready;
}

/// Terminal home-scoped authorization loss reported by a provider transport.
/// It intentionally carries no backend problem detail because a foreign or
/// revoked home is disclosed through the same non-identifying boundary.
final class AiGatewayAuthorizationDeniedException implements Exception {
  const AiGatewayAuthorizationDeniedException();

  String get safeMessage =>
      'Access to this household changed. AI processing was stopped.';
}

abstract interface class CredentialVault {
  bool get supportsNativeSecrets;

  Future<void> write({required String profileId, required String secret});

  Future<bool> contains(String profileId);

  Future<void> delete(String profileId);
}

abstract interface class ServerCredentialProvisioningPort {
  Future<void> replaceCredential({
    required String homeId,
    required String profileId,
    required String secret,
  });

  Future<void> deleteCredential({
    required String homeId,
    required String profileId,
  });
}

abstract interface class AiMediaPreparationPort {
  Future<PreparedMediaBatch> prepare({
    required String homeId,
    required AiExtractionKind purpose,
    required List<AiMediaAsset> assets,
  });

  Future<void> discard(PreparedMediaBatch batch);
}

abstract interface class AiProviderRepository {
  Future<List<AiProviderProfile>> listForHome(String homeId);

  Future<AiProviderProfile?> findById({
    required String homeId,
    required String providerId,
  });

  Future<void> save(AiProviderProfile profile);

  Future<void> delete({required String homeId, required String providerId});
}

abstract interface class AiProviderGateway {
  AiGatewayRoute get route;

  Future<AiGatewayReadiness> readiness(AiProviderProfile profile);

  Future<AiExtractionResult<ReceiptProposal>> extractReceipt(
    AiExtractionRequest request,
  );

  Future<AiExtractionResult<StockPhotoProposal>> extractStockPhoto(
    AiExtractionRequest request,
  );
}

abstract interface class AiGatewayResolver {
  AiProviderGateway? forRoute(AiGatewayRoute route);
}

abstract interface class AiRunRepository {
  Future<void> save(AiRunRecord run);

  Future<AiRunRecord?> findById({
    required String homeId,
    required String runId,
  });
}

abstract interface class AiProposalRepository {
  Future<void> saveReceipt({
    required String homeId,
    required ReceiptProposal proposal,
  });

  Future<ReceiptProposal?> findReceipt({
    required String homeId,
    required String proposalId,
  });

  Future<void> saveStockPhoto({
    required String homeId,
    required StockPhotoProposal proposal,
  });

  Future<StockPhotoProposal?> findStockPhoto({
    required String homeId,
    required String proposalId,
  });

  Future<void> markReceiptApproved({
    required String homeId,
    required String proposalId,
  });

  Future<void> markStockCountApproved({
    required String homeId,
    required String proposalId,
  });

  Future<void> saveReceiptCommitOutcome({
    required String homeId,
    required String idempotencyKey,
    required CommitOutcome outcome,
  });

  Future<CommitOutcome?> findReceiptCommitOutcome({
    required String homeId,
    required String idempotencyKey,
  });

  Future<void> saveCountCommitOutcome({
    required String homeId,
    required String idempotencyKey,
    required CommitOutcome outcome,
  });

  Future<CommitOutcome?> findCountCommitOutcome({
    required String homeId,
    required String idempotencyKey,
  });
}

abstract interface class CatalogCandidateLookupPort {
  Future<List<CatalogCandidate>> search({
    required String homeId,
    required String query,
    int limit = 20,
  });
}

abstract interface class ReceiptCommitPort {
  Future<CommitOutcome> commitApprovedReceipt({
    required ReviewedReceipt receipt,
    required String idempotencyKey,
  });
}

abstract interface class StockCountCommitPort {
  Future<CommitOutcome> closeApprovedCount({
    required ReviewedStockCount count,
    required String idempotencyKey,
  });
}

abstract interface class AiIdentifierFactory {
  String nextId();
}
