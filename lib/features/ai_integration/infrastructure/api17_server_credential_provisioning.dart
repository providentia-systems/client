import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Write-only BYOK provisioning through the home-scoped Laminas vault.
/// Secrets are never returned to Flutter after this call succeeds.
final class Api17ServerCredentialProvisioning
    implements ServerCredentialProvisioningPort {
  const Api17ServerCredentialProvisioning(this._client);

  final ProvidentiaApiClient _client;

  @override
  Future<void> replaceCredential({
    required String homeId,
    required String profileId,
    required String secret,
  }) async {
    if (secret.length < 16 || secret.length > 500) {
      throw ArgumentError.value(
        secret.length,
        'secret',
        'must contain between 16 and 500 characters',
      );
    }
    await _client.putAiProviderCredential(
      homeId: homeId,
      providerId: profileId,
      body: <String, Object?>{'credential': secret},
    );
  }

  @override
  Future<void> deleteCredential({
    required String homeId,
    required String profileId,
  }) {
    return _client
        .deleteAiProviderCredential(homeId: homeId, providerId: profileId)
        .then<void>((_) {});
  }
}
