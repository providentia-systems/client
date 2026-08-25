import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  group('generated ProvidentiaApiClient', () {
    test('decodes the liveness contract', () async {
      final client = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/health/live');
          expect(request.headers['Accept'], 'application/json');
          return http.Response(
            jsonEncode(<String, Object?>{
              'status': 'alive',
              'timestamp': '2026-07-29T12:00:00Z',
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final status = await client.getLiveness();

      expect(status.status, 'alive');
      expect(status.timestamp, DateTime.utc(2026, 7, 29, 12));
    });

    test('decodes structured readiness checks', () async {
      final client = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'status': 'ready',
              'checks': <String, Object?>{
                'database': <String, Object?>{'status': 'up'},
                'queue': <String, Object?>{
                  'status': 'optional',
                  'detail': 'Broker not required by this profile.',
                },
              },
            }),
            200,
          );
        }),
      );

      final readiness = await client.getReadiness();

      expect(readiness.status, 'ready');
      expect(readiness.checks['database']?.status, 'up');
      expect(readiness.checks['queue']?.status, 'optional');
      expect(
        readiness.checks['queue']?.detail,
        'Broker not required by this profile.',
      );
    });

    test('decodes authoritative system information fields', () async {
      final client = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'product': 'Providentia',
              'apiVersion': 'v1',
              'applicationVersion': '0.1.0',
              'environment': 'test',
              'runtime': 'PHP 8.4',
              'databaseDriver': 'pdo_sqlite',
              'queueAdapter': 'enqueue-redis',
              'queueBroker': 'redis-compatible',
            }),
            200,
          );
        }),
      );

      final info = await client.getSystemInfo();

      expect(info.product, 'Providentia');
      expect(info.apiVersion, 'v1');
      expect(info.applicationVersion, '0.1.0');
      expect(info.databaseDriver, 'pdo_sqlite');
      expect(info.queueAdapter, 'enqueue-redis');
      expect(info.queueBroker, 'redis-compatible');
    });

    test('decodes RFC 9457 failures and request IDs', () async {
      final client = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'type': 'https://providentia.example/problems/not-ready',
              'title': 'Service unavailable',
              'status': 503,
              'detail': 'Database connectivity failed.',
              'requestId': 'request-01',
              'retryable': true,
            }),
            503,
            headers: <String, String>{
              'content-type': 'application/problem+json',
              'x-request-id': 'request-01',
            },
          );
        }),
      );

      await expectLater(
        client.getReadiness(),
        throwsA(
          isA<ProvidentiaApiException>()
              .having((error) => error.statusCode, 'statusCode', 503)
              .having((error) => error.requestId, 'requestId', 'request-01')
              .having(
                (error) => error.problem.requestId,
                'problem requestId',
                'request-01',
              )
              .having(
                (error) => error.problem.extensions['retryable'],
                'retryable extension',
                true,
              ),
        ),
      );
    });

    test('returns metrics as text without JSON coercion', () async {
      final client = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/metrics');
          return http.Response(
            'providentia_up 1\n',
            200,
            headers: <String, String>{
              'content-type': 'text/plain; version=0.0.4',
            },
          );
        }),
      );

      expect(await client.getMetrics(), 'providentia_up 1\n');
    });

    test('publishes the complete API 1.15.0 operation registry', () {
      expect(ProvidentiaApiClient.operations, hasLength(174));
      expect(
        ProvidentiaApiClient.operations['createAiExtraction'],
        isA<ApiOperation>()
            .having((operation) => operation.method, 'method', 'POST')
            .having(
              (operation) => operation.pathTemplate,
              'path',
              '/api/v1/homes/{homeId}/ai/extractions',
            )
            .having((operation) => operation.multipart, 'multipart', true),
      );
      expect(
        ProvidentiaApiClient.operations.keys,
        containsAll(<String>[
          'login',
          'startLoginLink',
          'getLoginLinkStatus',
          'exchangeLoginLink',
          'refreshSession',
          'getCurrentUser',
          'createHome',
          'listPendingHomeInvitations',
          'listPlatformAdministrators',
          'listHomeStock',
          'cancelStockCountSession',
          'commitReceipt',
          'unresolveReceiptLine',
          'createShoppingSuggestionRun',
          'getInventoryReport',
          'createHomeCategory',
          'listHomeCategories',
          'createCatalogContribution',
          'createCatalogProductImageContribution',
          'listCatalogContributionReviewQueue',
          'listOperatorAccounts',
          'getOperatorAccount',
        ]),
      );
    });

    test('sends JSON bodies through generated operation methods', () async {
      final client = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/auth/login');
          expect(
            request.headers['Content-Type'],
            startsWith('application/json'),
          );
          expect(jsonDecode(request.body), <String, Object?>{
            'email': 'owner@example.test',
            'password': 'correct horse battery staple',
          });
          return http.Response(
            jsonEncode(<String, Object?>{'accessToken': 'redacted'}),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final response = await client.login(
        body: <String, Object?>{
          'email': 'owner@example.test',
          'password': 'correct horse battery staple',
        },
      );

      expect(response.requireObject()['accessToken'], 'redacted');
    });

    test('encodes path parameters and forwards query values', () async {
      final client = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test/base'),
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'https://api.example.test/api/v1/homes/home%20one/stock?limit=50',
          );
          expect(request.url.queryParameters['limit'], '50');
          return http.Response('[]', 200);
        }),
      );

      final response = await client.listHomeStock(
        homeId: 'home one',
        query: <String, String>{'limit': '50'},
      );

      expect(response.requireList(), isEmpty);
    });

    test('rejects incomplete generated path parameters before transport', () {
      final client = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(
        () => client.invokeOperation(operationId: 'getReceipt'),
        throwsArgumentError,
      );
    });
  });
}
