import 'dart:collection';

enum AiProviderKind { openAi, anthropic, gemini, xAi, openAiCompatible, ollama }

enum AiTransport { serverProxy, directNative }

enum AiEndpointProtocol {
  openAiResponses,
  anthropicMessages,
  geminiGenerateContent,
  openAiChatCompletions,
  ollamaChat,
}

enum AiPrivacyMode { serverProxyCloud, strictLocal, directCloudAdvanced }

enum AiCapability {
  vision,
  strictJsonSchema,
  multiImage,
  boundingRegions,
  pdfInput,
  storeFalse,
}

enum AiProviderAvailability { available, missingBackendContract, unavailable }

enum AiExtractionKind { receipt, stockPhoto }

enum AiRunState {
  draft,
  awaitingConsent,
  processing,
  reviewRequired,
  quarantined,
  approved,
  rejected,
  failed,
  committed,
}

enum ReceiptDocumentClassification {
  receipt,
  invoice,
  medicineLeaflet,
  other,
  unknown,
}

enum StockImageClassification {
  pantryStock,
  householdStock,
  medicine,
  unrelated,
  unknown,
}

enum CatalogResolutionKind { existingPack, privateProduct, unresolved }

final class AiProviderProfile {
  AiProviderProfile({
    required this.id,
    required this.homeId,
    required this.displayName,
    required this.kind,
    required this.transport,
    required this.protocol,
    required this.model,
    required Set<AiCapability> capabilities,
    required this.availability,
    this.endpoint,
    this.credentialConfigured = false,
    this.strictLocalAttestedAt,
    this.revision = 1,
    this.enabled = true,
    this.estimatedCostMicros = 0,
  }) : capabilities = UnmodifiableSetView<AiCapability>(
         Set<AiCapability>.of(capabilities),
       ) {
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
    if (estimatedCostMicros < 0 || estimatedCostMicros > 1000000000) {
      throw ArgumentError.value(
        estimatedCostMicros,
        'estimatedCostMicros',
        'must be between 0 and 1000000000',
      );
    }
  }

  final String id;
  final String homeId;
  final String displayName;
  final AiProviderKind kind;
  final AiTransport transport;
  final AiEndpointProtocol protocol;
  final Uri? endpoint;
  final String model;
  final Set<AiCapability> capabilities;
  final AiProviderAvailability availability;
  final bool credentialConfigured;
  final DateTime? strictLocalAttestedAt;
  final int revision;
  final bool enabled;
  final int estimatedCostMicros;

  /// Provider identifier published by the server contract. This is distinct
  /// from [id], which identifies one revisioned household profile.
  String get providerWireId => switch (kind) {
    AiProviderKind.openAi => 'openai',
    AiProviderKind.anthropic => 'anthropic',
    AiProviderKind.gemini => 'gemini',
    AiProviderKind.xAi => 'xai',
    AiProviderKind.openAiCompatible => 'openai-compatible',
    AiProviderKind.ollama => 'ollama',
  };

  AiProviderProfile copyWith({
    String? displayName,
    Uri? endpoint,
    String? model,
    Set<AiCapability>? capabilities,
    AiProviderAvailability? availability,
    bool? credentialConfigured,
    DateTime? strictLocalAttestedAt,
    int? revision,
    bool? enabled,
    int? estimatedCostMicros,
  }) => AiProviderProfile(
    id: id,
    homeId: homeId,
    displayName: displayName ?? this.displayName,
    kind: kind,
    transport: transport,
    protocol: protocol,
    endpoint: endpoint ?? this.endpoint,
    model: model ?? this.model,
    capabilities: capabilities ?? this.capabilities,
    availability: availability ?? this.availability,
    credentialConfigured: credentialConfigured ?? this.credentialConfigured,
    strictLocalAttestedAt: strictLocalAttestedAt ?? this.strictLocalAttestedAt,
    revision: revision ?? this.revision,
    enabled: enabled ?? this.enabled,
    estimatedCostMicros: estimatedCostMicros ?? this.estimatedCostMicros,
  );
}

final class AiMediaAsset {
  const AiMediaAsset({
    required this.id,
    required this.homeId,
    required this.localReference,
    required this.purpose,
    required this.mimeType,
    required this.byteLength,
    required this.createdAt,
    this.pageIndex,
    this.width,
    this.height,
  });

