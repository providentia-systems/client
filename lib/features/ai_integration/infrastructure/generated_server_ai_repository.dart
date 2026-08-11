import 'package:http/http.dart' as http;
import 'package:providentia/features/ai_integration/application/server_ai_repository.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Closed, current-contract (API 1.12) boundary for household AI management
/// and mandatory review. Raw response maps and credential material never
/// leave this adapter.
final class GeneratedServerAiRepository implements ServerAiRepository {
  const GeneratedServerAiRepository(this._client);

  final ProvidentiaApiClient _client;

  @override
  Future<AiServerWorkspace> loadWorkspace({required String homeId}) {
    return _run(() async {
      _requireHomeId(homeId);
      final responses = await Future.wait<ApiResponse>(<Future<ApiResponse>>[
        _client.getAiSettings(homeId: homeId),
        _client.listAiProviderProfiles(homeId: homeId),
        _client.getAiOrchestrationPolicy(homeId: homeId),
      ]);
      final settingsObject = responses[0].requireObject();
      final profilesObject = responses[1].requireObject();
      final policyObject = responses[2].requireObject();
      _rejectForeignHome(settingsObject, homeId);
      _rejectForeignHome(profilesObject, homeId);
      _rejectForeignHome(policyObject, homeId);

      final settings = _settings(settingsObject, homeId);
      final profiles = _objectList(profilesObject, 'items')
          .map((object) => _profile(object, homeId, settings))
          .toList(growable: false);
      if (profiles.map((profile) => profile.id).toSet().length !=
          profiles.length) {
        throw const FormatException('Duplicate AI provider profile.');
      }
      final policy = _policy(policyObject, homeId);
      final profileIds = profiles.map((profile) => profile.id).toSet();
      if (policy.extractionProfileIds.any(
            (profileId) => !profileIds.contains(profileId),
          ) ||
          (policy.validationProfileId != null &&
              !profileIds.contains(policy.validationProfileId))) {
        throw const FormatException('AI policy references an unknown profile.');
      }
      return AiServerWorkspace(
        homeId: homeId,
        settings: settings,
        profiles: profiles,
        policy: policy,
      );
    });
  }

  @override
  Future<AiServerSettings> updateSettings({
    required String homeId,
    required AiSettingsUpdate update,
  }) {
    return _run(() async {
      _requireHomeId(homeId);
      if (update.expectedRevision < 0) {
        throw const FormatException('Invalid AI settings revision.');
      }
      final object = (await _client.putAiSettings(
        homeId: homeId,
        body: <String, Object?>{
          'mode': _modeWireValue(update.mode),
          'provider': update.provider,
          'model': update.model,
          'expectedRevision': update.expectedRevision,
        },
      )).requireObject();
      _rejectForeignHome(object, homeId);
      if (_integer(object, 'revision', minimum: 0) !=
              update.expectedRevision + 1 ||
          _string(object, 'mode') != _modeWireValue(update.mode) ||
          _nullableString(object, 'provider') != update.provider ||
          _nullableString(object, 'model') != update.model) {
        throw const FormatException(
          'AI settings update was not revision-bound.',
        );
      }
      final refreshed = (await _client.getAiSettings(
        homeId: homeId,
      )).requireObject();
      _rejectForeignHome(refreshed, homeId);
      final parsed = _settings(refreshed, homeId);
      if (parsed.revision != update.expectedRevision + 1 ||
          parsed.mode != update.mode ||
          parsed.provider != update.provider ||
          parsed.model != update.model) {
        throw const FormatException(
          'AI settings refresh changed after update.',
        );
      }
      return parsed;
    });
  }

