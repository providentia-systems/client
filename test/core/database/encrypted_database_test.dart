import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/encrypted_database.dart';
import 'package:providentia/core/security/database_key_store.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory directory;
  late _Keys keys;

  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'providentia-encryption-test-',
    );
    keys = _Keys();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('test binary really contains SQLCipher rather than plain SQLite', () {
    final raw = sqlite3.openInMemory();
    try {
      expect(
        raw.select('PRAGMA cipher_version').single.values.single,
        startsWith('4.'),
      );
    } finally {
      raw.close();
    }
  });

  test('first creation encrypts the file and survives a cold reopen', () async {
    final prepared = await prepareEncryptedDatabase(
      directory: directory,
      keyStore: keys,
    );
    var database = _open(prepared);
    await database.customStatement('CREATE TABLE probe (value TEXT NOT NULL)');
    await database.customStatement(
      "INSERT INTO probe VALUES ('private marker')",
    );
    await database.close();
    final bytes = prepared.file.readAsBytesSync();
    expect(
      ascii.decode(bytes, allowInvalid: true),
      isNot(contains('private marker')),
    );
    expect(
      ascii.decode(bytes.take(16).toList(), allowInvalid: true),
      isNot('SQLite format 3\u0000'),
    );
    final plain = sqlite3.open(prepared.file.path);
    try {
      expect(
        () => plain.select('SELECT * FROM probe'),
        throwsA(isA<SqliteException>()),
      );
    } finally {
      plain.close();
    }
    final reopened = await prepareEncryptedDatabase(
      directory: directory,
      keyStore: keys,
    );
    expect(reopened.key, prepared.key);
    expect(keys.writes, 1);
    database = _open(reopened);
    expect(
      (await database.customSelect('SELECT value FROM probe').getSingle()).data,
      {'value': 'private marker'},
    );
    await database.close();
  });

  test('key setup survives background Drift isolate connections', () async {
    final prepared = await prepareEncryptedDatabase(
      directory: directory,
      keyStore: keys,
    );
    AppDatabase connect() => AppDatabase(
      driftDatabase(
        name: 'providentia_encryption_background_test',
        native: DriftNativeOptions(
          shareAcrossIsolates: true,
          databasePath: () async => prepared.file.path,
          tempDirectoryPath: () async => null,
          setup: (raw) => configureEncryptedDatabase(raw, prepared.key),
        ),
      ),
    );
    final first = connect();
    try {
      await first.customStatement('CREATE TABLE background_probe (value TEXT)');
      await first.customStatement(
        "INSERT INTO background_probe VALUES ('encrypted background row')",
      );
    } finally {
      await first.close();
    }
    final second = connect();
    try {
      expect(
        (await second
                .customSelect('SELECT value FROM background_probe')
                .getSingle())
            .data,
        {'value': 'encrypted background row'},
      );
    } finally {
      await second.close();
    }
    final reopened = await prepareEncryptedDatabase(
      directory: directory,
      keyStore: keys,
    );
    final direct = _open(reopened);
    expect(
      (await direct
              .customSelect('SELECT value FROM background_probe')
              .getSingle())
          .data,
      {'value': 'encrypted background row'},
    );
    await direct.close();
  });

  test(
    'plaintext migration preserves every table, schema version and outbox envelope',
    () async {
      final expected = await _createLegacy(directory);
      final prepared = await prepareEncryptedDatabase(
        directory: directory,
        keyStore: keys,
      );
      final database = _open(prepared);
      expect(await _snapshot(database), expected);
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle()).data,
        {'user_version': 3},
      );
      await database.close();
      expect(
        File('${directory.path}/$legacyDatabaseName').existsSync(),
        isFalse,
      );
      expect(
        File('${directory.path}/$encryptedStagingName').existsSync(),
        isFalse,
      );
      for (final suffix in ['-wal', '-shm', '-journal']) {
        expect(
          File('${directory.path}/$legacyDatabaseName$suffix').existsSync(),
          isFalse,
        );
      }
    },
  );

  test('format migration precedes ordinary v1-to-v3 Drift upgrades', () async {
    await _createLegacy(directory);
    final raw = sqlite3.open('${directory.path}/$legacyDatabaseName');
    for (final column in [
      'originating_account_id',
      'enqueue_sequence',
      'safe_failure_code',
      'request_correlation_id',
      'payload_schema_version',
    ]) {
      raw.execute('ALTER TABLE client_operations DROP COLUMN $column');
    }
    for (final table in [
      'local_operation_sequences',
      'local_sync_cursors',
      'record_tombstones',
      'local_media_metadata',
      'sync_conflict_records',
    ]) {
      raw.execute('DROP TABLE $table');
    }
    raw.execute('PRAGMA user_version = 1');
    raw.close();
    final prepared = await prepareEncryptedDatabase(
      directory: directory,
      keyStore: keys,
    );
    final encrypted = sqlite3.open(prepared.file.path);
    configureEncryptedDatabase(encrypted, prepared.key);
    expect(encrypted.select('PRAGMA user_version').single.values.single, 1);
    encrypted.close();
    final database = _open(prepared);
    final operations = await database.select(database.clientOperations).get();
    expect(operations, hasLength(5));
    expect(operations.map((row) => row.operationId).toSet(), {
      'op-pending',
      'op-syncing',
      'op-retry_wait',
      'op-conflict',
      'op-acknowledged',
    });
    for (final operation in operations) {
      expect(operation.payload, '{"nested":{"value":3}}');
      expect(operation.payloadSchemaVersion, 1);
      expect(operation.originatingAccountId, isNull);
    }
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle()).data,
      {'user_version': 3},
    );
    await database.close();
  });

  test('committed rows present only in legacy WAL survive encryption', () async {
    final original = directory;
    await _createLegacy(original);
    final source = sqlite3.open('${original.path}/$legacyDatabaseName');
    late Directory recovered;
    try {
      source.execute('PRAGMA journal_mode = WAL');
      source.execute('PRAGMA wal_autocheckpoint = 0');
      source.execute(
        "UPDATE client_operations SET payload = '{\"wal_only\":true}' WHERE operation_id = 'op-pending'",
      );
      recovered = Directory('${directory.path}/recovered')..createSync();
      for (final suffix in ['', '-wal']) {
        File(
          '${original.path}/$legacyDatabaseName$suffix',
        ).copySync('${recovered.path}/$legacyDatabaseName$suffix');
      }
    } finally {
      source.close();
    }
    final prepared = await prepareEncryptedDatabase(
      directory: recovered,
      keyStore: keys,
    );
    final database = _open(prepared);
    final row = await database
        .customSelect(
          "SELECT payload FROM client_operations WHERE operation_id = 'op-pending'",
        )
        .getSingle();
    expect(row.data['payload'], '{"wal_only":true}');
    await database.close();
  });

  test(
    'missing and wrong keys preserve the encrypted bytes without reset',
    () async {
      final prepared = await prepareEncryptedDatabase(
        directory: directory,
        keyStore: keys,
      );
      final database = _open(prepared);
      await database.customSelect('SELECT * FROM client_operations').get();
      await database.close();
      final bytes = prepared.file.readAsBytesSync();
      final savedKey = keys.key;
      keys.key = null;
      await expectLater(
        prepareEncryptedDatabase(directory: directory, keyStore: keys),
        throwsA(_code('key_missing')),
      );
      expect(keys.writes, 1);
      expect(prepared.file.readAsBytesSync(), bytes);
      keys.key = '0' * 64;
      await expectLater(
        prepareEncryptedDatabase(directory: directory, keyStore: keys),
        throwsA(_code('database_unlock_failed')),
      );
      expect(keys.writes, 1);
      expect(prepared.file.readAsBytesSync(), bytes);
      keys.key = savedKey;
      await prepareEncryptedDatabase(directory: directory, keyStore: keys);
    },
  );

  test('secure-store outage never touches the legacy source', () async {
    await _createLegacy(directory);
    final legacy = File('${directory.path}/$legacyDatabaseName');
    final bytes = legacy.readAsBytesSync();
    keys.failReads = true;
    await expectLater(
      prepareEncryptedDatabase(directory: directory, keyStore: keys),
      throwsA(_code('key_store_unavailable')),
    );
    expect(legacy.readAsBytesSync(), bytes);
    expect(
      File('${directory.path}/$encryptedDatabaseName').existsSync(),
      isFalse,
    );
  });

  test(
    'an interrupted partial export is retried from verified original',
    () async {
      final expected = await _createLegacy(directory);
      File(
        '${directory.path}/$encryptedStagingName',
      ).writeAsStringSync('partial');
      final prepared = await prepareEncryptedDatabase(
        directory: directory,
        keyStore: keys,
      );
      final database = _open(prepared);
      expect(await _snapshot(database), expected);
      await database.close();
    },
  );

  test(
    'crash between publication and cleanup rechecks before deleting source',
    () async {
      final expected = await _createLegacy(directory);
      final legacy = File('${directory.path}/$legacyDatabaseName');
      final legacyBytes = legacy.readAsBytesSync();
      await prepareEncryptedDatabase(directory: directory, keyStore: keys);
      legacy.writeAsBytesSync(legacyBytes, flush: true);
      final prepared = await prepareEncryptedDatabase(
        directory: directory,
        keyStore: keys,
      );
      expect(legacy.existsSync(), isFalse);
      final database = _open(prepared);
      expect(await _snapshot(database), expected);
      await database.close();
    },
  );

  test(
    'divergent plaintext and encrypted copies fail closed preserving both',
    () async {
      await _createLegacy(directory);
      final legacy = File('${directory.path}/$legacyDatabaseName');
      final bytes = legacy.readAsBytesSync();
      final prepared = await prepareEncryptedDatabase(
        directory: directory,
        keyStore: keys,
      );
      legacy.writeAsBytesSync(bytes);
      final raw = sqlite3.open(legacy.path);
      raw.execute("UPDATE local_records SET payload = 'changed elsewhere'");
      raw.close();
      await expectLater(
        prepareEncryptedDatabase(directory: directory, keyStore: keys),
        throwsA(_code('migration_verification_failed')),
      );
      expect(legacy.existsSync(), isTrue);
      expect(prepared.file.existsSync(), isTrue);
    },
  );

  test('only-copy staging recovery never invents a missing key', () async {
    final prepared = await prepareEncryptedDatabase(
      directory: directory,
      keyStore: keys,
    );
    prepared.file.renameSync('${directory.path}/$encryptedStagingName');
    final savedKey = keys.key;
    keys.key = null;
    await expectLater(
      prepareEncryptedDatabase(directory: directory, keyStore: keys),
      throwsA(_code('key_missing')),
    );
    keys.key = savedKey;
    final recovered = await prepareEncryptedDatabase(
      directory: directory,
      keyStore: keys,
    );
    expect(recovered.file.existsSync(), isTrue);
  });

  test(
    'corrupt legacy file is kept for recovery rather than replaced',
    () async {
      final file = File('${directory.path}/$legacyDatabaseName')
        ..writeAsStringSync('corrupt source');
      await expectLater(
        prepareEncryptedDatabase(directory: directory, keyStore: keys),
        throwsA(_code('legacy_format_invalid')),
      );
      expect(file.readAsStringSync(), 'corrupt source');
    },
  );

  test('concurrent opens reuse a single verified key', () async {
    final results = await Future.wait(
      List.generate(
        4,
        (_) => prepareEncryptedDatabase(directory: directory, keyStore: keys),
      ),
    );
    expect(results.map((result) => result.key).toSet(), hasLength(1));
    expect(keys.writes, 1);
  });

  test('a non-cipher SQLite implementation cannot silently accept a key', () {
    final raw = _PlainSqlite();
    expect(
      () => configureEncryptedDatabase(raw, 'a' * 64),
      throwsA(_code('cipher_unavailable')),
    );
    expect(raw.writes, 0);
  });

  test('unsafe key input is rejected without interpolation', () {
    final raw = sqlite3.openInMemory();
    try {
      expect(
        () => configureEncryptedDatabase(raw, "'; SELECT 1; --"),
        throwsA(_code('key_invalid')),
      );
    } finally {
      raw.close();
    }
  });
}

