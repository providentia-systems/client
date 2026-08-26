import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/catalog_import/application/catalog_import_ports.dart';
import 'package:providentia/features/catalog_import/domain/catalog_import_models.dart';
import 'package:providentia/features/catalog_import/infrastructure/generated_catalog_import_transport.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

const String _homeId = '0f0e46f2-3c62-45a2-93a5-95d7a34a2a11';
const String _importId = '5b7a4a44-9a5b-4a75-9d5e-27d8a3d2b901';
const String _idempotencyKey = 'a2c4e6a8-1111-4222-8333-444455556666';

void main() {
  test(
    'stage posts the exact records payload and idempotency header',
    () async {
      http.Request? seen;
      final transport = GeneratedCatalogImportTransport(
        _client((request) async {
          seen = request;
          return _json(_batchJson(status: 'staged'), status: 201);
        }),
      );
      const records = <Map<String, Object?>>[
        <String, Object?>{
          'recordType': 'home_product',
          'name': 'Rolled oats',
          'brand': 'Acme',
        },
        <String, Object?>{
          'recordType': 'home_product',
          'privateName': 'Weekend oats',
        },
      ];

      final batch = await transport.stage(
        homeId: _homeId,
        idempotencyKey: _idempotencyKey,
        records: records,
      );

      expect(seen, isNotNull);
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/api/v1/homes/$_homeId/catalog-imports');
      expect(seen!.headers['Idempotency-Key'], _idempotencyKey);
      expect(seen!.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(seen!.body), <String, Object?>{'records': records});
      expect(batch.id, _importId);
      expect(batch.homeId, _homeId);
      expect(batch.status, CatalogImportBatchStatus.staged);
      expect(batch.revision, 3);
      expect(batch.rows, hasLength(2));
      expect(
        batch.rows.first.resolution,
        CatalogImportRowResolution.linkCatalog,
      );
      expect(batch.rows.last.resolution, CatalogImportRowResolution.error);
      expect(batch.rows.last.errorDetail, 'Unknown barcode');
      expect(batch.rows.first.displayName, 'Rolled oats');
    },
  );

  test('stage rejects out-of-contract keys and batch sizes locally', () {
    final transport = GeneratedCatalogImportTransport(
      _client((_) async => fail('The transport must not be called.')),
    );
    const record = <String, Object?>{'recordType': 'home_product'};
    expect(
      () => transport.stage(
        homeId: _homeId,
        idempotencyKey: 'short',
        records: const <Map<String, Object?>>[record],
      ),
      throwsArgumentError,
    );
    expect(
      () => transport.stage(
        homeId: _homeId,
        idempotencyKey: _idempotencyKey,
        records: const <Map<String, Object?>>[],
      ),
      throwsArgumentError,
    );
    expect(
      () => transport.stage(
        homeId: _homeId,
        idempotencyKey: _idempotencyKey,
        records: List<Map<String, Object?>>.filled(501, record),
      ),
      throwsArgumentError,
    );
  });

  test('fetch reads one staged import scoped to the home', () async {
    http.Request? seen;
    final transport = GeneratedCatalogImportTransport(
      _client((request) async {
        seen = request;
        return _json(_batchJson(status: 'staged'));
      }),
    );

    final batch = await transport.fetch(homeId: _homeId, importId: _importId);

    expect(seen!.method, 'GET');
    expect(seen!.url.path, '/api/v1/homes/$_homeId/catalog-imports/$_importId');
    expect(batch.replayed, isFalse);
    expect(batch.rowCount, 2);
  });

  test('confirm sends the pinned confirmation word and revision', () async {
    http.Request? seen;
    final transport = GeneratedCatalogImportTransport(
      _client((request) async {
        seen = request;
        return _json(_batchJson(status: 'confirmed'));
      }),
    );

    final batch = await transport.confirm(
      homeId: _homeId,
      importId: _importId,
      expectedRevision: 3,
    );

    expect(seen!.method, 'POST');
    expect(
      seen!.url.path,
      '/api/v1/homes/$_homeId/catalog-imports/$_importId/confirm',
    );
    expect(jsonDecode(seen!.body), <String, Object?>{
      'expectedRevision': 3,
      'confirmation': 'apply_catalog_records',
    });
    expect(batch.status, CatalogImportBatchStatus.confirmed);
    expect(
      () => transport.confirm(
        homeId: _homeId,
        importId: _importId,
        expectedRevision: 0,
      ),
      throwsArgumentError,
    );
  });

  test('a batch from another home never crosses the boundary', () async {
    final transport = GeneratedCatalogImportTransport(
      _client(
        (_) async => _json(
          _batchJson(
            status: 'staged',
            homeId: '99999999-9999-4999-8999-999999999999',
          ),
        ),
      ),
    );
    await expectLater(
      transport.fetch(homeId: _homeId, importId: _importId),
      throwsA(isA<CatalogImportUnavailableException>()),
    );
  });

  for (final scenario in <({int status, Matcher expected})>[
    (
      status: 401,
      expected: isA<CatalogImportAuthenticationRequiredException>(),
    ),
    (status: 403, expected: isA<CatalogImportForbiddenException>()),
    (status: 404, expected: isA<CatalogImportUnavailableException>()),
    (status: 409, expected: isA<CatalogImportConflictException>()),
    (status: 413, expected: isA<CatalogImportTooLargeException>()),
    (status: 422, expected: isA<CatalogImportValidationException>()),
    (status: 500, expected: isA<CatalogImportUnavailableException>()),
  ]) {
    test('problem status ${scenario.status} maps to a typed failure', () async {
      final transport = GeneratedCatalogImportTransport(
        _client((_) async => _problem(scenario.status)),
      );
      await expectLater(
        transport.stage(
          homeId: _homeId,
          idempotencyKey: _idempotencyKey,
          records: const <Map<String, Object?>>[
            <String, Object?>{'recordType': 'home_product'},
          ],
        ),
        throwsA(scenario.expected),
      );
    });
  }

  test('malformed success bodies surface as unavailability', () async {
    final transport = GeneratedCatalogImportTransport(
      _client((_) async => _json(<String, Object?>{'id': _importId})),
    );
    await expectLater(
      transport.fetch(homeId: _homeId, importId: _importId),
      throwsA(isA<CatalogImportUnavailableException>()),
    );
  });
}

ProvidentiaApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => ProvidentiaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(handler),
);

Map<String, Object?> _batchJson({
  required String status,
  String homeId = _homeId,
}) => <String, Object?>{
  'id': _importId,
  'homeId': homeId,
  'status': status,
  'rowCount': 2,
  'validCount': 1,
  'errorCount': 1,
  'importedCount': status == 'confirmed' ? 1 : 0,
  'skippedCount': status == 'confirmed' ? 1 : 0,
  'revision': 3,
  'rows': <Object?>[
    <String, Object?>{
      'position': 0,
      'recordType': 'home_product',
      'record': <String, Object?>{'name': 'Rolled oats', 'brand': 'Acme'},
      'resolution': 'link_catalog',
      'productId': '2b1f4f60-9d6a-4b86-9e34-3f6f3f0a9d21',
      'packId': null,
      'errorCode': null,
      'errorDetail': null,
    },
    <String, Object?>{
      'position': 1,
      'recordType': 'home_product',
      'record': <String, Object?>{'privateName': 'Weekend oats'},
      'resolution': 'error',
      'errorCode': 'unknown_barcode',
      'errorDetail': 'Unknown barcode',
    },
  ],
};

http.Response _json(Map<String, Object?> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

http.Response _problem(int status) => _json(<String, Object?>{
  'type': 'https://api.example.test/problems/catalog-import',
  'title': 'Catalog import problem',
  'status': status,
  'requestId': 'request-catalog-import',
}, status: status);
