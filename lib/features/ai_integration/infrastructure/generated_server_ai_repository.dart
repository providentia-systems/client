import 'package:http/http.dart' as http;
import 'package:providentia/features/ai_integration/application/server_ai_repository.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Closed, current-contract (API 1.19) boundary for household AI management
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
      final endpoint = draft.endpoint?.trim();
      final body = <String, Object?>{
        'label': draft.label.trim(),
        'provider': draft.provider,
        'model': draft.model.trim(),
        'ownerScope': _ownerScopeWireValue(draft.ownerScope),
        'estimatedCostMicros': draft.estimatedCostMicros,
        'expectedRevision': draft.expectedRevision,
      };
      if (endpoint != null) body['endpoint'] = endpoint;
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
        serverPersistsUploadedMedia: false,
        mediaHandling: _safeMediaHandling,
      );
      final parsed = _profile(object, homeId, settings);
      if ((draft.id != null && parsed.id != draft.id) ||
          parsed.displayName != draft.label.trim() ||
          parsed.providerWireId != draft.provider ||
          parsed.model != draft.model.trim() ||
          parsed.ownerScope != draft.ownerScope ||
          parsed.endpoint?.toString() !=
              (endpoint == null ? null : Uri.parse(endpoint).toString()) ||
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
        403 || 404 => AiServerFailureKind.authorizationDenied,
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
      _boolean(object, 'serverPersistsUploadedMedia')) {
    throw const FormatException('Unsafe AI privacy flags.');
  }
  final mediaHandling = _mediaHandling(
    _object(object['mediaHandling'], 'AI media handling'),
  );
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
    serverPersistsUploadedMedia: false,
    mediaHandling: mediaHandling,
  );
}

AiMediaHandling _mediaHandling(Map<String, Object?> object) {
  final directExtractionUpload = switch (_string(
    object,
    'directExtractionUpload',
  )) {
    'transient_not_persisted' => AiDirectExtractionUpload.transientNotPersisted,
    _ => throw const FormatException(
      'Unsafe direct-extraction media handling.',
    ),
  };
  final privateMediaStorage = switch (_string(object, 'privateMediaStorage')) {
    'explicit_encrypted_opt_in' => AiPrivateMediaStorage.explicitEncryptedOptIn,
    _ => throw const FormatException('Unsafe private-media storage policy.'),
  };
  final retentionValues = _stringList(object, 'privateMediaRetentionOptions');
  final retentionOptions = retentionValues.map((value) {
    return switch (value) {
      'transient' => AiPrivateMediaRetention.transient,
      'retained' => AiPrivateMediaRetention.retained,
      _ => throw const FormatException(
        'Unsafe private-media retention option.',
      ),
    };
  }).toSet();
  if (retentionValues.length != retentionOptions.length ||
      _boolean(object, 'plaintextMediaAtRest') ||
      !_boolean(object, 'cloudProviderTransmissionRequiresConsent')) {
    throw const FormatException('Unsafe AI media-handling policy.');
  }
  return AiMediaHandling(
    directExtractionUpload: directExtractionUpload,
    privateMediaStorage: privateMediaStorage,
    privateMediaRetentionOptions: retentionOptions,
    plaintextMediaAtRest: false,
    cloudProviderTransmissionRequiresConsent: true,
  );
}

