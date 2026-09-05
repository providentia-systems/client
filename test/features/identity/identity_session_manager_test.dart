import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/networking/session_http_client.dart';
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/application/identity_session_manager.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

void main() {
  test(
    'origin client persists the email-code binding before prompting',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.manager.requestEmailCode('Person@Example.com');
      expect(fixture.transport.started.single.email, 'person@example.com');
      expect(fixture.pendingStore.value?.bindingToken, _pollToken);
      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.waitingForEmailCode,
      );
      expect(fixture.transport.exchangeCalls, 0);
    },
  );

  test('account-scoped device grant accepts its bound installation', () async {
    final fixture = _Fixture(installationId: _installationId);
    addTearDown(fixture.dispose);
    await fixture.manager.requestEmailCode('person@example.com');
    fixture.transport
      ..exchangeGrant = _grant(
        fixture.clock.value,
        installationId: _installationId,
      )
      ..currentUser = _currentUser(fixture.clock.value);

    await fixture.manager.verifyEmailCode('12345678');

    expect(fixture.transport.exchangeCalls, 1);
    expect(fixture.transport.lastExchange?.bindingToken, _pollToken);
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.authenticated,
    );
    expect(fixture.manager.snapshot.currentUser?.email, 'person@example.com');
    expect(fixture.pendingStore.value, isNull);
    expect(fixture.credentials.value?.refreshToken, 'refresh-token');
    expect(fixture.credentials.value?.deviceId, _deviceId);
    expect(fixture.credentials.value?.installationId, _installationId);
  });

  test('grant for another installation is rejected and revoked', () async {
    final fixture = _Fixture(installationId: _installationId);
    addTearDown(fixture.dispose);
    await fixture.manager.requestEmailCode('person@example.com');

    await fixture.manager.verifyEmailCode('12345678');

    expect(fixture.manager.snapshot.status, IdentitySessionStatus.failure);
    expect(fixture.manager.snapshot.safeMessage, contains('different device'));
    expect(fixture.credentials.value, isNull);
    expect(fixture.transport.logoutCalls, 1);
  });

  test(
    'expired email code is retired without a verification request',
    () async {
      final clock = _MutableClock(DateTime.utc(2026, 8, 9, 12));
      final fixture = _Fixture(clock: clock);
      addTearDown(fixture.dispose);
      await fixture.manager.requestEmailCode('person@example.com');
      clock.value = fixture.transport.expiresAt;
      fixture.transport.expiresAt = clock.value.add(const Duration(minutes: 2));

      await fixture.manager.verifyEmailCode('12345678');

      expect(fixture.transport.statusCalls, 0);
      expect(fixture.transport.exchangeCalls, 0);
      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.emailCodeExpired,
      );
    },
  );

  test(
    'waiting for an email code never starts background authentication',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.manager.requestEmailCode('person@example.com');
      await Future<void>.delayed(Duration.zero);
      expect(fixture.transport.statusCalls, 0);
      expect(fixture.transport.exchangeCalls, 0);
      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.waitingForEmailCode,
      );
      await fixture.manager.verifyEmailCode('12345678');
      expect(fixture.transport.exchangeCalls, 1);
      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.authenticated,
      );
    },
  );

  test(
    'ambiguous single-use exchange failure requires a new login link',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.manager.requestEmailCode('person@example.com');
      fixture.transport.exchangeError = const IdentityTransportException(
        kind: IdentityFailureKind.network,
        safeMessage: 'Connection lost.',
      );

      await fixture.manager.verifyEmailCode('12345678');

      expect(fixture.transport.exchangeCalls, 1);
      expect(fixture.pendingStore.value, isNull);
      expect(fixture.manager.snapshot.pendingEmailCode, isNull);
      expect(fixture.manager.snapshot.loginEmail, 'person@example.com');
      expect(
        fixture.manager.snapshot.safeMessage,
        contains('Request a new email code'),
      );
    },
  );

  test(
    'fatal current-user rejection clears and revokes the new grant',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.manager.requestEmailCode('person@example.com');
      fixture.transport.currentUserError = const IdentityTransportException(
        kind: IdentityFailureKind.authentication,
        safeMessage: 'Session rejected.',
      );

      await fixture.manager.verifyEmailCode('12345678');

      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.sessionExpired,
      );
      expect(fixture.manager.accessToken, isNull);
      expect(fixture.credentials.value, isNull);
      expect(fixture.transport.logoutCalls, 1);
    },
  );

  test('temporary current-user failure retains the issued session', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.manager.requestEmailCode('person@example.com');
    fixture.transport.currentUserError = const IdentityTransportException(
      kind: IdentityFailureKind.unavailable,
      safeMessage: 'Unavailable.',
    );

    await fixture.manager.verifyEmailCode('12345678');

    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.authenticated,
    );
    expect(fixture.manager.accessToken, 'access-token');
    expect(fixture.manager.snapshot.currentUser, isNull);
    expect(fixture.manager.snapshot.safeMessage, contains('Signed in'));
    expect(fixture.transport.logoutCalls, 0);
  });

  test('secure credential write failure revokes an orphan grant', () async {
    final fixture = _Fixture(credentialWriteFails: true);
    addTearDown(fixture.dispose);
    await fixture.manager.requestEmailCode('person@example.com');

    await fixture.manager.verifyEmailCode('12345678');

    expect(fixture.manager.snapshot.status, IdentitySessionStatus.failure);
    expect(fixture.manager.accessToken, isNull);
    expect(fixture.transport.logoutCalls, 1);
  });

  test(
    'verification needs no second pending challenge write',
    () async {
      final fixture = _Fixture(pendingWriteFailsAfter: 1);
      addTearDown(fixture.dispose);

      await fixture.manager.requestEmailCode('person@example.com');

      await fixture.manager.verifyEmailCode('12345678');

      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.authenticated,
      );
      expect(fixture.manager.snapshot.pendingEmailCode, isNull);
      expect(fixture.pendingStore.writes, 1);
    },
  );

  test('native restore rotates a 60-day sliding session', () async {
    final fixture = _Fixture(
      installationId: _installationId,
      stored: StoredNativeSession(
        sessionId: _sessionId,
        deviceId: _deviceId,
        installationId: _installationId,
        refreshToken: 'old-refresh-token',
      ),
    );
    addTearDown(fixture.dispose);
    fixture.transport
      ..refreshGrant = _grant(
        fixture.clock.value,
        installationId: _installationId,
      )
      ..currentUser = _currentUser(fixture.clock.value);

    await fixture.manager.restore();

    expect(fixture.transport.refreshTokens, <String?>['old-refresh-token']);
    expect(
      fixture.manager.snapshot.session?.refreshIdleTtl,
      const Duration(days: 60),
    );
    expect(fixture.credentials.value?.refreshToken, 'refresh-token');
    await fixture.manager.logout();
    expect(fixture.transport.logoutRefreshTokens, <String?>['refresh-token']);
  });

  test('durable native session never expires locally from idleness', () async {
    final clock = _MutableClock(DateTime.utc(2026, 8, 9, 12));
    final fixture = _Fixture(
      clock: clock,
      installationId: _installationId,
      stored: StoredNativeSession(
        sessionId: _sessionId,
        deviceId: _deviceId,
        installationId: _installationId,
        refreshToken: 'old-refresh-token',
      ),
    );
    addTearDown(fixture.dispose);
    fixture.transport
      ..refreshGrant = _grant(
        clock.value,
        installationId: _installationId,
        durable: true,
      )
      ..currentUser = _currentUser(clock.value);

    await fixture.manager.restore();

    expect(fixture.manager.snapshot.session?.isDurable, isTrue);
    expect(fixture.manager.snapshot.session?.refreshIdleTtl, isNull);
    expect(fixture.manager.snapshot.session?.idleExpiresAt, isNull);
    expect(fixture.manager.snapshot.session?.refreshExpiresAt, isNull);
    expect(fixture.credentials.value?.refreshToken, 'refresh-token');

    // Idle far beyond every removed transport ceiling: the trusted device
    // rotates its credential instead of being expired locally.
    clock.value = clock.value.add(const Duration(days: 400));
    fixture.transport.refreshGrant = _grant(
      clock.value,
      installationId: _installationId,
      durable: true,
    );

    expect(await fixture.manager.ensureFresh(), isTrue);
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.authenticated,
    );
    expect(fixture.manager.snapshot.session?.isDurable, isTrue);
    expect(await fixture.manager.tryRecover(), isTrue);
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.authenticated,
    );
  });

  test('a bounded session still expires at its finite deadline', () async {
    final clock = _MutableClock(DateTime.utc(2026, 8, 9, 12));
    final fixture = _Fixture(clock: clock);
    addTearDown(fixture.dispose);
    await fixture.manager.requestEmailCode('person@example.com');

    await fixture.manager.verifyEmailCode('12345678');
    expect(fixture.manager.snapshot.session?.isDurable, isFalse);

    clock.value = clock.value.add(const Duration(days: 61));

    expect(await fixture.manager.ensureFresh(), isFalse);
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.sessionExpired,
    );
    expect(fixture.manager.accessToken, isNull);
  });

  test('cross-tab durable web grant round-trips null expiry', () async {
    final hub = _CoordinationHub();
    final firstPort = hub.connect();
    final secondPort = hub.connect();
    final now = DateTime.utc(2026, 8, 9, 12);
    firstPort.publishGrant(
      _grant(
        now,
        transport: ClientSessionTransport.webCookie,
        csrfToken: 'csrf-durable',
        durable: true,
      ),
    );
    final second = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
      sessionCoordination: secondPort,
    );
    second.transport.currentUser = _currentUser(
      now,
      transport: ClientSessionTransport.webCookie,
    );
    addTearDown(second.dispose);

    await second.manager.restore();

    expect(second.manager.csrfToken, 'csrf-durable');
    expect(second.manager.snapshot.isAuthenticated, isTrue);
    expect(second.manager.snapshot.session?.isDurable, isTrue);
    expect(second.manager.snapshot.session?.idleExpiresAt, isNull);
    expect(second.manager.snapshot.session?.refreshExpiresAt, isNull);
    expect(second.manager.snapshot.session?.refreshIdleTtl, isNull);
  });

  test('remote logout rejection never restores cleared local state', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.manager.requestEmailCode('person@example.com');

    await fixture.manager.verifyEmailCode('12345678');
    fixture.transport.logoutError = const IdentityTransportException(
      kind: IdentityFailureKind.forbidden,
      safeMessage: 'Logout proof was rejected.',
    );

    await fixture.manager.logout();

    expect(fixture.transport.logoutCalls, 1);
    expect(fixture.manager.snapshot.status, IdentitySessionStatus.signedOut);
    expect(fixture.manager.accessToken, isNull);
    expect(fixture.credentials.value, isNull);
  });

  test(
    'temporary refresh failure keeps an existing session signed in',
    () async {
      final clock = _MutableClock(DateTime.utc(2026, 8, 9, 12));
      final fixture = _Fixture(clock: clock);
      addTearDown(fixture.dispose);
      await fixture.manager.requestEmailCode('person@example.com');

      await fixture.manager.verifyEmailCode('12345678');
      clock.value = clock.value.add(const Duration(minutes: 14));
      fixture.transport.refreshError = const IdentityTransportException(
        kind: IdentityFailureKind.unavailable,
        safeMessage: 'Temporarily unavailable.',
      );

      expect(await fixture.manager.ensureFresh(), isFalse);
      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.authenticated,
      );
      expect(fixture.manager.snapshot.session?.sessionId, _sessionId);

      fixture.transport.refreshError = null;
      expect(await fixture.manager.ensureFresh(), isTrue);
      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.authenticated,
      );
    },
  );

  test(
    'a real 401 forces one rotation while access metadata is fresh',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.manager.requestEmailCode('person@example.com');

      await fixture.manager.verifyEmailCode('12345678');

      final recovered = await fixture.manager.tryRecover();

      expect(recovered, isTrue);
      expect(fixture.transport.refreshTokens, <String?>['refresh-token']);
      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.authenticated,
      );
    },
  );

  test('a rejected forced rotation clears the authenticated session', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.manager.requestEmailCode('person@example.com');

    await fixture.manager.verifyEmailCode('12345678');
    fixture.transport.refreshError = const IdentityTransportException(
      kind: IdentityFailureKind.authentication,
      safeMessage: 'Refresh rejected.',
    );

    expect(await fixture.manager.tryRecover(), isFalse);
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.sessionExpired,
    );
    expect(fixture.manager.accessToken, isNull);
    expect(fixture.credentials.value, isNull);
  });

  test('cancel A cannot erase a concurrently requested B', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.manager.requestEmailCode('a@example.com');

    final cancel = fixture.manager.cancelEmailCode();
    final startB = fixture.manager.requestEmailCode('b@example.com');
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.requestingEmailCode,
    );
    await Future.wait<void>(<Future<void>>[cancel, startB.then<void>((_) {})]);

    expect(fixture.manager.snapshot.loginEmail, 'b@example.com');
    expect(fixture.pendingStore.value?.email, 'b@example.com');
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.waitingForEmailCode,
    );
  });

  test('resend preempts an approval exchange already in flight', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.manager.requestEmailCode('a@example.com');
    fixture.transport.exchangeGate = Completer<SessionGrant>();

    final poll = fixture.manager.verifyEmailCode('12345678');
    await _until(() => fixture.transport.exchangeCalls == 1);
    final resend = fixture.manager.requestEmailCode('b@example.com');
    fixture.transport.exchangeGate!.complete(_grant(fixture.clock.value));
    await Future.wait<void>(<Future<void>>[poll, resend.then<void>((_) {})]);

    expect(fixture.transport.logoutCalls, 1);
    expect(fixture.manager.snapshot.loginEmail, 'b@example.com');
    expect(fixture.pendingStore.value?.email, 'b@example.com');
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.waitingForEmailCode,
    );
  });

  test('late receipt persistence cannot overwrite replacement proof', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.pendingStore
      ..blockWriteAt = 1
      ..writeGate = Completer<void>();

    final startA = fixture.manager.requestEmailCode('a@example.com');
    await _until(() => fixture.pendingStore.writes == 1);
    final startB = fixture.manager.requestEmailCode('b@example.com');
    fixture.pendingStore.writeGate!.complete();
    await Future.wait<void>(<Future<void>>[
      startA.then<void>((_) {}),
      startB.then<void>((_) {}),
    ]);

    expect(fixture.pendingStore.value?.email, 'b@example.com');
    expect(fixture.manager.snapshot.loginEmail, 'b@example.com');
  });

  test(
    'logout during delayed credential write cannot resurrect grant',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.credentials
        ..blockWriteAt = 1
        ..writeGate = Completer<void>();
      await fixture.manager.requestEmailCode('person@example.com');

      final poll = fixture.manager.verifyEmailCode('12345678');
      await _until(() => fixture.credentials.writes == 1);
      final logout = fixture.manager.logout();
      // Durable logout does not claim completion until its tombstone is queued
      // behind the in-flight credential write.
      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.verifyingEmailCode,
      );
      fixture.credentials.writeGate!.complete();
      await Future.wait<void>(<Future<void>>[poll, logout]);

      expect(fixture.credentials.value, isNull);
      expect(fixture.manager.accessToken, isNull);
      expect(fixture.manager.snapshot.status, IdentitySessionStatus.signedOut);
      expect(fixture.transport.logoutCalls, greaterThanOrEqualTo(2));
    },
  );

  test('late native write is cleared after its caller times out', () async {
    final fixture = _Fixture(requestTimeout: const Duration(milliseconds: 20));
    addTearDown(fixture.dispose);
    fixture.credentials
      ..blockWriteAt = 1
      ..writeGate = Completer<void>();
    await fixture.manager.requestEmailCode('person@example.com');

    final poll = fixture.manager.verifyEmailCode('12345678');
    await _until(() => fixture.credentials.writes == 1);
    await poll;
    expect(fixture.manager.snapshot.isAuthenticated, isFalse);

    fixture.credentials.writeGate!.complete();
    await _until(() => fixture.credentials.value == null);
    expect(fixture.credentials.value, isNull);
    expect(fixture.manager.accessToken, isNull);
  });

  test(
    'definitive start rate limit does not poll a nonexistent request',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.transport.startError = const IdentityTransportException(
        kind: IdentityFailureKind.rateLimited,
        safeMessage: 'Wait before trying again.',
      );

      await expectLater(
        fixture.manager.requestEmailCode('person@example.com'),
        throwsA(isA<IdentityTransportException>()),
      );

      expect(fixture.transport.statusCalls, 0);
      expect(fixture.pendingStore.value, isNull);
      expect(fixture.manager.snapshot.pendingEmailCode, isNull);
    },
  );

  test('exchange rate limit retains approved proof for retry', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.manager.requestEmailCode('person@example.com');
    fixture.transport.exchangeError = const IdentityTransportException(
      kind: IdentityFailureKind.rateLimited,
      safeMessage: 'Wait before trying again.',
    );

    await fixture.manager.verifyEmailCode('12345678');
    expect(fixture.pendingStore.value, isNotNull);
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.waitingForEmailCode,
    );

    fixture.transport.exchangeError = null;
    await fixture.manager.verifyEmailCode('12345678');
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.authenticated,
    );
  });

  test('ambiguous web exchange clears any hidden cookie session', () async {
    final fixture = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
    );
    addTearDown(fixture.dispose);
    await fixture.manager.requestEmailCode('person@example.com');
    final logoutBeforeExchange = fixture.transport.logoutCalls;
    fixture.transport.exchangeError = const IdentityTransportException(
      kind: IdentityFailureKind.network,
      safeMessage: 'Connection lost.',
    );

    await fixture.manager.verifyEmailCode('12345678');

    expect(fixture.transport.logoutCalls, logoutBeforeExchange + 1);
    expect(fixture.pendingStore.value, isNull);
    expect(fixture.manager.snapshot.status, IdentitySessionStatus.failure);
  });

  test(
    'timed-out initial proof write is cleaned after late completion',
    () async {
      final fixture = _Fixture(requestTimeout: const Duration(milliseconds: 5));
      addTearDown(fixture.dispose);
      fixture.pendingStore
        ..blockWriteAt = 1
        ..writeGate = Completer<void>();

      final request = fixture.manager.requestEmailCode('person@example.com');
      await expectLater(
        request,
        throwsA(isA<IdentityCredentialStoreException>()),
      );
      fixture.pendingStore.writeGate!.complete();
      await _until(() => fixture.pendingStore.value == null);

      expect(fixture.manager.snapshot.pendingEmailCode, isNull);
      expect(fixture.transport.started, hasLength(1));
    },
  );

  test('a new account cannot start while old credentials cannot be retired', () async {
    final fixture = _Fixture(stored: StoredNativeSession(sessionId: _sessionId, deviceId: _deviceId, refreshToken: 'account-a-refresh'));
    addTearDown(fixture.dispose);
    fixture.credentials.clearFails = true;
    await expectLater(fixture.manager.requestEmailCode('account-b@example.com'), throwsA(isA<IdentityCredentialStoreException>()));
    expect(fixture.transport.started, isEmpty);
    expect(fixture.pendingStore.value, isNull);
    expect(fixture.pendingStore.logoutIntent, isTrue);
    expect(fixture.manager.snapshot.isAuthenticated, isFalse);
  });

  test('delayed cross-tab grants cannot roll CSRF metadata backward', () async {
    final hub = _CoordinationHub();
    final firstPort = hub.connect();
    final secondPort = hub.connect();
    final now = DateTime.utc(2026, 8, 9, 12);
    final initial = _grant(
      now,
      transport: ClientSessionTransport.webCookie,
      csrfToken: 'csrf-1',
    );
    firstPort.publishGrant(initial);
    final first = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
      sessionCoordination: firstPort,
    );
    final second = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
      sessionCoordination: secondPort,
    );
    first.transport.currentUser = _currentUser(
      now,
      transport: ClientSessionTransport.webCookie,
    );
    second.transport.currentUser = first.transport.currentUser;
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await Future.wait<void>(<Future<void>>[
      first.manager.restore(),
      second.manager.restore(),
    ]);

    final rotated = _grant(
      now.add(const Duration(seconds: 1)),
      transport: ClientSessionTransport.webCookie,
      csrfToken: 'csrf-2',
    );
    final latest = _grant(
      now.add(const Duration(seconds: 2)),
      transport: ClientSessionTransport.webCookie,
      csrfToken: 'csrf-3',
    );
    second.transport.currentUser = _currentUser(
      now.add(const Duration(seconds: 2)),
      transport: ClientSessionTransport.webCookie,
    );
    hub.holdBroadcasts = true;
    firstPort.publishGrant(rotated);
    firstPort.publishGrant(latest);
    hub.flushHeld(reverse: true);
    await _until(() => second.manager.csrfToken == 'csrf-3');
    await Future<void>.delayed(Duration.zero);

    expect(second.manager.csrfToken, 'csrf-3');
    expect(
      second.manager.snapshot.session?.accessExpiresAt,
      latest.metadata.accessExpiresAt,
    );
    expect(second.transport.logoutCalls, 0);
  });

  test('two tabs sharing an approved proof exchange it only once', () async {
    final hub = _CoordinationHub();
    final sharedPending = _MemoryPendingStore()
      ..value = PendingEmailCode(
        requestId: _requestId,
        email: 'person@example.com',
        createdAt: DateTime.utc(2026, 8, 9, 12),
        expiresAt: DateTime.utc(2026, 8, 9, 12, 15),
        bindingToken: _pollToken,
        resendAt: (DateTime.utc(
          2026,
          8,
          9,
          12,
        )).add(const Duration(seconds: 60)),
      );
    final first = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
      sessionCoordination: hub.connect(),
      sharedPendingStore: sharedPending,
    );
    final second = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
      sessionCoordination: hub.connect(),
      sharedPendingStore: sharedPending,
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await Future.wait<void>(<Future<void>>[
      first.manager.restore(),
      second.manager.restore(),
    ]);

    await Future.wait<void>(<Future<void>>[
      first.manager.verifyEmailCode('12345678'),
      second.manager.verifyEmailCode('12345678'),
    ]);
    await _until(
      () =>
          first.manager.snapshot.isAuthenticated &&
          second.manager.snapshot.isAuthenticated,
    );

    expect(first.transport.exchangeCalls + second.transport.exchangeCalls, 1);
    expect(sharedPending.value, isNull);
    expect(first.manager.csrfToken, 'csrf-token');
    expect(second.manager.csrfToken, 'csrf-token');
  });

  test('state-changing web request excludes a sibling refresh', () async {
    final hub = _CoordinationHub();
    final firstPort = hub.connect();
    final secondPort = hub.connect();
    final now = DateTime.utc(2026, 8, 9, 12);
    final initial = _grant(
      now,
      transport: ClientSessionTransport.webCookie,
      csrfToken: 'csrf-1',
    );
    firstPort.publishGrant(initial);
    final first = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
      sessionCoordination: firstPort,
    );
    final second = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
      sessionCoordination: secondPort,
    );
    first.transport.currentUser = _currentUser(
      now,
      transport: ClientSessionTransport.webCookie,
    );
    second.transport.currentUser = first.transport.currentUser;
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await Future.wait<void>(<Future<void>>[
      first.manager.restore(),
      second.manager.restore(),
    ]);

    final sendStarted = Completer<void>();
    final releaseSend = Completer<void>();
    final client = SessionHttpClient(
      inner: MockClient((request) async {
        expect(request.headers['X-CSRF-Token'], 'csrf-1');
        sendStarted.complete();
        await releaseSend.future;
        return http.Response('{}', 200);
      }),
      sessions: second.manager,
    );
    addTearDown(client.close);
    final mutation = client.post(
      Uri.parse('https://api.example.test/homes/current'),
      body: '{}',
    );
    await sendStarted.future;

    final refreshedGrant = _grant(
      now.add(const Duration(seconds: 1)),
      transport: ClientSessionTransport.webCookie,
      csrfToken: 'csrf-2',
    );
    first.transport
      ..refreshGrant = refreshedGrant
      ..currentUser = _currentUser(
        now.add(const Duration(seconds: 1)),
        transport: ClientSessionTransport.webCookie,
      );
    final refresh = first.manager.tryRecover();
    await Future<void>.delayed(Duration.zero);
    expect(first.transport.refreshTokens, isEmpty);

    releaseSend.complete();
    expect((await mutation).statusCode, 200);
    expect(await refresh, isTrue);
    expect(first.manager.csrfToken, 'csrf-2');
  });

  test('queued logout cannot clear a newer cross-tab login', () async {
    final hub = _CoordinationHub();
    final firstPort = hub.connect();
    final secondPort = hub.connect();
    final now = DateTime.utc(2026, 8, 9, 12);
    firstPort.publishGrant(
      _grant(
        now,
        transport: ClientSessionTransport.webCookie,
        csrfToken: 'csrf-a',
      ),
    );
    final first = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
      sessionCoordination: firstPort,
    );
    final second = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
      sessionCoordination: secondPort,
    );
    first.transport.currentUser = _currentUser(
      now,
      transport: ClientSessionTransport.webCookie,
    );
    second.transport.currentUser = first.transport.currentUser;
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await Future.wait<void>(<Future<void>>[
      first.manager.restore(),
      second.manager.restore(),
    ]);

    hub
      ..blockExclusiveAt = hub.exclusiveCalls + 2
      ..exclusiveGate = Completer<void>();
    final logout = first.manager.logout();
    await _until(() => hub.exclusiveCalls == hub.blockExclusiveAt);
    final accountB = _grant(
      now.add(const Duration(seconds: 1)),
      transport: ClientSessionTransport.webCookie,
      sessionId: _secondSessionId,
      userId: _secondUserId,
      csrfToken: 'csrf-b',
    );
    first.transport.currentUser = _currentUser(
      now.add(const Duration(seconds: 1)),
      transport: ClientSessionTransport.webCookie,
      sessionId: _secondSessionId,
      userId: _secondUserId,
    );
    secondPort.publishGrant(accountB);
    hub.exclusiveGate!.complete();
    await logout;

    expect(first.transport.logoutCalls, 0);
    expect(first.manager.snapshot.session?.sessionId, _secondSessionId);
    expect(first.manager.csrfToken, 'csrf-b');
    expect(first.manager.snapshot.isAuthenticated, isTrue);

    final restored = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
      sessionCoordination: hub.connect(),
    );
    restored.transport.currentUser = _currentUser(
      now.add(const Duration(seconds: 1)),
      transport: ClientSessionTransport.webCookie,
      sessionId: _secondSessionId,
      userId: _secondUserId,
    );
    addTearDown(restored.dispose);
    await restored.manager.restore();

    expect(restored.manager.snapshot.session?.sessionId, _secondSessionId);
    expect(restored.manager.csrfToken, 'csrf-b');
    expect(restored.transport.logoutCalls, 0);
  });

  test('grant publication failure clears the issued browser session', () async {
    final hub = _CoordinationHub();
    final fixture = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
      sessionCoordination: hub.connect(),
    );
    addTearDown(fixture.dispose);
    await fixture.manager.requestEmailCode('person@example.com');
    hub.failGrantPublication = true;

    await fixture.manager.verifyEmailCode('12345678');

    expect(fixture.manager.snapshot.isAuthenticated, isFalse);
    expect(fixture.manager.csrfToken, isNull);
    expect(fixture.transport.logoutCalls, greaterThanOrEqualTo(1));
    expect(hub.latest?.signedOut, isTrue);
  });

  test(
    'refresh publication failure retires the rotated browser grant',
    () async {
      final hub = _CoordinationHub();
      final fixture = _Fixture(
        sessionTransport: ClientSessionTransport.webCookie,
        sessionCoordination: hub.connect(),
      );
      addTearDown(fixture.dispose);
      await fixture.manager.requestEmailCode('person@example.com');

      await fixture.manager.verifyEmailCode('12345678');
      final logoutCallsBeforeRefresh = fixture.transport.logoutCalls;
      hub.failGrantPublication = true;
      fixture.transport.refreshGrant = _grant(
        fixture.clock.value.add(const Duration(seconds: 1)),
        transport: ClientSessionTransport.webCookie,
        csrfToken: 'rotated-csrf',
      );
      fixture.transport.currentUser = _currentUser(
        fixture.clock.value.add(const Duration(seconds: 1)),
        transport: ClientSessionTransport.webCookie,
      );

      expect(await fixture.manager.tryRecover(), isFalse);

      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.sessionExpired,
      );
      expect(fixture.manager.csrfToken, isNull);
      expect(
        fixture.transport.logoutCalls,
        greaterThan(logoutCallsBeforeRefresh),
      );
      expect(hub.latest?.signedOut, isTrue);
    },
  );

  test(
    'active-home publication failure signs the browser out safely',
    () async {
      final hub = _CoordinationHub();
      final fixture = _Fixture(
        sessionTransport: ClientSessionTransport.webCookie,
        sessionCoordination: hub.connect(),
      );
      addTearDown(fixture.dispose);
      fixture.transport.currentUser = _currentUser(
        fixture.clock.value,
        transport: ClientSessionTransport.webCookie,
        homes: <CurrentUserHomeView>[
          CurrentUserHomeView(id: _homeId, name: 'Family home', role: 'owner'),
        ],
      );
      await fixture.manager.requestEmailCode('person@example.com');

      await fixture.manager.verifyEmailCode('12345678');
      hub.failGrantPublication = true;

      await expectLater(
        fixture.manager.coordinateActiveHomeMutation<void>(
          homeId: _homeId,
          mutation: () async {},
        ),
        throwsA(isA<IdentityTransportException>()),
      );

      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.sessionExpired,
      );
      expect(fixture.manager.snapshot.session, isNull);
      expect(hub.latest?.signedOut, isTrue);
    },
  );

  test('offline browser logout tombstone blocks a restart restore', () async {
    final hub = _CoordinationHub();
    final pendingStore = _MemoryPendingStore();
    final first = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
      sessionCoordination: hub.connect(),
      sharedPendingStore: pendingStore,
    );
    addTearDown(first.dispose);
    await first.manager.requestEmailCode('person@example.com');

    await first.manager.verifyEmailCode('12345678');
    first.transport.logoutError = const IdentityTransportException(
      kind: IdentityFailureKind.network,
      safeMessage: 'Offline.',
    );

    await first.manager.logout();

    expect(first.manager.snapshot.status, IdentitySessionStatus.signedOut);
    expect(pendingStore.logoutIntent, isTrue);
    final restored = _Fixture(
      sessionTransport: ClientSessionTransport.webCookie,
      sessionCoordination: hub.connect(),
      sharedPendingStore: pendingStore,
    );
    restored.transport.logoutError = const IdentityTransportException(
      kind: IdentityFailureKind.network,
      safeMessage: 'Still offline.',
    );
    addTearDown(restored.dispose);

    await restored.manager.restore();

    expect(restored.transport.refreshTokens, isEmpty);
    expect(restored.manager.snapshot.status, IdentitySessionStatus.signedOut);
    expect(restored.manager.snapshot.safeMessage, contains('connection'));
    expect(pendingStore.logoutIntent, isTrue);
  });

  test(
    'restart after exchange cookie commit clears the unfinished session',
    () async {
      final hub = _CoordinationHub();
      final port = hub.connect();
      port.publishAuthenticationIntent(_requestId);
      final pendingStore = _MemoryPendingStore()
        ..cookieMutation = const BrowserCookieMutationJournal(
          kind: BrowserCookieMutationKind.emailCodeVerification,
          operationId: _requestId,
        );
      final restored = _Fixture(
        sessionTransport: ClientSessionTransport.webCookie,
        sessionCoordination: port,
        sharedPendingStore: pendingStore,
      );
      addTearDown(restored.dispose);

      await restored.manager.restore();

      expect(restored.transport.logoutCalls, 1);
      expect(restored.transport.refreshTokens, isEmpty);
      expect(restored.manager.snapshot.status, IdentitySessionStatus.signedOut);
      expect(restored.manager.csrfToken, isNull);
      expect(pendingStore.cookieMutation, isNull);
      expect(hub.latest?.signedOut, isTrue);
    },
  );

  test(
    'restart after refresh cookie rotation rejects stale coordinated CSRF',
    () async {
      final hub = _CoordinationHub();
      final port = hub.connect();
      port.publishGrant(
        _grant(
          DateTime.utc(2026, 8, 9, 12),
          transport: ClientSessionTransport.webCookie,
          csrfToken: 'stale-csrf',
        ),
      );
      final pendingStore = _MemoryPendingStore()
        ..cookieMutation = const BrowserCookieMutationJournal(
          kind: BrowserCookieMutationKind.sessionRefresh,
          operationId: 'refresh:$_sessionId:old-access-expiry',
        );
      final restored = _Fixture(
        sessionTransport: ClientSessionTransport.webCookie,
        sessionCoordination: port,
        sharedPendingStore: pendingStore,
      );
      addTearDown(restored.dispose);

      await restored.manager.restore();

      expect(restored.transport.logoutCalls, 1);
      expect(restored.transport.refreshTokens, isEmpty);
      expect(restored.manager.snapshot.status, IdentitySessionStatus.signedOut);
      expect(restored.manager.csrfToken, isNull);
      expect(pendingStore.cookieMutation, isNull);
      expect(hub.latest?.signedOut, isTrue);
    },
  );

  test(
    'cookie mutations are journaled before transport and published first',
    () async {
      final hub = _CoordinationHub();
      final fixture = _Fixture(
        sessionTransport: ClientSessionTransport.webCookie,
        sessionCoordination: hub.connect(),
      );
      addTearDown(fixture.dispose);
      BrowserCookieMutationKind? observedKind;
      fixture.transport.onExchange = () {
        observedKind = fixture.pendingStore.cookieMutation?.kind;
      };
      fixture.pendingStore.onClearCookieMutation = () {
        expect(hub.latest?.grant?.secrets.csrfToken, 'exchange-csrf');
      };
      fixture.transport.exchangeGrant = _grant(
        fixture.clock.value,
        transport: ClientSessionTransport.webCookie,
        csrfToken: 'exchange-csrf',
      );
      await fixture.manager.requestEmailCode('person@example.com');

      await fixture.manager.verifyEmailCode('12345678');

      expect(observedKind, BrowserCookieMutationKind.emailCodeVerification);
      expect(fixture.pendingStore.cookieMutation, isNull);
      fixture.transport.onRefresh = () {
        observedKind = fixture.pendingStore.cookieMutation?.kind;
      };
      fixture.pendingStore.onClearCookieMutation = () {
        expect(hub.latest?.grant?.secrets.csrfToken, 'refresh-csrf');
      };
      fixture.transport
        ..refreshGrant = _grant(
          fixture.clock.value.add(const Duration(seconds: 1)),
          transport: ClientSessionTransport.webCookie,
          csrfToken: 'refresh-csrf',
        )
        ..currentUser = _currentUser(
          fixture.clock.value.add(const Duration(seconds: 1)),
          transport: ClientSessionTransport.webCookie,
        );

      expect(await fixture.manager.tryRecover(), isTrue);

      expect(observedKind, BrowserCookieMutationKind.sessionRefresh);
      expect(fixture.pendingStore.cookieMutation, isNull);
    },
  );

  test(
    'stalled cookie-journal CAS holds the origin lock against a newer proof',
    () async {
      final hub = _CoordinationHub();
      final sharedStore = _MemoryPendingStore();
      final first = _Fixture(
        sessionTransport: ClientSessionTransport.webCookie,
        sessionCoordination: hub.connect(),
        sharedPendingStore: sharedStore,
        requestTimeout: const Duration(milliseconds: 20),
      );
      final second = _Fixture(
        sessionTransport: ClientSessionTransport.webCookie,
        sessionCoordination: hub.connect(),
        sharedPendingStore: sharedStore,
        requestId: _secondRequestId,
        requestTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.manager.requestEmailCode('a@example.com');
      sharedStore
        ..cookieClearGate = Completer<void>()
        ..cookieClearRead = Completer<void>();

      var firstCompleted = false;
      final firstPoll = first.manager
          .verifyEmailCode('12345678')
          .whenComplete(() => firstCompleted = true);
      final cookieClearGate = sharedStore.cookieClearGate!;
      addTearDown(() {
        if (!cookieClearGate.isCompleted) cookieClearGate.complete();
      });
      await sharedStore.cookieClearRead!.future.timeout(const Duration(seconds: 2), onTimeout: () { fail('journal not reached: state=' + first.manager.snapshot.status.name + ', reason=' + (first.manager.snapshot.safeMessage ?? '') + ', exchanges=' + first.transport.exchangeCalls.toString()); });

      final secondStart = second.manager.requestEmailCode('b@example.com');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(firstCompleted, isFalse);
      expect(second.transport.started, isEmpty);
      expect(
        sharedStore.cookieMutation?.kind,
        BrowserCookieMutationKind.emailCodeVerification,
      );

      sharedStore.cookieClearGate!.complete();
      await Future.wait<void>(<Future<void>>[
        firstPoll,
        secondStart.then<void>((_) {}),
      ]);

      expect(sharedStore.cookieMutation, isNull);
      expect(sharedStore.value?.requestId, _secondRequestId);
      expect(sharedStore.value?.email, 'b@example.com');
      expect(second.transport.started, hasLength(1));
    },
  );
}