  final String id;
  final String homeId;
  final String localReference;
  final AiExtractionKind purpose;
  final String mimeType;
  final int byteLength;
  final DateTime createdAt;
  final int? pageIndex;
  final int? width;
  final int? height;
}

final class PreparedAiMedia {
  const PreparedAiMedia({
    required this.sourceMediaId,
    required this.ephemeralReference,
    required this.previewReference,
    required this.sha256,
    required this.mimeType,
    required this.byteLength,
    required this.width,
    required this.height,
    required this.pageIndex,
  });

  final String sourceMediaId;
  final String ephemeralReference;
  final String previewReference;
  final String sha256;
  final String mimeType;
  final int byteLength;
  final int width;
  final int height;
  final int pageIndex;
}

final class PreparedMediaBatch {
  PreparedMediaBatch({
    required this.id,
    required this.homeId,
    required this.purpose,
    required List<PreparedAiMedia> media,
  }) : media = UnmodifiableListView<PreparedAiMedia>(
         List<PreparedAiMedia>.of(media),
       );

  final String id;
  final String homeId;
  final AiExtractionKind purpose;
  final List<PreparedAiMedia> media;

  List<String> get orderedHashes =>
      media.map((item) => item.sha256).toList(growable: false);
}

final class AiConsent {
  AiConsent({
    required this.providerId,
    required this.providerRevision,
    required this.privacyMode,
    required this.purpose,
    required List<String> orderedMediaHashes,
    required this.disclosureVersion,
    required this.confirmedAt,
  }) : orderedMediaHashes = UnmodifiableListView<String>(
         List<String>.of(orderedMediaHashes),
       );

  final String providerId;
  final int providerRevision;
  final AiPrivacyMode privacyMode;
  final AiExtractionKind purpose;
  final List<String> orderedMediaHashes;
  final String disclosureVersion;
  final DateTime confirmedAt;
}

final class AiExtractionRequest {
  const AiExtractionRequest({
    required this.runId,
    required this.homeId,
    required this.kind,
    required this.provider,
    required this.privacyMode,
    required this.media,
    required this.schemaVersion,
    required this.promptVersion,
    required this.timeout,
    this.targetId,
    this.maxOutputTokens = 4096,
    this.storeProviderResponse = false,
  });

  final String runId;
  final String homeId;
  final AiExtractionKind kind;
  final AiProviderProfile provider;
  final AiPrivacyMode privacyMode;
  final PreparedMediaBatch media;
  final String schemaVersion;
  final String promptVersion;
  final Duration timeout;

  /// Optional ordinary domain resource bound to this extraction. Stock-photo
  /// workflows bind this to the already-open count session.
  final String? targetId;
  final int maxOutputTokens;
  final bool storeProviderResponse;
}

final class AiRunMetadata {
  const AiRunMetadata({
    required this.providerKind,
    required this.model,
    required this.protocol,
    required this.promptVersion,
    required this.schemaVersion,
    required this.processingTime,
    this.inputTokens,
    this.outputTokens,
    this.estimatedCostMinorUnits,
    this.providerCorrelationId,
  });

  final AiProviderKind providerKind;
  final String model;
  final AiEndpointProtocol protocol;
  final String promptVersion;
  final String schemaVersion;
  final Duration processingTime;
  final int? inputTokens;
  final int? outputTokens;
  final int? estimatedCostMinorUnits;
  final String? providerCorrelationId;
}

final class AiRunRecord {
  const AiRunRecord({
    required this.id,
    required this.homeId,
    required this.kind,
    required this.providerId,
    required this.state,
    required this.createdAt,
    this.metadata,
    this.safeFailureCode,
  });

  final String id;
  final String homeId;
  final AiExtractionKind kind;
  final String providerId;
  final AiRunState state;
  final DateTime createdAt;
  final AiRunMetadata? metadata;
  final String? safeFailureCode;

  AiRunRecord withState(
    AiRunState next, {
    AiRunMetadata? metadata,
    String? safeFailureCode,
  }) => AiRunRecord(
    id: id,
    homeId: homeId,
    kind: kind,
    providerId: providerId,
    state: next,
    createdAt: createdAt,
    metadata: metadata ?? this.metadata,
    safeFailureCode: safeFailureCode,
  );
}

final class ExtractedField<T> {
  const ExtractedField({required this.value, required this.confidence});