  @override
  Future<AiProviderProfile> saveProviderProfile({
    required String homeId,
    required AiProviderProfileDraft draft,
    String? credential,
  }) {
    return _run(() async {
      _requireHomeId(homeId);
      _validateProfileDraft(draft);
      if (credential != null &&
          (credential.length < 16 || credential.length > 500)) {
        throw const AiServerException(AiServerFailureKind.validation);
      }
      final body = <String, Object?>{
        'label': draft.label.trim(),
        'provider': draft.provider,
        'model': draft.model.trim(),
        'estimatedCostMicros': draft.estimatedCostMicros,
        'expectedRevision': draft.expectedRevision,
      };
      if (credential != null) body['credential'] = credential;
      final ApiResponse response;
      if (draft.id == null) {
        response = await _client.createAiProviderProfile(
          homeId: homeId,
          body: body,
        );
      } else {
        response = await _client.updateAiProviderProfile(
          homeId: homeId,
          profileId: draft.id!,
          body: body,
        );
      }
      final object = response.requireObject();
      _rejectForeignHome(object, homeId);
      final settings = AiServerSettings(
        homeId: homeId,
        mode: AiServerMode.serverProxy,
        provider: draft.provider,
        model: draft.model.trim(),
        revision: 0,
        availableProviders: <AiAvailableServerProvider>[
          AiAvailableServerProvider(
            id: draft.provider,
            requiresCredential: credential != null,
          ),
        ],
        credentialEncryptionAvailable: true,
        humanReviewRequired: true,
        serverPersistsUploadedMedia: true,
      );
      final parsed = _profile(object, homeId, settings);
      if ((draft.id != null && parsed.id != draft.id) ||
          parsed.displayName != draft.label.trim() ||
          parsed.providerWireId != draft.provider ||
          parsed.model != draft.model.trim() ||
          parsed.estimatedCostMicros != draft.estimatedCostMicros ||
          parsed.revision != draft.expectedRevision + 1) {
        throw const FormatException(
          'AI provider update was not revision-bound.',
        );
      }
      return parsed;
    });
  }

  @override
  Future<void> deleteProviderProfile({
    required String homeId,
    required String profileId,
    required int expectedRevision,
  }) {
    return _run(() async {
      _requireHomeId(homeId);
      if (profileId.trim().isEmpty || expectedRevision < 1) {
        throw const AiServerException(AiServerFailureKind.validation);
      }
      await _client.deleteAiProviderProfile(
        homeId: homeId,
        profileId: profileId,
        body: <String, Object?>{'expectedRevision': expectedRevision},
      );
    });
  }

  @override
  Future<AiOrchestrationPolicy> updatePolicy({
    required String homeId,
    required AiOrchestrationPolicyUpdate update,
  }) {
    return _run(() async {
      _requireHomeId(homeId);
      _validatePolicyUpdate(update);
      final object = (await _client.putAiOrchestrationPolicy(
        homeId: homeId,
        body: <String, Object?>{
          'extractionProfileIds': update.extractionProfileIds,
          'validationProfileId': update.validationProfileId,
          'maxAttempts': update.maxAttempts,
          'maxTotalTokens': update.maxTotalTokens,
          'maxEstimatedCostMicros': update.maxEstimatedCostMicros,
          'expectedRevision': update.expectedRevision,
        },
      )).requireObject();
      _rejectForeignHome(object, homeId);
      final parsed = _policy(object, homeId);
      if (parsed.revision != update.expectedRevision + 1 ||
          !_sameStrings(
            parsed.extractionProfileIds,
            update.extractionProfileIds,
          ) ||
          parsed.validationProfileId != update.validationProfileId ||
          parsed.maxAttempts != update.maxAttempts ||
          parsed.maxTotalTokens != update.maxTotalTokens ||
          parsed.maxEstimatedCostMicros != update.maxEstimatedCostMicros) {
        throw const FormatException('AI policy update was not revision-bound.');
      }
      return parsed;
    });
  }

  @override
  Future<AiExtractionReview> loadExtractionReview({
    required String homeId,
    required String extractionId,
  }) {
    return _run(() async {
      _requireHomeId(homeId);
      if (extractionId.trim().isEmpty) {
        throw const FormatException('Missing extraction identity.');
      }
      final object = (await _client.getAiExtraction(
        homeId: homeId,
        extractionId: extractionId,
      )).requireObject();
      _rejectForeignHome(object, homeId);
      return _extractionReview(object, homeId, extractionId);
    });
  }

