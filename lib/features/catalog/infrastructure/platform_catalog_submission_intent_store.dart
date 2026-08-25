import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/features/catalog/application/catalog_submission_intent.dart';

/// Durable idempotency-key storage containing no contribution payload or
/// household identifier in plaintext.
final class PlatformCatalogSubmissionIntentStore
    implements CatalogSubmissionIntentStore {
  PlatformCatalogSubmissionIntentStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _prefix = 'providentia.catalog-submission-intent.v1.';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(CatalogSubmissionIntentKey key) async {
    final value = await _storage.read(key: _key(key));
    if (value == null) return null;
    if (!isUuid(value)) {
      await _storage.delete(key: _key(key));
      return null;
    }
    return value;
  }

  @override
  Future<void> write(CatalogSubmissionIntent intent) =>
      _storage.write(key: _key(intent.key), value: intent.submissionId);

  @override
  Future<void> delete(CatalogSubmissionIntent intent) async {
    final key = _key(intent.key);
    if (await _storage.read(key: key) == intent.submissionId) {
      await _storage.delete(key: key);
    }
  }

  String _key(CatalogSubmissionIntentKey key) => '$_prefix${key.storageSlot}';
}
