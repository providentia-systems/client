import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:providentia/core/security/database_key_store.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

const legacyDatabaseName = 'providentia.sqlite';
const encryptedDatabaseName = 'providentia.encrypted.sqlite';
const encryptedStagingName = 'providentia.encrypted.sqlite.migrating';

final class PreparedEncryptedDatabase {
  const PreparedEncryptedDatabase(this.file, this.key);

  final File file;
  final String key;
}

Future<void> _initializationTail = Future<void>.value();

/// Prepare the file before Drift has a chance to read a page or run migrations.
/// A process lock and an in-isolate queue serialize key creation and migration.
/// The secure-store plugin stays on the calling isolate; copying runs off-UI.
Future<PreparedEncryptedDatabase> prepareEncryptedDatabase({
  required Directory directory,
  required DatabaseKeyStore keyStore,
}) async {
  final previous = _initializationTail;
  final completed = Completer<void>();
  _initializationTail = completed.future;
  RandomAccessFile? lock;
  var locked = false;
  final isolateLockName =
      'providentia-database-init/'
      '${sha256.convert(utf8.encode(directory.absolute.path))}';
  ReceivePort? isolateLock;
  try {
    await previous;
    final waiting = Stopwatch()..start();
    isolateLock = ReceivePort();
    // POSIX file locks are process-scoped. The name-server guard additionally
    // serializes independent Flutter isolates in this engine/process. If a
    // holder dies without cleanup, fail closed until the application restarts.
    while (!IsolateNameServer.registerPortWithName(
      isolateLock.sendPort,
      isolateLockName,
    )) {
      if (waiting.elapsed >= const Duration(seconds: 15)) {
        throw const LocalDatabaseSecurityException('database_busy');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await directory.create(recursive: true);
    lock = await File(
      '${directory.path}/providentia.encryption.lock',
    ).open(mode: FileMode.append);
    while (!locked) {
      try {
        await lock.lock(FileLock.exclusive);
        locked = true;
      } on FileSystemException {
        if (waiting.elapsed >= const Duration(seconds: 15)) {
          throw const LocalDatabaseSecurityException('database_busy');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    final legacy = File('${directory.path}/$legacyDatabaseName');
    final encrypted = File('${directory.path}/$encryptedDatabaseName');
    final staging = File('${directory.path}/$encryptedStagingName');
    final key = await loadDatabaseKey(
      keyStore,
      existingEncryptedDatabase:
          await encrypted.exists() ||
          (await staging.exists() && !await legacy.exists()),
    );
    final path = directory.path;
    await Isolate.run(() => _prepareFiles(path, key));
    return PreparedEncryptedDatabase(encrypted, key);
  } on LocalDatabaseSecurityException {
    rethrow;
  } on Object {
    // SQLite and filesystem errors can carry SQL/key material or private paths.
    throw const LocalDatabaseSecurityException('database_open_failed');
  } finally {
    try {
      if (locked) {
        await lock?.unlock();
      }
      await lock?.close();
    } on Object {
      throw const LocalDatabaseSecurityException('database_lock_failed');
    } finally {
      if (isolateLock != null &&
          IsolateNameServer.lookupPortByName(isolateLockName) ==
              isolateLock.sendPort) {
        IsolateNameServer.removePortNameMapping(isolateLockName);
      }
      isolateLock?.close();
      completed.complete();
    }
  }
}

/// Applied before any schema/page access for every production connection.
void configureEncryptedDatabase(CommonDatabase database, String key) {
  try {
    if (!isValidDatabaseKey(key)) {
      throw const LocalDatabaseSecurityException('key_invalid');
    }
    _requireCipher(database);
    database.execute('PRAGMA cipher_log_level = NONE');
    // The strict hex validation above is required: PRAGMA does not bind values.
    database.execute('PRAGMA key = "x\'$key\'"');
    database.execute('PRAGMA cipher_compatibility = 4');
    database.execute('PRAGMA cipher_memory_security = ON');
    database.execute('PRAGMA temp_store = MEMORY');
    database.select('SELECT count(*) FROM sqlite_master');
  } on LocalDatabaseSecurityException {
    rethrow;
  } on Object {
    throw const LocalDatabaseSecurityException('database_unlock_failed');
  }
}

void _requireCipher(CommonDatabase database) {
  final rows = database.select('PRAGMA cipher_version');
  if (rows.isEmpty ||
      rows.single.values.single is! String ||
      !(rows.single.values.single as String).startsWith('4.')) {
    throw const LocalDatabaseSecurityException('cipher_unavailable');
  }
}

void _prepareFiles(String directory, String key) {
  final legacy = File('$directory/$legacyDatabaseName');
  final encrypted = File('$directory/$encryptedDatabaseName');
  final staging = File('$directory/$encryptedStagingName');
  try {
    if (encrypted.existsSync()) {
      _verifyEncrypted(encrypted, key);
      if (legacy.existsSync()) {
        // A crash after promotion but before cleanup is safe to resume only if
        // the two complete databases still agree. Never choose one by timestamp.
        _withLegacy(legacy, (source) {
          _attachEncrypted(source, encrypted, key);
          _verifyCopy(source);
          source.execute('DETACH DATABASE encrypted_copy');
        });
        _removePlaintext(legacy);
      }
      _removeFileFamily(staging);
      return;
    }
    if (legacy.existsSync()) {
      _withLegacy(legacy, (source) {
        // A partial export is disposable only while the verified source exists.
        _removeFileFamily(staging);
        _attachEncrypted(source, staging, key);
        final version = source
            .select('PRAGMA user_version')
            .single
            .values
            .single;
        source.select("SELECT sqlcipher_export('encrypted_copy')");
        source.execute('PRAGMA encrypted_copy.user_version = $version');
        _verifyCopy(source);
        source.execute('DETACH DATABASE encrypted_copy');
        _verifyEncrypted(staging, key);
        _flush(staging);
        staging.renameSync(encrypted.path);
        _verifyEncrypted(encrypted, key);
      });
      // No production connection is returned before all legacy files are gone.
      _removePlaintext(legacy);
      return;
    }
    if (!staging.existsSync()) {
      final database = sqlite3.open(staging.path);
      try {
        configureEncryptedDatabase(database, key);
        database.execute('PRAGMA user_version = 0');
      } finally {
        database.close();
      }
    }
    // If this is the only remaining copy (interrupted first initialization),
    // verify it rather than deleting/recreating it on an unexpected error.
    _verifyEncrypted(staging, key);
    _flush(staging);
    staging.renameSync(encrypted.path);
    _verifyEncrypted(encrypted, key);
    _removePlaintext(legacy);
  } on LocalDatabaseSecurityException {
    rethrow;
  } on Object {
    throw const LocalDatabaseSecurityException('migration_failed');
  }
}

void _withLegacy(File file, void Function(Database) action) {
  final header = file.openSync();
  late final List<int> bytes;
  try {
    bytes = header.readSync(16);
  } finally {
    header.closeSync();
  }
  if (bytes.isNotEmpty &&
      ascii.decode(bytes, allowInvalid: true) != 'SQLite format 3\u0000') {
    throw const LocalDatabaseSecurityException('legacy_format_invalid');
  }
  // SQLCipher ATTACH inherits the connection's CREATE flag. The source was
  // just verified above, but CREATE must remain enabled for the new copy.
  final database = sqlite3.open(file.path);
  try {
    _requireCipher(database);
    database.execute('PRAGMA cipher_log_level = NONE');
    database.execute('PRAGMA temp_store = MEMORY');
    database.execute('PRAGMA busy_timeout = 5000');
    // This checkpoints all committed WAL work, and fails if another instance
    // still holds the old database. Exclusive locking remains until close.
    database.execute('PRAGMA locking_mode = EXCLUSIVE');
    final mode = database.select('PRAGMA journal_mode = DELETE');
    if (mode.single.values.single != 'delete') {
      throw const LocalDatabaseSecurityException('legacy_database_busy');
    }
    database.execute('BEGIN EXCLUSIVE');
    database.execute('COMMIT');
    _verifyIntegrity(database, 'main');
    action(database);
  } finally {
    database.close();
  }
}

void _attachEncrypted(Database database, File file, String key) {
  database.execute('ATTACH DATABASE ? AS encrypted_copy KEY ?', [
    file.path,
    "x'$key'",
  ]);
  database.execute('PRAGMA encrypted_copy.cipher_compatibility = 4');
}

void _verifyCopy(Database database) {
  _verifyIntegrity(database, 'encrypted_copy');
  final sourceVersion = database
      .select('PRAGMA user_version')
      .single
      .values
      .single;
  final copyVersion = database
      .select('PRAGMA encrypted_copy.user_version')
      .single
      .values
      .single;
  if (sourceVersion != copyVersion) {
    throw const LocalDatabaseSecurityException('migration_verification_failed');
  }
  const schemaColumns = 'type, name, tbl_name, sql';
  _assertEqualQueries(
    database,
    'SELECT $schemaColumns FROM main.sqlite_master',
    'SELECT $schemaColumns FROM encrypted_copy.sqlite_master',
  );
  for (final table in database.select(
    "SELECT name FROM main.sqlite_master WHERE type = 'table'",
  )) {
    final name = _quoteIdentifier(table['name'] as String);
    final columns = database
        .select('PRAGMA main.table_info($name)')
        .map((column) => _quoteIdentifier(column['name'] as String))
        .join(', ');
    // Grouped multiplicities compare all values, including duplicate rows.
    _assertEqualQueries(
      database,
      'SELECT $columns, count(*) FROM main.$name GROUP BY $columns',
      'SELECT $columns, count(*) FROM encrypted_copy.$name GROUP BY $columns',
    );
  }
}

void _assertEqualQueries(Database database, String left, String right) {
  if (database
          .select('SELECT 1 FROM ($left EXCEPT $right) LIMIT 1')
          .isNotEmpty ||
      database
          .select('SELECT 1 FROM ($right EXCEPT $left) LIMIT 1')
          .isNotEmpty) {
    throw const LocalDatabaseSecurityException('migration_verification_failed');
  }
}

String _quoteIdentifier(String value) => '"${value.replaceAll('"', '""')}"';

void _verifyIntegrity(CommonDatabase database, String schema) {
  final rows = database.select('PRAGMA $schema.integrity_check');
  if (rows.length != 1 || rows.single.values.single != 'ok') {
    throw const LocalDatabaseSecurityException('database_integrity_failed');
  }
}

void _verifyEncrypted(File file, String key) {
  final database = sqlite3.open(file.path, mode: OpenMode.readWrite);
  try {
    configureEncryptedDatabase(database, key);
    _verifyIntegrity(database, 'main');
    if (database.select('PRAGMA cipher_integrity_check').isNotEmpty) {
      throw const LocalDatabaseSecurityException('database_integrity_failed');
    }
  } finally {
    database.close();
  }
}

void _flush(File file) {
  final handle = file.openSync(mode: FileMode.append);
  try {
    handle.flushSync();
  } finally {
    handle.closeSync();
  }
}

void _removePlaintext(File legacy) => _removeFileFamily(legacy);

void _removeFileFamily(File file) {
  for (final suffix in const ['-wal', '-shm', '-journal', '']) {
    final candidate = File('${file.path}$suffix');
    if (candidate.existsSync()) {
      candidate.deleteSync();
    }
  }
}
