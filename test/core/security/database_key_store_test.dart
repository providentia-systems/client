import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/security/database_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'generates 256 random bits and verifies secure-store persistence',
    () async {
      final store = _Keys();
      final key = await loadDatabaseKey(
        store,
        existingEncryptedDatabase: false,
      );
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(store.key, key);
      expect(store.writes, 1);
      expect(
        await loadDatabaseKey(store, existingEncryptedDatabase: true),
        key,
      );
      expect(store.writes, 1);
      final other = await loadDatabaseKey(
        _Keys(),
        existingEncryptedDatabase: false,
      );
      expect(other, isNot(key));
    },
  );

  test(
    'never generates a replacement for missing existing encryption key',
    () async {
      final store = _Keys();
      await expectLater(
        loadDatabaseKey(store, existingEncryptedDatabase: true),
        throwsA(_code('key_missing')),
      );
      expect(store.writes, 0);
    },
  );

  test('malformed stored key is preserved and rejected', () async {
    final store = _Keys()..key = 'malformed';
    await expectLater(
      loadDatabaseKey(store, existingEncryptedDatabase: false),
      throwsA(_code('key_invalid')),
    );
    expect(store.key, 'malformed');
    expect(store.writes, 0);
  });

  test('failed readback never permits database creation', () async {
    await expectLater(
      loadDatabaseKey(
        _Keys()..ignoreWrites = true,
        existingEncryptedDatabase: false,
      ),
      throwsA(_code('key_not_persisted')),
    );
  });

  test(
    'platform failures do not expose secret/path exception details',
    () async {
      await expectLater(
        loadDatabaseKey(
          _Keys()..failReads = true,
          existingEncryptedDatabase: false,
        ),
        throwsA(_code('key_store_unavailable')),
      );
      expect(
        const LocalDatabaseSecurityException('key_missing').toString(),
        'Local database protection is unavailable (key_missing).',
      );
    },
  );

  test(
    'secure-store adapter roundtrips only its dedicated database key',
    () async {
      FlutterSecureStorage.setMockInitialValues({'session': 'unrelated'});
      final store = SecureDatabaseKeyStore();
      expect(await store.read(), isNull);
      final key = 'a' * 64;
      await store.write(key);
      expect(await store.read(), key);
      expect(
        await const FlutterSecureStorage().read(key: 'session'),
        'unrelated',
      );
    },
  );
}

Matcher _code(String code) => isA<LocalDatabaseSecurityException>().having(
  (error) => error.code,
  'code',
  code,
);

final class _Keys implements DatabaseKeyStore {
  String? key;
  int writes = 0;
  bool ignoreWrites = false;
  bool failReads = false;

  @override
  Future<String?> read() async {
    if (failReads) {
      throw StateError('private secret /private/path');
    }
    return key;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    if (!ignoreWrites) {
      key = value;
    }
  }
}