Matcher _code(String code) => isA<LocalDatabaseSecurityException>().having(
  (error) => error.code,
  'code',
  code,
);

AppDatabase _open(PreparedEncryptedDatabase prepared) => AppDatabase(
  NativeDatabase(
    prepared.file,
    setup: (raw) => configureEncryptedDatabase(raw, prepared.key),
  ),
);

Future<Map<String, List<Map<String, Object?>>>> _createLegacy(
  Directory directory,
) async {
  final database = AppDatabase(
    NativeDatabase(File('${directory.path}/$legacyDatabaseName')),
  );
  await database.customSelect('SELECT * FROM local_records').get();
  await database.customStatement(
    "INSERT INTO local_records VALUES ('home-1', 'receipt_draft', 'draft-1', '{\"private\":\"receipt\"}', 7, 0, 10, NULL)",
  );
  for (final state in [
    'pending',
    'syncing',
    'retry_wait',
    'conflict',
    'acknowledged',
  ]) {
    await database.customStatement(
      '''
      INSERT INTO client_operations (
        originating_account_id, enqueue_sequence, safe_failure_code,
        request_correlation_id, operation_id, device_id, home_id, entity_type,
        entity_id, operation_type, base_revision, client_timestamp,
        payload_schema_version, payload, retry_count, next_attempt_at,
        last_safe_error, state, server_cursor, acknowledged_at
      ) VALUES ('account-1', 8, 'safe-code', 'correlation', ?, 'device-1',
        'home-1', 'purchase', 'purchase-1', 'create', 4, 11, 2,
        '{"nested":{"value":3}}', 2, 12, 'safe-error', ?, 'cursor-9', 13)
    ''',
      ['op-$state', state],
    );
  }
  await database.customStatement(
    'INSERT INTO local_operation_sequences VALUES (1, 9)',
  );
  await database.customStatement(
    "INSERT INTO local_sync_cursors VALUES ('home-1', 'home_changes', 2, 3, 'cursor-9', 14)",
  );
  await database.customStatement(
    "INSERT INTO record_tombstones VALUES ('home-1', 'purchase', 'deleted-1', 5, 'cursor-8', 15)",
  );
  await database.customStatement(
    "INSERT INTO local_media_metadata VALUES ('media-1', 'home-1', 'receipt', 'synthetic-reference', 'hash', 'image/png', 10, 'local_only', 16)",
  );
  await database.customStatement(
    "INSERT INTO sync_conflict_records VALUES ('conflict-1', 'op-conflict', 'home-1', 'purchase', 'purchase-1', 'revision', '{\"local\":1}', '{\"remote\":2}', 5, 17, NULL, NULL)",
  );
  final snapshot = await _snapshot(database);
  await database.close();
  return snapshot;
}

Future<Map<String, List<Map<String, Object?>>>> _snapshot(
  AppDatabase database,
) async {
  final result = <String, List<Map<String, Object?>>>{};
  for (final table in [
    'local_records',
    'client_operations',
    'local_operation_sequences',
    'local_sync_cursors',
    'record_tombstones',
    'local_media_metadata',
    'sync_conflict_records',
  ]) {
    result[table] =
        (await database
                .customSelect('SELECT * FROM $table ORDER BY rowid')
                .get())
            .map((row) => row.data)
            .toList();
  }
  return result;
}

final class _Keys implements DatabaseKeyStore {
  String? key;
  int writes = 0;
  bool failReads = false;
  @override
  Future<String?> read() async {
    if (failReads) throw StateError('secret private path');
    return key;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    key = value;
  }
}

final class _PlainSqlite implements CommonDatabase {
  int writes = 0;

  @override
  ResultSet select(String sql, [List<Object?> parameters = const []]) =>
      ResultSet(const [], null, const []);

  @override
  void execute(String sql, [List<Object?> parameters = const []]) {
    writes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
