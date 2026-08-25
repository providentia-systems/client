import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/catalog/application/catalog_product_image_service.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/domain/catalog_product_image_models.dart';
import 'package:providentia/features/catalog/infrastructure/generated_catalog_product_image_repository.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test(
    'multipart request is exact and response keeps submission identity',
    () async {
      late http.Request captured;
      final repository = GeneratedCatalogProductImageRepository(
        _client((request) async {
          captured = request;
          return _json(_success(), status: 201);
        }),
      );
      final draft = _draft();

      final result = await repository.submitProductImage(
        submissionId: _submissionId,
        expectedConsentRevision: 7,
        source: _source,
        image: draft,
        altText: 'Front of the oats package',
      );

      expect(captured.method, 'POST');
      expect(
        captured.url.path,
        '/api/v1/homes/$_homeId/catalog-contributions/images',
      );
      expect(
        captured.headers['content-type'],
        startsWith('multipart/form-data;'),
      );
      final body = latin1.decode(captured.bodyBytes);
      for (final field in <String, String>{
        'submissionId': _submissionId,
        'sourceEntityId': _homeProductId,
        'expectedConsentRevision': '7',
        'altText': 'Front of the oats package',
        'sourceDigest': draft.sourceDigest,
        'rightsDeclarationVersion':
            CatalogProductImageDraft.rightsDeclarationVersion,
        'submissionConfirmed': 'true',
      }.entries) {
        expect(body, contains('name="${field.key}"'));
        expect(body, contains('\r\n\r\n${field.value}\r\n'));
      }
      expect(body, contains('name="image"'));
      expect(body, contains('filename="catalog-image.png"'));
      expect(body, contains('content-type: image/png'));
      expect(result.contributionId, _submissionId);
      expect(result.status, CatalogProductImageSubmissionStatus.pending);
      expect(result.revision, 1);
      expect(result.assetDigest, _assetDigest);
      expect(draft.isReleased, isFalse);
      draft.release();
    },
  );

  test('a response id distinct from submissionId fails closed', () async {
    final repository = GeneratedCatalogProductImageRepository(
      _client(
        (_) async => _json(<String, Object?>{
          ..._success(),
          'id': _otherId,
        }, status: 201),
      ),
    );
    final draft = _draft();

    await expectLater(
      repository.submitProductImage(
        submissionId: _submissionId,
        expectedConsentRevision: 7,
        source: _source,
        image: draft,
        altText: 'Front of the oats package',
      ),
      throwsA(isA<CatalogContributionUnavailableException>()),
    );
    draft.release();
  });

  test(
    '200 exact replay is accepted but extra response fields fail closed',
    () async {
      var extraField = false;
      final repository = GeneratedCatalogProductImageRepository(
        _client(
          (_) async => _json(<String, Object?>{
            ..._success(),
            if (extraField) 'homeId': _homeId,
          }),
        ),
      );
      final replayDraft = _draft();

      final replay = await repository.submitProductImage(
        submissionId: _submissionId,
        expectedConsentRevision: 7,
        source: _source,
        image: replayDraft,
        altText: 'Front of the oats package',
      );
      expect(replay.contributionId, _submissionId);
      extraField = true;
      await expectLater(
        repository.submitProductImage(
          submissionId: _submissionId,
          expectedConsentRevision: 7,
          source: _source,
          image: replayDraft,
          altText: 'Front of the oats package',
        ),
        throwsA(isA<CatalogContributionUnavailableException>()),
      );
      replayDraft.release();
    },
  );

  for (final scenario in <({int status, String title, Matcher expected})>[
    (
      status: 401,
      title: 'Authentication required',
      expected: isA<CatalogContributionAuthenticationRequiredException>(),
    ),
    (
      status: 403,
      title: 'Forbidden',
      expected: isA<CatalogContributionForbiddenException>(),
    ),
    (
      status: 404,
      title: 'Source home product not found',
      expected: isA<CatalogContributionSourceUnavailableException>(),
    ),
    (
      status: 409,
      title: 'Sharing consent required',
      expected: isA<CatalogServerConsentRequiredException>(),
    ),
    (
      status: 409,
      title: 'Image contribution conflict',
      expected: isA<CatalogContributionConflictException>(),
    ),
    (
      status: 413,
      title: 'Image too large',
      expected: isA<CatalogProductImageTooLargeException>(),
    ),
    (
      status: 415,
      title: 'Unsupported media type',
      expected: isA<CatalogProductImageUnsupportedException>(),
    ),
    (
      status: 422,
      title: 'Invalid image contribution',
      expected: isA<CatalogContributionValidationException>(),
    ),
    (
      status: 503,
      title: 'Image processing unavailable',
      expected: isA<CatalogProductImageServiceUnavailableException>(),
    ),
  ]) {
    test('${scenario.status} ${scenario.title} maps exactly', () async {
      final repository = GeneratedCatalogProductImageRepository(
        _client(
          (_) async => _json(
            _problem(scenario.status, scenario.title),
            status: scenario.status,
          ),
        ),
      );
      final draft = _draft();

      await expectLater(
        repository.submitProductImage(
          submissionId: _submissionId,
          expectedConsentRevision: 7,
          source: _source,
          image: draft,
          altText: 'Front of the oats package',
        ),
        throwsA(scenario.expected),
      );
      draft.release();
    });
  }
}

const String _homeId = '01912345-6789-7abc-8def-0123456789ab';
const String _homeProductId = '01912345-6789-7abc-8def-1123456789ab';
const String _submissionId = '01912345-6789-7abc-8def-2123456789ab';
const String _otherId = '01912345-6789-7abc-8def-3123456789ab';
const String _assetDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final CatalogProductImageSource _source = CatalogProductImageSource(
  homeId: _homeId,
  homeProductId: _homeProductId,
  displayName: 'Rolled oats',
);

CatalogProductImageDraft _draft() => CatalogProductImageDraft(
  bytes: Uint8List.fromList(List<int>.generate(32, (index) => index)),
  mediaType: CatalogProductImageMediaType.png,
  width: 32,
  height: 24,
);

Map<String, Object?> _success() => <String, Object?>{
  'id': _submissionId,
  'contributionType': 'product_image',
  'payload': <String, Object?>{
    'sourceDigest': _draft().sourceDigest,
    'assetDigest': _assetDigest,
    'mediaType': 'image/webp',
    'altText': 'Front of the oats package',
    'provenance': 'homeowner_original',
    'rightsDeclarationVersion':
        CatalogProductImageDraft.rightsDeclarationVersion,
    'reuseNoticeVersion': CatalogProductImageDraft.reuseNoticeVersion,
  },
  'status': 'pending',
  'revision': 1,
  'createdAt': '2026-08-25T12:00:00Z',
};

Map<String, Object?> _problem(int status, String title) => <String, Object?>{
  'type': 'about:blank',
  'title': title,
  'status': status,
  'requestId': 'request-product-image',
};

ProvidentiaApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => ProvidentiaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(handler),
);

http.Response _json(Map<String, Object?> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );
