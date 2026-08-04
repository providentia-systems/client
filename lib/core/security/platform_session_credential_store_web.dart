import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

/// Browsers authenticate only with Secure, HttpOnly backend cookies.
/// Bearer and refresh credentials are never written to browser storage.
final class PlatformSessionCredentialStore implements SessionCredentialStore {
  @override
  bool get supportsPersistentSecrets => false;

  @override
  Future<StoredNativeSession?> read() async => null;

  @override
  Future<void> write(StoredNativeSession session) {
    throw const IdentityCredentialStoreException(
      'Browser session secrets cannot be persisted by the application.',
    );
  }

  @override
  Future<void> clear() async {}
}
