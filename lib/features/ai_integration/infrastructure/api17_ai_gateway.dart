import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/ephemeral_bytes.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

abstract interface class PreparedMediaByteReader {
  Future<Uint8List> read(PreparedAiMedia media);
}

/// Server-proxy AI adapter for the bounded API 1.12 multi-image contract.
final class Api17AiGateway implements AiProviderGateway {
  factory Api17AiGateway({
    required ProvidentiaApiClient client,
    required PreparedMediaByteReader mediaReader,
  }) => Api17AiGateway._(client, mediaReader);

  const Api17AiGateway._(this._client, this._mediaReader);

  final ProvidentiaApiClient _client;
  final PreparedMediaByteReader _mediaReader;

  @override
  AiGatewayRoute get route => AiGatewayRoute.serverProxyCloud;

  @override
  Future<AiGatewayReadiness> readiness(AiProviderProfile profile) async {
    if (profile.transport != AiTransport.serverProxy) {
      return const AiGatewayReadiness(
        state: AiGatewayReadinessState.missingCapability,
        safeMessage: 'This provider is not configured for the server proxy.',
      );
    }
    try {
      final settings = (await _client.getAiSettings(
        homeId: profile.homeId,
      )).requireObject();
      if (settings['credentialEncryptionAvailable'] != true) {
        return const AiGatewayReadiness(
          state: AiGatewayReadinessState.unavailable,
          safeMessage: 'Encrypted AI credential storage is unavailable.',
        );
      }
      final providers = settings['availableServerProviders'];
      final supported =
          providers is List<Object?> &&
          providers.whereType<Map<String, Object?>>().any(
            (provider) => provider['id'] == profile.providerWireId,
          );
      return supported
          ? const AiGatewayReadiness.ready()
          : const AiGatewayReadiness(
              state: AiGatewayReadinessState.missingCapability,
              safeMessage:
                  'The selected provider is not enabled by the server.',
            );
    } on ProvidentiaApiException catch (error) {
      if (error.statusCode == 403 || error.statusCode == 404) {
        throw const AiGatewayAuthorizationDeniedException();
      }
      return const AiGatewayReadiness(
        state: AiGatewayReadinessState.unavailable,
        safeMessage: 'AI settings could not be verified.',
      );
    } on Object {
      return const AiGatewayReadiness(
        state: AiGatewayReadinessState.unavailable,
        safeMessage: 'AI settings could not be verified.',
      );
    }
  }

  @override
  Future<AiExtractionResult<ReceiptProposal>> extractReceipt(
    AiExtractionRequest request,
  ) async {
    try {
      final extraction = await _extract(request);
      final proposal = _receiptProposal(request, extraction);
      if (proposal.requiresQuarantine) {
        return AiExtractionQuarantined<ReceiptProposal>(
          classification: proposal.classification.name,
        );
      }
      return AiExtractionSuccess<ReceiptProposal>(
        proposal: proposal,
        metadata: _metadata(request, extraction),
      );
    } on _Api17AiBoundaryException catch (error) {
      return AiExtractionFailure<ReceiptProposal>(
        code: error.code,
        safeMessage: error.safeMessage,
      );
    } on ProvidentiaApiException catch (error) {
      if (error.statusCode == 403 || error.statusCode == 404) {
        throw const AiGatewayAuthorizationDeniedException();
      }
      return AiExtractionFailure<ReceiptProposal>(
        code: 'server_${error.statusCode}',
        safeMessage: 'The AI extraction could not be completed safely.',
      );
    } on Object {
      return const AiExtractionFailure<ReceiptProposal>(
        code: 'invalid_ai_response',
        safeMessage: 'The AI response did not match the required schema.',
      );
    }
  }

  @override
  Future<AiExtractionResult<StockPhotoProposal>> extractStockPhoto(
    AiExtractionRequest request,
  ) async {
    try {
      final extraction = await _extract(request);
      final proposal = _stockProposal(request, extraction);
      if (proposal.requiresQuarantine) {
        return AiExtractionQuarantined<StockPhotoProposal>(
          classification: proposal.classification.name,
        );
      }
      return AiExtractionSuccess<StockPhotoProposal>(
        proposal: proposal,
        metadata: _metadata(request, extraction),
      );
    } on _Api17AiBoundaryException catch (error) {
      return AiExtractionFailure<StockPhotoProposal>(
        code: error.code,
        safeMessage: error.safeMessage,
      );
    } on ProvidentiaApiException catch (error) {
      if (error.statusCode == 403 || error.statusCode == 404) {
        throw const AiGatewayAuthorizationDeniedException();
      }
      return AiExtractionFailure<StockPhotoProposal>(
        code: 'server_${error.statusCode}',
        safeMessage: 'The AI extraction could not be completed safely.',
      );
    } on Object {
      return const AiExtractionFailure<StockPhotoProposal>(
        code: 'invalid_ai_response',
        safeMessage: 'The AI response did not match the required schema.',
      );
    }
  }

