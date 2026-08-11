import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_ai_gateway.dart';
import 'package:providentia/features/ai_integration/infrastructure/strict_local_provider_gateway.dart';

void main() {
  group('strict-local endpoint guard', () {
    const guard = StrictLocalEndpointGuard();

    test(
      'allows explicit IPv4 private, loopback, and IPv6 ULA routes',
      () async {
        for (final uri in <String>[
          'http://127.0.0.1:11434',
          'http://10.2.3.4:11434',
          'https://192.168.1.20',
          'http://172.31.4.2',
          'http://[::1]:11434',
          'https://[fd12:3456::9]',
        ]) {
          final result = await guard.resolve(
            endpoint: Uri.parse(uri),
            resolver: const _Resolver(<String>[]),
          );
          expect(result.addresses, isNotEmpty, reason: uri);
        }
      },
    );

    test(
      'rejects public, metadata, mapped, link-local, and alternate routes',
      () async {
        for (final uri in <String>[
          'https://8.8.8.8',
          'http://169.254.169.254/latest',
          'http://100.100.100.200',
          'http://[fe80::1]',
          'http://[::ffff:127.0.0.1]',
          'http://[2001:4860:4860::8888]',
          'http://[fd00:ec2::254]',
          'ftp://127.0.0.1',
          'http://user:secret@127.0.0.1',
          'http://127.0.0.1?next=https://example.com',
        ]) {
          await expectLater(
            guard.resolve(
              endpoint: Uri.parse(uri),
              resolver: const _Resolver(<String>[]),
            ),
            throwsA(isA<StrictLocalBoundaryException>()),
            reason: uri,
          );
        }
      },
    );

    test('requires every DNS answer to be private', () async {
      final safe = await guard.resolve(
        endpoint: Uri.parse('http://pantry.local:11434'),
        resolver: const _Resolver(<String>['192.168.1.4', 'fd12::4']),
      );
      expect(safe.addresses, hasLength(2));

      await expectLater(
        guard.resolve(
          endpoint: Uri.parse('https://pantry.local'),
          resolver: const _Resolver(<String>['192.168.1.4', '203.0.113.2']),
        ),
        throwsA(
          isA<StrictLocalBoundaryException>().having(
            (error) => error.code,
            'code',
            'unsafe_resolved_address',
          ),
        ),
      );
      await expectLater(
        guard.resolve(
          endpoint: Uri.parse('https://provider.example'),
          resolver: const _Resolver(<String>['192.168.1.4']),
        ),
        throwsA(isA<StrictLocalBoundaryException>()),
      );
    });
  });

  test(
    'default transport denies platforms without peer verification',
    () async {
      final gateway = StrictLocalProviderGateway(
        resolver: const _Resolver(<String>[]),
        transport: const DeniedStrictLocalHttpTransport(),
        mediaReader: _MediaReader(<Uint8List>[]),
      );

      final readiness = await gateway.readiness(_ollamaProfile());

      expect(readiness.state, AiGatewayReadinessState.unavailable);
      expect(readiness.safeMessage, contains('native transport'));
    },
  );

  test(
    'readiness verifies installed Ollama model and vision capability',
    () async {
      final transport = _Transport((request) {
        final body = switch (request.uri.path) {
          '/api/tags' => <String, Object?>{
            'models': <Object?>[
              <String, Object?>{'name': 'llava:latest'},
            ],
          },
          '/api/show' => <String, Object?>{
            'capabilities': <Object?>['completion', 'vision'],
          },
          _ => throw StateError('unexpected ${request.uri}'),
        };
        return _response(request, body);
      });
      final gateway = _gateway(transport: transport);

      expect((await gateway.readiness(_ollamaProfile())).isReady, isTrue);
      expect(transport.requests.map((item) => item.uri.path), <String>[
        '/api/tags',
        '/api/show',
      ]);
    },
  );

  test('cloud-routed Ollama models are rejected before transport', () async {
    final transport = _Transport(
      (request) => throw StateError('must not call'),
    );
    final gateway = _gateway(transport: transport);

    final readiness = await gateway.readiness(
      _ollamaProfile(model: 'gpt-oss:cloud'),
    );

    expect(readiness.isReady, isFalse);
    expect(readiness.safeMessage, contains('Cloud-routed'));
    expect(transport.requests, isEmpty);
  });

  test(
    'generic LAN adapter checks models and sends strict HTTPS schema',
    () async {
      final bytes = Uint8List.fromList(<int>[9, 8, 7]);
      late Map<String, Object?> sent;
      final transport = _Transport((request) {
        final body = switch (request.uri.path) {
          '/v1/models' => <String, Object?>{
            'data': <Object?>[
              <String, Object?>{'id': 'local-vision'},
            ],
          },
          '/v1/chat/completions' => () {
            sent =
                jsonDecode(utf8.decode(request.body!)) as Map<String, Object?>;
            return <String, Object?>{
              'choices': <Object?>[
                <String, Object?>{
                  'message': <String, Object?>{
                    'content': jsonEncode(_receiptProposalJson()),
                  },
                },
              ],
            };
          }(),
          _ => throw StateError('unexpected ${request.uri}'),
        };
        return StrictLocalTransportResponse(
          statusCode: 200,
          body: Uint8List.fromList(utf8.encode(jsonEncode(body))),
          finalUri: request.uri,
          connectedPeerAddress: '192.168.1.4',
          redirected: false,
        );
      });
      final gateway = _gateway(
        transport: transport,
        mediaReader: _MediaReader(<Uint8List>[bytes]),
      );
      final profile = _genericProfile();

      expect((await gateway.readiness(profile)).isReady, isTrue);
      final result = await gateway.extractReceipt(
        _request(<Uint8List>[bytes], profile: profile),
      );

      expect(result, isA<AiExtractionSuccess<ReceiptProposal>>());
      expect(sent['stream'], isFalse);
      final responseFormat = sent['response_format']! as Map<String, Object?>;
      final jsonSchema = responseFormat['json_schema']! as Map<String, Object?>;
      expect(jsonSchema['strict'], isTrue);
      expect(
        transport.requests.every((item) => item.uri.scheme == 'https'),
        isTrue,
      );
    },
  );

  test('redirect and DNS rebinding responses fail closed', () async {
    for (final responseFactory
        in <StrictLocalTransportResponse Function(StrictLocalTransportRequest)>[
          (request) => StrictLocalTransportResponse(
            statusCode: 302,
            body: Uint8List(0),
            finalUri: Uri.parse('https://example.com'),
            connectedPeerAddress: '127.0.0.1',
            redirected: true,
            headers: const <String, String>{'location': 'https://example.com'},
          ),
          (request) => StrictLocalTransportResponse(
            statusCode: 200,
            body: Uint8List.fromList(utf8.encode('{}')),
            finalUri: request.uri,
            connectedPeerAddress: '10.0.0.99',
            redirected: false,
          ),
        ]) {
      final gateway = _gateway(transport: _Transport(responseFactory));
      final readiness = await gateway.readiness(_ollamaProfile());
      expect(readiness.isReady, isFalse);
    }
  });

  test('ordered sanitized images and strict schema reach Ollama', () async {
    final first = Uint8List.fromList(<int>[1, 2, 3]);
    final second = Uint8List.fromList(<int>[4, 5]);
    late Map<String, Object?> sent;
    final transport = _Transport((request) {
      sent = jsonDecode(utf8.decode(request.body!)) as Map<String, Object?>;
      return _response(request, <String, Object?>{
        'message': <String, Object?>{
          'content': jsonEncode(_receiptProposalJson()),
        },
      });
    });
    final gateway = _gateway(
      transport: transport,
      mediaReader: _MediaReader(<Uint8List>[first, second]),
    );

    final result = await gateway.extractReceipt(
      _request(<Uint8List>[first, second]),
    );

    expect(result, isA<AiExtractionSuccess<ReceiptProposal>>());
    final messages = sent['messages']! as List<Object?>;
    final message = messages.single! as Map<String, Object?>;
    expect(message['images'], <String>[
      base64Encode(first),
      base64Encode(second),
    ]);
    expect(sent['stream'], isFalse);
    expect(sent['format'], isA<Map<String, Object?>>());
  });

  test('invalid extra proposal fields fail strict parsing', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);
    final payload = _receiptProposalJson()..['unexpected'] = true;
    final gateway = _gateway(
      mediaReader: _MediaReader(<Uint8List>[bytes]),
      transport: _Transport(
        (request) => _response(request, <String, Object?>{
          'message': <String, Object?>{'content': jsonEncode(payload)},
        }),
      ),
    );

    final result = await gateway.extractReceipt(_request(<Uint8List>[bytes]));

    expect(result, isA<AiExtractionFailure<ReceiptProposal>>());
    expect(
      (result as AiExtractionFailure<ReceiptProposal>).code,
      'invalid_ai_response',
    );
  });
}

