import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:providentia/features/catalog/application/catalog_product_image_service.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/domain/catalog_product_image_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// API 1.18 multipart boundary for a single consent-bound product image.
final class GeneratedCatalogProductImageRepository
    implements CatalogProductImageRepository {
  const GeneratedCatalogProductImageRepository(this._client);

  final ProvidentiaApiClient _client;

  @override
  Future<CatalogProductImageSubmission> submitProductImage({
    required String submissionId,
    required int expectedConsentRevision,
    required CatalogProductImageSource source,
    required CatalogProductImageDraft image,
    required String altText,
  }) async {
    final uploadBytes = image.copyBytes();
    try {
      final response = await _client.createCatalogProductImageContribution(
        homeId: source.homeId,
        formFields: <String, String>{
          'submissionId': submissionId,
          'sourceEntityId': source.homeProductId,
          'expectedConsentRevision': expectedConsentRevision.toString(),
          'altText': altText,
          'sourceDigest': image.sourceDigest,
          'rightsDeclarationVersion':
              CatalogProductImageDraft.rightsDeclarationVersion,
          'submissionConfirmed': 'true',
        },
        files: <http.MultipartFile>[
          http.MultipartFile.fromBytes(
            'image',
            uploadBytes,
            filename: 'catalog-image.${image.mediaType.fileExtension}',
            contentType: MediaType.parse(image.mediaType.wireName),
          ),
        ],
      );
      return _submission(
        response.requireObject(),
        expectedSubmissionId: submissionId,
        expectedSourceDigest: image.sourceDigest,
        expectedAltText: altText,
      );
    } on ProvidentiaApiException catch (error) {
      throw _imageFailure(error);
    } on CatalogContributionAuthenticationRequiredException {
      rethrow;
    } on CatalogContributionForbiddenException {
      rethrow;
    } on CatalogContributionSourceUnavailableException {
      rethrow;
    } on CatalogServerConsentRequiredException {
      rethrow;
    } on CatalogContributionConflictException {
      rethrow;
    } on CatalogProductImageTooLargeException {
      rethrow;
    } on CatalogProductImageUnsupportedException {
      rethrow;
    } on CatalogContributionValidationException {
      rethrow;
    } on CatalogProductImageServiceUnavailableException {
      rethrow;
    } on FormatException {
      throw const CatalogContributionUnavailableException();
    } on ArgumentError {
      throw const CatalogContributionUnavailableException();
    } on http.ClientException {
      throw const CatalogContributionUnavailableException();
    } finally {
      _wipe(uploadBytes);
    }
  }
}

CatalogProductImageSubmission _submission(
  Map<String, Object?> object, {
  required String expectedSubmissionId,
  required String expectedSourceDigest,
  required String expectedAltText,
}) {
  const topLevelFields = <String>{
    'id',
    'contributionType',
    'payload',
    'status',
    'revision',
    'createdAt',
  };
  if (object.keys.toSet().difference(topLevelFields).isNotEmpty ||
      !object.keys.toSet().containsAll(topLevelFields)) {
    throw const FormatException('Unexpected image contribution response.');
  }
  final id = _string(object, 'id');
  if (id != expectedSubmissionId ||
      _string(object, 'contributionType') != 'product_image') {
    throw const FormatException('Image contribution identity changed.');
  }
  final payload = _object(object, 'payload');
  const payloadFields = <String>{
    'sourceDigest',
    'assetDigest',
    'mediaType',
    'altText',
    'provenance',
    'rightsDeclarationVersion',
    'reuseNoticeVersion',
  };
  final payloadKeys = payload.keys.toSet();
  if (payloadKeys.length != payloadFields.length ||
      !payloadKeys.containsAll(payloadFields) ||
      _string(payload, 'sourceDigest') != expectedSourceDigest ||
      _string(payload, 'mediaType') != 'image/webp' ||
      _string(payload, 'altText') != expectedAltText ||
      _string(payload, 'provenance') != 'homeowner_original' ||
      _string(payload, 'rightsDeclarationVersion') !=
          CatalogProductImageDraft.rightsDeclarationVersion ||
      _string(payload, 'reuseNoticeVersion') !=
          CatalogProductImageDraft.reuseNoticeVersion) {
    throw const FormatException('Image contribution projection changed.');
  }
  final assetDigest = _string(payload, 'assetDigest');
  if (!_digestPattern.hasMatch(assetDigest)) {
    throw const FormatException('Invalid sanitized image digest.');
  }
  final createdAt = DateTime.tryParse(_string(object, 'createdAt'));
  if (createdAt == null || !createdAt.isUtc) {
    throw const FormatException('Invalid image contribution timestamp.');
  }
  return CatalogProductImageSubmission(
    contributionId: id,
    status: _status(object['status']),
    revision: _positiveInteger(object, 'revision'),
    assetDigest: assetDigest,
  );
}

Exception _imageFailure(ProvidentiaApiException error) {
  return switch (error.statusCode) {
    401 => const CatalogContributionAuthenticationRequiredException(),
    403 => const CatalogContributionForbiddenException(),
    404 => const CatalogContributionSourceUnavailableException(),
    409 when error.problem.title.toLowerCase() == 'sharing consent required' =>
      const CatalogServerConsentRequiredException(),
    409 => const CatalogContributionConflictException(),
    413 => const CatalogProductImageTooLargeException(),
    415 => const CatalogProductImageUnsupportedException(),
    400 || 422 => const CatalogContributionValidationException(),
    503 => const CatalogProductImageServiceUnavailableException(),
    _ => const CatalogContributionUnavailableException(),
  };
}

CatalogProductImageSubmissionStatus _status(Object? value) => switch (value) {
  'pending' => CatalogProductImageSubmissionStatus.pending,
  'approved' => CatalogProductImageSubmissionStatus.approved,
  'rejected' => CatalogProductImageSubmissionStatus.rejected,
  'withdrawn' => CatalogProductImageSubmissionStatus.withdrawn,
  _ => throw const FormatException('Unknown image contribution status.'),
};

Map<String, Object?> _object(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('Missing $key.');
  }
  return value;
}

String _string(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key.');
  }
  return value;
}

int _positiveInteger(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! int || value < 1) throw FormatException('Invalid $key.');
  return value;
}

void _wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

final RegExp _digestPattern = RegExp(r'^[a-f0-9]{64}$');
