import 'dart:collection';

import 'package:providentia/features/ai_integration/domain/ai_models.dart';

enum AiServerMode { manualOnly, serverProxy, localDirect }

enum AiDirectExtractionUpload { transientNotPersisted }

enum AiPrivateMediaStorage { explicitEncryptedOptIn }

enum AiPrivateMediaRetention { transient, retained }

enum AiCandidateReviewStatus { pending, accepted, rejected }

enum AiCandidateType { receiptLine, stockItem }

enum AiCandidateDecision { accept, reject }

enum AiServerFailureKind {
  authenticationRequired,
  authorizationDenied,
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
    AiServerFailureKind.authorizationDenied =>
      'Access to this household changed. AI processing was stopped.',
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

/// Closed, server-published media behavior shown before AI transmission.
/// Direct extraction and optional private-media storage are deliberately
/// separate so a client never describes one path using the other's policy.
final class AiMediaHandling {
  AiMediaHandling({
    required this.directExtractionUpload,
    required this.privateMediaStorage,
    required Set<AiPrivateMediaRetention> privateMediaRetentionOptions,
    required this.plaintextMediaAtRest,
    required this.cloudProviderTransmissionRequiresConsent,
  }) : privateMediaRetentionOptions =
           UnmodifiableSetView<AiPrivateMediaRetention>(
             Set<AiPrivateMediaRetention>.of(privateMediaRetentionOptions),
           ) {
    if (privateMediaRetentionOptions.length != 2 ||
        !privateMediaRetentionOptions.contains(
          AiPrivateMediaRetention.transient,
        ) ||
        !privateMediaRetentionOptions.contains(
          AiPrivateMediaRetention.retained,
        ) ||
        plaintextMediaAtRest ||
        !cloudProviderTransmissionRequiresConsent) {
      throw ArgumentError('The AI media-handling policy is unsafe.');
    }
  }

  final AiDirectExtractionUpload directExtractionUpload;
  final AiPrivateMediaStorage privateMediaStorage;
  final Set<AiPrivateMediaRetention> privateMediaRetentionOptions;
  final bool plaintextMediaAtRest;
  final bool cloudProviderTransmissionRequiresConsent;
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
    required this.mediaHandling,
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
  @Deprecated('Use mediaHandling.directExtractionUpload.')
  final bool serverPersistsUploadedMedia;
  final AiMediaHandling mediaHandling;

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

/// Strict, allowlisted receipt header values returned with a reviewed
/// extraction. They remain inert until an ordinary purchasing command is
/// confirmed separately.
final class AiReceiptHeaderPayload {
  AiReceiptHeaderPayload({
    required this.merchant,
    required this.receiptNumber,
    required this.purchaseDate,
    required this.currency,
    required this.totalMinorUnits,
    required this.taxMinorUnits,
    required this.notes,
  }) {
    _boundedOptionalText(merchant, 'merchant', 191);
    _boundedOptionalText(receiptNumber, 'receiptNumber', 191);
    _boundedOptionalText(notes, 'notes', 2000);
    if (currency != null && !RegExp(r'^[A-Z]{3}$').hasMatch(currency!)) {
      throw ArgumentError.value(currency, 'currency', 'must be ISO 4217');
    }
    if ((totalMinorUnits ?? 0) < 0 || (taxMinorUnits ?? 0) < 0) {
      throw ArgumentError('Receipt amounts must not be negative.');
    }
  }

  final String? merchant;
  final String? receiptNumber;
  final DateTime? purchaseDate;
  final String? currency;
  final int? totalMinorUnits;
  final int? taxMinorUnits;
  final String? notes;
}

/// The only receipt-line fields permitted to cross from mandatory AI review
/// into the ordinary purchasing handoff.
final class AiReceiptCandidatePayload {
  AiReceiptCandidatePayload({
    required this.rawText,
    required this.description,
    required this.quantity,
    required this.packText,
    required this.unitPriceMinorUnits,
    required this.lineTotalMinorUnits,
    required this.header,
  }) {
    if (description.trim().isEmpty || description.length > 500) {
      throw ArgumentError.value(
        description,
        'description',
        'must contain 1 to 500 characters',
      );
    }
    _boundedOptionalText(rawText, 'rawText', 500);
    _boundedOptionalText(packText, 'packText', 191);
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'must be positive');
    }
    if ((unitPriceMinorUnits ?? 0) < 0 || (lineTotalMinorUnits ?? 0) < 0) {
      throw ArgumentError('Receipt-line amounts must not be negative.');
    }
  }

  final String? rawText;
  final String description;
  final double quantity;
  final String? packText;
  final int? unitPriceMinorUnits;
  final int? lineTotalMinorUnits;
  final AiReceiptHeaderPayload? header;
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
    this.receiptPayload,
  });

  final String homeId;
  final String extractionId;
  final int position;
  final AiCandidateType type;
  final String label;
  final AiCandidateReviewStatus status;
  final int revision;
  final AiReceiptCandidatePayload? receiptPayload;
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
    required List<AiReviewCandidate> acceptedCandidates,
  }) : acceptedCandidates = UnmodifiableListView<AiReviewCandidate>(
         List<AiReviewCandidate>.of(acceptedCandidates),
       ) {
    if (homeId.trim().isEmpty || extractionId.trim().isEmpty) {
      throw ArgumentError('AI review handoff has an invalid scope.');
    }
    if (acceptedCandidates.isEmpty ||
        acceptedCandidates
                .map((candidate) => candidate.position)
                .toSet()
                .length !=
            acceptedCandidates.length ||
        acceptedCandidates.any(
          (candidate) =>
              candidate.homeId != homeId ||
              candidate.extractionId != extractionId ||
              candidate.status != AiCandidateReviewStatus.accepted ||
              (kind == AiExtractionKind.receipt) !=
                  (candidate.type == AiCandidateType.receiptLine),
        )) {
      throw ArgumentError('AI review handoff contains an unsafe candidate.');
    }
  }

  final String homeId;
  final String extractionId;
  final AiExtractionKind kind;
  final List<AiReviewCandidate> acceptedCandidates;

  List<int> get acceptedPositions => List<int>.unmodifiable(
    acceptedCandidates.map((candidate) => candidate.position),
  );

  List<AiReceiptCandidatePayload> get acceptedReceiptPayloads =>
      List<AiReceiptCandidatePayload>.unmodifiable(
        acceptedCandidates
            .map((candidate) => candidate.receiptPayload)
            .whereType<AiReceiptCandidatePayload>(),
      );

  bool get requiresOrdinaryDomainCommand => true;
}

void _boundedOptionalText(String? value, String name, int maximum) {
  if (value != null && (value.trim().isEmpty || value.length > maximum)) {
    throw ArgumentError.value(
      value,
      name,
      'must contain 1 to $maximum characters',
    );
  }
}
