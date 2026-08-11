import 'package:http/http.dart' as http;
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Current pinned-contract boundary for home-scoped catalog sharing.
///
/// The adapter reads the current revisioned consent before every submission
/// and serializes only the contract's product-identity allowlist. Household
/// attribution is limited to the authenticated home endpoint and is never
/// copied into the sanitized moderator payload.
final class GeneratedCatalogContributionRepository
    implements CatalogProposalRepository, CatalogSharingConsentRepository {
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
    required String homeId,
    required String homeProductId,
    required SanitizedCatalogProposal proposal,
  }) async {
    final consent = await loadConsent(homeId: homeId);
    if (!consent.shareProductIdentity || consent.revision < 1) {
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
          'type': 'product_identity',
          'sourceEntityId': homeProductId,
          'expectedConsentRevision': consent.revision,
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
