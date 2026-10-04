// Run with tool/browser_security/run_probe.sh. Synthetic, isolated origin only.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/browser_database_contract.dart';
import 'package:providentia/core/database/browser_database_web.dart';
import 'package:web/web.dart' as web;

const _name = 'providentia.browser-security-test';
const _secret = 'synthetic long browser passphrase';

Future<void> main() async {
  final results = <String>[];
  try {
    final mode = Uri.base.queryParameters['mode'];
    if (mode == 'busy') {
      final competitor = WebBrowserDatabaseVault(databaseName: _name);
      await code(competitor.prepare, 'database_busy');
      report({
        'ok': true,
        'results': ['a separate tab cannot acquire the open vault'],
      });
      return;
    }
    late WebBrowserDatabaseVault vault;
    late BrowserDatabaseSession session;
    late AppDatabase database;
    if (mode != 'reopen') {
      final preparing = WebBrowserDatabaseVault(
        databaseName: '$_name.cancel-prepare',
      );
      final preparation = code(preparing.prepare, 'database_locked');
      await preparing.close();
      await preparation;
      final cancelling = WebBrowserDatabaseVault(
        databaseName: '$_name.cancel-unlock',
      );
      await cancelling.prepare();
      final unlocking = code(
        () => cancelling.unlock(_secret),
        'database_locked',
      );
      await cancelling.close();
      await unlocking;
      final afterCancel = WebBrowserDatabaseVault(
        databaseName: '$_name.cancel-unlock',
      );
      check(
        await afterCancel.prepare() == BrowserDatabaseState.create,
        'cancelled unlock leaves no new checkpoint',
      );
      await afterCancel.close();
      results.add(
        'close cancels pending prepare/unlock before releasing ownership',
      );
      vault = WebBrowserDatabaseVault(databaseName: _name);
      final prepared = vault.prepare();
      check(
        identical(prepared, vault.prepare()),
        'concurrent prepare shares one lock',
      );
      check(await prepared == BrowserDatabaseState.create, 'new vault');
      final competitor = WebBrowserDatabaseVault(databaseName: _name);
      await code(competitor.prepare, 'database_busy');
      results.add('exclusive lock rejects a second connection');
      session = await vault.unlock(_secret);
      database = AppDatabase(session.executor);
      await database.customStatement(
        'CREATE TABLE proof (id INTEGER PRIMARY KEY, value TEXT)',
      );
      await database.transaction(() async {
        await database
            .into(database.localRecords)
            .insert(
              LocalRecordsCompanion.insert(
                homeId: 'synthetic-home',
                entityType: 'item',
                entityId: 'synthetic-item',
                payload: '{"marker":"synthetic private projection"}',
                updatedAt: DateTime.utc(2026),
              ),
            );
        await database
            .into(database.clientOperations)
            .insert(
              ClientOperationsCompanion.insert(
                operationId: 'synthetic-operation',
                deviceId: 'synthetic-device',
                homeId: 'synthetic-home',
                entityType: 'item',
                entityId: 'synthetic-item',
                operationType: 'create',
                clientTimestamp: DateTime.utc(2026),
                payload: '{"marker":"synthetic private outbox"}',
                state: 'pending',
              ),
            );
        await database.customStatement(
          "INSERT INTO proof VALUES (1, 'synthetic secret outbox marker')",
        );
        await database.customStatement(
          "INSERT INTO proof VALUES (2, 'projection')",
        );
        await database.transaction(() async {
          await database.customStatement(
            "INSERT INTO proof VALUES (3, 'nested savepoint')",
          );
        });
      });
      final stored = await readRecord();
      check(
        !stored.contains('synthetic secret') &&
            !stored.contains('SQLite format'),
        'ciphertext only',
      );
      check(!stored.contains(_secret), 'no persisted passphrase');
      final first = jsonDecode(stored) as Map<String, dynamic>;
      await database.customStatement(
        "UPDATE proof SET value='committed' WHERE id=2",
      );
      final second = jsonDecode(await readRecord()) as Map<String, dynamic>;
      check(first['iv'] != second['iv'], 'fresh IV');
      results.add(
        'AES-GCM ciphertext-only persistence and fresh random IV per checkpoint',
      );
      try {
        await database.transaction(() async {
          await database.customStatement(
            "INSERT INTO proof VALUES (4, 'must roll back')",
          );
          throw StateError('synthetic rollback');
        });
      } on StateError {
        /* expected */
      }
      if (mode == 'seed') {
        // Keep the vault open. The runner opens a competing tab, then destroys
        // this entire document before another page must unlock the ciphertext.
        report({'ok': true, 'results': results});
        return;
      }
      await database.close();
      await session.close();
      await vault.close();
    }
    vault = WebBrowserDatabaseVault(databaseName: _name);
    check(
      await vault.prepare() == BrowserDatabaseState.unlock,
      'cold reopen requires unlock',
    );
    final beforeWrong = await readRecord();
    await code(
      () => vault.unlock('incorrect local passphrase'),
      'unlock_failed',
    );
    check(
      await readRecord() == beforeWrong,
      'wrong passphrase preserves ciphertext',
    );
    session = await vault.unlock(_secret);
    database = AppDatabase(session.executor);
    final rows = await database
        .customSelect('SELECT * FROM proof ORDER BY id')
        .get();
    check(
      rows.length == 3 && rows[1].data['value'] == 'committed',
      'cold reopen exact transaction contents',
    );
    check(
      (await database.select(database.localRecords).get()).single.entityId ==
          'synthetic-item',
      'projection preserved',
    );
    check(
      (await database.select(database.clientOperations).get())
              .single
              .operationId ==
          'synthetic-operation',
      'outbox preserved',
    );
    results.add(
      'wrong passphrase fails without reset; cold reopen retains complete nested transaction and rollback',
    );
    await database.close();
    await vault.close();
    // A valid-shaped but modified GCM tag is refused, never overwritten.
    final corrupt = jsonDecode(await readRecord()) as Map<String, dynamic>;
    final bytes = base64Decode(corrupt['ciphertext'] as String);
    bytes[bytes.length - 1] ^= 1;
    corrupt['ciphertext'] = base64Encode(bytes);
    await writeRecord(jsonEncode(corrupt));
    vault = WebBrowserDatabaseVault(databaseName: _name);
    await vault.prepare();
    await code(() => vault.unlock(_secret), 'unlock_failed');
    check(
      await readRecord() == jsonEncode(corrupt),
      'corrupt ciphertext preserved',
    );
    await vault.close();
    results.add(
      'authentication-tag tampering fails closed and preserves recovery data',
    );
    // Detect and preserve legacy IDB storage, including an otherwise empty DB.
    final legacy = await openDb('providentia');
    legacy.close();
    vault = WebBrowserDatabaseVault(databaseName: _name);
    await code(vault.prepare, 'legacy_data_detected');
    check(
      (await web.window.indexedDB.databases().toDart).toDart.any(
        (db) => db.name == 'providentia',
      ),
      'legacy preserved',
    );
    results.add('legacy IndexedDB refuses upgrade without deleting data');
    await deleteDb('providentia');
    final root = await web.window.navigator.storage.getDirectory().toDart;
    final drift = await root
        .getDirectoryHandle(
          'drift_db',
          web.FileSystemGetDirectoryOptions(create: true),
        )
        .toDart;
    await drift
        .getDirectoryHandle(
          'providentia',
          web.FileSystemGetDirectoryOptions(create: true),
        )
        .toDart;
    vault = WebBrowserDatabaseVault(databaseName: _name);
    await code(vault.prepare, 'legacy_data_detected');
    await drift.getDirectoryHandle('providentia').toDart;
    results.add('legacy OPFS refuses upgrade without deleting data');
    report({'ok': true, 'results': results});
  } on Object catch (error, stack) {
    report({
      'ok': false,
      'error': '$error',
      'stack': '$stack',
      'results': results,
    });
  }
}

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

