import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:drift/drift.dart';
import 'package:providentia/core/database/browser_database_contract.dart';
import 'package:providentia/core/database/checkpoint_database.dart';
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

const browserVaultName = 'providentia.encrypted.v1';
const _store = 'snapshots';
const _record = 'database';
const _iterations = 600000;
const _memoryPath = '/providentia.sqlite';
const _maxSnapshotBytes = 64 * 1024 * 1024;

BrowserDatabaseVault createBrowserDatabaseVault() => WebBrowserDatabaseVault();

/// WebCrypto is supplied by the browser; no cryptography is implemented in Dart.
/// The non-extractable key exists only for the unlocked lifetime of this vault.
final class WebBrowserDatabaseVault implements BrowserDatabaseVault {
  WebBrowserDatabaseVault({
    this.databaseName = browserVaultName,
    Uri? sqlite3Uri,
  }) : sqlite3Uri = sqlite3Uri ?? Uri.parse('sqlite3.wasm');

  final String databaseName;
  final Uri sqlite3Uri;
  web.IDBDatabase? _storage;
  _Envelope? _envelope;
  web.CryptoKey? _key;
  Completer<void>? _releaseLock;
  Future<void>? _lockRequest;
  _BrowserSession? _session;
  bool _prepared = false;
  bool _unlocking = false;
  int _generation = 0;
  bool _closed = false;
  Future<BrowserDatabaseSession>? _pendingUnlock;
  Future<void>? _closing;
  Future<BrowserDatabaseState>? _preparing;

  @override
  Future<BrowserDatabaseState> prepare() {
    _requireActive(_generation);
    return _preparing ??= _prepare();
  }

  Future<BrowserDatabaseState> _prepare() async {
    final generation = _generation;
    _requireActive(generation);
    if (_prepared) {
      return _envelope == null
          ? BrowserDatabaseState.create
          : BrowserDatabaseState.unlock;
    }
    try {
      _requireFeatures();
      await _acquireLock();
      _requireActive(generation);
      // Both supported legacy backends are inspected without opening, writing,
      // deleting or migrating them. Unknown storage is a closed gate, not empty.
      await _rejectLegacyStorage();
      _requireActive(generation);
      final storage = await _openStorage();
      if (_closed || generation != _generation) {
        storage.close();
        _requireActive(generation);
      }
      _storage = storage;
      final saved = await _readSnapshot();
      _requireActive(generation);
      _envelope = saved == null ? null : _Envelope.parse(saved);
      _prepared = true;
      return _envelope == null
          ? BrowserDatabaseState.create
          : BrowserDatabaseState.unlock;
    } on BrowserDatabaseProtectionException {
      await close();
      rethrow;
    } on Object {
      await close();
      throw const BrowserDatabaseProtectionException('storage_unavailable');
    }
  }

  void _requireActive(int generation) {
    if (_closed || generation != _generation) {
      throw const BrowserDatabaseProtectionException('database_locked');
    }
  }

  void _requireFeatures() {
    if (!web.window.isSecureContext ||
        !web.window.hasProperty('crypto'.toJS).toDart ||
        !web.window.crypto.hasProperty('subtle'.toJS).toDart ||
        !web.window.navigator.hasProperty('locks'.toJS).toDart ||
        !web.window.navigator.hasProperty('storage'.toJS).toDart ||
        !web.window.hasProperty('indexedDB'.toJS).toDart ||
        !web.window.indexedDB.hasProperty('databases'.toJS).toDart ||
        !web.window.navigator.storage.hasProperty('getDirectory'.toJS).toDart) {
      throw const BrowserDatabaseProtectionException('unsupported_browser');
    }
  }

  Future<void> _acquireLock() async {
    final granted = Completer<void>();
    final released = Completer<void>();
    _releaseLock = released;
    _lockRequest = web.window.navigator.locks
        .request(
          '$databaseName.exclusive',
          web.LockOptions(mode: 'exclusive', ifAvailable: true),
          ((web.Lock? lock) {
            if (lock == null) {
              granted.completeError(
                const BrowserDatabaseProtectionException('database_busy'),
              );
              return Future<JSAny?>.value(null).toJS;
            }
            granted.complete();
            return released.future.then<JSAny?>((_) => null).toJS;
          }).toJS,
        )
        .toDart
        .then<void>(
          (_) {},
          onError: (Object _) {
            if (!granted.isCompleted) {
              granted.completeError(
                const BrowserDatabaseProtectionException('unsupported_browser'),
              );
            }
          },
        );
    await granted.future;
  }

