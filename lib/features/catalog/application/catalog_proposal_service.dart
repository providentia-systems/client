import 'package:providentia/features/catalog/domain/catalog_models.dart';

abstract interface class CatalogProposalRepository {
  Future<CatalogSubmissionLink> submit({
    required String homeId,
    required String homeProductId,
    required SanitizedCatalogProposal proposal,
  });
}

final class CatalogProposalConsentRequiredException implements Exception {
  const CatalogProposalConsentRequiredException();
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
      barcode: _clean(product.barcode),
    );
  }

  Future<CatalogSubmissionLink> submit({
    required PrivateProduct product,
    required SanitizedCatalogProposal preview,
    required bool explicitlyConsented,
  }) {
    if (!explicitlyConsented) {
      throw const CatalogProposalConsentRequiredException();
    }
    return _repository.submit(
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