  Future<Map<String, Object?>> _extract(AiExtractionRequest request) async {
    if (request.homeId.trim().isEmpty ||
        request.homeId != request.provider.homeId ||
        request.homeId != request.media.homeId ||
        request.media.purpose != request.kind) {
      throw const _Api17AiBoundaryException(
        'home_scope_mismatch',
        'The provider, media, and extraction must belong to the active home.',
      );
    }
    if (request.privacyMode != AiPrivacyMode.serverProxyCloud ||
        request.provider.transport != AiTransport.serverProxy) {
      throw const _Api17AiBoundaryException(
        'invalid_ai_route',
        'The selected privacy route cannot use the server proxy.',
      );
    }
    if (request.media.media.isEmpty || request.media.media.length > 8) {
      throw const _Api17AiBoundaryException(
        'api17_image_limit',
        'Select between one and eight prepared images.',
      );
    }
    final preparedBytes = <Uint8List>[];
    Uint8List? aggregateBytes;
    try {
      for (final media in request.media.media) {
        if (!const <String>{
          'image/jpeg',
          'image/png',
          'image/webp',
        }.contains(media.mimeType)) {
          throw const _Api17AiBoundaryException(
            'unsupported_media_type',
            'Prepare every selected image as JPEG, PNG, or WebP.',
          );
        }
        final bytes = await _mediaReader.read(media);
        preparedBytes.add(bytes);
        if (bytes.length != media.byteLength ||
            sha256.convert(bytes).toString() != media.sha256) {
          throw const _Api17AiBoundaryException(
            'prepared_media_changed',
            'A prepared image changed after consent. Prepare the selection again.',
          );
        }
      }
      final aggregateByteCount = preparedBytes.fold<int>(
        0,
        (total, bytes) => total + bytes.length,
      );
      aggregateBytes = Uint8List(aggregateByteCount);
      var aggregateOffset = 0;
      for (final bytes in preparedBytes) {
        aggregateBytes.setRange(
          aggregateOffset,
          aggregateOffset + bytes.length,
          bytes,
        );
        aggregateOffset += bytes.length;
      }
      final aggregateSha256 = sha256.convert(aggregateBytes).toString();
      final media = request.media.media.first;
      final formFields = <String, String>{
        'kind': request.kind == AiExtractionKind.receipt ? 'receipt' : 'stock',
        'transmissionConsent': 'true',
      };
      final targetId = request.targetId?.trim();
      if (targetId != null && targetId.isNotEmpty) {
        formFields['targetId'] = targetId;
      }
      final created = (await _client.createAiExtraction(
        homeId: request.homeId,
        formFields: formFields,
        files: List<http.MultipartFile>.generate(preparedBytes.length, (index) {
          final item = request.media.media[index];
          return http.MultipartFile.fromBytes(
            index == 0 ? 'image' : 'images[]',
            preparedBytes[index],
            filename:
                'prepared-${item.sha256.substring(0, 12)}.${_extension(item.mimeType)}',
            contentType: MediaType.parse(item.mimeType),
          );
        }),
      )).requireObject();
      final extractionId = _string(created, 'id');
      if (created['status'] != 'review_required') {
        throw const _Api17AiBoundaryException(
          'invalid_ai_response',
          'The AI extraction did not enter mandatory review.',
        );
      }
      final createdCandidateCount = _integer(created, 'candidateCount');
      final observationCount = _integer(created, 'observationCount');
      if (createdCandidateCount < 0 || createdCandidateCount > 200) {
        throw const FormatException('Invalid candidate count.');
      }
      if (observationCount != request.media.media.length) {
        throw const FormatException('Invalid observation count.');
      }
      final extraction = (await _client.getAiExtraction(
        homeId: request.homeId,
        extractionId: extractionId,
      )).requireObject();
      if (extraction['status'] != 'review_required') {
        throw _Api17AiBoundaryException(
          'extraction_${extraction['status'] ?? 'unknown'}',
          'The extraction did not reach mandatory human review.',
        );
      }
      _validateExtractionBinding(
        request: request,
        firstMedia: media,
        aggregateSha256: aggregateSha256,
        aggregateByteCount: aggregateByteCount,
        extractionId: extractionId,
        candidateCount: createdCandidateCount,
        extraction: extraction,
      );
      return extraction;
    } finally {
      for (final bytes in preparedBytes) {
        wipeEphemeralBytes(bytes);
      }
      wipeEphemeralBytes(aggregateBytes);
    }
  }

