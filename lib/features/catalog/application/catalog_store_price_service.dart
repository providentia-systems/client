import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/domain/catalog_store_price_models.dart';

abstract interface class CatalogStorePriceRepository {
  Future<CatalogContributionReceipt> submitStorePrice({
    required String submissionId,
    required int expectedConsentRevision,
    required CatalogStorePriceObservation observation,
  });
}

final class CatalogStorePriceService {
  CatalogStorePriceService(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final CatalogStorePriceRepository _repository;
  final DateTime Function() _clock;

  CatalogStorePriceObservation preview({
    required CatalogStorePriceSource source,
    required String storeName,
    String? storeLocation,
    required String price,
    required String currency,
    required DateTime observedOn,
  }) {
    final observation = CatalogStorePriceObservation(
      source: source,
      storeName: storeName,
      storeLocation: storeLocation,
      price: price,
      currency: currency,
      observedOn: observedOn,
    );
    final today = _utcDate(_clock());
    if (observation.observedOn.isAfter(today)) {
      throw ArgumentError.value(
        observedOn,
        'observedOn',
        'must not be in the future',
      );
    }
    return observation;
  }

  Future<CatalogContributionReceipt> submit({
    required String submissionId,
    required int expectedConsentRevision,
    required CatalogStorePriceObservation observation,
    required bool explicitlyConsented,
  }) {
    if (!explicitlyConsented) {
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
    return _repository.submitStorePrice(
      submissionId: submissionId,
      expectedConsentRevision: expectedConsentRevision,
      observation: observation,
    );
  }
}

DateTime _utcDate(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}
