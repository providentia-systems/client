import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/config/runtime_configuration.dart';
import 'package:providentia/core/networking/api_client_factory.dart';

void main() {
  test(
    'development bearer is attached only at the composition boundary',
    () async {
      final configuration = RuntimeConfiguration(
        apiBaseUri: Uri.parse('http://localhost:8080'),
        environment: 'development',
        developmentBearerToken: 'dev-integration-token',
      );
      final client = const ApiClientFactory().create(
        configuration: configuration,
        httpClient: MockClient((request) async {
          expect(
            request.headers['Authorization'],
            'Bearer dev-integration-token',
          );
          return http.Response(
            jsonEncode(<String, Object?>{
              'status': 'alive',
              'timestamp': '2026-07-30T12:00:00Z',
            }),
            200,
          );
        }),
      );

      await client.getLiveness();
      client.close();
    },
  );
}
