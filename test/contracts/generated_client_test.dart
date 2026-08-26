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

    test('publishes only the API 1.19.0 homeowner operation registry', () {
      expect(ProvidentiaApiClient.operations, hasLength(140));
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
        ProvidentiaApiClient.operations['removeHomeMembership'],
        isA<ApiOperation>()
            .having((operation) => operation.method, 'method', 'DELETE')
            .having(
              (operation) => operation.pathTemplate,
              'path',
              '/api/v1/homes/{homeId}/memberships/{userId}',
            )
            .having((operation) => operation.multipart, 'multipart', false),
      );
      expect(
        ProvidentiaApiClient.operations.keys,
        containsAll(<String>[
          'startLoginLink',
          'proveLoginLinkApproval',
          'reviewLoginLinkApproval',
          'decideLoginLinkApproval',
          'getLoginLinkStatus',
          'exchangeLoginLink',
          'refreshSession',
          'getCurrentUser',
          'removeHomeMembership',
          'createHome',
          'listPendingHomeInvitations',
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
          'listPublishedCatalogContributions',
          'submitCatalogProposal',
        ]),
      );
      // API 1.19.0 removed the entire human-account password and
      // email-verification surface; login links are the only human sign-in.
      for (final forbiddenOperation in <String>[
        'registerAccount',
        'login',
        'verifyEmail',
        'resendEmailVerification',
        'requestPasswordReset',
        'completePasswordReset',
        'getMetrics',
        'listPlatformAdministrators',
        'grantPlatformAdministrator',
        'revokePlatformAdministrator',
        'listCatalogContributionReviewQueue',
        'decideCatalogContribution',
        'putCatalogContributionProposal',
        'getCatalogProductImageContributionPreview',
        'putCatalogProductImageContributionPublication',
        'getCatalogWorkbench',
        'listOperatorAccounts',
        'getOperatorAccount',
        'acceptBillingWebhook',
      ]) {
        expect(
          ProvidentiaApiClient.operations.containsKey(forbiddenOperation),
          isFalse,
          reason: forbiddenOperation,
        );
      }
      for (final operation in ProvidentiaApiClient.operations.values) {
        expect(operation.pathTemplate, isNot('/metrics'));
        for (final forbiddenPrefix in <String>[
          '/api/v1/admin/',
          '/api/v1/catalog-admin/',
          '/api/v1/operator/',
          '/api/v1/platform/',
          '/api/v1/billing/webhooks/',
          '/api/v1/catalog-contributions/review',
        ]) {
          expect(
            operation.pathTemplate.startsWith(forbiddenPrefix),
            isFalse,
            reason: operation.operationId,
          );
        }
        if (operation.pathTemplate.startsWith(
          '/api/v1/catalog-contributions/',
        )) {
          for (final forbiddenModerationSegment in <String>[
            '/decision',
            '/image-preview',
            '/image-publication',
          ]) {
            expect(
              operation.pathTemplate.contains(forbiddenModerationSegment),
              isFalse,
              reason: operation.operationId,
            );
          }
        }
      }
    });

    test('sends JSON bodies through generated operation methods', () async {
      final client = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/auth/login-links');
          expect(
            request.headers['Content-Type'],
            startsWith('application/json'),
          );
          expect(jsonDecode(request.body), <String, Object?>{
            'email': 'owner@example.test',
            'applicationKind': 'homeowner',
          });
          return http.Response(
            jsonEncode(<String, Object?>{'accepted': true}),
            202,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final response = await client.startLoginLink(
        body: <String, Object?>{
          'email': 'owner@example.test',
          'applicationKind': 'homeowner',
        },
      );

      expect(response.requireObject()['accepted'], true);
    });

    test('sends the revisioned membership removal without a body', () async {
      final client = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/api/v1/homes/home-1/memberships/user%201');
          expect(request.url.queryParameters['expectedRevision'], '7');
          expect(request.body, isEmpty);
          return http.Response('', 204);
        }),
      );

      final response = await client.removeHomeMembership(
        homeId: 'home-1',
        userId: 'user 1',
        query: <String, String>{'expectedRevision': '7'},
      );

      expect(response.statusCode, 204);
      expect(response.body, isNull);
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
