import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/application/identity_session_manager.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 12);

  test(
    'native restore rotates and securely replaces the refresh token',
    () async {
      final store = _MemoryCredentialStore(
        stored: StoredNativeSession(
          sessionId: 'old-session',
          deviceId: 'device-1',
          refreshToken: 'old-refresh-token',
        ),
      );
      final transport = _FakeIdentityTransport(
        sessionTransport: ClientSessionTransport.nativeBearer,
        grant: _nativeGrant(now, refreshToken: 'rotated-refresh-token'),
      );
      final manager = _manager(transport, store, now);
      addTearDown(manager.dispose);

      await manager.restore();

      expect(transport.refreshTokens, <String?>['old-refresh-token']);
      expect(manager.snapshot.status, IdentitySessionStatus.authenticated);
      expect(manager.accessToken, 'access-token');
      expect(store.stored?.refreshToken, 'rotated-refresh-token');
      expect(store.writes, 1);
    },
  );

  test(
    'refresh is single-flight for concurrent authenticated requests',
    () async {
      final completion = Completer<SessionGrant>();
      final store = _MemoryCredentialStore(
        stored: StoredNativeSession(
          sessionId: 'session-1',
          deviceId: 'device-1',
          refreshToken: 'refresh-token',
        ),
      );
      final transport = _FakeIdentityTransport(
        sessionTransport: ClientSessionTransport.nativeBearer,
        refreshCompletion: completion,
      );
      final manager = _manager(transport, store, now);
      addTearDown(manager.dispose);

      final first = manager.restore();
      final second = manager.tryRecover();
      final third = manager.tryRecover();
      await Future<void>.delayed(Duration.zero);

      expect(transport.refreshCalls, 1);
      completion.complete(_nativeGrant(now));
      await Future.wait<void>(<Future<void>>[
        first,
        second.then((_) {}),
        third.then((_) {}),
      ]);
      expect(transport.refreshCalls, 1);
    },
  );

  test(
    'web restore uses cookies and never reads or writes native secrets',
    () async {
      final store = _MemoryCredentialStore(supportsPersistentSecrets: false);
      final transport = _FakeIdentityTransport(
        sessionTransport: ClientSessionTransport.webCookie,
        grant: _webGrant(now),
      );
      final manager = _manager(transport, store, now);
      addTearDown(manager.dispose);

      await manager.restore();

      expect(transport.refreshTokens, <String?>[null]);
      expect(store.reads, 0);
      expect(store.writes, 0);
      expect(manager.accessToken, isNull);
      expect(manager.csrfToken, 'csrf-token');
      expect(manager.snapshot.status, IdentitySessionStatus.authenticated);
    },
  );

  test(
    'authentication failure clears native credentials and expires session',
    () async {
      final store = _MemoryCredentialStore(
        stored: StoredNativeSession(
          sessionId: 'session-1',
          deviceId: 'device-1',
          refreshToken: 'replayed-refresh-token',
        ),
      );
      final transport = _FakeIdentityTransport(
        sessionTransport: ClientSessionTransport.nativeBearer,
        refreshError: const IdentityTransportException(
          kind: IdentityFailureKind.authentication,
          safeMessage: 'Sign in again to continue.',
        ),
      );
      final manager = _manager(transport, store, now);
      addTearDown(manager.dispose);

      await manager.restore();

      expect(manager.snapshot.status, IdentitySessionStatus.expired);
      expect(manager.snapshot.safeMessage, 'Sign in again to continue.');
      expect(store.stored, isNull);
      expect(manager.accessToken, isNull);
    },
  );

  test(
    'challenge completion accepts a one-time code without storing it',
    () async {
      final store = _MemoryCredentialStore();
      final transport = _FakeIdentityTransport(
        sessionTransport: ClientSessionTransport.nativeBearer,
        grant: _nativeGrant(now),
      );
      final manager = _manager(transport, store, now);
      addTearDown(manager.dispose);

      final receipt = await manager.requestChallenge('Person@Example.com');
      await manager.completeChallenge(
        PasswordlessProof.oneTimeCode(
          email: receipt.email,
          code: '739204',
          challengeId: receipt.challengeId,
        ),
      );

      expect(transport.challengeEmails, <String>['person@example.com']);
      expect(transport.lastProof?.kind, PasswordlessProofKind.oneTimeCode);
      expect(manager.snapshot.status, IdentitySessionStatus.authenticated);
      expect(store.stored?.refreshToken, 'refresh-token');
    },
  );

  test(
    'logout clears local credentials when remote logout is unavailable',
    () async {
      final store = _MemoryCredentialStore();
      final transport = _FakeIdentityTransport(
        sessionTransport: ClientSessionTransport.nativeBearer,
        grant: _nativeGrant(now),
        logoutError: const IdentityTransportException(
          kind: IdentityFailureKind.network,
          safeMessage: 'No connection.',
        ),
      );
      final manager = _manager(transport, store, now);
      addTearDown(manager.dispose);
      await manager.completeChallenge(
        PasswordlessProof.magicLink(token: 'private-magic-link-token'),
      );

      await manager.logout();

      expect(manager.snapshot.status, IdentitySessionStatus.signedOut);
      expect(manager.accessToken, isNull);
      expect(store.stored, isNull);
    },
  );

  test(
    'logout closes the local session before remote logout completes',
    () async {
      final logoutCompletion = Completer<void>();
      final store = _MemoryCredentialStore();
      final transport = _FakeIdentityTransport(
        sessionTransport: ClientSessionTransport.nativeBearer,
        grant: _nativeGrant(now),
        logoutCompletion: logoutCompletion,
      );
      final manager = _manager(transport, store, now);
      addTearDown(manager.dispose);
      await manager.completeChallenge(
        PasswordlessProof.magicLink(token: 'private-magic-link-token'),
      );

      final logout = manager.logout();

      expect(manager.snapshot.status, IdentitySessionStatus.signedOut);
      expect(manager.accessToken, isNull);
      expect(store.stored, isNull);
      expect(transport.logoutAccessTokens, <String?>['access-token']);

      logoutCompletion.complete();
      await logout;
    },
  );

  test('logout fences and revokes a delayed refresh grant', () async {
    final refreshCompletion = Completer<SessionGrant>();
    final store = _MemoryCredentialStore();
    final transport = _FakeIdentityTransport(
      sessionTransport: ClientSessionTransport.nativeBearer,
      grant: _nativeGrant(now),
      refreshCompletion: refreshCompletion,
    );
    final manager = _manager(transport, store, now);
    addTearDown(manager.dispose);
    await manager.completeChallenge(
      PasswordlessProof.magicLink(token: 'private-magic-link-token'),
    );

    final refresh = manager.tryRecover();
    await Future<void>.delayed(Duration.zero);
    expect(transport.refreshCalls, 1);

    await manager.logout();
    refreshCompletion.complete(
      _nativeGrant(now, refreshToken: 'late-refresh-token'),
    );

    expect(await refresh, isFalse);
    expect(manager.snapshot.status, IdentitySessionStatus.signedOut);
    expect(manager.accessToken, isNull);
    expect(store.stored, isNull);
    expect(store.writes, 1);
    expect(transport.logoutAccessTokens, <String?>[
      'access-token',
      'access-token',
    ]);
  });

  test('OpenAPI 1.7 password compatibility accepts a secure grant', () async {
    final store = _MemoryCredentialStore();
    final transport = _FakeIdentityTransport(
      sessionTransport: ClientSessionTransport.nativeBearer,
      grant: _nativeGrant(now),
    );
    final manager = _manager(transport, store, now);
    addTearDown(manager.dispose);

    await manager.signInWithPassword(
      email: 'Person@Example.com',
      password: 'not-logged-or-persisted',
    );

    expect(transport.passwordEmails, <String>['person@example.com']);
    expect(manager.snapshot.status, IdentitySessionStatus.authenticated);
    expect(store.stored?.refreshToken, 'refresh-token');
  });
}