  ReceiptProposal _receiptProposal(
    AiExtractionRequest request,
    Map<String, Object?> extraction,
  ) {
    final result = _object(extraction['result'], 'result');
    final warnings = _strings(result['warnings']);
    final candidates = _objects(extraction['candidates']);
    final lines = <ReceiptLineProposal>[];
    for (final candidate in candidates) {
      final payload = _object(candidate['payload'], 'candidate payload');
      final confidence = _number(payload['confidence']);
      final fields = _object(payload['fieldConfidence'], 'field confidence');
      lines.add(
        ReceiptLineProposal(
          lineId:
              '${_string(extraction, 'id')}:${_integer(candidate, 'position')}',
          rawText:
              _optionalString(payload['rawText']) ??
              _string(payload, 'description'),
          brand: _field(_optionalString(payload['brand']), confidence),
          productName: _field(
            _optionalString(payload['product']) ??
                _string(payload, 'description'),
            _confidence(fields['description'], confidence),
          ),
          productFamily: _field(null, 0),
          variant: _field(_optionalString(payload['variant']), confidence),
          packDescription: _field(
            _optionalString(payload['packText']),
            _confidence(fields['packText'], confidence),
          ),
          quantity: ExtractedField<double>(
            value: double.tryParse(_string(payload, 'quantity')),
            confidence: _confidence(fields['quantity'], confidence),
          ),
          unitPrice: _field(
            _optionalString(payload['unitPrice']),
            _confidence(fields['unitPrice'], confidence),
          ),
          lineTotal: _field(
            _optionalString(payload['lineTotal']),
            _confidence(fields['lineTotal'], confidence),
          ),
          discount: _field(
            _optionalString(payload['discountAmount']),
            confidence,
          ),
          tax: _field(_optionalString(payload['taxAmount']), confidence),
          notes: _field(null, 0),
          confidence: confidence,
          warnings: <String>[
            ..._strings(payload['warnings']),
            ..._strings(payload['unresolvedValues']),
          ],
          region: _region(payload['boundingRegion']),
        ),
      );
    }
    final classification = switch (result['documentType']) {
      'receipt' => ReceiptDocumentClassification.receipt,
      _ => ReceiptDocumentClassification.unknown,
    };
    return ReceiptProposal(
      id: _string(extraction, 'id'),
      runId: request.runId,
      schemaVersion: request.schemaVersion,
      classification: classification,
      header: ReceiptHeaderProposal(
        purchaseDate: _field(_optionalString(result['purchaseDate']), 0.5),
        storeName: _field(_optionalString(result['merchant']), 0.5),
        receiptNumber: _field(_optionalString(result['receiptNumber']), 0.5),
        currency: _field(_optionalString(result['currency']), 0.5),
        subtotal: _field(null, 0),
        taxTotal: _field(_optionalString(result['taxAmount']), 0.5),
        discountTotal: _field(null, 0),
        total: _field(_optionalString(result['totalAmount']), 0.5),
      ),
      lines: lines,
      warnings: warnings,
    );
  }

  StockPhotoProposal _stockProposal(
    AiExtractionRequest request,
    Map<String, Object?> extraction,
  ) {
    final result = _object(extraction['result'], 'result');
    final candidates = _deduplicateStockCandidates(
      _objects(extraction['candidates']),
    );
    return StockPhotoProposal(
      id: _string(extraction, 'id'),
      runId: request.runId,
      schemaVersion: request.schemaVersion,
      classification: result['documentType'] == 'stock'
          ? StockImageClassification.pantryStock
          : StockImageClassification.unknown,
      candidates: candidates
          .map((candidate) {
            final payload = _object(candidate['payload'], 'candidate payload');
            final confidence = _number(payload['confidence']);
            final quantity = double.tryParse(_string(payload, 'quantity')) ?? 0;
            return StockCandidateProposal(
              candidateId:
                  '${_string(extraction, 'id')}:${_integer(candidate, 'position')}',
              brand: _field(_optionalString(payload['brand']), confidence),
              productName: _field(
                _optionalString(payload['product']) ??
                    _string(payload, 'description'),
                confidence,
              ),
              variant: _field(_optionalString(payload['variant']), confidence),
              packDescription: _field(
                _optionalString(payload['packText']),
                confidence,
              ),
              quantityMinimum: quantity,
              quantityMaximum: quantity,
              confidence: confidence,
              warnings: <String>[
                ..._strings(payload['warnings']),
                ..._strings(payload['unresolvedValues']),
              ],
              region: _region(payload['boundingRegion']),
            );
          })
          .toList(growable: false),
      warnings: _strings(result['warnings']),
    );
  }