  @override
  Future<AiExtractionReview> reviewCandidate({
    required AiReviewCandidate candidate,
    required AiCandidateDecision decision,
  }) {
    return _run(() async {
      _requireHomeId(candidate.homeId);
      if (candidate.extractionId.trim().isEmpty ||
          candidate.position < 0 ||
          candidate.revision < 1 ||
          candidate.status != AiCandidateReviewStatus.pending) {
        throw const AiServerException(AiServerFailureKind.validation);
      }
      await _client.reviewAiExtractionCandidate(
        homeId: candidate.homeId,
        extractionId: candidate.extractionId,
        position: candidate.position.toString(),
        body: <String, Object?>{
          'decision': switch (decision) {
            AiCandidateDecision.accept => 'accepted',
            AiCandidateDecision.reject => 'rejected',
          },
          'expectedRevision': candidate.revision,
        },
      );
      final review = await loadExtractionReview(
        homeId: candidate.homeId,
        extractionId: candidate.extractionId,
      );
      final updated = review.candidates
          .where((item) => item.position == candidate.position)
          .firstOrNull;
      final expectedStatus = switch (decision) {
        AiCandidateDecision.accept => AiCandidateReviewStatus.accepted,
        AiCandidateDecision.reject => AiCandidateReviewStatus.rejected,
      };
      if (updated == null ||
          updated.status != expectedStatus ||
          updated.revision != candidate.revision + 1) {
        throw const FormatException(
          'AI review decision was not revision-bound.',
        );
      }
      return review;
    });
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AiServerException {
      rethrow;
    } on ProvidentiaApiException catch (error) {
      throw AiServerException(switch (error.statusCode) {
        401 => AiServerFailureKind.authenticationRequired,
        403 || 404 => AiServerFailureKind.forbidden,
        409 => AiServerFailureKind.conflict,
        400 || 413 || 415 || 422 => AiServerFailureKind.validation,
        _ => AiServerFailureKind.unavailable,
      });
    } on FormatException {
      throw const AiServerException(AiServerFailureKind.invalidResponse);
    } on ArgumentError {
      throw const AiServerException(AiServerFailureKind.invalidResponse);
    } on http.ClientException {
      throw const AiServerException(AiServerFailureKind.unavailable);
    }
  }
}

AiServerSettings _settings(Map<String, Object?> object, String homeId) {
  final mode = switch (_string(object, 'mode')) {
    'manual_only' => AiServerMode.manualOnly,
    'server_proxy' => AiServerMode.serverProxy,
    'local_direct' => AiServerMode.localDirect,
    _ => throw const FormatException('Unknown AI mode.'),
  };
  final provider = _nullableString(object, 'provider');
  final model = _nullableString(object, 'model');
  if (mode == AiServerMode.manualOnly && (provider != null || model != null)) {
    throw const FormatException('Manual AI settings selected a provider.');
  }
  if (mode != AiServerMode.manualOnly && (provider == null || model == null)) {
    throw const FormatException('Active AI settings omitted a provider.');
  }
  if (_boolean(object, 'cloudByokOnNativeClients') ||
      !_boolean(object, 'humanReviewRequired') ||
      !_boolean(object, 'serverPersistsUploadedMedia')) {
    throw const FormatException('Unsafe AI privacy flags.');
  }
  final available = _objectList(object, 'availableServerProviders')
      .map((item) {
        final id = _string(item, 'id');
        if (!_serverProviderIds.contains(id)) {
          throw const FormatException('Unknown server AI provider.');
        }
        return AiAvailableServerProvider(
          id: id,
          requiresCredential: _boolean(item, 'requiresCredential'),
        );
      })
      .toList(growable: false);
  if (available.map((provider) => provider.id).toSet().length !=
      available.length) {
    throw const FormatException('Duplicate server AI provider.');
  }
  return AiServerSettings(
    homeId: homeId,
    mode: mode,
    provider: provider,
    model: model,
    revision: _integer(object, 'revision', minimum: 0),
    availableProviders: available,
    credentialEncryptionAvailable: _boolean(
      object,
      'credentialEncryptionAvailable',
    ),
    humanReviewRequired: true,
    serverPersistsUploadedMedia: true,
  );
}

