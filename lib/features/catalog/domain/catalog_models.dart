enum CatalogProposalStatus { pending, inReview, approved, rejected, withdrawn }

/// A home-private product that is usable without global publication.
///
/// This type deliberately contains private fields. It must never be serialized
/// as a catalog proposal.
final class PrivateProduct {
  PrivateProduct({
    required this.homeId,
    required this.homeProductId,
    required this.displayName,
    this.brand,
    this.variant,
    this.packText,
    this.packAmount,
    this.unitCode,
    this.categoryId,
    this.barcode,
    this.privateNote,
  }) {
    _requireText(homeId, 'homeId');
    _requireText(homeProductId, 'homeProductId');
    _requireText(displayName, 'displayName');
    if (packAmount != null && packAmount! <= 0) {
      throw ArgumentError.value(packAmount, 'packAmount', 'must be positive');
    }
  }

  final String homeId;
  final String homeProductId;
  final String displayName;
  final String? brand;
  final String? variant;
  final String? packText;
  final double? packAmount;
  final String? unitCode;
  final String? categoryId;
  final String? barcode;
  final String? privateNote;
}

/// The complete, construction-level allowlist for global proposal data.
///
/// There is intentionally no generic metadata bag and no home, user, price,
/// quantity, receipt, store, private-note, media, or AI field.
final class SanitizedCatalogProposal {
  SanitizedCatalogProposal({
    required this.canonicalName,
    required this.locale,
    this.brand,
    this.variant,
    this.packText,
    this.packAmount,
    this.unitCode,
    this.categoryId,
    this.barcode,
  }) {
    _requireText(canonicalName, 'canonicalName');
    _requireText(locale, 'locale');
    if (packAmount != null && packAmount! <= 0) {
      throw ArgumentError.value(packAmount, 'packAmount', 'must be positive');
    }
    if ((packAmount == null) != (unitCode == null)) {
      throw ArgumentError(
        'packAmount and unitCode must either both be present or both be absent',
      );
    }
  }

  static const Set<String> allowedWireFields = <String>{
    'canonicalName',
    'locale',
    'brand',
    'variant',
    'packText',
    'packAmount',
    'unitCode',
    'categoryId',
    'barcode',
  };

  final String canonicalName;
  final String locale;
  final String? brand;
  final String? variant;
  final String? packText;
  final double? packAmount;
  final String? unitCode;
  final String? categoryId;
  final String? barcode;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'canonicalName': canonicalName,
      'locale': locale,
      if (brand != null) 'brand': brand,
      if (variant != null) 'variant': variant,
      if (packText != null) 'packText': packText,
      if (packAmount != null) 'packAmount': packAmount,
      if (unitCode != null) 'unitCode': unitCode,
      if (categoryId != null) 'categoryId': categoryId,
      if (barcode != null) 'barcode': barcode,
    };
  }
}

/// Private link to a sanitized proposal. Moderation DTOs never contain this.
final class CatalogSubmissionLink {
  CatalogSubmissionLink({
    required this.homeId,
    required this.homeProductId,
    required this.proposalId,
    required this.status,
  }) {
    _requireText(homeId, 'homeId');
    _requireText(homeProductId, 'homeProductId');
    _requireText(proposalId, 'proposalId');
  }

  final String homeId;
  final String homeProductId;
  final String proposalId;
  final CatalogProposalStatus status;
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}
