import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';

AiProviderProfile serverProvider({
  int revision = 1,
  AiProviderAvailability availability = AiProviderAvailability.available,
}) => AiProviderProfile(
  id: 'provider-1',
  homeId: 'home-1',
  displayName: 'OpenAI via Providentia',
  kind: AiProviderKind.openAi,
  transport: AiTransport.serverProxy,
  protocol: AiEndpointProtocol.openAiResponses,
  model: 'gpt-5-mini',
  capabilities: <AiCapability>{
    AiCapability.vision,
    AiCapability.strictJsonSchema,
    AiCapability.storeFalse,
  },
  availability: availability,
  credentialConfigured: true,
  revision: revision,
);

AiProviderProfile localProvider({
  String model = 'gemma3',
  DateTime? attestedAt,
}) => AiProviderProfile(
  id: 'provider-local',
  homeId: 'home-1',
  displayName: 'Kitchen Ollama',
  kind: AiProviderKind.ollama,
  transport: AiTransport.directNative,
  protocol: AiEndpointProtocol.ollamaChat,
  endpoint: Uri.parse('http://127.0.0.1:11434'),
  model: model,
  capabilities: <AiCapability>{
    AiCapability.vision,
    AiCapability.strictJsonSchema,
  },
  availability: AiProviderAvailability.available,
  strictLocalAttestedAt: attestedAt ?? DateTime.utc(2026, 7, 30),
);

