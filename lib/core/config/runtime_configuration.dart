/// Public, non-secret runtime values supplied to the Flutter application.
class RuntimeConfiguration {
  const RuntimeConfiguration._({
    required this.apiBaseUri,
    required this.environment,
  });

  factory RuntimeConfiguration({
    required Uri apiBaseUri,
    required String environment,
  }) {
    if (environment.trim().isEmpty) {
      throw const FormatException('Environment cannot be empty.');
    }
    return RuntimeConfiguration._(
      apiBaseUri: _validateApiBaseUri(apiBaseUri.toString()),
      environment: environment,
    );
  }

  factory RuntimeConfiguration.fromEnvironment() {
    const rawApiBaseUrl = String.fromEnvironment(
      'PROVIDENTIA_API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    );
    const environment = String.fromEnvironment(
      'PROVIDENTIA_ENVIRONMENT',
      defaultValue: 'development',
    );

    return RuntimeConfiguration(
      apiBaseUri: Uri.parse(rawApiBaseUrl),
      environment: environment,
    );
  }

  final Uri apiBaseUri;
  final String environment;

  static Uri _validateApiBaseUri(String value) {
    final uri = Uri.parse(value);
    final isLoopback =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';

    if (!uri.hasScheme || !uri.hasAuthority) {
      throw const FormatException(
        'PROVIDENTIA_API_BASE_URL must be an absolute URI.',
      );
    }
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && isLoopback)) {
      throw const FormatException(
        'PROVIDENTIA_API_BASE_URL must use HTTPS outside loopback development.',
      );
    }
    if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'PROVIDENTIA_API_BASE_URL cannot contain credentials, query, or fragment.',
      );
    }

    return uri;
  }
}
