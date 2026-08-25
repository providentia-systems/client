import 'package:http/http.dart' as http;
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/application/catalog_store_price_service.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';
import 'package:providentia/features/catalog/domain/catalog_store_price_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Current pinned-contract boundary for home-scoped catalog sharing.
///
/// The adapter reads the current revisioned consent before every submission
/// and serializes only the contract's identity and store-price allowlists.
/// Household attribution is limited to the authenticated home endpoint and
/// is never copied into the sanitized moderator payload.
final class GeneratedCatalogContributionRepository
    implements
        CatalogProposalRepository,
        CatalogSharingConsentRepository,
        CatalogStorePriceRepository {
  const GeneratedCatalogContributionRepository(this._client);

  final ProvidentiaApiClient _client;

  @override
  Future<CatalogSharingConsent> loadConsent({required String homeId}) {
    return _run(() async {
      final object = (await _client.getCatalogContributionConsent(
        homeId: homeId,
      )).requireObject();
      return _consent(object, expectedHomeId: homeId);
    });
  }

  @override
  Future<CatalogSharingConsent> updateConsent({
    required String homeId,
    required CatalogSharingConsentUpdate update,
  }) {
    return _run(() async {
      final object = (await _client.putCatalogContributionConsent(
        homeId: homeId,
        body: update.toJson(),
      )).requireObject();
      return _consent(object, expectedHomeId: homeId);
    });
  }

  @override
  Future<CatalogSubmissionLink> submit({
    required String submissionId,
    required String homeId,
    required String homeProductId,
    required int expectedConsentRevision,
    required SanitizedCatalogProposal proposal,
  }) async {
    if (expectedConsentRevision < 1) {
      throw const CatalogServerConsentRequiredException();
    }
    final payload = proposal.toIdentityContributionJson();
    if (!CatalogProposalServiceWirePolicy.isIdentityPayload(payload)) {
      throw const CatalogContributionValidationException();
    }
    return _run(() async {
      final object = (await _client.createCatalogContribution(
        homeId: homeId,
        body: <String, Object?>{
          'submissionId': submissionId,
          'type': 'product_identity',
          'sourceEntityId': homeProductId,
          'expectedConsentRevision': expectedConsentRevision,
          'payload': payload,
        },
      )).requireObject();
      return CatalogSubmissionLink(
        homeId: homeId,
        homeProductId: homeProductId,
        proposalId: _string(object, 'id'),
        status: _proposalStatus(object['status']),
      );
    }, submitting: true);
  }

  @override
  Future<CatalogContributionReceipt> submitStorePrice({
    required String submissionId,
    required int expectedConsentRevision,
    required CatalogStorePriceObservation observation,
  }) async {
    if (expectedConsentRevision < 1) {
      throw const CatalogServerConsentRequiredException();
    }
    final source = observation.source;
    final payload = observation.toPayloadJson();
    if (!CatalogProposalServiceWirePolicy.isStorePricePayload(payload)) {
      throw const CatalogContributionValidationException();
    }
    return _run(() async {
      final object = (await _client.createCatalogContribution(
        homeId: source.homeId,
        body: <String, Object?>{
          'submissionId': submissionId,
          'type': 'store_price',
          'sourceEntityId': source.homeProductId,
          'expectedConsentRevision': expectedConsentRevision,
          'payload': payload,
        },
      )).requireObject();
      if (_string(object, 'contributionType') != 'store_price') {
        throw const FormatException('Catalog contribution type changed.');
      }
      return CatalogContributionReceipt(
        homeId: source.homeId,
        sourceEntityId: source.homeProductId,
        contributionId: _string(object, 'id'),
        type: CatalogContributionType.storePrice,
        status: _proposalStatus(object['status']),
        revision: _positiveInteger(object, 'revision'),
      );
    }, submitting: true);
  }

  Future<T> _run<T>(
    Future<T> Function() action, {
    bool submitting = false,
  }) async {
    try {
      return await action();
    } on CatalogServerConsentRequiredException {
      rethrow;
    } on CatalogContributionValidationException {
      rethrow;
    } on ProvidentiaApiException catch (error) {
      throw _catalogFailure(error, submitting: submitting);
    } on FormatException {
      throw const CatalogContributionUnavailableException();
    } on ArgumentError {
      throw const CatalogContributionUnavailableException();
    } on http.ClientException {
      throw const CatalogContributionUnavailableException();
    }
  }
}

/// A named, testable policy guard at the final serialization boundary.
abstract final class CatalogProposalServiceWirePolicy {
  static bool isIdentityPayload(Map<String, Object?> payload) {
    final keys = payload.keys.toSet();
    if (!SanitizedCatalogProposal.identityContributionWireFields.containsAll(
      keys,
    )) {
      return false;
    }
    final name = payload['canonicalName'];
    return name is String && name.trim().isNotEmpty;
  }

  static bool isStorePricePayload(Map<String, Object?> payload) {
    const required = <String>{
      'productId',
      'packId',
      'storeName',
      'price',
      'currency',
      'observedOn',
    };
    final keys = payload.keys.toSet();
    return keys.containsAll(required) &&
        CatalogStorePriceObservation.allowedWireFields.containsAll(keys) &&
        payload['productId'] is String &&
        payload['packId'] is String &&
        payload['storeName'] is String &&
        payload['price'] is String &&
        payload['currency'] is String &&
        payload['observedOn'] is String &&
        (payload['storeLocation'] == null ||
            payload['storeLocation'] is String);
  }
}

CatalogSharingConsent _consent(
  Map<String, Object?> object, {
  required String expectedHomeId,
}) {
  final homeId = _string(object, 'homeId');
  if (homeId != expectedHomeId) {
    throw const FormatException('Catalog consent crossed the home boundary.');
  }
  return CatalogSharingConsent(
    homeId: homeId,
    shareProductIdentity: _boolean(object, 'shareProductIdentity'),
    shareProductImages: _boolean(object, 'shareProductImages'),
    shareStorePrices: _boolean(object, 'shareStorePrices'),
    noticeVersion: _string(object, 'noticeVersion'),
    revision: _integer(object, 'revision'),
  );
}

Exception _catalogFailure(
  ProvidentiaApiException error, {
  required bool submitting,
}) {
  return switch (error.statusCode) {
    401 => const CatalogContributionAuthenticationRequiredException(),
    403 => const CatalogContributionForbiddenException(),
    409
        when submitting &&
            error.problem.title.toLowerCase().contains('consent') =>
      const CatalogServerConsentRequiredException(),
    409 => const CatalogContributionConflictException(),
    404 => const CatalogContributionSourceUnavailableException(),
    400 || 422 => const CatalogContributionValidationException(),
    _ => const CatalogContributionUnavailableException(),
  };
}

CatalogProposalStatus _proposalStatus(Object? value) {
  return switch (value) {
    'pending' => CatalogProposalStatus.pending,
    'approved' => CatalogProposalStatus.approved,
    'rejected' => CatalogProposalStatus.rejected,
    'withdrawn' => CatalogProposalStatus.withdrawn,
    _ => throw const FormatException('Unknown catalog contribution status.'),
  };
}

String _string(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key.');
  }
  return value;
}

bool _boolean(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! bool) {
    throw FormatException('Missing $key.');
  }
  return value;
}

int _integer(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! int) {
    throw FormatException('Missing $key.');
  }
  return value;
}

int _positiveInteger(Map<String, Object?> object, String key) {
  final value = _integer(object, key);
  if (value < 1) throw FormatException('Invalid $key.');
  return value;
}
