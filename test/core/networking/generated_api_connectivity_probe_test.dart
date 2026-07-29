import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/networking/generated_api_connectivity_probe.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test('generated readiness client reports online', () async {
    final probe = GeneratedApiConnectivityProbe(
      ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/health/ready');
          return http.Response(
            jsonEncode(<String, Object?>{
              'status': 'ready',
              'checks': <String, Object?>{
                'database': <String, Object?>{'status': 'up'},
                'queue': <String, Object?>{'status': 'up'},
              },
            }),
            200,
          );
        }),
      ),
    );

    final result = await probe.check();

    expect(result.availability, SyncAvailability.online);
    expect(result.safeMessage, isNull);
  });

  test(
    'token expiry is authentication-required, not authorization blocked',
    () async {
      final probe = GeneratedApiConnectivityProbe(
        ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient((_) async {
            return http.Response(
              jsonEncode(<String, Object?>{
                'type': 'https://providentia.example/problems/token-expired',
                'title': 'Access token expired',
                'status': 401,
                'requestId': 'request-401',
              }),
              401,
            );
          }),
        ),
      );

      final result = await probe.check();

      expect(result.availability, SyncAvailability.authenticationRequired);
      expect(result.safeMessage, contains('Sign in again'));
    },
  );

  test('retryable service failure leaves local work offline', () async {
    final probe = GeneratedApiConnectivityProbe(
      ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'type': 'https://providentia.example/problems/not-ready',
              'title': 'Service unavailable',
              'status': 503,
              'requestId': 'request-503',
              'retryable': true,
            }),
            503,
          );
        }),
      ),
    );

    final result = await probe.check();

    expect(result.availability, SyncAvailability.offline);
    expect(result.safeMessage, contains('temporarily unavailable'));
  });
}
