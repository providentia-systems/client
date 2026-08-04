import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_ai_gateway.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test(
    'server readiness requires encrypted storage and a listed provider',
    () async {
      final gateway = Api17AiGateway(
        client: _client((request) async {
          expect(request.url.path, '/api/v1/homes/home-1/ai/settings');
          return _json(<String, Object?>{
            'credentialEncryptionAvailable': true,
            'availableServerProviders': <Object?>[
              <String, Object?>{'id': 'openai', 'requiresCredential': true},
            ],
          });
        }),
        mediaReader: _MediaReader(_bytes),
      );

      expect((await gateway.readiness(_profile())).isReady, isTrue);
      expect(
        (await gateway.readiness(
          _profile(transport: AiTransport.directNative),
        )).state,
        AiGatewayReadinessState.missingCapability,
      );
    },
  );

  test('receipt extraction maps reviewed lines and run metadata', () async {
    final gateway = Api17AiGateway(
      client: _extractionClient(documentType: 'receipt'),
      mediaReader: _MediaReader(_bytes),
    );

    final result = await gateway.extractReceipt(
      _request(AiExtractionKind.receipt),
    );

    final success = result as AiExtractionSuccess<ReceiptProposal>;
    expect(
      success.proposal.classification,
      ReceiptDocumentClassification.receipt,
    );
    expect(success.proposal.header.storeName.value, 'Providentia Market');
    expect(success.proposal.lines.single.productName.value, 'Rice');
    expect(success.proposal.lines.single.quantity.value, 2);
    expect(success.proposal.lines.single.region?.width, 0.3);
    expect(success.metadata.model, 'vision-production');
    expect(success.metadata.processingTime, const Duration(milliseconds: 125));
    expect(success.metadata.inputTokens, 42);
    expect(success.metadata.outputTokens, 17);
  });

  test('stock extraction maps reviewed candidates and warnings', () async {
    final gateway = Api17AiGateway(
      client: _extractionClient(documentType: 'stock'),
      mediaReader: _MediaReader(_bytes),
    );

    final result = await gateway.extractStockPhoto(
      _request(AiExtractionKind.stockPhoto),
    );

    final success = result as AiExtractionSuccess<StockPhotoProposal>;
    expect(
      success.proposal.classification,
      StockImageClassification.pantryStock,
    );
    expect(success.proposal.candidates.single.productName.value, 'Rice');
    expect(success.proposal.candidates.single.quantityMinimum, 2);
    expect(success.proposal.candidates.single.quantityMaximum, 2);
    expect(
      success.proposal.candidates.single.warnings,
      contains('Check pack size'),
    );
    expect(success.proposal.warnings, contains('Review every line'));
  });

  test('unsupported routes and changed prepared bytes fail closed', () async {
    final gateway = Api17AiGateway(
      client: _client((_) async => throw StateError('must not call server')),
      mediaReader: _MediaReader(Uint8List(15)),
    );
    final wrongRoute = _request(
      AiExtractionKind.receipt,
      profile: _profile(transport: AiTransport.directNative),
      privacyMode: AiPrivacyMode.strictLocal,
    );

    final routeFailure =
        await gateway.extractReceipt(wrongRoute)
            as AiExtractionFailure<ReceiptProposal>;
    expect(routeFailure.code, 'invalid_ai_route');

    final byteFailure =
        await gateway.extractReceipt(_request(AiExtractionKind.receipt))
            as AiExtractionFailure<ReceiptProposal>;
    expect(byteFailure.code, 'prepared_media_changed');
  });
}

ProvidentiaApiClient _extractionClient({required String documentType}) {
  return _client((request) async {
    expect(request.url.path, startsWith('/api/v1/homes/home-1/ai/extractions'));
    if (request.method == 'POST') {
      expect(request.headers['content-type'], contains('multipart/form-data'));
      return _json(<String, Object?>{'id': 'extraction-1'}, statusCode: 201);
    }
    expect(request.method, 'GET');
    expect(request.url.path, endsWith('/extraction-1'));
    return _json(_extraction(documentType));
  });
}

ProvidentiaApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => ProvidentiaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(handler),
);

http.Response _json(Object body, {int statusCode = 200}) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: const <String, String>{'content-type': 'application/json'},
);

Map<String, Object?> _extraction(String documentType) => <String, Object?>{
  'id': 'extraction-1',
  'status': 'review_required',
  'model': 'vision-production',
  'processingMs': 125,
  'usage': <String, Object?>{'inputTokens': 42, 'outputTokens': 17},
  'result': <String, Object?>{
    'documentType': documentType,
    'merchant': 'Providentia Market',
    'receiptNumber': 'R-100',
    'purchaseDate': '2026-08-04',
    'currency': 'NAD',
    'totalAmount': '20.00',
    'taxAmount': '3.00',
    'warnings': <Object?>['Review every line'],
  },
  'candidates': <Object?>[
    <String, Object?>{
      'position': 0,
      'payload': <String, Object?>{
        'rawText': 'Rice 2 x 10.00',
        'description': 'Rice',
        'brand': 'Providentia',
        'product': 'Rice',
        'variant': 'Long grain',
        'packText': '1 kg',
        'quantity': '2',
        'unitPrice': '10.00',
        'lineTotal': '20.00',
        'discountAmount': '0.00',
        'taxAmount': '3.00',
        'confidence': 0.92,
        'fieldConfidence': <String, Object?>{
          'description': 0.94,
          'packText': 0.91,
          'quantity': 0.96,
          'unitPrice': 0.9,
          'lineTotal': 0.93,
        },
        'warnings': <Object?>['Check pack size'],
        'unresolvedValues': <Object?>[],
        'boundingRegion': <String, Object?>{
          'x': 0.1,
          'y': 0.2,
          'width': 0.3,
          'height': 0.1,
        },
      },
    },
  ],
};

AiExtractionRequest _request(
  AiExtractionKind kind, {
  AiProviderProfile? profile,
  AiPrivacyMode privacyMode = AiPrivacyMode.serverProxyCloud,
}) => AiExtractionRequest(
  runId: 'run-1',
  homeId: 'home-1',
  kind: kind,
  provider: profile ?? _profile(),
  privacyMode: privacyMode,
  media: PreparedMediaBatch(
    id: 'batch-1',
    homeId: 'home-1',
    purpose: kind,
    media: const <PreparedAiMedia>[
      PreparedAiMedia(
        sourceMediaId: 'source-1',
        ephemeralReference: 'memory://prepared-1',
        previewReference: 'memory://preview-1',
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        mimeType: 'image/jpeg',
        byteLength: 16,
        width: 1200,
        height: 1600,
        pageIndex: 0,
      ),
    ],
  ),
  schemaVersion: kind == AiExtractionKind.receipt ? 'receipt-v1' : 'stock-v1',
  promptVersion: 'prompt-v1',
  timeout: const Duration(seconds: 30),
);

AiProviderProfile _profile({AiTransport transport = AiTransport.serverProxy}) =>
    AiProviderProfile(
      id: 'openai',
      homeId: 'home-1',
      displayName: 'OpenAI',
      kind: AiProviderKind.openAi,
      transport: transport,
      protocol: AiEndpointProtocol.openAiResponses,
      model: 'vision-production',
      capabilities: <AiCapability>{
        AiCapability.vision,
        AiCapability.strictJsonSchema,
      },
      availability: AiProviderAvailability.available,
      credentialConfigured: true,
    );

final Uint8List _bytes = Uint8List.fromList(
  List<int>.generate(16, (index) => index),
);

final class _MediaReader implements PreparedMediaByteReader {
  const _MediaReader(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> read(PreparedAiMedia media) async => bytes;
}