AiProviderProfile _profile(
  Map<String, Object?> object,
  String homeId,
  AiServerSettings settings,
) {
  final id = _string(object, 'id');
  final provider = _string(object, 'provider');
  final kind = switch (provider) {
    'openai' => AiProviderKind.openAi,
    'anthropic' => AiProviderKind.anthropic,
    'gemini' => AiProviderKind.gemini,
    'xai' => AiProviderKind.xAi,
    'openai-compatible' => AiProviderKind.openAiCompatible,
    'ollama' => AiProviderKind.ollama,
    _ => throw const FormatException('Unknown AI provider profile.'),
  };
  final lastFour = object['lastFour'];
  if (lastFour != null && (lastFour is! String || lastFour.length != 4)) {
    throw const FormatException('Invalid credential status metadata.');
  }
  return AiProviderProfile(
    id: id,
    homeId: homeId,
    displayName: _string(object, 'label'),
    kind: kind,
    transport: AiTransport.serverProxy,
    protocol: switch (kind) {
      AiProviderKind.openAi => AiEndpointProtocol.openAiResponses,
      AiProviderKind.anthropic => AiEndpointProtocol.anthropicMessages,
      AiProviderKind.gemini => AiEndpointProtocol.geminiGenerateContent,
      AiProviderKind.xAi || AiProviderKind.openAiCompatible =>
        AiEndpointProtocol.openAiChatCompletions,
      AiProviderKind.ollama => AiEndpointProtocol.ollamaChat,
    },
    model: _string(object, 'model'),
    capabilities: <AiCapability>{
      AiCapability.vision,
      AiCapability.strictJsonSchema,
      AiCapability.multiImage,
      if (kind == AiProviderKind.openAi) AiCapability.storeFalse,
    },
    availability: settings.supportsProvider(provider)
        ? AiProviderAvailability.available
        : AiProviderAvailability.unavailable,
    credentialConfigured: _boolean(object, 'credentialConfigured'),
    revision: _integer(object, 'revision', minimum: 1),
    estimatedCostMicros: _integer(
      object,
      'estimatedCostMicros',
      minimum: 0,
      maximum: 1000000000,
    ),
  );
}

AiOrchestrationPolicy _policy(Map<String, Object?> object, String homeId) {
  final extractionIds = _stringList(object, 'extractionProfileIds');
  final validationId = _nullableString(object, 'validationProfileId');
  final maxAttempts = _integer(object, 'maxAttempts', minimum: 1, maximum: 8);
  if (maxAttempts < extractionIds.length + (validationId == null ? 0 : 1)) {
    throw const FormatException('AI policy attempts cannot run its profiles.');
  }
  return AiOrchestrationPolicy(
    homeId: homeId,
    extractionProfileIds: extractionIds,
    validationProfileId: validationId,
    maxAttempts: maxAttempts,
    maxTotalTokens: _integer(
      object,
      'maxTotalTokens',
      minimum: 1,
      maximum: 1000000,
    ),
    maxEstimatedCostMicros: _integer(
      object,
      'maxEstimatedCostMicros',
      minimum: 0,
      maximum: 1000000000,
    ),
    revision: _integer(object, 'revision', minimum: 0),
  );
}

AiExtractionReview _extractionReview(
  Map<String, Object?> object,
  String homeId,
  String extractionId,
) {
  if (_string(object, 'id') != extractionId ||
      _string(object, 'status') != 'review_required') {
    throw const FormatException('AI extraction identity or state changed.');
  }
  final kind = switch (_string(object, 'kind')) {
    'receipt' => AiExtractionKind.receipt,
    'stock' => AiExtractionKind.stockPhoto,
    _ => throw const FormatException('Unknown AI extraction kind.'),
  };
  final candidates = _objectList(object, 'candidates')
      .map((candidate) {
        final payload = _object(candidate['payload'], 'candidate payload');
        final candidateType = switch (_string(candidate, 'candidateType')) {
          'receipt_line' => AiCandidateType.receiptLine,
          'stock_item' => AiCandidateType.stockItem,
          _ => throw const FormatException('Unknown AI candidate type.'),
        };
        if (_string(payload, 'candidateType') !=
                switch (candidateType) {
                  AiCandidateType.receiptLine => 'receipt_line',
                  AiCandidateType.stockItem => 'stock_item',
                } ||
            (kind == AiExtractionKind.receipt) !=
                (candidateType == AiCandidateType.receiptLine)) {
          throw const FormatException('AI candidate kind mismatch.');
        }
        final label =
            _optionalString(payload['product']) ??
            _optionalString(payload['description']) ??
            _optionalString(payload['rawText']);
        if (label == null) {
          throw const FormatException('AI candidate has no review label.');
        }
        return AiReviewCandidate(
          homeId: homeId,
          extractionId: extractionId,
          position: _integer(candidate, 'position', minimum: 0),
          type: candidateType,
          label: label,
          status: switch (_string(candidate, 'reviewStatus')) {
            'pending' => AiCandidateReviewStatus.pending,
            'accepted' => AiCandidateReviewStatus.accepted,
            'rejected' => AiCandidateReviewStatus.rejected,
            _ => throw const FormatException('Unknown AI candidate status.'),
          },
          revision: _integer(candidate, 'revision', minimum: 1),
        );
      })
      .toList(growable: false);
  if (candidates.map((candidate) => candidate.position).toSet().length !=
      candidates.length) {
    throw const FormatException('Duplicate AI candidate position.');
  }
  return AiExtractionReview(
    homeId: homeId,
    extractionId: extractionId,
    kind: kind,
    candidates: candidates,
  );
}

