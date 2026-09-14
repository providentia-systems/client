import 'package:providentia/features/ai_integration/domain/ai_models.dart';

/// Private device-local references, not copies of AI results or media. A store
/// instance is permanently bound to one account and home by composition.
final class AiReviewResumeReference {
  const AiReviewResumeReference({
    required this.extractionId,
    required this.kind,
  });
  final String extractionId;
  final AiExtractionKind kind;
}

abstract interface class AiReviewResumeStore {
  Future<List<AiReviewResumeReference>> list();
  Future<void> remember(AiReviewResumeReference reference);
}
