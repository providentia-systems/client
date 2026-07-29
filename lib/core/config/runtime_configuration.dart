/// Public, non-secret runtime values supplied to the Flutter application.
class RuntimeConfiguration {
  const RuntimeConfiguration._({
    required this.apiBaseUri,
    required this.environment,
    required this.developmentHomeId,
    required this.developmentBearerToken,
  });

  factory RuntimeConfiguration({
    required Uri apiBaseUri,
    required String environment,
    String? developmentHomeId,
    String? developmentBearerToken,
  }) {
    if (environment.trim().isEmpty) {
      throw const FormatException('Environment cannot be empty.');
    }
    final validatedApiBaseUri = _validateApiBaseUri(apiBaseUri.toString());
    return RuntimeConfiguration._(
      apiBaseUri: validatedApiBaseUri,
      environment: environment,
      developmentHomeId: _validateDevelopmentHomeId(
        developmentHomeId,
        environment: environment,
        apiBaseUri: validatedApiBaseUri,
      ),
      developmentBearerToken: _validateDevelopmentBearerToken(
        developmentBearerToken,
        environment: environment,
        apiBaseUri: validatedApiBaseUri,
      ),
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
    const developmentHomeId = String.fromEnvironment('PROVIDENTIA_DEV_HOME_ID');
    const developmentBearerToken = String.fromEnvironment(
      'PROVIDENTIA_DEV_BEARER_TOKEN',
    );

    return RuntimeConfiguration(
      apiBaseUri: Uri.parse(rawApiBaseUrl),
      environment: environment,
      developmentHomeId: developmentHomeId.isEmpty ? null : developmentHomeId,
      developmentBearerToken: developmentBearerToken.isEmpty
          ? null
          : developmentBearerToken,
    );
  }

  final Uri apiBaseUri;
  final String environment;
  final String? developmentHomeId;
  final String? developmentBearerToken;

  /// Returns the owner-supplied home used by the development launch bootstrap.
  /// Production must replace this with the authenticated session's active
  /// home and may not infer authorization from this value.
  String requireBootstrapHomeId() {
    final homeId = developmentHomeId;
    if (homeId == null) {
      throw const FormatException(
        'Set PROVIDENTIA_DEV_HOME_ID to an authorized home UUID with '
        '--dart-define. Authenticated active-home selection replaces this '
        'development bootstrap in production.',
      );
    }
    return homeId;
  }

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

  static String? _validateDevelopmentHomeId(
    String? value, {
    required String environment,
    required Uri apiBaseUri,
  }) {
    if (value == null) {
      return null;
    }
    if (environment != 'development' || !_isLoopback(apiBaseUri)) {
      throw const FormatException(
        'PROVIDENTIA_DEV_HOME_ID is permitted only for development against '
        'a loopback API.',
      );
    }
    final canonicalUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-'
      r'[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    if (!canonicalUuid.hasMatch(value)) {
      throw const FormatException(
        'PROVIDENTIA_DEV_HOME_ID must be a canonical UUID.',
      );
    }
    return value.toLowerCase();
  }

  static String? _validateDevelopmentBearerToken(
    String? value, {
    required String environment,
    required Uri apiBaseUri,
  }) {
    if (value == null) {
      return null;
    }
    if (environment != 'development' || !_isLoopback(apiBaseUri)) {
      throw const FormatException(
        'PROVIDENTIA_DEV_BEARER_TOKEN is permitted only for development '
        'against a loopback API.',
      );
    }
    if (value.trim().isEmpty || RegExp(r'\s').hasMatch(value)) {
      throw const FormatException(
        'PROVIDENTIA_DEV_BEARER_TOKEN cannot be empty or contain whitespace.',
      );
    }
    return value;
  }

  static bool _isLoopback(Uri uri) {
    return uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1';
  }
}