final AiMediaHandling _safeMediaHandling = AiMediaHandling(
  directExtractionUpload: AiDirectExtractionUpload.transientNotPersisted,
  privateMediaStorage: AiPrivateMediaStorage.explicitEncryptedOptIn,
  privateMediaRetentionOptions: const <AiPrivateMediaRetention>{
    AiPrivateMediaRetention.transient,
    AiPrivateMediaRetention.retained,
  },
  plaintextMediaAtRest: false,
  cloudProviderTransmissionRequiresConsent: true,
);

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
  final ownerScope = switch (_string(object, 'ownerScope')) {
    'private' => AiProfileOwnerScope.private,
    'home' => AiProfileOwnerScope.home,
    _ => throw const FormatException('Unknown AI profile owner scope.'),
  };
  return AiProviderProfile(
    id: id,
    homeId: homeId,
    displayName: _string(object, 'label'),
    kind: kind,
    ownerScope: ownerScope,
    endpoint: _profileEndpoint(object, provider),
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

/// Endpoint values are profile-owned base URLs for the openai-compatible and
/// ollama providers only. Every other provider must publish null. The client
/// mirrors the write policy loosely: an absolute HTTPS URL, with plain HTTP
/// tolerated only for ollama because the deployment opt-in may allow
/// local-network endpoints there.
Uri? _profileEndpoint(Map<String, Object?> object, String provider) {
  if (!object.containsKey('endpoint')) {
    throw const FormatException('Missing endpoint.');
  }
  final value = object['endpoint'];
  if (value == null) return null;
  if (value is! String || !_validEndpoint(value, provider)) {
    throw const FormatException('Invalid endpoint.');
  }
  return Uri.parse(value);
}

bool _validEndpoint(String endpoint, String provider) {
  if (endpoint.trim() != endpoint ||
      endpoint.isEmpty ||
      endpoint.length > 300 ||
      (provider != 'openai-compatible' && provider != 'ollama')) {
    return false;
  }
  final parsed = Uri.tryParse(endpoint);
  return parsed != null &&
      parsed.isAbsolute &&
      parsed.host.isNotEmpty &&
      (parsed.scheme == 'https' ||
          (provider == 'ollama' && parsed.scheme == 'http'));
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
  _integer(object, 'schemaVersion', minimum: 2, maximum: 2);
  final kind = switch (_string(object, 'kind')) {
    'receipt' => AiExtractionKind.receipt,
    'stock' => AiExtractionKind.stockPhoto,
    _ => throw const FormatException('Unknown AI extraction kind.'),
  };
  final receiptHeader = kind == AiExtractionKind.receipt
      ? _receiptHeader(object['result'])
      : null;
  final candidates = _objectList(object, 'candidates')
      .map((candidate) {
        final payload = _object(candidate['payload'], 'candidate payload');
        final candidateType = switch (_string(candidate, 'candidateType')) {
          'receipt_line' => AiCandidateType.receiptLine,
          'stock_item' => AiCandidateType.stockItem,
          _ => throw const FormatException('Unknown AI candidate type.'),
        };
        _validateCandidatePayload(payload, candidateType);
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
          receiptPayload: candidateType == AiCandidateType.receiptLine
              ? _receiptCandidatePayload(payload, receiptHeader)
              : null,
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

AiReceiptHeaderPayload? _receiptHeader(Object? value) {
  if (value == null) return null;
  final result = _object(value, 'AI extraction result');
  _requireExactKeys(result, _receiptResultKeys, 'AI extraction result');
  if (_string(result, 'documentType') != 'receipt') {
    throw const FormatException('AI receipt result changed kind.');
  }
  _boundedStringList(result['warnings'], 'receipt warnings', 50);
  if (result['candidates'] is! List<Object?>) {
    throw const FormatException('Invalid receipt result candidates.');
  }
  return AiReceiptHeaderPayload(
    merchant: _nullableBoundedText(result, 'merchant', 191),
    receiptNumber: _nullableBoundedText(result, 'receiptNumber', 191),
    purchaseDate: _nullableDate(result, 'purchaseDate'),
    currency: _nullableCurrency(result, 'currency'),
    totalMinorUnits: _nullableMinorUnits(result, 'totalAmount'),
    taxMinorUnits: _nullableMinorUnits(result, 'taxAmount'),
    notes: _nullableBoundedText(result, 'notes', 2000),
  );
}

AiReceiptCandidatePayload _receiptCandidatePayload(
  Map<String, Object?> payload,
  AiReceiptHeaderPayload? header,
) => AiReceiptCandidatePayload(
  rawText: _nullableBoundedText(payload, 'rawText', 500),
  description: _boundedString(payload, 'description', 500),
  quantity: _positiveDecimal(payload, 'quantity'),
  packText: _nullableBoundedText(payload, 'packText', 191),
  unitPriceMinorUnits: _nullableMinorUnits(payload, 'unitPrice'),
  lineTotalMinorUnits: _nullableMinorUnits(payload, 'lineTotal'),
  header: header,
);

void _validateCandidatePayload(
  Map<String, Object?> payload,
  AiCandidateType candidateType,
) {
  _requireExactKeys(payload, _candidatePayloadKeys, 'AI candidate payload');
  _boundedString(payload, 'description', 500);
  for (final field in <String>['rawText', 'brand', 'product', 'variant']) {
    _nullableBoundedText(payload, field, 500);
  }
  switch (candidateType) {
    case AiCandidateType.receiptLine:
      if (_string(payload, 'candidateType') != 'receipt_line') {
        throw const FormatException('AI candidate kind mismatch.');
      }
      _positiveDecimal(payload, 'quantity');
      _requireNull(payload, 'quantityMinimum');
      _requireNull(payload, 'quantityMaximum');
      break;
    case AiCandidateType.stockItem:
      if (_string(payload, 'candidateType') != 'stock_item') {
        throw const FormatException('AI candidate kind mismatch.');
      }
      _requireNull(payload, 'quantity');
      final minimum = _nonNegativeDecimal(payload, 'quantityMinimum');
      final maximum = _nonNegativeDecimal(payload, 'quantityMaximum');
      if (maximum < minimum) {
        throw const FormatException('Invalid stock quantity range.');
      }
      break;
  }
  _nullableBoundedText(payload, 'packText', 191);
  for (final field in <String>[
    'unitPrice',
    'lineTotal',
    'discountAmount',
    'taxAmount',
  ]) {
    _nullableMinorUnits(payload, field);
  }
  final boundingRegion = payload['boundingRegion'];
  if (boundingRegion != null && boundingRegion is! Map<String, Object?>) {
    throw const FormatException('Invalid AI candidate bounding region.');
  }
  final confidence = payload['confidence'];
  if (confidence is! num || confidence < 0 || confidence > 1) {
    throw const FormatException('Invalid AI candidate confidence.');
  }
  if (payload['fieldConfidence'] is! Map<String, Object?>) {
    throw const FormatException('Invalid AI candidate field confidence.');
  }
  _boundedStringList(payload['warnings'], 'candidate warnings', 20);
  _boundedStringList(
    payload['unresolvedValues'],
    'candidate unresolved values',
    20,
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
      (draft.endpoint != null &&
          !_validEndpoint(draft.endpoint!.trim(), draft.provider)) ||
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

String _ownerScopeWireValue(AiProfileOwnerScope scope) => switch (scope) {
  AiProfileOwnerScope.private => 'private',
  AiProfileOwnerScope.home => 'home',
};

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

String _boundedString(Map<String, Object?> object, String key, int maximum) {
  final value = _string(object, key).trim();
  if (value.length > maximum) throw FormatException('Invalid $key.');
  return value;
}

String? _nullableBoundedText(
  Map<String, Object?> object,
  String key,
  int maximum,
) {
  if (!object.containsKey(key)) throw FormatException('Missing $key.');
  final value = object[key];
  if (value == null) return null;
  if (value is! String || value.length > maximum) {
    throw FormatException('Invalid $key.');
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

double _positiveDecimal(Map<String, Object?> object, String key) {
  final parsed = _nonNegativeDecimal(object, key);
  if (parsed <= 0) throw FormatException('Invalid $key.');
  return parsed;
}

double _nonNegativeDecimal(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String || !_decimalPattern.hasMatch(value)) {
    throw FormatException('Invalid $key.');
  }
  final parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite || parsed < 0) {
    throw FormatException('Invalid $key.');
  }
  return parsed;
}

void _requireNull(Map<String, Object?> object, String key) {
  if (!object.containsKey(key) || object[key] != null) {
    throw FormatException('Invalid $key.');
  }
}

int? _nullableMinorUnits(Map<String, Object?> object, String key) {
  if (!object.containsKey(key)) throw FormatException('Missing $key.');
  final value = object[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid $key.');
  final match = _decimalPartsPattern.firstMatch(value);
  if (match == null) throw FormatException('Invalid $key.');
  final fraction = match.group(2) ?? '';
  if (fraction.length > 2 && fraction.substring(2).contains(RegExp('[1-9]'))) {
    throw FormatException('Invalid $key precision.');
  }
  final whole = int.tryParse(match.group(1)!);
  final cents = int.tryParse('${fraction}00'.substring(0, 2));
  if (whole == null || cents == null) throw FormatException('Invalid $key.');
  return whole * 100 + cents;
}

DateTime? _nullableDate(Map<String, Object?> object, String key) {
  final raw = _nullableBoundedText(object, key, 10);
  if (raw == null) return null;
  final match = _datePattern.firstMatch(raw);
  if (match == null) throw FormatException('Invalid $key.');
  final parsed = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  if ('${parsed.year.toString().padLeft(4, '0')}-'
          '${parsed.month.toString().padLeft(2, '0')}-'
          '${parsed.day.toString().padLeft(2, '0')}' !=
      raw) {
    throw FormatException('Invalid $key.');
  }
  return parsed;
}

String? _nullableCurrency(Map<String, Object?> object, String key) {
  final value = _nullableBoundedText(object, key, 3);
  if (value != null && !_currencyPattern.hasMatch(value)) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

void _boundedStringList(Object? value, String label, int maximum) {
  if (value is! List<Object?> ||
      value.length > maximum ||
      value.any((item) => item is! String || item.length > 500)) {
    throw FormatException('Invalid $label.');
  }
}

void _requireExactKeys(
  Map<String, Object?> object,
  Set<String> expected,
  String label,
) {
  if (object.length != expected.length ||
      !object.keys.every(expected.contains)) {
    throw FormatException('Unexpected $label fields.');
  }
}

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
final RegExp _decimalPattern = RegExp(
  r'^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,8})?$',
);
final RegExp _decimalPartsPattern = RegExp(r'^([0-9]+)(?:\.([0-9]+))?$');
final RegExp _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');
const Set<String> _candidatePayloadKeys = <String>{
  'candidateType',
  'rawText',
  'description',
  'brand',
  'product',
  'variant',
  'quantity',
  'quantityMinimum',
  'quantityMaximum',
  'packText',
  'unitPrice',
  'lineTotal',
  'discountAmount',
  'taxAmount',
  'boundingRegion',
  'confidence',
  'fieldConfidence',
  'warnings',
  'unresolvedValues',
};
const Set<String> _receiptResultKeys = <String>{
  'documentType',
  'merchant',
  'receiptNumber',
  'purchaseDate',
  'currency',
  'totalAmount',
  'taxAmount',
  'notes',
  'warnings',
  'candidates',
};
