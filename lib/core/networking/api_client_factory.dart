import 'package:http/http.dart' as http;
import 'package:providentia/core/config/runtime_configuration.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Composition-root factory for the generated backend client.
///
/// Feature and widget code must depend on application-owned repositories in
/// later phases; it must never construct this transport client directly.
final class ApiClientFactory {
  const ApiClientFactory();

  ProvidentiaApiClient create({
    required RuntimeConfiguration configuration,
    http.Client? httpClient,
  }) {
    return ProvidentiaApiClient(
      baseUri: configuration.apiBaseUri,
      httpClient: httpClient,
    );
  }
}
