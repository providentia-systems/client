import 'package:providentia/features/catalog/domain/catalog_models.dart';

/// A home-private product linked to one published catalog product and pack.
///
/// Home identifiers scope the authenticated request but are never serialized
/// into the public store-price payload.
final class CatalogStorePriceSource {
  CatalogStorePriceSource({
    required this.homeId,
    required this.homeProductId,
    required this.productId,
    required this.packId,
    required this.displayName,
    required this.packText,
  }) {
    _requireUuid(homeId, 'homeId');
    _requireUuid(homeProductId, 'homeProductId');
    _requireUuid(productId, 'productId');
    _requireUuid(packId, 'packId');
    _requireText(displayName, 'displayName', 191);
    _requireText(packText, 'packText', 191);
  }

  final String homeId;
  final String homeProductId;
  final String productId;
  final String packId;
  final String displayName;
  final String packText;
}

/// Exact public observation preview for API 1.18 `store_price` contribution.
///
/// No receipt, household, user, quantity, private note, or media field can be
/// attached to this closed DTO.
final class CatalogStorePriceObservation {
  CatalogStorePriceObservation({
    required this.source,
    required String storeName,
    String? storeLocation,
    required String price,
    required String currency,
    required DateTime observedOn,
  }) : storeName = storeName.trim(),
       storeLocation = _optional(storeLocation),
       price = price.trim(),
       currency = currency.trim().toUpperCase(),
       observedOn = DateTime.utc(
         observedOn.year,
         observedOn.month,
         observedOn.day,
       ) {
    _requireText(this.storeName, 'storeName', 191);
    if (this.storeLocation != null && this.storeLocation!.length > 191) {
      throw ArgumentError.value(
        storeLocation,
        'storeLocation',
        'must not exceed 191 characters',
      );
    }
    if (!_pricePattern.hasMatch(this.price)) {
      throw ArgumentError.value(
        price,
        'price',
        'must be a non-negative decimal with 2 to 4 fractional digits',
      );
    }
    if (!_currencyPattern.hasMatch(this.currency)) {
      throw ArgumentError.value(
        currency,
        'currency',
        'must be a three-letter currency code',
      );
    }
  }

  static const Set<String> allowedWireFields = <String>{
    'productId',
    'packId',
    'storeName',
    'storeLocation',
    'price',
    'currency',
    'observedOn',
  };

  final CatalogStorePriceSource source;
  final String storeName;
  final String? storeLocation;
  final String price;
  final String currency;
  final DateTime observedOn;

  Map<String, Object?> toPayloadJson() => <String, Object?>{
    'productId': source.productId,
    'packId': source.packId,
    'storeName': storeName,
    if (storeLocation != null) 'storeLocation': storeLocation,
    'price': price,
    'currency': currency,
    'observedOn': _date(observedOn),
  };
}

enum CatalogContributionType { productIdentity, storePrice }

/// Neutral receipt for a consent-bound catalog contribution.
///
/// A store-price contribution is not a catalog proposal, so this receipt uses
/// the backend contribution identity and source identity without product-
/// proposal terminology.
final class CatalogContributionReceipt {
  CatalogContributionReceipt({
    required this.homeId,
    required this.sourceEntityId,
    required this.contributionId,
    required this.type,
    required this.status,
    required this.revision,
  }) {
    _requireUuid(homeId, 'homeId');
    _requireUuid(sourceEntityId, 'sourceEntityId');
    _requireUuid(contributionId, 'contributionId');
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
  }

  final String homeId;
  final String sourceEntityId;
  final String contributionId;
  final CatalogContributionType type;
  final CatalogProposalStatus status;
  final int revision;
}

String _date(DateTime value) {
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

String? _optional(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

void _requireText(String value, String name, int maximumLength) {
  if (value.isEmpty || value.length > maximumLength) {
    throw ArgumentError.value(
      value,
      name,
      'must contain 1 to $maximumLength characters',
    );
  }
}

void _requireUuid(String value, String name) {
  if (!_uuidPattern.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be a UUID');
  }
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final RegExp _pricePattern = RegExp(r'^(?:0|[1-9][0-9]{0,11})\.[0-9]{2,4}$');
final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');
