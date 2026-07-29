import 'dart:async';

import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Uses the pinned, generated API client to classify backend availability.
///
/// No feature or widget sees the generated transport type.
final class GeneratedApiConnectivityProbe implements ConnectivityProbe {
  const GeneratedApiConnectivityProbe(
    this._client, {
    this.timeout = const Duration(seconds: 8),
  });

  final ProvidentiaApiClient _client;
  final Duration timeout;

  @override
  Future<ConnectivityResult> check() async {
    try {
      final readiness = await _client.getReadiness().timeout(timeout);
      if (readiness.status == 'ready') {
        return const ConnectivityResult.online();
      }
      return const ConnectivityResult.offline(
        'The service is starting. Local changes remain safe.',
      );
    } on ProvidentiaApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return const ConnectivityResult.authenticationRequired(
          'Sign in again to continue synchronizing.',
        );
      }
      return ConnectivityResult.offline(
        error.problem.extensions['retryable'] == true
            ? 'The service is temporarily unavailable. Retrying safely.'
            : 'The service cannot be reached. Local changes remain safe.',
      );
    } on TimeoutException {
      return const ConnectivityResult.offline(
        'The service did not respond. Local changes remain safe.',
      );
    } on Object {
      return const ConnectivityResult.offline(
        'No connection. Local changes remain safe.',
      );
    }
  }
}