IdentitySessionManager _manager(
  _FakeIdentityTransport transport,
  _MemoryCredentialStore store,
  DateTime now,
) {
  return IdentitySessionManager(
    transport: transport,
    credentialStore: store,
    device: DeviceDescriptor(
      id: 'device-1',
      name: 'Test device',
      platform: 'test',
    ),
    clock: () => now,
  );
}

SessionGrant _nativeGrant(
  DateTime now, {
  String refreshToken = 'refresh-token',
}) {
  return SessionGrant(
    metadata: SessionMetadata(
      sessionId: 'session-1',
      deviceId: 'device-1',
      accessExpiresAt: now.add(const Duration(minutes: 15)),
      transport: ClientSessionTransport.nativeBearer,
    ),
    secrets: SessionSecrets(
      accessToken: 'access-token',
      refreshToken: refreshToken,
    ),
  );
}

SessionGrant _webGrant(DateTime now) {
  return SessionGrant(
    metadata: SessionMetadata(
      sessionId: 'session-web',
      deviceId: 'browser-1',
      accessExpiresAt: now.add(const Duration(minutes: 15)),
      transport: ClientSessionTransport.webCookie,
    ),
    secrets: const SessionSecrets(csrfToken: 'csrf-token'),
  );
}

final class _MemoryCredentialStore implements SessionCredentialStore {
  _MemoryCredentialStore({this.stored, this.supportsPersistentSecrets = true});