void _validateProfileDraft(AiProviderProfileDraft draft) {
  final id = draft.id;
  if ((id != null &&
          (id.isEmpty || id.length > 36 || !_profileIdPattern.hasMatch(id))) ||
      draft.label.trim().isEmpty ||
      draft.label.trim().length > 80 ||
      draft.model.trim().isEmpty ||
      draft.model.trim().length > 120 ||
      !_serverProviderIds.contains(draft.provider) ||
      draft.estimatedCostMicros < 0 ||
      draft.estimatedCostMicros > 1000000000 ||
      draft.expectedRevision < 0 ||
      (id == null && draft.expectedRevision != 0) ||
      (id != null && draft.expectedRevision < 1)) {
    throw const AiServerException(AiServerFailureKind.validation);
  }
}

void _validatePolicyUpdate(AiOrchestrationPolicyUpdate update) {
  if (update.extractionProfileIds.isEmpty ||
      update.extractionProfileIds.length > 4 ||
      update.extractionProfileIds.toSet().length !=
          update.extractionProfileIds.length ||
      update.extractionProfileIds.any(
        (id) => id.isEmpty || id.length > 36 || !_profileIdPattern.hasMatch(id),
      ) ||
      (update.validationProfileId != null &&
          (update.validationProfileId!.isEmpty ||
              update.validationProfileId!.length > 36 ||
              !_profileIdPattern.hasMatch(update.validationProfileId!))) ||
      update.maxAttempts <
          update.extractionProfileIds.length +
              (update.validationProfileId == null ? 0 : 1) ||
      update.maxAttempts > 8 ||
      update.maxTotalTokens < 1 ||
      update.maxTotalTokens > 1000000 ||
      update.maxEstimatedCostMicros < 0 ||
      update.maxEstimatedCostMicros > 1000000000 ||
      update.expectedRevision < 0) {
    throw const AiServerException(AiServerFailureKind.validation);
  }
}

String _modeWireValue(AiServerMode mode) => switch (mode) {
  AiServerMode.manualOnly => 'manual_only',
  AiServerMode.serverProxy => 'server_proxy',
  AiServerMode.localDirect => 'local_direct',
};

void _requireHomeId(String homeId) {
  if (homeId.trim().isEmpty) {
    throw const AiServerException(AiServerFailureKind.validation);
  }
}

void _rejectForeignHome(Object? value, String expectedHomeId) {
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      if (entry.key == 'homeId' && entry.value != expectedHomeId) {
        throw const FormatException('AI response crossed a home boundary.');
      }
      _rejectForeignHome(entry.value, expectedHomeId);
    }
  } else if (value is List<Object?>) {
    for (final item in value) {
      _rejectForeignHome(item, expectedHomeId);
    }
  }
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Missing $label.');
  }
  return value;
}

List<Map<String, Object?>> _objectList(
  Map<String, Object?> object,
  String key,
) {
  final value = object[key];
  if (value is! List<Object?>) {
    throw FormatException('Missing $key.');
  }
  return value.map((item) => _object(item, key)).toList(growable: false);
}

List<String> _stringList(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('Missing $key.');
  }
  final strings = value.cast<String>();
  if (strings.any((item) => item.isEmpty || item.length > 36) ||
      strings.toSet().length != strings.length) {
    throw FormatException('Invalid $key.');
  }
  return List<String>.unmodifiable(strings);
}

String _string(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key.');
  }
  return value;
}

String? _nullableString(Map<String, Object?> object, String key) {
  if (!object.containsKey(key)) throw FormatException('Missing $key.');
  final value = object[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

String? _optionalString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

bool _boolean(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! bool) throw FormatException('Missing $key.');
  return value;
}

int _integer(
  Map<String, Object?> object,
  String key, {
  required int minimum,
  int? maximum,
}) {
  final value = object[key];
  if (value is! int ||
      value < minimum ||
      (maximum != null && value > maximum)) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

bool _sameStrings(List<String> first, List<String> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

const Set<String> _serverProviderIds = <String>{
  'openai',
  'anthropic',
  'gemini',
  'xai',
  'openai-compatible',
  'ollama',
};
final RegExp _profileIdPattern = RegExp(r'^[A-Za-z0-9-]{1,36}$');