  Future<void> _rejectLegacyStorage() async {
    final databases = await web.window.indexedDB.databases().toDart;
    if (databases.toDart.any((database) => database.name == 'providentia')) {
      throw const BrowserDatabaseProtectionException('legacy_data_detected');
    }
    final root = await web.window.navigator.storage.getDirectory().toDart;
    try {
      final driftRoot = await root.getDirectoryHandle('drift_db').toDart;
      await driftRoot.getDirectoryHandle('providentia').toDart;
      throw const BrowserDatabaseProtectionException('legacy_data_detected');
    } on BrowserDatabaseProtectionException {
      rethrow;
    } on Object catch (error) {
      // Only a verified NotFoundError means there was no old database. Security,
      // permission and storage errors must not be interpreted as missing data.
      if (!error.isA<web.DOMException>() ||
          (error as web.DOMException).name != 'NotFoundError') {
        throw const BrowserDatabaseProtectionException('legacy_check_failed');
      }
    }
  }

  Future<web.IDBDatabase> _openStorage() {
    final result = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(databaseName, 1);
    request.onupgradeneeded = ((web.IDBVersionChangeEvent event) {
      final database = request.result as web.IDBDatabase;
      if (event.oldVersion != 0) {
        request.transaction!.abort();
      } else {
        database.createObjectStore(_store);
      }
    }).toJS;
    request.onsuccess = ((web.Event _) {
      final database = request.result as web.IDBDatabase;
      if (result.isCompleted) {
        database.close();
      } else if (!database.objectStoreNames.contains(_store)) {
        database.close();
        result.completeError(
          const BrowserDatabaseProtectionException('storage_format_invalid'),
        );
      } else {
        result.complete(database);
      }
    }).toJS;
    void fail(web.Event _) {
      if (!result.isCompleted) {
        result.completeError(
          const BrowserDatabaseProtectionException('storage_unavailable'),
        );
      }
    }

    request.onerror = fail.toJS;
    request.onblocked = fail.toJS;
    return result.future;
  }

  Future<String?> _readSnapshot() async {
    final transaction = _storage!.transaction(_store.toJS, 'readonly');
    final completed = _completeTransaction(transaction);
    final request = transaction.objectStore(_store).get(_record.toJS);
    String? value;
    request.onsuccess = ((web.Event _) {
      final result = request.result;
      if (result != null && !result.isUndefined) {
        if (!result.isA<JSString>()) {
          transaction.abort();
        } else {
          value = (result as JSString).toDart;
        }
      }
    }).toJS;
    await completed;
    return value;
  }

  Future<void> _writeSnapshot(String serialized) async {
    final transaction = _storage!.transaction(
      _store.toJS,
      'readwrite',
      web.IDBTransactionOptions(durability: 'strict'),
    );
    final completed = _completeTransaction(transaction);
    if (transaction.durability != 'strict') {
      transaction.abort();
      try {
        await completed;
      } on Object {
        // The unsupported transaction was deliberately aborted.
      }
      throw const BrowserDatabaseProtectionException('unsupported_browser');
    }
    transaction.objectStore(_store).put(serialized.toJS, _record.toJS);
    await completed;
  }

  Future<void> _completeTransaction(web.IDBTransaction transaction) {
    final completed = Completer<void>();
    transaction.oncomplete = ((web.Event _) => completed.complete()).toJS;
    void fail(web.Event _) {
      if (!completed.isCompleted) {
        completed.completeError(
          const BrowserDatabaseProtectionException('storage_write_failed'),
        );
      }
    }

    transaction.onabort = fail.toJS;
    transaction.onerror = fail.toJS;
    return completed.future;
  }

