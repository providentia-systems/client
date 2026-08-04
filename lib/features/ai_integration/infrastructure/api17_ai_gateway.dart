import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

abstract interface class PreparedMediaByteReader {
  Future<Uint8List> read(PreparedAiMedia media);
}

/// Server-proxy AI adapter for the single-image API 1.7 extraction contract.
/// Multi-page, video-frame batches and independent validation deliberately
/// remain in the orchestration layer until Laminas publishes a batch contract.
final class Api17AiGateway implements AiProviderGateway {
  const Api17AiGateway({
    required ProvidentiaApiClient client,
    required PreparedMediaByteReader mediaReader,
  }) : _client = client,
       _mediaReader = mediaReader;

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
            (provider) => provider['id'] == profile.id,
          );
      return supported
          ? const AiGatewayReadiness.ready()
          : const AiGatewayReadiness(
              state: AiGatewayReadinessState.missingCapability,
              safeMessage:
                  'The selected provider is not enabled by the server.',
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
    if (request.privacyMode != AiPrivacyMode.serverProxyCloud ||
        request.provider.transport != AiTransport.serverProxy) {
      throw const _Api17AiBoundaryException(
        'invalid_ai_route',
        'The selected privacy route cannot use the server proxy.',
      );
    }
    if (request.media.media.length != 1) {
      throw const _Api17AiBoundaryException(
        'api17_single_image_only',
        'This server version accepts one prepared image per extraction.',
      );
    }
    final media = request.media.media.single;
    if (!const <String>{
      'image/jpeg',
      'image/png',
      'image/webp',
    }.contains(media.mimeType)) {
      throw const _Api17AiBoundaryException(
        'unsupported_media_type',
        'Prepare the selected media as JPEG, PNG, or WebP.',
      );
    }
    final bytes = await _mediaReader.read(media);
    if (bytes.length != media.byteLength) {
      throw const _Api17AiBoundaryException(
        'prepared_media_changed',
        'The prepared image changed after consent. Prepare it again.',
      );
    }
    final created = (await _client.createAiExtraction(
      homeId: request.homeId,
      formFields: <String, String>{
        'kind': request.kind == AiExtractionKind.receipt ? 'receipt' : 'stock',
        'transmissionConsent': 'true',
      },
      files: <http.MultipartFile>[
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename:
              'prepared-${media.sha256.substring(0, 12)}.${_extension(media.mimeType)}',
        ),
      ],
    )).requireObject();
    final extractionId = _string(created, 'id');
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
    return extraction;
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
    final candidates = _objects(extraction['candidates']);
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
