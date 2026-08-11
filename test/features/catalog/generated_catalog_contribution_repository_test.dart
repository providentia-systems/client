import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';
import 'package:providentia/features/catalog/infrastructure/generated_catalog_contribution_repository.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test(
    'submission is bound to current consent and an exact payload allowlist',
    () async {
      Map<String, Object?>? submitted;
      var requestCount = 0;
      final repository = GeneratedCatalogContributionRepository(
        _client((request) async {
          requestCount++;
          if (request.method == 'GET') {
            expect(
              request.url.path,
              '/api/v1/homes/$_homeId/catalog-contributions/consent',
            );
            return _json(_consentJson(revision: 4, identity: true));
          }
          expect(request.method, 'POST');
          expect(
            request.url.path,
            '/api/v1/homes/$_homeId/catalog-contributions',
          );
          submitted = _requestObject(request);
          return _json(<String, Object?>{
            'id': _contributionId,
            'status': 'pending',
            'revision': 1,
          }, status: 201);
        }),
      );
      final privateProduct = PrivateProduct(
        homeId: _homeId,
        homeProductId: _homeProductId,
        displayName: 'Rolled oats',
        brand: 'Example',
        variant: 'Private variant',
        packText: '1 kg bag',
        packAmount: 1,
        unitCode: 'kg',
        categoryId: _categoryId,
        categoryLabel: 'Breakfast cereal',
        barcode: '6001234567890',
        privateNote: 'Bottom shelf',
      );
      final service = CatalogProposalService(repository);
      final proposal = service.preview(
        product: privateProduct,
        locale: 'en-NA',
      );

      final link = await service.submit(
        product: privateProduct,
        preview: proposal,
        explicitlyConsented: true,
      );

      expect(requestCount, 2);
      expect(link.proposalId, _contributionId);
      expect(link.homeId, _homeId);
      expect(link.homeProductId, _homeProductId);
      expect(submitted, isNotNull);
      expect(submitted!.keys.toSet(), <String>{
        'type',
        'sourceEntityId',
        'expectedConsentRevision',
        'payload',
      });
      expect(submitted!['type'], 'product_identity');
      expect(submitted!['sourceEntityId'], _homeProductId);
      expect(submitted!['expectedConsentRevision'], 4);
      final payload = submitted!['payload']! as Map<String, Object?>;
      expect(payload.keys.toSet(), <String>{
        'canonicalName',
        'brand',
        'categoryLabel',
        'barcode',
        'packText',
      });
      expect(
        CatalogProposalServiceWirePolicy.isIdentityPayload(payload),
        isTrue,
      );
      for (final forbidden in <String>{
        'homeId',
        'homeProductId',
        'locale',
        'variant',
        'packAmount',
        'unitCode',
        'categoryId',
        'privateNote',
        'price',
        'quantity',
        'receipt',
        'store',
        'media',
        'aiMetadata',
      }) {
        expect(payload, isNot(contains(forbidden)));
      }
    },
  );

  test(
    'consent update sends the pinned notice and expected revision',
    () async {
      Map<String, Object?>? updated;
      final repository = GeneratedCatalogContributionRepository(
        _client((request) async {
          expect(request.method, 'PUT');
          updated = _requestObject(request);
          return _json(_consentJson(revision: 3, identity: true));
        }),
      );

      final consent = await repository.updateConsent(
        homeId: _homeId,
        update: CatalogSharingConsentUpdate(
          shareProductIdentity: true,
          shareProductImages: false,
          shareStorePrices: false,
          expectedRevision: 2,
        ),
      );

      expect(updated, <String, Object?>{
        'shareProductIdentity': true,
        'shareProductImages': false,
        'shareStorePrices': false,
        'noticeVersion': 'catalog-sharing-v1',
        'expectedRevision': 2,
      });
      expect(consent.revision, 3);
    },
  );

  test('disabled or absent server consent prevents submission', () async {
    var requestCount = 0;
    final repository = GeneratedCatalogContributionRepository(
      _client((request) async {
        requestCount++;
        expect(request.method, 'GET');
        return _json(_consentJson(revision: 0, identity: false));
      }),
    );
    final proposal = SanitizedCatalogProposal(
      canonicalName: 'Rolled oats',
      locale: 'en-NA',
    );

    await expectLater(
      repository.submit(
        homeId: _homeId,
        homeProductId: _homeProductId,
        proposal: proposal,
      ),
      throwsA(isA<CatalogServerConsentRequiredException>()),
    );
    expect(requestCount, 1);
  });

  test('cross-home consent response fails closed', () async {
    final repository = GeneratedCatalogContributionRepository(
      _client(
        (_) async => _json(<String, Object?>{
          ..._consentJson(revision: 1, identity: true),
          'homeId': _otherHomeId,
        }),
      ),
    );

    await expectLater(
      repository.loadConsent(homeId: _homeId),
      throwsA(isA<CatalogContributionUnavailableException>()),
    );
  });
}

const String _homeId = '01912345-6789-7abc-8def-0123456789ab';
const String _otherHomeId = '01912345-6789-7abc-8def-1123456789ab';
const String _homeProductId = '01912345-6789-7abc-8def-2123456789ab';
const String _categoryId = '01912345-6789-7abc-8def-3123456789ab';
const String _contributionId = '01912345-6789-7abc-8def-4123456789ab';

ProvidentiaApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => ProvidentiaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(handler),
);

Map<String, Object?> _consentJson({
  required int revision,
  required bool identity,
}) => <String, Object?>{
  'homeId': _homeId,
  'shareProductIdentity': identity,
  'shareProductImages': false,
  'shareStorePrices': false,
  'noticeVersion': 'catalog-sharing-v1',
  'revision': revision,
};

Map<String, Object?> _requestObject(http.Request request) {
  final value = jsonDecode(request.body);
  if (value is! Map<String, Object?>) {
    throw StateError('Expected an object request.');
  }
  return value;
}

http.Response _json(Map<String, Object?> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );
