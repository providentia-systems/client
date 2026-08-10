import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/security/device_identity_store.dart';
import 'package:providentia/core/security/origin_lock.dart';
import 'package:providentia/core/security/platform_pending_login_link_store.dart';
import 'package:providentia/core/security/platform_session_credential_store_native.dart';
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

void main() {
  test('atomic envelope ignores stale updates and remains bounded', () async {
    final storage = _MemorySecureStorage();
    final store = PlatformPendingLoginLinkStore(storage: storage);
    final first = _pending(_requestA, 'a@example.com');
    final second = _pending(_requestB, 'b@example.com');

    await store.write(first, activate: true);
    await store.write(second, activate: true);
    await store.write(first.withServerExpiry(first.expiresAt), activate: false);
    await store.clear(request: first);

    expect((await store.read())?.requestId, _requestB);
    await store.clear(request: second);
    expect(await store.read(), isNull);
    expect(
      storage.values.keys.where(
        (key) => key.startsWith('providentia.pending-login-link.'),
      ),
      <String>['providentia.pending-login-link.v3'],
    );
  });

  test('corrupt intent becomes a durable retirement tombstone', () async {
    final storage = _MemorySecureStorage()
      ..values['providentia.pending-login-link.v3'] = '{bad json';
    final store = PlatformPendingLoginLinkStore(storage: storage);

    await expectLater(
      store.read(),
      throwsA(isA<IdentityCredentialStoreException>()),
    );

    expect(await store.hasLogoutIntent(), isTrue);
    expect(await store.read(), isNull);
  });

  test('incomplete legacy head cannot fall back to an older account', () async {
    final storage = _MemorySecureStorage()
      ..values['providentia.pending-login-link.v2.head'] = _requestB
      ..values['providentia.pending-login-link.v2.$_requestA'] = jsonEncode(
        _pendingJson(_pending(_requestA, 'a@example.com')),
      );
    final store = PlatformPendingLoginLinkStore(storage: storage);

    await expectLater(
      store.read(),
      throwsA(isA<IdentityCredentialStoreException>()),
    );

    expect(await store.hasLogoutIntent(), isTrue);
    expect(await store.read(), isNull);
    expect(
      storage.values.keys.any(
        (key) => key.startsWith('providentia.pending-login-link.v2.'),
      ),
      isFalse,
    );
  });

  test('cold-origin device creation is serialized and canonical', () async {
    final storage = _MemorySecureStorage();
    final lock = _SerialOriginLock();
    final first = DeviceIdentityStore(storage: storage, originLock: lock);
    final second = DeviceIdentityStore(storage: storage, originLock: lock);

    final ids = await Future.wait<String>(<Future<String>>[
      first.getOrCreate(),
      second.getOrCreate(),
    ]);

    expect(ids[0], ids[1]);
    expect(lock.maximumConcurrent, 1);
    expect(storage.deviceWrites, 1);
    expect(
      ids.first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('native session store preserves both device identities', () async {
    final storage = _MemorySecureStorage();
    final store = PlatformSessionCredentialStore(storage: storage);
    final session = StoredNativeSession(
      sessionId: _requestA,
      deviceId: _requestB,
      installationId: _installationId,
      refreshToken: 'refresh-secret',
    );

    await store.write(session);
    final restored = await store.read();

    expect(restored?.deviceId, _requestB);
    expect(restored?.installationId, _installationId);
  });

  test('legacy native session treats its device ID as installation ID', () async {
    final storage = _MemorySecureStorage()
      ..values['providentia.native-session.v1'] = jsonEncode(<String, String>{
        'sessionId': _requestA,
        'deviceId': _requestB,
        'refreshToken': 'legacy-refresh-secret',
      });
    final restored = await PlatformSessionCredentialStore(
      storage: storage,
    ).read();

    expect(restored?.deviceId, _requestB);
    expect(restored?.installationId, _requestB);
  });

  test(
    'browser cookie mutation journal is durable and compare-and-cleared',
    () async {
      final storage = _MemorySecureStorage();
      final store = PlatformPendingLoginLinkStore(storage: storage);
      const exchange = BrowserCookieMutationJournal(
        kind: BrowserCookieMutationKind.loginLinkExchange,
        operationId: _requestA,
      );
      const refresh = BrowserCookieMutationJournal(
        kind: BrowserCookieMutationKind.sessionRefresh,
        operationId: 'refresh-session-a',
      );

      await store.beginCookieMutation(exchange);
      expect((await store.readCookieMutation())?.kind, exchange.kind);
      await store.beginCookieMutation(refresh);
      await store.clearCookieMutation(journal: exchange);
      expect(
        (await store.readCookieMutation())?.operationId,
        refresh.operationId,
      );

      await store.clearCookieMutation(journal: refresh);
      expect(await store.readCookieMutation(), isNull);
    },
  );
}

const _requestA = '0198a0b1-c2d3-7e4f-8123-456789abcde1';
const _requestB = '0198a0b1-c2d3-7e4f-8123-456789abcde2';
const _installationId = '0198a0b1-c2d3-7e4f-8123-456789abcde3';

PendingLoginLinkRequest _pending(String id, String email) =>
    PendingLoginLinkRequest(
      requestId: id,
      email: email,
      pollToken: 'poll-token-000000000000000000000000000000000',
      codeVerifier:
          'code-verifier-000000000000000000000000000000000000000000000000',
      state: 'login-state-000000000000000000000000000000000',
      createdAt: DateTime.utc(2026, 8, 9, 12),
      expiresAt: DateTime.utc(2026, 8, 9, 12, 15),
      pollInterval: const Duration(seconds: 3),
    );

Map<String, Object?> _pendingJson(PendingLoginLinkRequest request) =>
    <String, Object?>{
      'status': 'active',
      'requestId': request.requestId,
      'email': request.email,
      'pollToken': request.pollToken,
      'codeVerifier': request.codeVerifier,
      'state': request.state,
      'createdAt': request.createdAt.toIso8601String(),
      'expiresAt': request.expiresAt.toIso8601String(),
      'pollIntervalSeconds': request.pollInterval.inSeconds,
    };

final class _SerialOriginLock implements OriginLock {
  Future<void> _tail = Future<void>.value();
  int _concurrent = 0;
  int maximumConcurrent = 0;

  @override
  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    required Duration waitTimeout,
  }) {
    final result = Completer<T>();
    _tail = _tail.then<void>((_) async {
      _concurrent++;
      if (_concurrent > maximumConcurrent) maximumConcurrent = _concurrent;
      try {
        result.complete(await action());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        _concurrent--;
      }
    });
    return result.future;
  }
}

final class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};
  int deviceWrites = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key == 'providentia.device-id.v1') deviceWrites++;
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map<String, String>.of(values);
}
