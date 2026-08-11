import 'dart:collection';

import 'package:providentia/features/ai_integration/domain/ai_models.dart';

enum AiServerMode { manualOnly, serverProxy, localDirect }

enum AiCandidateReviewStatus { pending, accepted, rejected }

enum AiCandidateType { receiptLine, stockItem }

enum AiCandidateDecision { accept, reject }

enum AiServerFailureKind {
  authenticationRequired,
  forbidden,
  conflict,
  validation,
  unavailable,
  invalidResponse,
}

final class AiServerException implements Exception {
  const AiServerException(this.kind);

  final AiServerFailureKind kind;

  String get safeMessage => switch (kind) {
    AiServerFailureKind.authenticationRequired =>
      'Sign in again before using household AI.',
    AiServerFailureKind.forbidden =>
      'Your current household role does not allow this AI action.',
    AiServerFailureKind.conflict =>
      'AI settings changed on another device. Refresh and try again.',
    AiServerFailureKind.validation => 'Review the AI settings and try again.',
    AiServerFailureKind.unavailable =>
      'Household AI is temporarily unavailable.',
    AiServerFailureKind.invalidResponse =>
      'The AI service returned an unsafe or unexpected response.',
  };
}

/// Presentation capabilities derived from the backend's exact home permission
/// vocabulary. No capability implies another capability.
final class AiHomeCapabilities {
  const AiHomeCapabilities({
    required this.homeId,
    required this.mayRead,
    required this.mayUse,
    required this.mayManage,
  });

  factory AiHomeCapabilities.fromPermissions({
    required String homeId,
    required Set<String> permissions,
    bool active = true,
  }) {
    final normalizedHomeId = homeId.trim();
    if (!active || normalizedHomeId.isEmpty) {
      return const AiHomeCapabilities(
        homeId: '',
        mayRead: false,
        mayUse: false,
        mayManage: false,
      );
    }
    return AiHomeCapabilities(
      homeId: normalizedHomeId,
      mayRead: permissions.contains('ai.read'),
      mayUse: permissions.contains('ai.use'),
      mayManage: permissions.contains('ai.manage'),
    );
  }

  final String homeId;
  final bool mayRead;
  final bool mayUse;
  final bool mayManage;

  bool get hasAnyAccess => mayRead || mayUse || mayManage;
}

final class AiAvailableServerProvider {
  const AiAvailableServerProvider({
    required this.id,
    required this.requiresCredential,
  });

  final String id;
  final bool requiresCredential;
}

final class AiServerSettings {
  AiServerSettings({
    required this.homeId,
    required this.mode,
    required this.provider,
    required this.model,
    required this.revision,
    required List<AiAvailableServerProvider> availableProviders,
    required this.credentialEncryptionAvailable,
    required this.humanReviewRequired,
    required this.serverPersistsUploadedMedia,
  }) : availableProviders = UnmodifiableListView<AiAvailableServerProvider>(
         List<AiAvailableServerProvider>.of(availableProviders),
       ) {
    if (homeId.trim().isEmpty || revision < 0) {
      throw ArgumentError('AI settings have an invalid scope or revision.');
    }
  }

  final String homeId;
  final AiServerMode mode;
  final String? provider;
  final String? model;
  final int revision;
  final List<AiAvailableServerProvider> availableProviders;
  final bool credentialEncryptionAvailable;
  final bool humanReviewRequired;
  final bool serverPersistsUploadedMedia;

  bool supportsProvider(String providerId) =>
      availableProviders.any((provider) => provider.id == providerId);
}

final class AiOrchestrationPolicy {
  AiOrchestrationPolicy({
    required this.homeId,
    required List<String> extractionProfileIds,
    required this.validationProfileId,
    required this.maxAttempts,
    required this.maxTotalTokens,
    required this.maxEstimatedCostMicros,
    required this.revision,
  }) : extractionProfileIds = UnmodifiableListView<String>(
         List<String>.of(extractionProfileIds),
       ) {
    if (homeId.trim().isEmpty ||
        extractionProfileIds.length > 4 ||
        extractionProfileIds.toSet().length != extractionProfileIds.length ||
        maxAttempts < 1 ||
        maxAttempts > 8 ||
        maxTotalTokens < 1 ||
        maxTotalTokens > 1000000 ||
        maxEstimatedCostMicros < 0 ||
        maxEstimatedCostMicros > 1000000000 ||
        revision < 0) {
      throw ArgumentError('AI orchestration policy is invalid.');
    }
  }