  final T? value;
  final double confidence;
}

final class ReceiptHeaderProposal {
  const ReceiptHeaderProposal({
    required this.purchaseDate,
    required this.storeName,
    required this.receiptNumber,
    required this.currency,
    required this.subtotal,
    required this.taxTotal,
    required this.discountTotal,
    required this.total,
  });

  final ExtractedField<String> purchaseDate;
  final ExtractedField<String> storeName;
  final ExtractedField<String> receiptNumber;
  final ExtractedField<String> currency;
  final ExtractedField<String> subtotal;
  final ExtractedField<String> taxTotal;
  final ExtractedField<String> discountTotal;
  final ExtractedField<String> total;
}

final class ReceiptLineProposal {
  ReceiptLineProposal({
    required this.lineId,
    required this.rawText,
    required this.brand,
    required this.productName,
    required this.productFamily,
    required this.variant,
    required this.packDescription,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.discount,
    required this.tax,
    required this.notes,
    required this.confidence,
    required List<String> warnings,
    this.region,
  }) : warnings = UnmodifiableListView<String>(List<String>.of(warnings));

  final String lineId;
  final String rawText;
  final ExtractedField<String> brand;
  final ExtractedField<String> productName;
  final ExtractedField<String> productFamily;
  final ExtractedField<String> variant;
  final ExtractedField<String> packDescription;
  final ExtractedField<double> quantity;
  final ExtractedField<String> unitPrice;
  final ExtractedField<String> lineTotal;
  final ExtractedField<String> discount;
  final ExtractedField<String> tax;
  final ExtractedField<String> notes;
  final double confidence;
  final List<String> warnings;
  final NormalizedRegion? region;
}

final class ReceiptProposal {
  ReceiptProposal({
    required this.id,
    required this.runId,
    required this.schemaVersion,
    required this.classification,
    required this.header,
    required List<ReceiptLineProposal> lines,
    required List<String> warnings,
  }) : lines = UnmodifiableListView<ReceiptLineProposal>(
         List<ReceiptLineProposal>.of(lines),
       ),
       warnings = UnmodifiableListView<String>(List<String>.of(warnings));

  final String id;
  final String runId;
  final String schemaVersion;
  final ReceiptDocumentClassification classification;
  final ReceiptHeaderProposal header;
  final List<ReceiptLineProposal> lines;
  final List<String> warnings;

  bool get requiresQuarantine =>
      classification == ReceiptDocumentClassification.medicineLeaflet ||
      classification == ReceiptDocumentClassification.other;
}