Future<void> code(Future<Object?> Function() action, String expected) async {
  try {
    await action();
  } on BrowserDatabaseProtectionException catch (error) {
    check(error.code == expected, 'expected $expected, got ${error.code}');
    return;
  }
  throw StateError('Expected protection failure $expected');
}

Future<web.IDBDatabase> openDb(String name) {
  final result = Completer<web.IDBDatabase>();
  final request = web.window.indexedDB.open(name);
  request.onsuccess = ((web.Event _) => result.complete(
    request.result as web.IDBDatabase,
  )).toJS;
  request.onerror = ((web.Event _) => result.completeError(
    StateError('fixture IDB open'),
  )).toJS;
  return result.future;
}

Future<void> deleteDb(String name) {
  final result = Completer<void>();
  final request = web.window.indexedDB.deleteDatabase(name);
  request.onsuccess = ((web.Event _) => result.complete()).toJS;
  request.onerror = ((web.Event _) => result.completeError(
    StateError('fixture IDB delete'),
  )).toJS;
  return result.future;
}

Future<String> readRecord() async {
  final db = await openDb(_name);
  try {
    final result = Completer<String>();
    final request = db
        .transaction('snapshots'.toJS, 'readonly')
        .objectStore('snapshots')
        .get('database'.toJS);
    request.onsuccess = ((web.Event _) => result.complete(
      (request.result as JSString).toDart,
    )).toJS;
    return await result.future;
  } finally {
    db.close();
  }
}

Future<void> writeRecord(String record) async {
  final db = await openDb(_name);
  try {
    final result = Completer<void>();
    final tx = db.transaction('snapshots'.toJS, 'readwrite');
    tx.oncomplete = ((web.Event _) => result.complete()).toJS;
    tx.onabort = ((web.Event _) => result.completeError(
      StateError('fixture IDB write'),
    )).toJS;
    tx.objectStore('snapshots').put(record.toJS, 'database'.toJS);
    await result.future;
  } finally {
    db.close();
  }
}

void report(Map<String, Object> result) {
  final value = jsonEncode(result);
  web.window.setProperty('probeResult'.toJS, value.toJS);
  web.document.body!.textContent = value;
}