PreparedMediaBatch preparedBatch({
  AiExtractionKind purpose = AiExtractionKind.receipt,
  String hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) => PreparedMediaBatch(
  id: 'batch-1',
  homeId: 'home-1',
  purpose: purpose,
  media: <PreparedAiMedia>[
    PreparedAiMedia(
      sourceMediaId: 'media-1',
      ephemeralReference: 'ephemeral://batch-1/page-1',
      previewReference: 'preview://batch-1/page-1',
      sha256: hash,
      mimeType: 'image/jpeg',
      byteLength: 12000,
      width: 1200,
      height: 1600,
      pageIndex: 0,
    ),
  ],
);

AiConsent consentFor({
  required AiProviderProfile provider,
  required PreparedMediaBatch media,
  AiPrivacyMode privacyMode = AiPrivacyMode.serverProxyCloud,
}) => AiConsent(
  providerId: provider.id,
  providerRevision: provider.revision,
  privacyMode: privacyMode,
  purpose: media.purpose,
  orderedMediaHashes: media.orderedHashes,
  disclosureVersion: 'providentia-ai-privacy-v1',
  confirmedAt: DateTime.utc(2026, 7, 30),
);

ReceiptHeaderProposal receiptHeader() => const ReceiptHeaderProposal(
  purchaseDate: ExtractedField<String>(value: '2026-07-29', confidence: 0.95),
  storeName: ExtractedField<String>(
    value: 'Providentia Market',
    confidence: 0.9,
  ),
  receiptNumber: ExtractedField<String>(value: 'R-123', confidence: 0.85),
  currency: ExtractedField<String>(value: 'NAD', confidence: 0.99),
  subtotal: ExtractedField<String>(value: '19.99', confidence: 0.9),
  taxTotal: ExtractedField<String>(value: '0.00', confidence: 0.9),
  discountTotal: ExtractedField<String>(value: '0.00', confidence: 0.9),
  total: ExtractedField<String>(value: '19.99', confidence: 0.98),
);

ReceiptLineProposal receiptLine({
  String lineId = 'line-1',
}) => ReceiptLineProposal(
  lineId: lineId,
  rawText: '2 MILK 1L 19.99',
  brand: const ExtractedField<String>(value: null, confidence: 0.4),
  productName: const ExtractedField<String>(value: 'Milk', confidence: 0.92),
  productFamily: const ExtractedField<String>(value: 'Dairy', confidence: 0.8),
  variant: const ExtractedField<String>(value: null, confidence: 0.3),
  packDescription: const ExtractedField<String>(value: '1 L', confidence: 0.85),
  quantity: const ExtractedField<double>(value: 2, confidence: 0.93),
  unitPrice: const ExtractedField<String>(value: '9.995', confidence: 0.85),
  lineTotal: const ExtractedField<String>(value: '19.99', confidence: 0.95),
  discount: const ExtractedField<String>(value: '0.00', confidence: 0.7),
  tax: const ExtractedField<String>(value: '0.00', confidence: 0.7),
  notes: const ExtractedField<String>(value: null, confidence: 0.2),
  confidence: 0.9,
  warnings: const <String>[],
);

ReceiptProposal receiptProposal({
  String runId = 'run-1',
  ReceiptDocumentClassification classification =
      ReceiptDocumentClassification.receipt,
  List<ReceiptLineProposal>? lines,
}) => ReceiptProposal(
  id: 'receipt-proposal-1',
  runId: runId,
  schemaVersion: 'receipt-v1',
  classification: classification,
  header: receiptHeader(),
  lines: lines ?? <ReceiptLineProposal>[receiptLine()],
  warnings: const <String>[],
);

StockCandidateProposal stockCandidate({String candidateId = 'candidate-1'}) =>
    StockCandidateProposal(
      candidateId: candidateId,
      brand: const ExtractedField<String>(value: null, confidence: 0.3),
      productName: const ExtractedField<String>(value: 'Rice', confidence: 0.9),
      variant: const ExtractedField<String>(value: null, confidence: 0.2),
      packDescription: const ExtractedField<String>(
        value: '1 kg',
        confidence: 0.85,
      ),
      quantityMinimum: 2,
      quantityMaximum: 3,
      confidence: 0.82,
      warnings: const <String>['One package is partly occluded'],
    );

StockPhotoProposal stockProposal({
  String runId = 'run-1',
  StockImageClassification classification =
      StockImageClassification.pantryStock,
  List<StockCandidateProposal>? candidates,
}) => StockPhotoProposal(
  id: 'stock-proposal-1',
  runId: runId,
  schemaVersion: 'stock-photo-v1',
  classification: classification,
  candidates: candidates ?? <StockCandidateProposal>[stockCandidate()],
  warnings: const <String>[],
);

Map<String, Object?> validReceiptJson({
  String classification = 'receipt',
  List<Object?>? lines,
}) => <String, Object?>{
  'schemaVersion': 'receipt-v1',
  'classification': classification,
  'header': <String, Object?>{
    'purchaseDate': field('2026-07-29', 0.95),
    'storeName': field('Providentia Market', 0.9),
    'receiptNumber': field('R-123', 0.85),
    'currency': field('NAD', 0.99),
    'subtotal': field('19.99', 0.9),
    'taxTotal': field('0.00', 0.9),
    'discountTotal': field('0.00', 0.9),
    'total': field('19.99', 0.98),
  },
  'lines': lines ?? <Object?>[validReceiptLineJson()],
  'warnings': <Object?>[],
};

Map<String, Object?> validReceiptLineJson({String lineId = 'line-1'}) =>
    <String, Object?>{
      'lineId': lineId,
      'rawText': '2 MILK 1L 19.99',
      'brand': field(null, 0.4),
      'productName': field('Milk', 0.92),
      'productFamily': field('Dairy', 0.8),
      'variant': field(null, 0.3),
      'packDescription': field('1 L', 0.85),
      'unitPrice': field('9.995', 0.85),
      'lineTotal': field('19.99', 0.95),
      'discount': field('0.00', 0.7),
      'tax': field('0.00', 0.7),
      'notes': field(null, 0.2),
      'quantity': field(2, 0.93),
      'confidence': 0.9,
      'warnings': <Object?>[],
      'region': null,
    };

Map<String, Object?> field(Object? value, double confidence) =>
    <String, Object?>{'value': value, 'confidence': confidence};

const AiRunMetadata runMetadata = AiRunMetadata(
  providerKind: AiProviderKind.openAi,
  model: 'gpt-5-mini',
  protocol: AiEndpointProtocol.openAiResponses,
  promptVersion: 'receipt-extraction-v1',
  schemaVersion: 'receipt-v1',
  processingTime: Duration(milliseconds: 500),
);

final class FakeCredentialVault implements CredentialVault {
  FakeCredentialVault({this.supportsNativeSecrets = true});

  @override
  final bool supportsNativeSecrets;
  final Map<String, String> values = <String, String>{};

  @override
  Future<bool> contains(String profileId) async =>
      values.containsKey(profileId);

  @override
  Future<void> delete(String profileId) async {
    values.remove(profileId);
  }

  @override
  Future<void> write({
    required String profileId,
    required String secret,
  }) async {
    values[profileId] = secret;
  }
}

final class FakeServerCredentials implements ServerCredentialProvisioningPort {
  int replacements = 0;
  int deletions = 0;

  @override
  Future<void> deleteCredential({
    required String homeId,
    required String profileId,
  }) async {
    deletions++;
  }

  @override
  Future<void> replaceCredential({
    required String homeId,
    required String profileId,
    required String secret,
  }) async {
    replacements++;
  }
}

final class FakeMediaPreparation implements AiMediaPreparationPort {
  FakeMediaPreparation(this.batch);

  final PreparedMediaBatch batch;
  int discardCalls = 0;

  @override
  Future<void> discard(PreparedMediaBatch batch) async {
    discardCalls++;
  }

  @override
  Future<PreparedMediaBatch> prepare({
    required String homeId,
    required AiExtractionKind purpose,
    required List<AiMediaAsset> assets,
  }) async => batch;
}

final class FakeProviderRepository implements AiProviderRepository {
  final Map<String, AiProviderProfile> values = <String, AiProviderProfile>{};

  @override
  Future<void> delete({
    required String homeId,
    required String providerId,
  }) async {
    values.remove(providerId);
  }

  @override
  Future<AiProviderProfile?> findById({
    required String homeId,
    required String providerId,
  }) async => values[providerId];

  @override
  Future<List<AiProviderProfile>> listForHome(String homeId) async => values
      .values
      .where((profile) => profile.homeId == homeId)
      .toList(growable: false);

  @override
  Future<void> save(AiProviderProfile profile) async {
    values[profile.id] = profile;
  }
}

typedef ReceiptGatewayHandler =
    Future<AiExtractionResult<ReceiptProposal>> Function(
      AiExtractionRequest request,
    );
typedef StockGatewayHandler =
    Future<AiExtractionResult<StockPhotoProposal>> Function(
      AiExtractionRequest request,
    );

final class FakeGateway implements AiProviderGateway {
  FakeGateway({
    required this.route,
    this.receiptHandler,
    this.stockHandler,
    this.gatewayReadiness = const AiGatewayReadiness.ready(),
    this.readinessError,
  });

  @override
  final AiGatewayRoute route;
  final ReceiptGatewayHandler? receiptHandler;
  final StockGatewayHandler? stockHandler;
  final AiGatewayReadiness gatewayReadiness;
  final Object? readinessError;
  final List<AiExtractionRequest> requests = <AiExtractionRequest>[];

  @override
  Future<AiExtractionResult<ReceiptProposal>> extractReceipt(
    AiExtractionRequest request,
  ) {
    requests.add(request);
    return receiptHandler!(request);
  }

  @override
  Future<AiExtractionResult<StockPhotoProposal>> extractStockPhoto(
    AiExtractionRequest request,
  ) {
    requests.add(request);
    return stockHandler!(request);
  }

  @override
  Future<AiGatewayReadiness> readiness(AiProviderProfile profile) async {
    if (readinessError case final error?) throw error;
    return gatewayReadiness;
  }
}

final class FakeGatewayResolver implements AiGatewayResolver {
  FakeGatewayResolver(this.gateways);

  final Map<AiGatewayRoute, AiProviderGateway> gateways;

  @override
  AiProviderGateway? forRoute(AiGatewayRoute route) => gateways[route];
}

final class FakeRunRepository implements AiRunRepository {
  final Map<String, AiRunRecord> values = <String, AiRunRecord>{};

  @override
  Future<AiRunRecord?> findById({
    required String homeId,
    required String runId,
  }) async => values[runId];

  @override
  Future<void> save(AiRunRecord run) async {
    values[run.id] = run;
  }
}

final class FakeProposalRepository implements AiProposalRepository {
  final Map<String, ReceiptProposal> receipts = <String, ReceiptProposal>{};
  final Map<String, StockPhotoProposal> stocks = <String, StockPhotoProposal>{};
  final Map<String, CommitOutcome> receiptOutcomes = <String, CommitOutcome>{};
  final Map<String, CommitOutcome> countOutcomes = <String, CommitOutcome>{};
  int receiptApprovalMarks = 0;
  int countApprovalMarks = 0;

  @override
  Future<CommitOutcome?> findCountCommitOutcome({
    required String homeId,
    required String idempotencyKey,
  }) async => countOutcomes[idempotencyKey];

  @override
  Future<ReceiptProposal?> findReceipt({
    required String homeId,
    required String proposalId,
  }) async => receipts[proposalId];

  @override
  Future<CommitOutcome?> findReceiptCommitOutcome({
    required String homeId,
    required String idempotencyKey,
  }) async => receiptOutcomes[idempotencyKey];

  @override
  Future<StockPhotoProposal?> findStockPhoto({
    required String homeId,
    required String proposalId,
  }) async => stocks[proposalId];

  @override
  Future<void> markReceiptApproved({
    required String homeId,
    required String proposalId,
  }) async {
    receiptApprovalMarks++;
  }

  @override
  Future<void> markStockCountApproved({
    required String homeId,
    required String proposalId,
  }) async {
    countApprovalMarks++;
  }

  @override
  Future<void> saveCountCommitOutcome({
    required String homeId,
    required String idempotencyKey,
    required CommitOutcome outcome,
  }) async {
    countOutcomes[idempotencyKey] = outcome;
  }

  @override
  Future<void> saveReceipt({
    required String homeId,
    required ReceiptProposal proposal,
  }) async {
    receipts[proposal.id] = proposal;
  }

  @override
  Future<void> saveReceiptCommitOutcome({
    required String homeId,
    required String idempotencyKey,
    required CommitOutcome outcome,
  }) async {
    receiptOutcomes[idempotencyKey] = outcome;
  }

  @override
  Future<void> saveStockPhoto({
    required String homeId,
    required StockPhotoProposal proposal,
  }) async {
    stocks[proposal.id] = proposal;
  }
}

final class FakeReceiptCommit implements ReceiptCommitPort {
  int calls = 0;

  @override
  Future<CommitOutcome> commitApprovedReceipt({
    required ReviewedReceipt receipt,
    required String idempotencyKey,
  }) async {
    calls++;
    return const CommitOutcome(
      resourceId: 'receipt-committed-1',
      alreadyCommitted: false,
    );
  }
}

final class FakeStockCommit implements StockCountCommitPort {
  int calls = 0;

  @override
  Future<CommitOutcome> closeApprovedCount({
    required ReviewedStockCount count,
    required String idempotencyKey,
  }) async {
    calls++;
    return const CommitOutcome(
      resourceId: 'count-committed-1',
      alreadyCommitted: false,
    );
  }
}

final class FakeIdentifiers implements AiIdentifierFactory {
  int _next = 0;

  @override
  String nextId() {
    _next++;
    return 'run-$_next';
  }
}
