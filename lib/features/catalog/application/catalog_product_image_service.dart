import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/domain/catalog_product_image_models.dart';

abstract interface class CatalogProductImageRepository {
  Future<CatalogProductImageSubmission> submitProductImage({
    required String submissionId,
    required int expectedConsentRevision,
    required CatalogProductImageSource source,
    required CatalogProductImageDraft image,
    required String altText,
  });
}

enum CatalogProductImageAcquisitionFailureKind {
  tooLarge,
  unsupported,
  invalidDimensions,
  unreadable,
}

final class CatalogProductImageAcquisitionException implements Exception {
  const CatalogProductImageAcquisitionException(this.kind, this.safeMessage);

  final CatalogProductImageAcquisitionFailureKind kind;
  final String safeMessage;
}

final class CatalogProductImageTooLargeException implements Exception {
  const CatalogProductImageTooLargeException();
}

final class CatalogProductImageUnsupportedException implements Exception {
  const CatalogProductImageUnsupportedException();
}

final class CatalogProductImageServiceUnavailableException
    implements Exception {
  const CatalogProductImageServiceUnavailableException();
}

/// Validates the human-reviewed fields before the generated transport adapter.
final class CatalogProductImageService {
  const CatalogProductImageService(this._repository);

  final CatalogProductImageRepository _repository;

  String normalizeAltText(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > 191 ||
        normalized.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      throw ArgumentError.value(
        value,
        'altText',
        'must contain 1 to 191 printable characters',
      );
    }
    return normalized;
  }

  Future<CatalogProductImageSubmission> submit({
    required String submissionId,
    required int expectedConsentRevision,
    required CatalogProductImageSource source,
    required CatalogProductImageDraft image,
    required String altText,
    required bool rightsConfirmed,
    required bool submissionConfirmed,
  }) {
    if (!rightsConfirmed || !submissionConfirmed) {
      throw const CatalogProposalConsentRequiredException();
    }
    if (!isUuid(submissionId)) {
      throw ArgumentError.value(submissionId, 'submissionId', 'must be a UUID');
    }
    if (expectedConsentRevision < 1) {
      throw ArgumentError.value(
        expectedConsentRevision,
        'expectedConsentRevision',
        'must be positive',
      );
    }
    if (image.isReleased) {
      throw StateError('The selected image is no longer available.');
    }
    return _repository.submitProductImage(
      submissionId: submissionId,
      expectedConsentRevision: expectedConsentRevision,
      source: source,
      image: image,
      altText: normalizeAltText(altText),
    );
  }
}