  @override
  Future<BrowserDatabaseSession> unlock(String passphrase) async {
    _requireActive(_generation);
    if (_unlocking) {
      throw const BrowserDatabaseProtectionException('unlock_unavailable');
    }
    final pending = _unlock(passphrase, _generation);
    _pendingUnlock = pending;
    try {
      return await pending;
    } finally {
      if (identical(_pendingUnlock, pending)) _pendingUnlock = null;
    }
  }

  Future<BrowserDatabaseSession> _unlock(
    String passphrase,
    int generation,
  ) async {
    if (!_prepared || _unlocking || _session != null) {
      throw const BrowserDatabaseProtectionException('unlock_unavailable');
    }
    if (_envelope == null && passphrase.runes.length < 16) {
      throw const BrowserDatabaseProtectionException('passphrase_too_short');
    }
    _unlocking = true;
    InMemoryFileSystem? memory;
    CommonDatabase? database;
    Uint8List? cleartext;
    try {
      final envelope = _envelope;
      final salt = envelope?.salt ?? _random(16);
      final key = await _deriveKey(passphrase, salt);
      _requireActive(generation);
      _key = key;
      if (envelope != null) {
        try {
          cleartext =
              (await web.window.crypto.subtle
                          .decrypt(
                            envelope.parameters,
                            _key!,
                            envelope.ciphertext.toJS,
                          )
                          .toDart
                      as JSArrayBuffer)
                  .toDart
                  .asUint8List();
        } on Object {
          throw const BrowserDatabaseProtectionException('unlock_failed');
        }
      }
      _requireActive(generation);
      final sqlite3 = await WasmSqlite3.loadFromUrl(sqlite3Uri);
      _requireActive(generation);
      memory = InMemoryFileSystem();
      sqlite3.registerVirtualFileSystem(memory, makeDefault: true);
      if (cleartext != null) {
        final file = memory
            .xOpen(
              Sqlite3Filename(_memoryPath),
              SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE,
            )
            .file;
        file.xWrite(cleartext, 0);
        file.xClose();
      }
      database = sqlite3.open(_memoryPath);
      database.execute('PRAGMA journal_mode = DELETE');
      database.execute('PRAGMA temp_store = MEMORY');
      database.execute('PRAGMA user_version = ${database.userVersion}');
      final check = database.select('PRAGMA integrity_check');
      if (check.length != 1 || check.single.values.single != 'ok') {
        throw const BrowserDatabaseProtectionException('database_corrupt');
      }
      final ownedMemory = memory;
      final executor = CheckpointDatabase(
        database: database,
        checkpoint: () async {
          final bytes = Uint8List.fromList(ownedMemory.fileData[_memoryPath]!);
          if (bytes.length > _maxSnapshotBytes) {
            bytes.fillRange(0, bytes.length, 0);
            throw const BrowserDatabaseProtectionException(
              'database_too_large',
            );
          }
          try {
            final next = await _Envelope.encrypt(bytes, salt, _key!);
            await _writeSnapshot(next.serialize());
            _envelope = next;
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        },
        dispose: () async {
          _wipe(ownedMemory);
          sqlite3.unregisterVirtualFileSystem(ownedMemory);
          _key = null;
          await _release();
        },
      );
      _session = _BrowserSession(executor);
      return _session!;
    } on BrowserDatabaseProtectionException {
      database?.close();
      if (memory != null) _wipe(memory);
      _key = null;
      rethrow;
    } on Object {
      database?.close();
      if (memory != null) _wipe(memory);
      _key = null;
      throw const BrowserDatabaseProtectionException('database_open_failed');
    } finally {
      cleartext?.fillRange(0, cleartext.length, 0);
      _unlocking = false;
    }
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _generation++;
    // Key derivation/decryption/loading must finish or observe cancellation
    // before the exclusive browser lock or its storage handle is released.
    try {
      await _pendingUnlock;
    } on Object {
      // Cancellation/failure preserves the last durable ciphertext.
    }
    final session = _session;
    _session = null;
    if (session != null) await session.close();
    _key = null;
    await _release();
  }

  Future<void> _release() async {
    _prepared = false;
    _storage?.close();
    _storage = null;
    final release = _releaseLock;
    _releaseLock = null;
    if (release != null && !release.isCompleted) release.complete();
    await _lockRequest;
    _lockRequest = null;
  }
}

void _wipe(InMemoryFileSystem memory) {
  for (final bytes in memory.fileData.values) {
    bytes?.fillRange(0, bytes.length, 0);
  }
  memory.fileData.clear();
}

Uint8List _random(int length) {
  final bytes = Uint8List(length).toJS;
  web.window.crypto.getRandomValues(bytes);
  // Read the JS view explicitly: dart2wasm may copy a Dart typed list to JS.
  return Uint8List.fromList(bytes.toDart);
}

Future<web.CryptoKey> _deriveKey(String passphrase, Uint8List salt) async {
  final bytes = Uint8List.fromList(utf8.encode(passphrase));
  try {
    final material = await web.window.crypto.subtle
        .importKey(
          'raw',
          bytes.toJS,
          'PBKDF2'.toJS,
          false,
          ['deriveKey'.toJS].toJS,
        )
        .toDart;
    return await web.window.crypto.subtle
            .deriveKey(
              {
                'name': 'PBKDF2',
                'salt': salt,
                'iterations': _iterations,
                'hash': 'SHA-256',
              }.jsify()!,
              material,
              {'name': 'AES-GCM', 'length': 256}.jsify()!,
              false,
              ['encrypt'.toJS, 'decrypt'.toJS].toJS,
            )
            .toDart
        as web.CryptoKey;
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}

final class _BrowserSession implements BrowserDatabaseSession {
  _BrowserSession(this.executor);
  @override
  final QueryExecutor executor;
  @override
  Future<void> close() => executor.close();
}

final class _Envelope {
  const _Envelope(this.salt, this.iv, this.ciphertext);
  final Uint8List salt;
  final Uint8List iv;
  final Uint8List ciphertext;

  static _Envelope parse(String serialized) {
    try {
      if (serialized.length > ((_maxSnapshotBytes + 16) * 4 ~/ 3) + 4096) {
        throw const FormatException();
      }
      final value = jsonDecode(serialized) as Map<String, dynamic>;
      if (value['version'] != 1 ||
          value['kdf'] != 'PBKDF2-SHA256' ||
          value['iterations'] != _iterations ||
          value['cipher'] != 'AES-256-GCM') {
        throw const FormatException();
      }
      final envelope = _Envelope(
        base64Decode(value['salt'] as String),
        base64Decode(value['iv'] as String),
        base64Decode(value['ciphertext'] as String),
      );
      if (envelope.salt.length != 16 ||
          envelope.iv.length != 12 ||
          envelope.ciphertext.length < 16 ||
          envelope.ciphertext.length > _maxSnapshotBytes + 16) {
        throw const FormatException();
      }
      return envelope;
    } on Object {
      throw const BrowserDatabaseProtectionException('storage_format_invalid');
    }
  }

  JSObject get parameters =>
      {
            'name': 'AES-GCM',
            'iv': iv,
            'tagLength': 128,
            'additionalData': Uint8List.fromList(
              utf8.encode(
                'providentia.encrypted.v1|PBKDF2-SHA256|$_iterations|AES-256-GCM|${base64Encode(salt)}',
              ),
            ),
          }.jsify()!
          as JSObject;

  static Future<_Envelope> encrypt(
    Uint8List bytes,
    Uint8List salt,
    web.CryptoKey key,
  ) async {
    final envelope = _Envelope(salt, _random(12), Uint8List(0));
    final encrypted =
        await web.window.crypto.subtle
                .encrypt(envelope.parameters, key, bytes.toJS)
                .toDart
            as JSArrayBuffer;
    return _Envelope(salt, envelope.iv, encrypted.toDart.asUint8List());
  }

  String serialize() => jsonEncode({
    'version': 1,
    'kdf': 'PBKDF2-SHA256',
    'iterations': _iterations,
    'cipher': 'AES-256-GCM',
    'salt': base64Encode(salt),
    'iv': base64Encode(iv),
    'ciphertext': base64Encode(ciphertext),
  });
}