  StoredNativeSession? stored;
  int reads = 0;
  int writes = 0;
  int clears = 0;

  @override
  final bool supportsPersistentSecrets;

  @override
  Future<void> clear() async {
    clears++;
    stored = null;
  }

  @override
  Future<StoredNativeSession?> read() async {
    reads++;
    return stored;
  }

  @override
  Future<void> write(StoredNativeSession session) async {
    writes++;
    stored = session;
  }
}

final class _FakeIdentityTransport
    implements IdentityTransportPort, LegacyPasswordIdentityTransportPort {
  _FakeIdentityTransport({
    required this.sessionTransport,
    this.grant,
    this.refreshCompletion,
    this.refreshError,
    this.logoutError,
    this.logoutCompletion,
  });

  @override
  final ClientSessionTransport sessionTransport;
  final SessionGrant? grant;
  final Completer<SessionGrant>? refreshCompletion;
  final IdentityTransportException? refreshError;
  final IdentityTransportException? logoutError;
  final Completer<void>? logoutCompletion;

  int refreshCalls = 0;
  final List<String?> refreshTokens = <String?>[];
  final List<String> challengeEmails = <String>[];
  final List<String> passwordEmails = <String>[];
  final List<String?> logoutAccessTokens = <String?>[];
  PasswordlessProof? lastProof;

  @override
  Future<SessionGrant> completePasswordlessChallenge({
    required PasswordlessProof proof,
    required DeviceDescriptor device,
  }) async {
    lastProof = proof;
    return grant!;
  }

  @override
  Future<List<DeviceSessionView>> listDeviceSessions({
    String? accessToken,
    String? csrfToken,
  }) async => <DeviceSessionView>[];

  @override
  Future<SessionGrant> loginWithPassword({
    required String email,
    required String password,
    required DeviceDescriptor device,
  }) async {
    passwordEmails.add(email);
    return grant!;
  }

  @override
  Future<void> logout({String? accessToken, String? csrfToken}) async {
    logoutAccessTokens.add(accessToken);
    if (logoutError != null) {
      throw logoutError!;
    }
    if (logoutCompletion != null) {
      await logoutCompletion!.future;
    }
  }

  @override
  Future<SessionGrant> refreshSession({String? refreshToken}) async {
    refreshCalls++;
    refreshTokens.add(refreshToken);
    if (refreshError != null) {
      throw refreshError!;
    }
    if (refreshCompletion != null) {
      return refreshCompletion!.future;
    }
    return grant!;
  }

  @override
  Future<PasswordlessChallengeReceipt> requestPasswordlessChallenge({
    required String email,
  }) async {
    challengeEmails.add(email);
    return PasswordlessChallengeReceipt(
      email: email,
      challengeId: 'challenge-1',
      expiresAt: DateTime.utc(2026, 8, 4, 12, 10),
    );
  }

  @override
  Future<void> revokeDeviceSession({
    required String sessionId,
    String? accessToken,
    String? csrfToken,
  }) async {}
}
