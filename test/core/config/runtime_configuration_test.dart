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