  AiRunMetadata _metadata(
    AiExtractionRequest request,
    Map<String, Object?> extraction,
  ) {
    final usage = extraction['usage'] is Map<String, Object?>
        ? extraction['usage']! as Map<String, Object?>
        : const <String, Object?>{};
    return AiRunMetadata(
      providerKind: request.provider.kind,
      model: _optionalString(extraction['model']) ?? request.provider.model,
      protocol: request.provider.protocol,
      promptVersion: request.promptVersion,
      schemaVersion: request.schemaVersion,
      processingTime: Duration(
        milliseconds: _optionalInteger(extraction['processingMs']) ?? 0,
      ),
      inputTokens: _optionalInteger(usage['inputTokens']),
      outputTokens: _optionalInteger(usage['outputTokens']),
    );
  }
}

final class _Api17AiBoundaryException implements Exception {
  const _Api17AiBoundaryException(this.code, this.safeMessage);

  final String code;
  final String safeMessage;
}

void _validateExtractionBinding({
  required AiExtractionRequest request,
  required PreparedAiMedia firstMedia,
  required String aggregateSha256,
  required int aggregateByteCount,
  required String extractionId,
  required int candidateCount,
  required Map<String, Object?> extraction,
}) {
  final expectedKind = request.kind == AiExtractionKind.receipt
      ? 'receipt'
      : 'stock';
  if (_string(extraction, 'id') != extractionId ||
      _string(extraction, 'kind') != expectedKind ||
      _string(extraction, 'inputMimeType') != firstMedia.mimeType ||
      _string(extraction, 'inputSha256') != aggregateSha256 ||
      _integer(extraction, 'inputByteCount') != aggregateByteCount ||
      _integer(extraction, 'schemaVersion') != 1 ||
      _integer(extraction, 'promptTemplateVersion') < 1 ||
      _string(extraction, 'provider').trim().isEmpty ||
      _string(extraction, 'model').trim().isEmpty ||
      _objects(extraction['candidates']).length != candidateCount) {
    throw const FormatException('Extraction response binding changed.');
  }
  final expectedTarget = request.targetId?.trim();
  final actualTarget = _optionalString(extraction['targetId']);
  if ((expectedTarget == null || expectedTarget.isEmpty)
      ? actualTarget != null
      : actualTarget != expectedTarget) {
    throw const FormatException('Extraction target binding changed.');
  }
}

List<Map<String, Object?>> _deduplicateStockCandidates(
  List<Map<String, Object?>> candidates,
) {
  final seen = <String, int>{};
  final unique = <Map<String, Object?>>[];
  for (final candidate in candidates) {
    final payload = _object(candidate['payload'], 'candidate payload');
    String normalized(Object? value) => value is String
        ? value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')
        : '';
    final key = <String>[
      normalized(payload['description']),
      normalized(payload['product']),
      normalized(payload['brand']),
      normalized(payload['variant']),
      normalized(payload['packText']),
      normalized(payload['quantity']),
    ].join('|');
    final existingIndex = seen[key];
    if (existingIndex == null) {
      seen[key] = unique.length;
      unique.add(candidate);
      continue;
    }
    final retained = unique[existingIndex];
    final retainedPayload = _object(retained['payload'], 'candidate payload');
    final warnings = <String>{
      ..._strings(retainedPayload['warnings']),
      'Duplicate observation candidate removed; confirm the retained count once.',
    };
    unique[existingIndex] = <String, Object?>{
      ...retained,
      'payload': <String, Object?>{
        ...retainedPayload,
        'warnings': warnings.toList(growable: false),
      },
    };
  }
  return unique;
}

String _extension(String mimeType) => switch (mimeType) {
  'image/png' => 'png',
  'image/webp' => 'webp',
  _ => 'jpg',
};

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Missing $label.');
  }
  return value;
}

List<Map<String, Object?>> _objects(Object? value) {
  if (value is! List<Object?>) throw const FormatException('Expected a list.');
  return value
      .map((item) => _object(item, 'list item'))
      .toList(growable: false);
}

List<String> _strings(Object? value) => value is List<Object?>
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];

String _string(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String || value.isEmpty) throw FormatException('Missing $key.');
  return value;
}

String? _optionalString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int _integer(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is num) return value.toInt();
  throw FormatException('Missing $key.');
}

int? _optionalInteger(Object? value) => value is num ? value.toInt() : null;

double _number(Object? value) {
  if (value is num && value.isFinite && value >= 0 && value <= 1) {
    return value.toDouble();
  }
  throw const FormatException('Expected a confidence value.');
}

double _confidence(Object? value, double fallback) =>
    value is num ? value.toDouble().clamp(0.0, 1.0).toDouble() : fallback;

ExtractedField<String> _field(String? value, double confidence) =>
    ExtractedField<String>(value: value, confidence: confidence);

NormalizedRegion? _region(Object? value) {
  if (value == null) return null;
  final region = _object(value, 'bounding region');
  return NormalizedRegion(
    pageIndex: 0,
    x: _number(region['x']),
    y: _number(region['y']),
    width: _number(region['width']),
    height: _number(region['height']),
  );
}