  final String homeId;
  final List<String> extractionProfileIds;
  final String? validationProfileId;
  final int maxAttempts;
  final int maxTotalTokens;
  final int maxEstimatedCostMicros;
  final int revision;
}

final class AiServerWorkspace {
  AiServerWorkspace({
    required this.homeId,
    required this.settings,
    required List<AiProviderProfile> profiles,
    required this.policy,
  }) : profiles = UnmodifiableListView<AiProviderProfile>(
         List<AiProviderProfile>.of(profiles),
       ) {
    if (homeId != settings.homeId || homeId != policy.homeId) {
      throw ArgumentError('AI workspace crossed a home boundary.');
    }
    if (profiles.any((profile) => profile.homeId != homeId)) {
      throw ArgumentError('AI provider profile crossed a home boundary.');
    }
  }

  final String homeId;
  final AiServerSettings settings;
  final List<AiProviderProfile> profiles;
  final AiOrchestrationPolicy policy;

  AiProviderProfile? profile(String id) {
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }
}

final class AiSettingsUpdate {
  const AiSettingsUpdate({
    required this.mode,
    required this.provider,
    required this.model,
    required this.expectedRevision,
  });

  final AiServerMode mode;
  final String? provider;
  final String? model;
  final int expectedRevision;
}

final class AiProviderProfileDraft {
  const AiProviderProfileDraft({
    required this.id,
    required this.label,
    required this.provider,
    required this.model,
    required this.estimatedCostMicros,
    required this.expectedRevision,
  });

  /// Null creates a new server-owned profile identity.
  final String? id;
  final String label;
  final String provider;
  final String model;
  final int estimatedCostMicros;
  final int expectedRevision;
}

final class AiOrchestrationPolicyUpdate {
  AiOrchestrationPolicyUpdate({
    required List<String> extractionProfileIds,
    required this.validationProfileId,
    required this.maxAttempts,
    required this.maxTotalTokens,
    required this.maxEstimatedCostMicros,
    required this.expectedRevision,
  }) : extractionProfileIds = UnmodifiableListView<String>(
         List<String>.of(extractionProfileIds),
       );

  final List<String> extractionProfileIds;
  final String? validationProfileId;
  final int maxAttempts;
  final int maxTotalTokens;
  final int maxEstimatedCostMicros;
  final int expectedRevision;
}

final class AiReviewCandidate {
  const AiReviewCandidate({
    required this.homeId,
    required this.extractionId,
    required this.position,
    required this.type,
    required this.label,
    required this.status,
    required this.revision,
  });

  final String homeId;
  final String extractionId;
  final int position;
  final AiCandidateType type;
  final String label;
  final AiCandidateReviewStatus status;
  final int revision;
}

final class AiExtractionReview {
  AiExtractionReview({
    required this.homeId,
    required this.extractionId,
    required this.kind,
    required List<AiReviewCandidate> candidates,
  }) : candidates = UnmodifiableListView<AiReviewCandidate>(
         List<AiReviewCandidate>.of(candidates),
       ) {
    if (homeId.trim().isEmpty || extractionId.trim().isEmpty) {
      throw ArgumentError('AI extraction review has an invalid scope.');
    }
    if (candidates.any(
      (candidate) =>
          candidate.homeId != homeId || candidate.extractionId != extractionId,
    )) {
      throw ArgumentError('AI candidate crossed an extraction boundary.');
    }
  }

  final String homeId;
  final String extractionId;
  final AiExtractionKind kind;
  final List<AiReviewCandidate> candidates;

  bool get hasPending => candidates.any(
    (candidate) => candidate.status == AiCandidateReviewStatus.pending,
  );
}

/// Safe boundary between AI review and ordinary inventory/purchase commands.
/// Building this value never mutates household state.
final class AiReviewHandoff {
  AiReviewHandoff({
    required this.homeId,
    required this.extractionId,
    required this.kind,
    required List<int> acceptedPositions,
  }) : acceptedPositions = UnmodifiableListView<int>(
         List<int>.of(acceptedPositions),
       );

  final String homeId;
  final String extractionId;
  final AiExtractionKind kind;
  final List<int> acceptedPositions;

  bool get requiresOrdinaryDomainCommand => true;
}
