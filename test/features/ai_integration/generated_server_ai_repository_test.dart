import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/generated_server_ai_repository.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test(
    'loads revision-bound settings, profiles, and policy for one home',
    () async {
      final repository = GeneratedServerAiRepository(
        _client((request) async {
          return switch (request.url.path) {
            '/api/v1/homes/home-1/ai/settings' => _json(_settings()),
            '/api/v1/homes/home-1/ai/profiles' => _json(<String, Object?>{
              'items': <Object?>[
                _profile(provider: 'anthropic', id: 'profile-1'),
                _profile(provider: 'gemini', id: 'profile-2'),
              ],
            }),
            '/api/v1/homes/home-1/ai/policy' => _json(
              _policy(extractionIds: const <String>['profile-1']),
            ),
            _ => throw StateError('Unexpected ${request.url.path}'),
          };
        }),
      );

      final workspace = await repository.loadWorkspace(homeId: 'home-1');

      expect(workspace.homeId, 'home-1');
      expect(workspace.settings.revision, 4);
      expect(workspace.settings.humanReviewRequired, isTrue);
      expect(workspace.profiles, hasLength(2));
      expect(workspace.profiles.first.kind, AiProviderKind.anthropic);
      expect(
        workspace.profiles.first.protocol,
        AiEndpointProtocol.anthropicMessages,
      );
      expect(workspace.profiles.first.revision, 3);
      expect(workspace.profiles.first.estimatedCostMicros, 2500);
      expect(workspace.policy.revision, 2);
      expect(workspace.policy.extractionProfileIds, <String>['profile-1']);
    },
  );

  test('nested foreign home attribution fails closed', () async {
    final repository = GeneratedServerAiRepository(
      _client((request) async {
        return switch (request.url.path.split('/').last) {
          'settings' => _json(<String, Object?>{
            ..._settings(),
            'providerProfiles': <Object?>[
              <String, Object?>{'homeId': 'home-2'},
            ],
          }),
          'profiles' => _json(<String, Object?>{'items': <Object?>[]}),
          'policy' => _json(_policy()),
          _ => throw StateError('Unexpected ${request.url.path}'),
        };
      }),
    );

    await expectLater(
      repository.loadWorkspace(homeId: 'home-1'),
      throwsA(
        isA<AiServerException>().having(
          (error) => error.kind,
          'kind',
          AiServerFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test(
    'profile credential is write-only and response secret is ignored',
    () async {
      final requests = <http.Request>[];
      const secret = 'provider-secret-123456';
      final repository = GeneratedServerAiRepository(
        _client((request) async {
          requests.add(request);
          return _json(<String, Object?>{
            ..._profile(id: 'profile-new', revision: 1),
            'credential': secret,
          }, statusCode: 201);
        }),
      );

      final profile = await repository.saveProviderProfile(
        homeId: 'home-1',
        draft: const AiProviderProfileDraft(
          id: null,
          label: 'Receipt extractor',
          provider: 'openai',
          model: 'gpt-5-mini',
          estimatedCostMicros: 2500,
          expectedRevision: 0,
        ),
        credential: secret,
      );

      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/v1/homes/home-1/ai/profiles');
      expect(
        jsonDecode(requests.single.body),
        containsPair('credential', secret),
      );
      expect(profile.id, 'profile-new');
      expect(profile.credentialConfigured, isTrue);
      expect(profile.toString(), isNot(contains(secret)));
      expect(profile.displayName, isNot(contains(secret)));
    },
  );

  test('settings update verifies the write and refresh revisions', () async {
    final requests = <http.Request>[];
    final repository = GeneratedServerAiRepository(
      _client((request) async {
        requests.add(request);
        if (request.method == 'PUT') {
          return _json(<String, Object?>{
            'mode': 'server_proxy',
            'provider': 'openai',
            'model': 'gpt-5-mini',
            'revision': 5,
          });
        }
        return _json(_settings(revision: 5));
      }),
    );

    final settings = await repository.updateSettings(
      homeId: 'home-1',
      update: const AiSettingsUpdate(
        mode: AiServerMode.serverProxy,
        provider: 'openai',
        model: 'gpt-5-mini',
        expectedRevision: 4,
      ),
    );

    expect(requests.map((request) => request.method), <String>['PUT', 'GET']);
    expect(
      jsonDecode(requests.first.body),
      containsPair('expectedRevision', 4),
    );
    expect(settings.revision, 5);
  });

  test('candidate decision is explicit, revision-bound, and AI-only', () async {
    final requests = <http.Request>[];
    var reviewed = false;
    final repository = GeneratedServerAiRepository(
      _client((request) async {
        requests.add(request);
        if (request.method == 'PUT') {
          reviewed = true;
          return http.Response('', 204);
        }
        return _json(
          _extraction(
            reviewStatus: reviewed ? 'accepted' : 'pending',
            candidateRevision: reviewed ? 2 : 1,
          ),
        );
      }),
    );
    final pending = (await repository.loadExtractionReview(
      homeId: 'home-1',
      extractionId: _extractionId,
    )).candidates.single;

    final updated = await repository.reviewCandidate(
      candidate: pending,
      decision: AiCandidateDecision.accept,
    );

    expect(updated.candidates.single.status, AiCandidateReviewStatus.accepted);
    expect(updated.candidates.single.revision, 2);
    final decisionRequest = requests.singleWhere(
      (request) => request.method == 'PUT',
    );
    expect(
      decisionRequest.url.path,
      '/api/v1/homes/home-1/ai/extractions/$_extractionId/candidates/0',
    );
    expect(jsonDecode(decisionRequest.body), <String, Object?>{
      'decision': 'accepted',
      'expectedRevision': 1,
    });
    expect(
      requests.every((request) => request.url.path.contains('/ai/')),
      isTrue,
    );
    expect(
      requests.any(
        (request) =>
            request.url.path.contains('/inventory') ||
            request.url.path.contains('/purchases') ||
            request.url.path.contains('/sync'),
      ),
      isFalse,
    );
  });

  test('malformed and forbidden responses use safe typed failures', () async {
    final malformed = GeneratedServerAiRepository(
      _client(
        (_) async => _json(<String, Object?>{
          ..._extraction(),
          'id': 'another-extraction',
        }),
      ),
    );
    await expectLater(
      malformed.loadExtractionReview(
        homeId: 'home-1',
        extractionId: _extractionId,
      ),
      throwsA(
        isA<AiServerException>().having(
          (error) => error.kind,
          'kind',
          AiServerFailureKind.invalidResponse,
        ),
      ),
    );

    final forbidden = GeneratedServerAiRepository(
      _client(
        (_) async => _json(<String, Object?>{
          'type': 'forbidden',
          'title': 'Internal authorization detail',
          'status': 403,
          'detail': 'private policy internals',
        }, statusCode: 403),
      ),
    );
    await expectLater(
      forbidden.loadExtractionReview(
        homeId: 'home-1',
        extractionId: _extractionId,
      ),
      throwsA(
        isA<AiServerException>()
            .having(
              (error) => error.kind,
              'kind',
              AiServerFailureKind.forbidden,
            )
            .having(
              (error) => error.safeMessage,
              'safeMessage',
              isNot(contains('private policy internals')),
            ),
      ),
    );
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

Map<String, Object?> _settings({int revision = 4}) => <String, Object?>{
  'mode': 'server_proxy',
  'provider': 'openai',
  'model': 'gpt-5-mini',
  'revision': revision,
  'availableServerProviders': <Object?>[
    for (final id in const <String>[
      'openai',
      'anthropic',
      'gemini',
      'xai',
      'openai-compatible',
      'ollama',
    ])
      <String, Object?>{'id': id, 'requiresCredential': id != 'ollama'},
  ],
  'cloudByokOnNativeClients': false,
  'serverPersistsUploadedMedia': true,
  'humanReviewRequired': true,
  'credentialEncryptionAvailable': true,
};

Map<String, Object?> _profile({
  String id = 'profile-new',
  String provider = 'openai',
  int revision = 3,
}) => <String, Object?>{
  'id': id,
  'label': 'Receipt extractor',
  'provider': provider,
  'model': 'gpt-5-mini',
  'credentialConfigured': true,
  'lastFour': '3456',
  'estimatedCostMicros': 2500,
  'revision': revision,
};

Map<String, Object?> _policy({List<String> extractionIds = const <String>[]}) =>
    <String, Object?>{
      'extractionProfileIds': extractionIds,
      'validationProfileId': null,
      'maxAttempts': extractionIds.isEmpty ? 4 : extractionIds.length,
      'maxTotalTokens': 50000,
      'maxEstimatedCostMicros': 1000000,
      'revision': 2,
    };

Map<String, Object?> _extraction({
  String reviewStatus = 'pending',
  int candidateRevision = 1,
}) => <String, Object?>{
  'id': _extractionId,
  'kind': 'receipt',
  'provider': 'openai',
  'model': 'gpt-5-mini',
  'status': 'review_required',
  'inputMimeType': 'image/jpeg',
  'inputSha256':
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'inputByteCount': 100,
  'schemaVersion': 1,
  'promptTemplateVersion': 1,
  'processingMs': 20,
  'candidates': <Object?>[
    <String, Object?>{
      'position': 0,
      'candidateType': 'receipt_line',
      'confidence': '0.95',
      'reviewStatus': reviewStatus,
      'revision': candidateRevision,
      'payload': <String, Object?>{
        'candidateType': 'receipt_line',
        'rawText': 'Rice 1 kg',
        'description': 'Rice',
        'brand': null,
        'product': 'Rice',
        'variant': null,
        'quantity': '1',
        'packText': '1 kg',
        'unitPrice': '20.00',
        'lineTotal': '20.00',
        'discountAmount': null,
        'taxAmount': null,
        'boundingRegion': null,
        'confidence': 0.95,
        'fieldConfidence': <String, Object?>{},
        'warnings': <Object?>[],
        'unresolvedValues': <Object?>[],
      },
    },
  ],
};

const String _extractionId = '11111111-1111-4111-8111-111111111111';