final class NormalizedRegion {
  const NormalizedRegion({
    required this.pageIndex,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int pageIndex;
  final double x;
  final double y;
  final double width;
  final double height;
}

/// Revision-bound identity for a server-proxy stock candidate.
///
/// Strict-local proposals deliberately omit this value. Keeping this small
/// binding beside the proposal lets the inventory workflow require the
/// backend review decision before it issues an ordinary count command without
/// coupling the provider-neutral proposal model to the server repository.
enum StockCandidateServerReviewStatus { pending, accepted, rejected }

final class StockCandidateServerReviewBinding {
  StockCandidateServerReviewBinding({
    required this.extractionId,
    required this.position,
    required this.revision,
    required this.status,
  }) {
    if (extractionId.trim().isEmpty || position < 0 || revision < 1) {
      throw ArgumentError('Invalid server stock-candidate review binding.');
    }
  }

  final String extractionId;
  final int position;
  final int revision;
  final StockCandidateServerReviewStatus status;
}

final class StockCandidateProposal {
  StockCandidateProposal({
    required this.candidateId,
    required this.brand,
    required this.productName,
    required this.variant,
    required this.packDescription,
    required this.quantityMinimum,
    required this.quantityMaximum,
    required this.confidence,
    required List<String> warnings,
    this.region,
    this.serverReview,
  }) : warnings = UnmodifiableListView<String>(List<String>.of(warnings));

  final String candidateId;
  final ExtractedField<String> brand;
  final ExtractedField<String> productName;
  final ExtractedField<String> variant;
  final ExtractedField<String> packDescription;
  final double quantityMinimum;
  final double quantityMaximum;
  final double confidence;
  final List<String> warnings;
  final NormalizedRegion? region;
  final StockCandidateServerReviewBinding? serverReview;
}

final class StockPhotoProposal {
  StockPhotoProposal({
    required this.id,
    required this.runId,
    required this.schemaVersion,
    required this.classification,
    required List<StockCandidateProposal> candidates,
    required List<String> warnings,
  }) : candidates = UnmodifiableListView<StockCandidateProposal>(
         List<StockCandidateProposal>.of(candidates),
       ),
       warnings = UnmodifiableListView<String>(List<String>.of(warnings));

  final String id;
  final String runId;
  final String schemaVersion;
  final StockImageClassification classification;
  final List<StockCandidateProposal> candidates;
  final List<String> warnings;

  bool get requiresQuarantine =>
      classification == StockImageClassification.medicine ||
      classification == StockImageClassification.unrelated;
}

sealed class AiExtractionResult<T> {
  const AiExtractionResult();
}

final class AiExtractionSuccess<T> extends AiExtractionResult<T> {
  const AiExtractionSuccess({required this.proposal, required this.metadata});

  final T proposal;
  final AiRunMetadata metadata;
}

final class AiExtractionRefused<T> extends AiExtractionResult<T> {
  const AiExtractionRefused({required this.safeReason});

  final String safeReason;
}

final class AiExtractionIncomplete<T> extends AiExtractionResult<T> {
  const AiExtractionIncomplete({required this.safeReason});

  final String safeReason;
}

final class AiExtractionFailure<T> extends AiExtractionResult<T> {
  const AiExtractionFailure({
    required this.code,
    required this.safeMessage,
    this.retryAfter,
  });

  final String code;
  final String safeMessage;
  final Duration? retryAfter;
}

final class AiExtractionQuarantined<T> extends AiExtractionResult<T> {
  const AiExtractionQuarantined({required this.classification});

  final String classification;
}

final class CatalogCandidate {
  const CatalogCandidate({
    required this.packId,
    required this.productName,
    required this.packDescription,
    required this.isPrivateToHome,
  });

  final String packId;
  final String productName;
  final String packDescription;
  final bool isPrivateToHome;
}

final class CatalogResolution {
  const CatalogResolution({
    required this.kind,
    this.packId,
    this.privateProductName,
  });

  final CatalogResolutionKind kind;
  final String? packId;
  final String? privateProductName;
}

final class ReviewedReceiptLine {
  const ReviewedReceiptLine({
    required this.proposalLineId,
    required this.resolution,
    required this.quantity,
    this.unitPrice,
    this.lineTotal,
  });

  final String proposalLineId;
  final CatalogResolution resolution;
  final double quantity;
  final String? unitPrice;
  final String? lineTotal;
}

final class ReviewedReceipt {
  ReviewedReceipt({
    required this.proposalId,
    required this.runId,
    required this.homeId,
    required this.approvedBy,
    required this.approvedAt,
    required this.humanConfirmed,
    required List<ReviewedReceiptLine> lines,
  }) : lines = UnmodifiableListView<ReviewedReceiptLine>(
         List<ReviewedReceiptLine>.of(lines),
       );

  final String proposalId;
  final String runId;
  final String homeId;
  final String approvedBy;
  final DateTime approvedAt;
  final bool humanConfirmed;
  final List<ReviewedReceiptLine> lines;
}

final class ConfirmedStockItem {
  const ConfirmedStockItem({
    required this.proposalCandidateId,
    required this.resolution,
    required this.quantity,
  });

  final String proposalCandidateId;
  final CatalogResolution resolution;
  final double quantity;
}

final class ReviewedStockCount {
  ReviewedStockCount({
    required this.proposalId,
    required this.runId,
    required this.homeId,
    required this.sessionId,
    required this.locationId,
    required this.closedBy,
    required this.closedAt,
    required this.explicitlyClosed,
    required List<ConfirmedStockItem> items,
  }) : items = UnmodifiableListView<ConfirmedStockItem>(
         List<ConfirmedStockItem>.of(items),
       );

  final String proposalId;
  final String runId;
  final String homeId;
  final String sessionId;
  final String locationId;
  final String closedBy;
  final DateTime closedAt;
  final bool explicitlyClosed;
  final List<ConfirmedStockItem> items;
}

final class CommitOutcome {
  const CommitOutcome({
    required this.resourceId,
    required this.alreadyCommitted,
  });

  final String resourceId;
  final bool alreadyCommitted;
}
