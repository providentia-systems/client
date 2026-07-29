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
      expect(configuration.environment, 'test');
    });

    test('environment defaults are safe for local development', () {
      final configuration = RuntimeConfiguration.fromEnvironment();

      expect(configuration.apiBaseUri, Uri.parse('http://localhost:8080'));
      expect(configuration.environment, 'development');
      expect(configuration.developmentHomeId, isNull);
      expect(configuration.requireBootstrapHomeId, throwsFormatException);
    });

    test('validates and normalizes the development home UUID', () {
      final configuration = RuntimeConfiguration(
        apiBaseUri: Uri.parse('http://localhost:8080'),
        environment: 'development',
        developmentHomeId: '0198A0B1-C2D3-7E4F-8123-456789ABCDEF',
      );

      expect(
        configuration.requireBootstrapHomeId(),
        '0198a0b1-c2d3-7e4f-8123-456789abcdef',
      );
    });

    test('rejects a non-UUID development home', () {
      expect(
        () => RuntimeConfiguration(
          apiBaseUri: Uri.parse('http://localhost:8080'),
          environment: 'development',
          developmentHomeId: 'local-prototype-home',
        ),
        throwsFormatException,
      );
    });

    test(
      'rejects the development home bootstrap outside loopback development',
      () {
        expect(
          () => RuntimeConfiguration(
            apiBaseUri: Uri.parse('https://api.example.test'),
            environment: 'production',
            developmentHomeId: '0198a0b1-c2d3-7e4f-8123-456789abcdef',
          ),
          throwsFormatException,
        );
      },
    );

    test('allows a development bearer only with loopback development', () {
      final configuration = RuntimeConfiguration(
        apiBaseUri: Uri.parse('http://127.0.0.1:8080'),
        environment: 'development',
        developmentBearerToken: 'dev-token-123',
      );
      expect(configuration.developmentBearerToken, 'dev-token-123');

      expect(
        () => RuntimeConfiguration(
          apiBaseUri: Uri.parse('https://api.example.test'),
          environment: 'development',
          developmentBearerToken: 'must-not-ship',
        ),
        throwsFormatException,
      );
      expect(
        () => RuntimeConfiguration(
          apiBaseUri: Uri.parse('http://localhost:8080'),
          environment: 'production',
          developmentBearerToken: 'must-not-ship',
        ),
        throwsFormatException,
      );
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
  });
}