Future<void> _until(bool Function() condition) async {
  for (var index = 0; index < 1000; index++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition was not reached.');
}

final class _CoordinationHub {
  final List<_HubPort> _ports = <_HubPort>[];
  final List<(_HubPort, CoordinatedSessionUpdate)> _held =
      <(_HubPort, CoordinatedSessionUpdate)>[];
  Future<void> _tail = Future<void>.value();
  CoordinatedSessionUpdate? latest;
  bool holdBroadcasts = false;
  bool failGrantPublication = false;
  int exclusiveCalls = 0;
  int? blockExclusiveAt;
  Completer<void>? exclusiveGate;

  _HubPort connect() {
    final port = _HubPort(this);
    _ports.add(port);
    return port;
  }

  Future<T> exclusive<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then<void>((_) async {
      exclusiveCalls++;
      if (exclusiveCalls == blockExclusiveAt) {
        await exclusiveGate!.future;
      }
      try {
        result.complete(await action());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  void publish(_HubPort sender, CoordinatedSessionUpdate update) {
    if (failGrantPublication && update.grant != null) {
      throw StateError('durable grant publication unavailable');
    }
    latest = update;
    for (final port in _ports) {
      if (identical(port, sender)) continue;
      if (holdBroadcasts) {
        _held.add((port, update));
      } else {
        port.add(update);
      }
    }
  }

  void flushHeld({bool reverse = false}) {
    final held = List<(_HubPort, CoordinatedSessionUpdate)>.of(_held);
    _held.clear();
    holdBroadcasts = false;
    final deliveries = reverse ? held.reversed : held;
    for (final entry in deliveries) {
      entry.$1.add(entry.$2);
    }
  }

  Future<void> remove(_HubPort port) async {
    _ports.remove(port);
  }
}

final class _HubPort implements SessionCoordinationPort {
  _HubPort(this._hub);

  final _CoordinationHub _hub;
  final StreamController<CoordinatedSessionUpdate> _updates =
      StreamController<CoordinatedSessionUpdate>.broadcast(sync: true);

  @override
  Stream<CoordinatedSessionUpdate> get updates => _updates.stream;

  void add(CoordinatedSessionUpdate update) => _updates.add(update);

  @override
  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    required Duration lockWaitTimeout,
  }) => _hub.exclusive(action);

  @override
  Future<CoordinatedSessionUpdate?> readLatest() async => _hub.latest;

  @override
  void publishGrant(SessionGrant grant, {String? intentId}) => _hub.publish(
    this,
    CoordinatedSessionUpdate.grant(grant, intentId: intentId),
  );

  @override
  void publishAuthenticationIntent(String intentId) => _hub.publish(
    this,
    CoordinatedSessionUpdate.authenticationIntent(intentId),
  );

  @override
  void publishSignedOut() =>
      _hub.publish(this, const CoordinatedSessionUpdate.signedOut());

  @override
  Future<void> dispose() async {
    await _hub.remove(this);
    await _updates.close();
  }
}

const _requestId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const _secondRequestId = '0198a0b1-c2d3-7e4f-8123-456789abcdd4';
const _sessionId = '0198a0b1-c2d3-7e4f-8123-456789abcdea';
const _deviceId = '0198a0b1-c2d3-7e4f-8123-456789abcdeb';
const _installationId = '0198a0b1-c2d3-7e4f-8123-456789abcd00';
const _userId = '0198a0b1-c2d3-7e4f-8123-456789abcdec';
const _secondSessionId = '0198a0b1-c2d3-7e4f-8123-456789abcdd1';
const _secondUserId = '0198a0b1-c2d3-7e4f-8123-456789abcdd2';
const _homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdd3';
const _pollToken = 'poll-token-private-proof-000000000000000000000000';
const _verifier =
    'pkce-verifier-private-proof-000000000000000000000000000000000000';
const _state = 'state-private-proof-000000000000000000000000000000';
const _pollChallenge = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _codeChallenge = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

final class _Fixture {
  _Fixture({
    _MutableClock? clock,
    String installationId = _deviceId,
    bool credentialWriteFails = false,
    int? pendingWriteFailsAfter,
    StoredNativeSession? stored,
    ClientSessionTransport sessionTransport =
        ClientSessionTransport.nativeBearer,
    Duration requestTimeout = const Duration(seconds: 15),
    _MemoryPendingStore? sharedPendingStore,
    String requestId = _requestId,
    SessionCoordinationPort sessionCoordination =
        const LocalSessionCoordination(),
  }) : clock = clock ?? _MutableClock(DateTime.utc(2026, 8, 9, 12)),
       credentials = _MemoryCredentialStore(
         value: stored,
         writeFails: credentialWriteFails,
       ),
       pendingStore =
           sharedPendingStore ??
           _MemoryPendingStore(writeFailsAfter: pendingWriteFailsAfter),
       transport = _FakeIdentityTransport(sessionTransport) {
    manager = IdentitySessionManager(
      transport: transport,
      credentialStore: credentials,
      pendingEmailCodeStore: pendingStore,

      sessionCoordination: sessionCoordination,
      device: DeviceDescriptor(
        id: installationId,
        name: 'Test device',
        platform: 'linux',
      ),
      clock: () => this.clock.value,

      requestTimeout: requestTimeout,
    );
    transport.clock = this.clock;
    transport.requestId = requestId;
  }

  final _MutableClock clock;
  final _MemoryCredentialStore credentials;
  final _MemoryPendingStore pendingStore;
  final _FakeIdentityTransport transport;
  late final IdentitySessionManager manager;

  Future<void> dispose() => manager.dispose();
}

final class _MutableClock {
  _MutableClock(this.value);
  DateTime value;
}

final class _MemoryPendingStore implements PendingEmailCodeStore {
  _MemoryPendingStore({this.writeFailsAfter});
  final int? writeFailsAfter;
  PendingEmailCode? value;
  int writes = 0;
  int? blockWriteAt;
  Completer<void>? writeGate;
  Completer<void>? cookieClearGate;
  Completer<void>? cookieClearRead;
  bool clearFails = false;
  bool invalidateFails = false;
  bool logoutIntent = false;
  BrowserCookieMutationJournal? cookieMutation;
  void Function()? onClearCookieMutation;

  @override
  Future<void> clear({PendingEmailCode? request}) async {
    if (request != null && value?.requestId != request.requestId) return;
    if (clearFails) throw StateError('secure store clear unavailable');
    value = null;
  }

  @override
  Future<void> invalidate(PendingEmailCode request) async {
    if (invalidateFails) throw StateError('secure store write unavailable');
    value = null;
  }

  @override
  Future<bool> hasLogoutIntent() async => logoutIntent;

  @override
  Future<void> markLogoutIntent() async => logoutIntent = true;

  @override
  Future<void> clearLogoutIntent() async => logoutIntent = false;

  @override
  Future<BrowserCookieMutationJournal?> readCookieMutation() async =>
      cookieMutation;

  @override
  Future<void> beginCookieMutation(
    BrowserCookieMutationJournal journal,
  ) async => cookieMutation = journal;

  @override
  Future<void> clearCookieMutation({
    BrowserCookieMutationJournal? journal,
  }) async {
    final matches =
        journal == null ||
        (cookieMutation?.kind == journal.kind &&
            cookieMutation?.operationId == journal.operationId);
    if (!matches) {
      return;
    }
    if (cookieClearGate case final gate?) {
      if (cookieClearRead case final read? when !read.isCompleted) {
        read.complete();
      }
      await gate.future;
      cookieClearGate = null;
    }
    onClearCookieMutation?.call();
    cookieMutation = null;
  }

  @override
  Future<PendingEmailCode?> read() async => value;

  @override
  Future<void> write(PendingEmailCode request, {required bool activate}) async {
    writes++;
    if (writes == blockWriteAt) {
      await writeGate!.future;
    }
    if (writeFailsAfter != null && writes > writeFailsAfter!) {
      throw StateError('secure store unavailable');
    }
    value = request;
  }
}

final class _MemoryCredentialStore implements SessionCredentialStore {
  _MemoryCredentialStore({this.value, this.writeFails = false});
  StoredNativeSession? value;
  final bool writeFails;
  int writes = 0;
  int? blockWriteAt;
  Completer<void>? writeGate;
  bool clearFails = false;

  @override
  bool get supportsPersistentSecrets => true;

  @override
  Future<void> clear() async {
    if (clearFails) throw StateError('secure store clear unavailable');
    value = null;
  }

  @override
  Future<StoredNativeSession?> read() async => value;

  @override
  Future<void> write(StoredNativeSession session) async {
    writes++;
    if (writes == blockWriteAt) {
      await writeGate!.future;
    }
    if (writeFails) throw StateError('secure store unavailable');
    value = session;
  }
}

final class _FakeIdentityTransport implements IdentityTransportPort {
  _FakeIdentityTransport(this.sessionTransport);
  @override
  final ClientSessionTransport sessionTransport;
  late _MutableClock clock;
  String requestId = _requestId;
  DateTime expiresAt = DateTime.utc(2026, 8, 9, 12, 15);
  IdentityTransportException? exchangeError;
  IdentityTransportException? currentUserError;
  IdentityTransportException? logoutError;
  IdentityTransportException? refreshError;
  IdentityTransportException? startError;
  IdentityTransportException? statusError;
  IdentityTransportException? cancelError;
  SessionGrant? exchangeGrant;
  SessionGrant? refreshGrant;
  CurrentUserView? currentUser;
  List<DeviceSessionView>? deviceSessions;
  Completer<PendingEmailCode>? startGate;
  Completer<SessionGrant>? exchangeGate;
  Completer<void>? cancelGate;
  Completer<SessionGrant>? refreshGate;
  Completer<CurrentUserView>? currentUserGate;
  void Function()? onExchange;
  void Function()? onRefresh;
  int statusCalls = 0;
  int exchangeCalls = 0;
  int logoutCalls = 0;
  int cancelCalls = 0;
  final List<String?> logoutRefreshTokens = <String?>[];
  PendingEmailCode? lastExchange;
  final List<({String email, DeviceDescriptor device})> started = [];
  final List<String?> refreshTokens = <String?>[];

  @override
  Future<PendingEmailCode> requestEmailCode({
    required String email,
    required DeviceDescriptor device,
  }) async {
    started.add((email: email, device: device));
    if (startGate case final gate?) return gate.future;
    if (startError case final error?) throw error;
    expiresAt = clock.value.add(const Duration(minutes: 10));
    return PendingEmailCode(
      requestId: requestId,
      email: email,
      bindingToken: _pollToken,
      createdAt: clock.value,
      expiresAt: expiresAt,
      resendAt: clock.value.add(const Duration(seconds: 60)),
    );
  }

  @override
  Future<SessionGrant> verifyEmailCode({
    required PendingEmailCode request,
    required String code,
  }) async {
    exchangeCalls++;
    lastExchange = request;
    onExchange?.call();
    if (exchangeGate case final gate?) return gate.future;
    if (exchangeError != null) throw exchangeError!;
    return exchangeGrant ?? _grant(clock.value, transport: sessionTransport);
  }

  @override
  Future<SessionGrant> refreshSession({String? refreshToken}) async {
    refreshTokens.add(refreshToken);
    onRefresh?.call();
    if (refreshGate case final gate?) return gate.future;
    if (refreshError case final error?) {
      throw error;
    }
    return refreshGrant ?? _grant(clock.value, transport: sessionTransport);
  }

  @override
  Future<CurrentUserView> getCurrentUser({
    String? accessToken,
    String? csrfToken,
  }) async {
    if (currentUserGate case final gate?) return gate.future;
    if (currentUserError != null) throw currentUserError!;
    return currentUser ??
        _currentUser(clock.value, transport: sessionTransport);
  }

  @override
  Future<void> logout({
    String? accessToken,
    String? refreshToken,
    String? csrfToken,
  }) async {
    logoutCalls++;
    logoutRefreshTokens.add(refreshToken);
    if (logoutError case final error?) {
      throw error;
    }
  }

  @override
  Future<List<DeviceSessionView>> listDeviceSessions({
    String? accessToken,
    String? csrfToken,
  }) async =>
      deviceSessions ??
      <DeviceSessionView>[
        _currentSession(clock.value, transport: sessionTransport),
      ];

  @override
  Future<void> revokeDeviceSession({
    required String sessionId,
    String? accessToken,
    String? csrfToken,
  }) async {}
}

SessionGrant _grant(
  DateTime now, {
  ClientSessionTransport transport = ClientSessionTransport.nativeBearer,
  String sessionId = _sessionId,
  String deviceId = _deviceId,
  String installationId = _deviceId,
  String userId = _userId,
  String? activeHomeId,
  String csrfToken = 'csrf-token',
  bool durable = false,
}) => SessionGrant(
  metadata: SessionMetadata(
    sessionId: sessionId,
    deviceId: deviceId,
    installationId: installationId,
    userId: userId,
    accessExpiresAt: now.add(const Duration(minutes: 15)),
    refreshExpiresAt: durable
        ? null
        : now.add(
            Duration(
              days: transport == ClientSessionTransport.webCookie ? 30 : 60,
            ),
          ),
    idleExpiresAt: durable
        ? null
        : now.add(
            Duration(
              days: transport == ClientSessionTransport.webCookie ? 30 : 60,
            ),
          ),
    refreshIdleTtl: durable
        ? null
        : Duration(
            days: transport == ClientSessionTransport.webCookie ? 30 : 60,
          ),
    transport: transport,
    activeHomeId: activeHomeId,
  ),
  secrets: transport == ClientSessionTransport.webCookie
      ? SessionSecrets(csrfToken: csrfToken)
      : const SessionSecrets(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
        ),
);

CurrentUserView _currentUser(
  DateTime now, {
  ClientSessionTransport transport = ClientSessionTransport.nativeBearer,
  String userId = _userId,
  String sessionId = _sessionId,
  String deviceId = _deviceId,
  String? activeHomeId,
  List<CurrentUserHomeView> homes = const <CurrentUserHomeView>[],
}) => CurrentUserView(
  userId: userId,
  email: 'person@example.com',
  emailVerified: true,
  homes: homes,
  pendingInvitations: const <CurrentUserInvitationView>[],
  platformRoles: const <PlatformRole>{},
  activeHomeId: activeHomeId,
  currentSession: _currentSession(
    now,
    transport: transport,
    sessionId: sessionId,
    deviceId: deviceId,
    activeHomeId: activeHomeId,
  ),
);

DeviceSessionView _currentSession(
  DateTime now, {
  ClientSessionTransport transport = ClientSessionTransport.nativeBearer,
  String sessionId = _sessionId,
  String deviceId = _deviceId,
  String? activeHomeId,
}) => DeviceSessionView(
  id: sessionId,
  deviceId: deviceId,
  deviceName: 'Test device',
  platform: 'linux',
  transport: transport,
  current: true,
  activeHomeId: activeHomeId,
  createdAt: now,
  lastSeenAt: now,
  accessExpiresAt: now.add(const Duration(minutes: 15)),
  refreshExpiresAt: now.add(
    Duration(days: transport == ClientSessionTransport.webCookie ? 30 : 60),
  ),
  idleExpiresAt: now.add(
    Duration(days: transport == ClientSessionTransport.webCookie ? 30 : 60),
  ),
);
