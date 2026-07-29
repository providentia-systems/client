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
  });
}
