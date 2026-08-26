/// Public, non-secret runtime values supplied to the Flutter application.
class RuntimeConfiguration {
  const RuntimeConfiguration._({
    required this.apiBaseUri,
    required this.homeownerAppLinkBaseUri,
    required this.environment,
  });

  factory RuntimeConfiguration({
    required Uri apiBaseUri,
    required String environment,
    Uri? homeownerAppLinkBaseUri,
  }) {
    final validatedEnvironment = environment.trim();
    if (validatedEnvironment.isEmpty) {
      throw const FormatException('Environment cannot be empty.');
    }
    final validatedApiBaseUri = _validateApiBaseUri(
      apiBaseUri.toString(),
      environment: validatedEnvironment,
    );
    final validatedHomeownerAppLinkBaseUri = _validateAppLinkBaseUri(
      homeownerAppLinkBaseUri ??
          Uri.parse('providentia://login-link/homeowner'),
      environment: validatedEnvironment,
    );
    return RuntimeConfiguration._(
      apiBaseUri: validatedApiBaseUri,
      homeownerAppLinkBaseUri: validatedHomeownerAppLinkBaseUri,
      environment: validatedEnvironment,
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
    const rawHomeownerAppLinkBase = String.fromEnvironment(
      'PROVIDENTIA_HOMEOWNER_APP_LINK_BASE',
      defaultValue: 'providentia://login-link/homeowner',
    );
    return RuntimeConfiguration(
      apiBaseUri: Uri.parse(rawApiBaseUrl),
      homeownerAppLinkBaseUri: Uri.parse(rawHomeownerAppLinkBase),
      environment: environment,
    );
  }

  final Uri apiBaseUri;
  final Uri homeownerAppLinkBaseUri;
  final String environment;

  static Uri _validateApiBaseUri(String value, {required String environment}) {
    final uri = Uri.parse(value);
    final isLoopback =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';

    if (!uri.hasScheme || !uri.hasAuthority) {
      throw const FormatException(
        'PROVIDENTIA_API_BASE_URL must be an absolute URI.',
      );
    }
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' && isLoopback && environment == 'development')) {
      throw const FormatException(
        'PROVIDENTIA_API_BASE_URL must use HTTPS outside loopback development.',
      );
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      throw const FormatException(
        'PROVIDENTIA_API_BASE_URL must be an origin without a path.',
      );
    }
    if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'PROVIDENTIA_API_BASE_URL cannot contain credentials, query, or fragment.',
      );
    }

    return uri;
  }

  static Uri _validateAppLinkBaseUri(Uri uri, {required String environment}) {
    final isLoopback =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    final supportedScheme =
        uri.scheme == 'providentia' ||
        uri.scheme == 'https' ||
        (uri.scheme == 'http' && isLoopback && environment == 'development');
    if (!supportedScheme ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.path != '/homeowner' ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'PROVIDENTIA_HOMEOWNER_APP_LINK_BASE must be HTTPS, Providentia, or '
        'loopback HTTP in development, without credentials, query, or fragment.',
      );
    }
    if (uri.scheme == 'providentia' && uri.host != 'login-link') {
      throw const FormatException(
        'The Providentia homeowner app-link host must be login-link.',
      );
    }
    return uri;
  }
}
