import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';

abstract interface class ServerAiRepository {
  Future<AiServerWorkspace> loadWorkspace({required String homeId});

  Future<AiServerSettings> updateSettings({
    required String homeId,
    required AiSettingsUpdate update,
  });

  /// [credential] is write-only boundary material. Implementations must pass
  /// it directly to the request body and must never retain or return it.
  Future<AiProviderProfile> saveProviderProfile({
    required String homeId,
    required AiProviderProfileDraft draft,
    String? credential,
  });

  Future<void> deleteProviderProfile({
    required String homeId,
    required String profileId,
    required int expectedRevision,
  });

  Future<AiOrchestrationPolicy> updatePolicy({
    required String homeId,
    required AiOrchestrationPolicyUpdate update,
  });

  Future<AiExtractionReview> loadExtractionReview({
    required String homeId,
    required String extractionId,
  });

  Future<AiExtractionReview> reviewCandidate({
    required AiReviewCandidate candidate,
    required AiCandidateDecision decision,
  });
}

final class AiReviewHandoffBuilder {
  const AiReviewHandoffBuilder();

  AiReviewHandoff build(AiExtractionReview review) {
    if (review.hasPending) {
      throw const AiServerException(AiServerFailureKind.validation);
    }
    final accepted = review.candidates
        .where(
          (candidate) => candidate.status == AiCandidateReviewStatus.accepted,
        )
        .toList(growable: false);
    if (accepted.isEmpty) {
      throw const AiServerException(AiServerFailureKind.validation);
    }
    return AiReviewHandoff(
      homeId: review.homeId,
      extractionId: review.extractionId,
      kind: review.kind,
      acceptedCandidates: accepted,
    );
  }
}