StrictLocalProviderGateway _gateway({
  required _Transport transport,
  _MediaReader? mediaReader,
}) => StrictLocalProviderGateway(
  resolver: const _Resolver(<String>[]),
  transport: transport,
  mediaReader: mediaReader ?? _MediaReader(<Uint8List>[]),
);

AiProviderProfile _ollamaProfile({String model = 'llava:latest'}) =>
    AiProviderProfile(
      id: 'local-1',
      homeId: 'home-1',
      displayName: 'Kitchen Ollama',
      kind: AiProviderKind.ollama,
      transport: AiTransport.directNative,
      protocol: AiEndpointProtocol.ollamaChat,
      endpoint: Uri.parse('http://127.0.0.1:11434'),
      model: model,
      capabilities: const <AiCapability>{
        AiCapability.vision,
        AiCapability.strictJsonSchema,
        AiCapability.multiImage,
      },
      availability: AiProviderAvailability.available,
      strictLocalAttestedAt: DateTime.utc(2026, 8, 11),
    );

AiProviderProfile _genericProfile() => AiProviderProfile(
  id: 'compatible-1',
  homeId: 'home-1',
  displayName: 'LAN vision server',
  kind: AiProviderKind.openAiCompatible,
  transport: AiTransport.directNative,
  protocol: AiEndpointProtocol.openAiChatCompletions,
  endpoint: Uri.parse('https://192.168.1.4:8443'),
  model: 'local-vision',
  capabilities: const <AiCapability>{
    AiCapability.vision,
    AiCapability.strictJsonSchema,
    AiCapability.multiImage,
  },
  availability: AiProviderAvailability.available,
  strictLocalAttestedAt: DateTime.utc(2026, 8, 11),
);

