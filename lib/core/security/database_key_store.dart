import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Deliberately carries neither a path nor the underlying platform exception.
final class LocalDatabaseSecurityException implements Exception {
  const LocalDatabaseSecurityException(this.code);

  final String code;

  @override
  String toString() => 'Local database protection is unavailable ($code).';
}

/// This key belongs to the installation, not to a refresh token or account.
/// Signing out must not destroy the key protecting unsynchronized local work.
abstract interface class DatabaseKeyStore {
  Future<String?> read();
  Future<void> write(String key);
}

final class SecureDatabaseKeyStore implements DatabaseKeyStore {
  SecureDatabaseKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: false,
              storageNamespace: 'providentia.database.v1',
            ),
            iOptions: IOSOptions(
              accountName: 'providentia.database.v1',
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
            mOptions: MacOsOptions(
              accountName: 'providentia.database.v1',
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  static const storageKey = 'providentia.database-key.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: storageKey);
    } on Object {
      throw const LocalDatabaseSecurityException('key_store_unavailable');
    }
  }

  @override
  Future<void> write(String key) async {
    try {
      await _storage.write(key: storageKey, value: key);
    } on Object {
      throw const LocalDatabaseSecurityException('key_store_unavailable');
    }
  }
}

bool isValidDatabaseKey(String key) => RegExp(r'^[0-9a-f]{64}$').hasMatch(key);

/// Call under the database initialization lock. Never replace an unreadable,
/// malformed or missing existing key: doing so could strand an outbox forever.
Future<String> loadDatabaseKey(
  DatabaseKeyStore store, {
  required bool existingEncryptedDatabase,
}) async {
  try {
    final saved = await store.read();
    if (saved != null) {
      if (!isValidDatabaseKey(saved)) {
        throw const LocalDatabaseSecurityException('key_invalid');
      }
      return saved;
    }
    if (existingEncryptedDatabase) {
      throw const LocalDatabaseSecurityException('key_missing');
    }
    final random = Random.secure();
    final created = List<int>.generate(
      32,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await store.write(created);
    // Persistence is proven before a single encrypted database byte is written.
    if (await store.read() != created) {
      throw const LocalDatabaseSecurityException('key_not_persisted');
    }
    return created;
  } on LocalDatabaseSecurityException {
    rethrow;
  } on Object {
    throw const LocalDatabaseSecurityException('key_store_unavailable');
  }
}
