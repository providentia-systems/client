import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:providentia/core/database/encrypted_database.dart';
import 'package:providentia/core/security/database_key_store.dart';

QueryExecutor openPlatformDatabase() => LazyDatabase(() async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final prepared = await prepareEncryptedDatabase(
      directory: directory,
      keyStore: SecureDatabaseKeyStore(),
    );
    return _connect(prepared.file, prepared.key);
  } on LocalDatabaseSecurityException {
    rethrow;
  } on Object {
    throw const LocalDatabaseSecurityException('database_open_failed');
  }
});

// Capture only the key/path in isolate callbacks, never a secure-store plugin.
QueryExecutor _connect(File file, String key) => driftDatabase(
  name: 'providentia_encrypted_v1',
  native: DriftNativeOptions(
    shareAcrossIsolates: true,
    databasePath: () async => file.path,
    setup: (database) => configureEncryptedDatabase(database, key),
  ),
);
