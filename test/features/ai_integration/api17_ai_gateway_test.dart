import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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

  test('server gateway wipes every reader-owned media buffer', () async {
    final successReader = _CapturingMediaReader(_bytes);
    final success = Api17AiGateway(
      client: _extractionClient(documentType: 'receipt'),
      mediaReader: successReader,
    );

    await success.extractReceipt(_request(AiExtractionKind.receipt));

    expect(successReader.issued, hasLength(1));
    expect(successReader.issued.single, everyElement(0));

    final failureReader = _CapturingMediaReader(_bytes);
    final failure = Api17AiGateway(
      client: _client(
        (_) async =>
            _json(<String, Object?>{'type': 'rate-limit'}, statusCode: 429),
      ),
      mediaReader: failureReader,
    );

    await failure.extractReceipt(_request(AiExtractionKind.receipt));

    expect(failureReader.issued, hasLength(1));
    expect(failureReader.issued.single, everyElement(0));
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

  for (final statusCode in <int>[403, 404]) {
    test('readiness HTTP $statusCode is terminal authorization denial', () {
      const privateDetail = 'private household membership diagnostics';
      final gateway = Api17AiGateway(
        client: _client(
          (_) async => _json(<String, Object?>{
            'type': 'about:blank',
            'title': statusCode == 403 ? 'Forbidden' : 'Not Found',
            'status': statusCode,
            'detail': privateDetail,
          }, statusCode: statusCode),
        ),
        mediaReader: _MediaReader(_bytes),
      );

      expect(
        gateway.readiness(_profile()),
        throwsA(
          isA<AiGatewayAuthorizationDeniedException>().having(
            (error) => error.safeMessage,
            'safeMessage',
            isNot(contains(privateDetail)),
          ),
        ),
      );
    });

    for (final kind in AiExtractionKind.values) {
      test(
        '${kind.name} extraction HTTP $statusCode is terminal authorization denial',
        () {
          const privateDetail = 'private household extraction diagnostics';
          final gateway = Api17AiGateway(
            client: _client(
              (_) async => _json(<String, Object?>{
                'type': 'about:blank',
                'title': statusCode == 403 ? 'Forbidden' : 'Not Found',
                'status': statusCode,
                'detail': privateDetail,
              }, statusCode: statusCode),
            ),
            mediaReader: _MediaReader(_bytes),
          );

          final extraction = kind == AiExtractionKind.receipt
              ? gateway.extractReceipt(_request(kind))
              : gateway.extractStockPhoto(_request(kind));
          expect(
            extraction,
            throwsA(
              isA<AiGatewayAuthorizationDeniedException>().having(
                (error) => error.safeMessage,
                'safeMessage',
                isNot(contains(privateDetail)),
              ),
            ),
          );
        },
      );
    }
  }

  test(
    'readiness uses provider kind, not household profile identity',
    () async {
      final gateway = Api17AiGateway(
        client: _client(
          (_) async => _json(<String, Object?>{
            'credentialEncryptionAvailable': true,
            'availableServerProviders': <Object?>[
              <String, Object?>{'id': 'openai', 'requiresCredential': true},
            ],
          }),
        ),
        mediaReader: _MediaReader(_bytes),
      );
      final profile = AiProviderProfile(
        id: 'household-profile-1',
        homeId: 'home-1',
        displayName: 'Receipt profile',
        kind: AiProviderKind.openAi,
        transport: AiTransport.serverProxy,
        protocol: AiEndpointProtocol.openAiResponses,
        model: 'vision-production',
        capabilities: <AiCapability>{
          AiCapability.vision,
          AiCapability.strictJsonSchema,
          AiCapability.storeFalse,
        },
        availability: AiProviderAvailability.available,
        credentialConfigured: true,
      );

      expect((await gateway.readiness(profile)).isReady, isTrue);
    },
  );

  test(
    'same-length changed media and cross-home requests fail closed',
    () async {
      var calls = 0;
      final changed = Api17AiGateway(
        client: _client((_) async {
          calls++;
          throw StateError('must not call server');
        }),
        mediaReader: _MediaReader(Uint8List.fromList(List<int>.filled(16, 9))),
      );
      final changedResult =
          await changed.extractReceipt(_request(AiExtractionKind.receipt))
              as AiExtractionFailure<ReceiptProposal>;
      expect(changedResult.code, 'prepared_media_changed');

      final foreignProfile = AiProviderProfile(
        id: 'openai',
        homeId: 'home-2',
        displayName: 'Foreign profile',
        kind: AiProviderKind.openAi,
        transport: AiTransport.serverProxy,
        protocol: AiEndpointProtocol.openAiResponses,
        model: 'vision-production',
        capabilities: const <AiCapability>{
          AiCapability.vision,
          AiCapability.strictJsonSchema,
        },
        availability: AiProviderAvailability.available,
        credentialConfigured: true,
      );
      final foreignResult =
          await changed.extractReceipt(
                _request(AiExtractionKind.receipt, profile: foreignProfile),
              )
              as AiExtractionFailure<ReceiptProposal>;
      expect(foreignResult.code, 'home_scope_mismatch');
      expect(calls, 0);
    },
  );

  test(
    'API 1.12 rejects empty batches and unprepared media before transmission',
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
      expect(batchFailure.code, 'api17_image_limit');

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
    'multi-image extraction preserves order and validates aggregate binding',
    () async {
      final secondBytes = Uint8List.fromList(
        List<int>.generate(16, (index) => index + 16),
      );
      final second = PreparedAiMedia(
        sourceMediaId: 'source-2',
        ephemeralReference: 'memory://prepared-2',
        previewReference: 'memory://preview-2',
        sha256: sha256.convert(secondBytes).toString(),
        mimeType: 'image/png',
        byteLength: secondBytes.length,
        width: 800,
        height: 600,
        pageIndex: 1,
      );
      final aggregate = sha256.convert(<int>[
        ..._bytes,
        ...secondBytes,
      ]).toString();
      final duplicateCandidate =
          (_extraction('stock')['candidates']! as List<Object?>).single;
      final gateway = Api17AiGateway(
        client: _client((request) async {
          if (request.method == 'POST') {
            final body = latin1.decode(request.bodyBytes, allowInvalid: true);
            expect(
              body.indexOf('name="image"'),
              lessThan(body.indexOf('name="images[]"')),
            );
            expect(body, isNot(contains('name="images"')));
            expect(body, contains('name="targetId"'));
            expect(body, contains('count-session-1'));
            return _json(
              _created(candidateCount: 2, observationCount: 2),
              statusCode: 201,
            );
          }
          return _json(<String, Object?>{
            ..._extraction('stock'),
            'targetId': 'count-session-1',
            'inputSha256': aggregate,
            'inputByteCount': 32,
            'candidates': <Object?>[
              duplicateCandidate,
              <String, Object?>{
                ...(duplicateCandidate! as Map<String, Object?>),
                'position': 1,
              },
            ],
          });
        }),
        mediaReader: _MappedMediaReader(<String, Uint8List>{
          'source-1': _bytes,
          'source-2': secondBytes,
        }),
      );

      final result = await gateway.extractStockPhoto(
        _request(
          AiExtractionKind.stockPhoto,
          media: <PreparedAiMedia>[_media(), second],
          targetId: 'count-session-1',
        ),
      );

      final success = result as AiExtractionSuccess<StockPhotoProposal>;
      expect(success.proposal.candidates, hasLength(1));
      expect(
        success.proposal.candidates.single.warnings,
        contains(
          'Duplicate observation candidate removed; confirm the retained count once.',
        ),
      );
    },
  );

  test('duplicate receipt lines remain separate review candidates', () async {
    final first =
        (_extraction('receipt')['candidates']! as List<Object?>).single!
            as Map<String, Object?>;
    final gateway = Api17AiGateway(
      client: _client((request) async {
        if (request.method == 'POST') {
          return _json(_created(candidateCount: 2), statusCode: 201);
        }
        return _json(<String, Object?>{
          ..._extraction('receipt'),
          'candidates': <Object?>[
            first,
            <String, Object?>{...first, 'position': 1},
          ],
        });
      }),
      mediaReader: _MediaReader(_bytes),
    );

    final result = await gateway.extractReceipt(
      _request(AiExtractionKind.receipt),
    );

    final success = result as AiExtractionSuccess<ReceiptProposal>;
    expect(success.proposal.lines, hasLength(2));
    expect(
      success.proposal.lines.map((line) => line.lineId).toSet(),
      hasLength(2),
    );
  });

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
              ? _json(_created(), statusCode: 201)
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
          ? _json(_created(), statusCode: 201)
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
      ..._binding(kind: 'receipt', mimeType: 'image/png'),
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
            ? _json(_created(), statusCode: 201)
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
        ..._binding(kind: 'stock', mimeType: 'image/webp'),
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
              ? _json(_created(), statusCode: 201)
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

  test('provider profile updates and gateway routing remain explicit', () {
    final timestamp = DateTime.utc(2026, 8, 4);
    final changed = _profile().copyWith(
      displayName: 'Validator',
      endpoint: Uri.parse('https://validator.example.test'),
      model: 'validator-model',
      capabilities: <AiCapability>{AiCapability.vision},
      availability: AiProviderAvailability.unavailable,
      credentialConfigured: false,
      strictLocalAttestedAt: timestamp,
      revision: 2,
      enabled: false,
    );
    final gateway = Api17AiGateway(
      client: _client((_) async => throw StateError('not called')),
      mediaReader: _MediaReader(_bytes),
    );

    expect(gateway.route, AiGatewayRoute.serverProxyCloud);
    expect(changed.displayName, 'Validator');
    expect(changed.endpoint, Uri.parse('https://validator.example.test'));
    expect(changed.model, 'validator-model');
    expect(changed.capabilities, <AiCapability>{AiCapability.vision});
    expect(changed.availability, AiProviderAvailability.unavailable);
    expect(changed.credentialConfigured, isFalse);
    expect(changed.strictLocalAttestedAt, timestamp);
    expect(changed.revision, 2);
    expect(changed.enabled, isFalse);
  });

  test('malformed candidate primitives never escape as proposals', () async {
    Future<AiExtractionFailure<ReceiptProposal>> extract(
      Map<String, Object?> payload, {
      Object position = 0,
    }) async {
      final response = <String, Object?>{
        ..._binding(kind: 'receipt'),
        'status': 'review_required',
        'result': <String, Object?>{'documentType': 'receipt'},
        'candidates': <Object?>[
          <String, Object?>{'position': position, 'payload': payload},
        ],
      };
      final gateway = Api17AiGateway(
        client: _client(
          (request) async => request.method == 'POST'
              ? _json(_created(), statusCode: 201)
              : _json(response),
        ),
        mediaReader: _MediaReader(_bytes),
      );
      return await gateway.extractReceipt(_request(AiExtractionKind.receipt))
          as AiExtractionFailure<ReceiptProposal>;
    }

    expect(
      (await extract(<String, Object?>{}, position: 'zero')).code,
      'invalid_ai_response',
    );
    expect(
      (await extract(<String, Object?>{
        'description': 'Rice',
        'quantity': '1',
        'confidence': 2,
        'fieldConfidence': <String, Object?>{},
      })).code,
      'invalid_ai_response',
    );
    expect(
      (await extract(<String, Object?>{
        'quantity': '1',
        'confidence': 0.5,
        'fieldConfidence': <String, Object?>{},
      })).code,
      'invalid_ai_response',
    );
  });
}

ProvidentiaApiClient _extractionClient({required String documentType}) {
  return _client((request) async {
    expect(request.url.path, startsWith('/api/v1/homes/home-1/ai/extractions'));
    if (request.method == 'POST') {
      expect(request.headers['content-type'], contains('multipart/form-data'));
      return _json(_created(), statusCode: 201);
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

Map<String, Object?> _created({
  int candidateCount = 1,
  int observationCount = 1,
}) => <String, Object?>{
  'id': 'extraction-1',
  'status': 'review_required',
  'candidateCount': candidateCount,
  'observationCount': observationCount,
};

Map<String, Object?> _binding({
  required String kind,
  String mimeType = 'image/jpeg',
}) => <String, Object?>{
  'id': 'extraction-1',
  'kind': kind,
  'provider': 'openai',
  'model': 'vision-production',
  'inputMimeType': mimeType,
  'inputSha256':
      'be45cb2605bf36bebde684841a28f0fd43c69850a3dce5fedba69928ee3a8991',
  'inputByteCount': 16,
  'schemaVersion': 1,
  'promptTemplateVersion': 1,
};

Map<String, Object?> _extraction(String documentType) => <String, Object?>{
  ..._binding(kind: documentType == 'stock' ? 'stock' : 'receipt'),
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
  String? targetId,
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
  targetId: targetId,
);

PreparedAiMedia _media({String mimeType = 'image/jpeg'}) => PreparedAiMedia(
  sourceMediaId: 'source-1',
  ephemeralReference: 'memory://prepared-1',
  previewReference: 'memory://preview-1',
  sha256: 'be45cb2605bf36bebde684841a28f0fd43c69850a3dce5fedba69928ee3a8991',
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
  Future<Uint8List> read(PreparedAiMedia media) async =>
      Uint8List.fromList(bytes);
}

final class _MappedMediaReader implements PreparedMediaByteReader {
  const _MappedMediaReader(this.bytesBySource);

  final Map<String, Uint8List> bytesBySource;

  @override
  Future<Uint8List> read(PreparedAiMedia media) async =>
      Uint8List.fromList(bytesBySource[media.sourceMediaId]!);
}

final class _CapturingMediaReader implements PreparedMediaByteReader {
  _CapturingMediaReader(this.bytes);

  final Uint8List bytes;
  final List<Uint8List> issued = <Uint8List>[];

  @override
  Future<Uint8List> read(PreparedAiMedia media) async {
    final copy = Uint8List.fromList(bytes);
    issued.add(copy);
    return copy;
  }
}