AiExtractionRequest _request(
  List<Uint8List> bytes, {
  AiProviderProfile? profile,
}) {
  final media = <PreparedAiMedia>[
    for (var index = 0; index < bytes.length; index++)
      PreparedAiMedia(
        sourceMediaId: 'media-$index',
        ephemeralReference: 'ephemeral://$index',
        previewReference: 'preview://$index',
        sha256: sha256.convert(bytes[index]).toString(),
        mimeType: 'image/jpeg',
        byteLength: bytes[index].length,
        width: 10,
        height: 10,
        pageIndex: index,
      ),
  ];
  return AiExtractionRequest(
    runId: 'run-1',
    homeId: 'home-1',
    kind: AiExtractionKind.receipt,
    provider: profile ?? _ollamaProfile(),
    privacyMode: AiPrivacyMode.strictLocal,
    media: PreparedMediaBatch(
      id: 'batch-1',
      homeId: 'home-1',
      purpose: AiExtractionKind.receipt,
      media: media,
    ),
    schemaVersion: 'receipt-v1',
    promptVersion: 'local-v1',
    timeout: const Duration(seconds: 10),
  );
}

Map<String, Object?> _receiptProposalJson() => <String, Object?>{
  'schemaVersion': 'receipt-v1',
  'classification': 'receipt',
  'header': <String, Object?>{
    for (final name in <String>[
      'purchaseDate',
      'storeName',
      'receiptNumber',
      'currency',
      'subtotal',
      'taxTotal',
      'discountTotal',
      'total',
    ])
      name: <String, Object?>{'value': null, 'confidence': 0.5},
  },
  'lines': <Object?>[],
  'warnings': <Object?>[],
};

StrictLocalTransportResponse _response(
  StrictLocalTransportRequest request,
  Map<String, Object?> body,
) => StrictLocalTransportResponse(
  statusCode: 200,
  body: Uint8List.fromList(utf8.encode(jsonEncode(body))),
  finalUri: request.uri,
  connectedPeerAddress: '127.0.0.1',
  redirected: false,
);

final class _Resolver implements StrictLocalNameResolver {
  const _Resolver(this.answers);

  final List<String> answers;

  @override
  Future<List<String>> resolve(
    String host, {
    required Duration timeout,
  }) async => answers;
}

final class _Transport implements StrictLocalHttpTransport {
  _Transport(this.handler);

  final StrictLocalTransportResponse Function(StrictLocalTransportRequest)
  handler;
  final List<StrictLocalTransportRequest> requests =
      <StrictLocalTransportRequest>[];

  @override
  bool get blocksRedirects => true;

  @override
  bool get exposesConnectedPeerAddress => true;

  @override
  Future<StrictLocalTransportResponse> send(
    StrictLocalTransportRequest request,
  ) async {
    requests.add(request);
    return handler(request);
  }
}

final class _MediaReader implements PreparedMediaByteReader {
  _MediaReader(this.values);

  final List<Uint8List> values;
  var index = 0;

  @override
  Future<Uint8List> read(PreparedAiMedia media) async => values[index++];
}
