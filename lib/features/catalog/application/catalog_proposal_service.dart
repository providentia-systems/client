import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';

abstract interface class CatalogProposalRepository {
  Future<CatalogSubmissionLink> submit({
    required String submissionId,
    required String homeId,
    required String homeProductId,
    required SanitizedCatalogProposal proposal,
  });
}

abstract interface class CatalogSharingConsentRepository {
  Future<CatalogSharingConsent> loadConsent({required String homeId});

  Future<CatalogSharingConsent> updateConsent({
    required String homeId,
    required CatalogSharingConsentUpdate update,
  });
}

final class CatalogProposalConsentRequiredException implements Exception {
  const CatalogProposalConsentRequiredException();
}

final class CatalogServerConsentRequiredException implements Exception {
  const CatalogServerConsentRequiredException();
}

final class CatalogContributionAuthenticationRequiredException
    implements Exception {
  const CatalogContributionAuthenticationRequiredException();
}

final class CatalogContributionForbiddenException implements Exception {
  const CatalogContributionForbiddenException();
}

final class CatalogContributionConflictException implements Exception {
  const CatalogContributionConflictException();
}

final class CatalogContributionValidationException implements Exception {
  const CatalogContributionValidationException();
}

final class CatalogContributionUnavailableException implements Exception {
  const CatalogContributionUnavailableException();
}

final class CatalogProposalService {
  const CatalogProposalService(this._repository);

  final CatalogProposalRepository _repository;

  SanitizedCatalogProposal preview({
    required PrivateProduct product,
    required String locale,
  }) {
    return SanitizedCatalogProposal(
      canonicalName: product.displayName,
      locale: locale,
      brand: _clean(product.brand),
      variant: _clean(product.variant),
      packText: _clean(product.packText),
      packAmount: product.packAmount,
      unitCode: _clean(product.unitCode),
      categoryId: _clean(product.categoryId),
      categoryLabel: _clean(product.categoryLabel),
      barcode: _clean(product.barcode),
    );
  }

  Future<CatalogSubmissionLink> submit({
    required String submissionId,
    required PrivateProduct product,
    required SanitizedCatalogProposal preview,
    required bool explicitlyConsented,
  }) {
    if (!explicitlyConsented) {
      throw const CatalogProposalConsentRequiredException();
    }
    if (!isUuid(submissionId)) {
      throw ArgumentError.value(submissionId, 'submissionId', 'must be a UUID');
    }
    return _repository.submit(
      submissionId: submissionId,
      homeId: product.homeId,
      homeProductId: product.homeProductId,
      proposal: preview,
    );
  }

  String? _clean(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}
