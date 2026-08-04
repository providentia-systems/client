import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_ai_gateway.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_server_credential_provisioning.dart';
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

  test(
    'readiness fails closed for encryption, provider, and network gaps',
    () async {
      var attempt = 0;
      final gateway = Api17AiGateway(
        client: _client((_) async {
          attempt += 1;
          return switch (attempt) {
            1 => _json(<String, Object?>{
              'credentialEncryptionAvailable': false,
              'availableServerProviders': <Object?>[],
            }),
            2 => _json(<String, Object?>{
              'credentialEncryptionAvailable': true,
              'availableServerProviders': <Object?>[],
            }),
            _ => throw http.ClientException('offline'),
          };
        }),
        mediaReader: _MediaReader(_bytes),
      );

      expect(
        (await gateway.readiness(_profile())).state,
        AiGatewayReadinessState.unavailable,
      );
      expect(
        (await gateway.readiness(_profile())).state,
        AiGatewayReadinessState.missingCapability,
      );
      expect(
        (await gateway.readiness(_profile())).state,
        AiGatewayReadinessState.unavailable,
      );
    },
  );

  test(
    'API 1.7 rejects batches and unprepared media before transmission',
    () async {
      final gateway = Api17AiGateway(
        client: _client((_) async => throw StateError('must not call server')),
        mediaReader: _MediaReader(_bytes),
      );

      final batchFailure =
          await gateway.extractReceipt(
                _request(
                  AiExtractionKind.receipt,
                  media: const <PreparedAiMedia>[],
                ),
              )
              as AiExtractionFailure<ReceiptProposal>;
      expect(batchFailure.code, 'api17_single_image_only');

      final mediaFailure =
          await gateway.extractReceipt(
                _request(
                  AiExtractionKind.receipt,
                  media: <PreparedAiMedia>[_media(mimeType: 'application/pdf')],
                ),
              )
              as AiExtractionFailure<ReceiptProposal>;
      expect(mediaFailure.code, 'unsupported_media_type');
    },
  );

  test(
    'server and malformed extraction responses become safe failures',
    () async {
      final serverFailure = Api17AiGateway(
        client: _client(
          (_) async =>
              _json(<String, Object?>{'type': 'rate-limit'}, statusCode: 429),
        ),
        mediaReader: _MediaReader(_bytes),
      );
      final rejected =
          await serverFailure.extractReceipt(_request(AiExtractionKind.receipt))
              as AiExtractionFailure<ReceiptProposal>;
      expect(rejected.code, 'server_429');

      final malformed = Api17AiGateway(
        client: _client(
          (request) async => request.method == 'POST'
              ? _json(<String, Object?>{'id': 'extraction-1'}, statusCode: 201)
              : _json(<String, Object?>{
                  ..._extraction('receipt'),
                  'candidates': 'not-a-list',
                }),
        ),
        mediaReader: _MediaReader(_bytes),
      );
      final invalid =
          await malformed.extractReceipt(_request(AiExtractionKind.receipt))
              as AiExtractionFailure<ReceiptProposal>;
      expect(invalid.code, 'invalid_ai_response');
    },
  );

  test('credential provisioning validates and writes secrets only', () async {
    final requests = <http.Request>[];
    final provisioning = Api17ServerCredentialProvisioning(
      _client((request) async {
        requests.add(request);
        return http.Response('', 204);
      }),
    );

    expect(
      () => provisioning.replaceCredential(
        homeId: 'home-1',
        profileId: 'openai',
        secret: 'short',
      ),
      throwsArgumentError,
    );
    expect(
      () => provisioning.replaceCredential(
        homeId: 'home-1',
        profileId: 'openai',
        secret: List<String>.filled(501, 'x').join(),
      ),
      throwsArgumentError,
    );

    await provisioning.replaceCredential(
      homeId: 'home-1',
      profileId: 'openai',
      secret: 'sk-providentia-secret',
    );
    await provisioning.deleteCredential(homeId: 'home-1', profileId: 'openai');

    expect(requests.map((request) => request.method), <String>[
      'PUT',
      'DELETE',
    ]);
    expect(
      requests.first.url.path,
      '/api/v1/homes/home-1/ai/credentials/openai',
    );
    expect(requests.first.body, contains('sk-providentia-secret'));
  });

  test('pending and stock-photo error responses fail closed', () async {
    ProvidentiaApiClient extractionClient(Object response) => _client(
      (request) async => request.method == 'POST'
          ? _json(<String, Object?>{'id': 'extraction-1'}, statusCode: 201)
          : _json(response),
    );

    final pending = Api17AiGateway(
      client: extractionClient(<String, Object?>{
        ..._extraction('receipt'),
        'status': 'processing',
      }),
      mediaReader: _MediaReader(_bytes),
    );
    final pendingFailure =
        await pending.extractReceipt(_request(AiExtractionKind.receipt))
            as AiExtractionFailure<ReceiptProposal>;
    expect(pendingFailure.code, 'extraction_processing');

    final routeFailure = Api17AiGateway(
      client: _client((_) async => throw StateError('must not call server')),
      mediaReader: _MediaReader(_bytes),
    );
    final wrongRoute =
        await routeFailure.extractStockPhoto(
              _request(
                AiExtractionKind.stockPhoto,
                profile: _profile(transport: AiTransport.directNative),
                privacyMode: AiPrivacyMode.strictLocal,
              ),
            )
            as AiExtractionFailure<StockPhotoProposal>;
    expect(wrongRoute.code, 'invalid_ai_route');

    final rejected = Api17AiGateway(
      client: _client(
        (_) async =>
            _json(<String, Object?>{'type': 'rate-limit'}, statusCode: 429),
      ),
      mediaReader: _MediaReader(_bytes),
    );
    final serverFailure =
        await rejected.extractStockPhoto(_request(AiExtractionKind.stockPhoto))
            as AiExtractionFailure<StockPhotoProposal>;
    expect(serverFailure.code, 'server_429');

    final malformed = Api17AiGateway(
      client: extractionClient(<String, Object?>{
        ..._extraction('stock'),
        'result': 'invalid',
      }),
      mediaReader: _MediaReader(_bytes),
    );
    final invalid =
        await malformed.extractStockPhoto(_request(AiExtractionKind.stockPhoto))
            as AiExtractionFailure<StockPhotoProposal>;
    expect(invalid.code, 'invalid_ai_response');
  });

  test('minimal optional receipt fields use deterministic fallbacks', () async {
    final minimal = <String, Object?>{
      'id': 'extraction-1',
      'status': 'review_required',
      'result': <String, Object?>{'documentType': 'invoice'},
      'candidates': <Object?>[
        <String, Object?>{
          'position': 0,
          'payload': <String, Object?>{
            'description': 'Rice',
            'quantity': '1',
            'confidence': 0.5,
            'fieldConfidence': <String, Object?>{},
          },
        },
      ],
    };
    final gateway = Api17AiGateway(
      client: _client(
        (request) async => request.method == 'POST'
            ? _json(<String, Object?>{'id': 'extraction-1'}, statusCode: 201)
            : _json(minimal),
      ),
      mediaReader: _MediaReader(_bytes),
    );

    final result =
        await gateway.extractReceipt(
              _request(
                AiExtractionKind.receipt,
                media: <PreparedAiMedia>[_media(mimeType: 'image/png')],
              ),
            )
            as AiExtractionSuccess<ReceiptProposal>;

    expect(
      result.proposal.classification,
      ReceiptDocumentClassification.unknown,
    );
    expect(result.proposal.lines.single.rawText, 'Rice');
    expect(result.proposal.lines.single.brand.value, isNull);
    expect(result.proposal.lines.single.region, isNull);
    expect(result.metadata.model, 'vision-production');
    expect(result.metadata.inputTokens, isNull);
  });

  test(
    'minimal stock fields and WebP media use deterministic fallbacks',
    () async {
      final minimal = <String, Object?>{
        'id': 'extraction-1',
        'status': 'review_required',
        'result': <String, Object?>{'documentType': 'unknown'},
        'candidates': <Object?>[
          <String, Object?>{
            'position': 0,
            'payload': <String, Object?>{
              'description': 'Rice',
              'quantity': 'not-a-number',
              'confidence': 0.5,
            },
          },
        ],
      };
      final gateway = Api17AiGateway(
        client: _client(
          (request) async => request.method == 'POST'
              ? _json(<String, Object?>{'id': 'extraction-1'}, statusCode: 201)
              : _json(minimal),
        ),
        mediaReader: _MediaReader(_bytes),
      );

      final result =
          await gateway.extractStockPhoto(
                _request(
                  AiExtractionKind.stockPhoto,
                  media: <PreparedAiMedia>[_media(mimeType: 'image/webp')],
                ),
              )
              as AiExtractionSuccess<StockPhotoProposal>;

      expect(result.proposal.classification, StockImageClassification.unknown);
      expect(result.proposal.candidates.single.productName.value, 'Rice');
      expect(result.proposal.candidates.single.brand.value, isNull);
      expect(result.proposal.candidates.single.quantityMinimum, 0);
      expect(result.proposal.candidates.single.region, isNull);
      expect(result.proposal.warnings, isEmpty);
    },
  );
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
  List<PreparedAiMedia>? media,
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
    media: media ?? <PreparedAiMedia>[_media()],
  ),
  schemaVersion: kind == AiExtractionKind.receipt ? 'receipt-v1' : 'stock-v1',
  promptVersion: 'prompt-v1',
  timeout: const Duration(seconds: 30),
);

PreparedAiMedia _media({String mimeType = 'image/jpeg'}) => PreparedAiMedia(
  sourceMediaId: 'source-1',
  ephemeralReference: 'memory://prepared-1',
  previewReference: 'memory://preview-1',
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  mimeType: mimeType,
  byteLength: 16,
  width: 1200,
  height: 1600,
  pageIndex: 0,
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
