import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/config/runtime_configuration.dart';

void main() {
  group('RuntimeConfiguration', () {
    test('accepts an HTTPS API endpoint', () {
      final configuration = RuntimeConfiguration(
        apiBaseUri: Uri.parse('https://api.example.test'),
        environment: 'test',
      );

      expect(configuration.apiBaseUri.scheme, 'https');
      expect(
        configuration.homeownerAppLinkBaseUri,
        Uri.parse('providentia://login-link/homeowner'),
      );
      expect(configuration.environment, 'test');
    });

    test('accepts a deployment-owned HTTPS homeowner app-link base', () {
      final configuration = RuntimeConfiguration(
        apiBaseUri: Uri.parse('https://api.example.test'),
        environment: 'production',
        homeownerAppLinkBaseUri: Uri.parse(
          'https://app.example.test/homeowner',
        ),
      );

      expect(
        configuration.homeownerAppLinkBaseUri,
        Uri.parse('https://app.example.test/homeowner'),
      );
    });

    test('accepts loopback HTTP app links only during development', () {
      final loopback = Uri.parse('http://127.0.0.1:8081/homeowner');
      expect(
        RuntimeConfiguration(
          apiBaseUri: Uri.parse('http://127.0.0.1:8080'),
          environment: 'development',
          homeownerAppLinkBaseUri: loopback,
        ).homeownerAppLinkBaseUri,
        loopback,
      );
      expect(
        () => RuntimeConfiguration(
          apiBaseUri: Uri.parse('https://api.example.test'),
          environment: 'production',
          homeownerAppLinkBaseUri: loopback,
        ),
        throwsFormatException,
      );
      expect(
        () => RuntimeConfiguration(
          apiBaseUri: Uri.parse('http://api.example.test'),
          environment: 'development',
          homeownerAppLinkBaseUri: Uri.parse(
            'http://app.example.test/homeowner',
          ),
        ),
        throwsFormatException,
      );
    });

    test('rejects app-link query, fragment, and the admin path', () {
      for (final uri in <Uri>[
        Uri.parse('providentia://login-link/admin'),
        Uri.parse('https://app.example.test/auth'),
        Uri.parse('providentia://login-link/homeowner?token=secret'),
        Uri.parse('https://app.example.test/homeowner#secret'),
      ]) {
        expect(
          () => RuntimeConfiguration(
            apiBaseUri: Uri.parse('https://api.example.test'),
            environment: 'production',
            homeownerAppLinkBaseUri: uri,
          ),
          throwsFormatException,
        );
      }
    });

    test('environment defaults are safe for local development', () {
      final configuration = RuntimeConfiguration.fromEnvironment();

      expect(configuration.apiBaseUri, Uri.parse('http://localhost:8080'));
      expect(configuration.environment, 'development');
    });

    test('rejects cleartext non-loopback API endpoints', () {
      expect(
        () => RuntimeConfiguration(
          apiBaseUri: Uri.parse('http://api.example.test'),
          environment: 'production',
        ),
        throwsFormatException,
      );
    });

    test('rejects cleartext loopback outside development', () {
      expect(
        () => RuntimeConfiguration(
          apiBaseUri: Uri.parse('http://localhost:8080'),
          environment: 'production',
        ),
        throwsFormatException,
      );
    });

    test(
      'rejects an API base path because configuration requires an origin',
      () {
        expect(
          () => RuntimeConfiguration(
            apiBaseUri: Uri.parse('https://api.example.test/providentia'),
            environment: 'production',
          ),
          throwsFormatException,
        );
      },
    );
  });
}
