import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

/// Persists only the rotating native refresh credential in OS secure storage.
final class PlatformSessionCredentialStore implements SessionCredentialStore {
  PlatformSessionCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _storageKey = 'providentia.native-session.v1';

  final FlutterSecureStorage _storage;

  @override
  bool get supportsPersistentSecrets => true;

  @override
  Future<StoredNativeSession?> read() async {
    final encoded = await _storage.read(key: _storageKey);
    if (encoded == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Expected an object.');
      }
      return StoredNativeSession(
        sessionId: _requiredString(decoded, 'sessionId'),
        deviceId: _requiredString(decoded, 'deviceId'),
        refreshToken: _requiredString(decoded, 'refreshToken'),
      );
    } on Object {
      await clear();
      throw const IdentityCredentialStoreException(
        'The saved session was invalid and has been removed.',
      );
    }
  }

  @override
  Future<void> write(StoredNativeSession session) {
    return _storage.write(
      key: _storageKey,
      value: jsonEncode(<String, String>{
        'sessionId': session.sessionId,
        'deviceId': session.deviceId,
        'refreshToken': session.refreshToken,
      }),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: _storageKey);
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key.');
  }
  return value;
}
