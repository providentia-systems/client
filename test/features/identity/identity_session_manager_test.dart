import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/networking/session_http_client.dart';
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/application/identity_session_manager.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

void main() {
  test('origin client starts a private S256 login request', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    await fixture.manager.requestLoginLink('Person@Example.com');

    final command = fixture.transport.started.single;
    expect(command.email, 'person@example.com');
    expect(command.requestId, _requestId);
    expect(command.pollChallenge, _pollChallenge);
    expect(command.codeChallenge, _codeChallenge);
    expect(command.state, _state);
    expect(command.pollChallenge, isNot(_pollToken));
    expect(command.codeChallenge, isNot(_verifier));
    expect(fixture.pendingStore.value?.pollToken, _pollToken);
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.waitingForLoginLink,
    );
  });

  test('approval on any device is polled and exchanged once', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.manager.requestLoginLink('person@example.com');
    fixture.transport.status = LoginLinkRequestStatus.approved;

    await fixture.manager.pollLoginLinkNow();

    expect(fixture.transport.exchangeCalls, 1);
    expect(fixture.transport.lastExchange?.pollToken, _pollToken);
    expect(fixture.transport.lastExchange?.codeVerifier, _verifier);
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.authenticated,
    );
    expect(fixture.manager.snapshot.currentUser?.email, 'person@example.com');
    expect(fixture.pendingStore.value, isNull);
    expect(fixture.credentials.value?.refreshToken, 'refresh-token');
  });

  test(
    'polls server at local expiry so a late approval is not missed',
    () async {
      final clock = _MutableClock(DateTime.utc(2026, 8, 9, 12));
      final fixture = _Fixture(clock: clock);
      addTearDown(fixture.dispose);
      await fixture.manager.requestLoginLink('person@example.com');
      clock.value = fixture.transport.expiresAt;
      fixture.transport
        ..status = LoginLinkRequestStatus.approved
        ..expiresAt = clock.value.add(const Duration(minutes: 2));

      await fixture.manager.pollLoginLinkNow();

      expect(fixture.transport.statusCalls, 1);
      expect(fixture.transport.exchangeCalls, 1);
      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.authenticated,
      );
    },
  );

  test(
    'lifecycle pause suppresses polling and resume checks immediately',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.manager.requestLoginLink('person@example.com');
      fixture.manager.pauseLoginLinkPolling();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.transport.statusCalls, 0);

      fixture.transport.status = LoginLinkRequestStatus.approved;
      fixture.manager.resumeLoginLinkPolling();
      await fixture.manager.pollLoginLinkNow();

      expect(fixture.transport.statusCalls, 1);
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
      await fixture.manager.requestLoginLink('person@example.com');
      fixture.transport
        ..status = LoginLinkRequestStatus.approved
        ..exchangeError = const IdentityTransportException(
          kind: IdentityFailureKind.network,
          safeMessage: 'Connection lost.',
        );

      await fixture.manager.pollLoginLinkNow();

      expect(fixture.transport.exchangeCalls, 1);
      expect(fixture.pendingStore.value, isNull);
      expect(fixture.manager.snapshot.pendingLoginLink, isNull);
      expect(fixture.manager.snapshot.loginEmail, 'person@example.com');
      expect(
        fixture.manager.snapshot.safeMessage,
        contains('Request a new login link'),
      );
    },
  );

  test(
    'fatal current-user rejection clears and revokes the new grant',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.manager.requestLoginLink('person@example.com');
      fixture.transport
        ..status = LoginLinkRequestStatus.approved
        ..currentUserError = const IdentityTransportException(
          kind: IdentityFailureKind.authentication,
          safeMessage: 'Session rejected.',
        );

      await fixture.manager.pollLoginLinkNow();

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
    await fixture.manager.requestLoginLink('person@example.com');
    fixture.transport
      ..status = LoginLinkRequestStatus.approved
      ..currentUserError = const IdentityTransportException(
        kind: IdentityFailureKind.unavailable,
        safeMessage: 'Unavailable.',
      );

    await fixture.manager.pollLoginLinkNow();

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
    await fixture.manager.requestLoginLink('person@example.com');
    fixture.transport.status = LoginLinkRequestStatus.approved;

    await fixture.manager.pollLoginLinkNow();

    expect(fixture.manager.snapshot.status, IdentitySessionStatus.failure);
    expect(fixture.manager.accessToken, isNull);
    expect(fixture.transport.logoutCalls, 1);
  });

  test(
    'follow-up pending-store failure never strands or leaks the request',
    () async {
      final fixture = _Fixture(pendingWriteFailsAfter: 1);
      addTearDown(fixture.dispose);

      await fixture.manager.requestLoginLink('person@example.com');
      fixture.transport.status = LoginLinkRequestStatus.expired;
      await fixture.manager.pollLoginLinkNow();

      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.loginLinkExpired,
      );
      expect(fixture.manager.snapshot.pendingLoginLink, isNull);
      expect(fixture.manager.snapshot.loginEmail, 'person@example.com');
    },
  );

  test('native restore rotates a 60-day sliding session', () async {
    final fixture = _Fixture(
      stored: StoredNativeSession(
        sessionId: _sessionId,
        deviceId: _deviceId,
        refreshToken: 'old-refresh-token',
      ),
    );
    addTearDown(fixture.dispose);

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

  test('remote logout rejection never restores cleared local state', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.manager.requestLoginLink('person@example.com');
    fixture.transport.status = LoginLinkRequestStatus.approved;
    await fixture.manager.pollLoginLinkNow();
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
      await fixture.manager.requestLoginLink('person@example.com');
      fixture.transport.status = LoginLinkRequestStatus.approved;
      await fixture.manager.pollLoginLinkNow();
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
      await fixture.manager.requestLoginLink('person@example.com');
      fixture.transport.status = LoginLinkRequestStatus.approved;
      await fixture.manager.pollLoginLinkNow();

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
    await fixture.manager.requestLoginLink('person@example.com');
    fixture.transport.status = LoginLinkRequestStatus.approved;
    await fixture.manager.pollLoginLinkNow();
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
    await fixture.manager.requestLoginLink('a@example.com');
    fixture.transport.cancelGate = Completer<void>();

    final cancel = fixture.manager.cancelLoginLink();
    await _until(() => fixture.transport.cancelCalls == 1);
    final startB = fixture.manager.requestLoginLink('b@example.com');
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.requestingLoginLink,
    );
    fixture.transport.cancelGate!.complete();
    await Future.wait<void>(<Future<void>>[cancel, startB.then<void>((_) {})]);

    expect(fixture.manager.snapshot.loginEmail, 'b@example.com');
    expect(fixture.pendingStore.value?.email, 'b@example.com');
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.waitingForLoginLink,
    );
  });

  test('resend preempts an approval exchange already in flight', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.manager.requestLoginLink('a@example.com');
    fixture.transport
      ..status = LoginLinkRequestStatus.approved
      ..exchangeGate = Completer<SessionGrant>();

    final poll = fixture.manager.pollLoginLinkNow();
    await _until(() => fixture.transport.exchangeCalls == 1);
    final resend = fixture.manager.requestLoginLink('b@example.com');
    fixture.transport.exchangeGate!.complete(_grant(fixture.clock.value));
    await Future.wait<void>(<Future<void>>[poll, resend.then<void>((_) {})]);

    expect(fixture.transport.logoutCalls, 1);
    expect(fixture.manager.snapshot.loginEmail, 'b@example.com');
    expect(fixture.pendingStore.value?.email, 'b@example.com');
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.waitingForLoginLink,
    );
  });

  test('late receipt persistence cannot overwrite replacement proof', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.pendingStore
      ..blockWriteAt = 2
      ..writeGate = Completer<void>();

    final startA = fixture.manager.requestLoginLink('a@example.com');
    await _until(() => fixture.pendingStore.writes == 2);
    final startB = fixture.manager.requestLoginLink('b@example.com');
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
      await fixture.manager.requestLoginLink('person@example.com');
      fixture.transport.status = LoginLinkRequestStatus.approved;

      final poll = fixture.manager.pollLoginLinkNow();
      await _until(() => fixture.credentials.writes == 1);
      final logout = fixture.manager.logout();
      // Durable logout does not claim completion until its tombstone is queued
      // behind the in-flight credential write.
      expect(
        fixture.manager.snapshot.status,
        IdentitySessionStatus.exchangingLoginLink,
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
    await fixture.manager.requestLoginLink('person@example.com');
    fixture.transport.status = LoginLinkRequestStatus.approved;

    final poll = fixture.manager.pollLoginLinkNow();
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
        fixture.manager.requestLoginLink('person@example.com'),
        throwsA(isA<IdentityTransportException>()),
      );

      expect(fixture.transport.statusCalls, 0);
      expect(fixture.pendingStore.value, isNull);
      expect(fixture.manager.snapshot.pendingLoginLink, isNull);
    },
  );

  test('exchange rate limit retains approved proof for retry', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.manager.requestLoginLink('person@example.com');
    fixture.transport
      ..status = LoginLinkRequestStatus.approved
      ..exchangeError = const IdentityTransportException(
        kind: IdentityFailureKind.rateLimited,
        safeMessage: 'Wait before trying again.',
      );

    await fixture.manager.pollLoginLinkNow();
    expect(fixture.pendingStore.value, isNotNull);
    expect(
      fixture.manager.snapshot.status,
      IdentitySessionStatus.waitingForLoginLink,
    );

    fixture.transport.exchangeError = null;
    await fixture.manager.pollLoginLinkNow();
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
    await fixture.manager.requestLoginLink('person@example.com');
    final logoutBeforeExchange = fixture.transport.logoutCalls;
    fixture.transport
      ..status = LoginLinkRequestStatus.approved
      ..exchangeError = const IdentityTransportException(
        kind: IdentityFailureKind.network,
        safeMessage: 'Connection lost.',
      );

    await fixture.manager.pollLoginLinkNow();

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

      final request = fixture.manager.requestLoginLink('person@example.com');
      await expectLater(
        request,
        throwsA(isA<IdentityCredentialStoreException>()),
      );
      fixture.pendingStore.writeGate!.complete();
      await _until(() => fixture.pendingStore.value == null);

      expect(fixture.manager.snapshot.pendingLoginLink, isNull);
      expect(fixture.transport.started, isEmpty);
    },
  );

  test('restored pending B wins over retained account A credential', () async {
    final first = _Fixture(
      stored: StoredNativeSession(
        sessionId: _sessionId,
        deviceId: _deviceId,
        refreshToken: 'account-a-refresh',
      ),
    );
    first.transport.refreshError = const IdentityTransportException(
      kind: IdentityFailureKind.network,
      safeMessage: 'Offline.',
    );
    await first.manager.restore();
    first.credentials.clearFails = true;
    await first.manager.requestLoginLink('account-b@example.com');
    final savedPending = first.pendingStore.value;
    final savedCredential = first.credentials.value;
    await first.dispose();

    final second = _Fixture(stored: savedCredential);
    addTearDown(second.dispose);
    second.pendingStore.value = savedPending;
    await second.manager.restore();

    expect(second.transport.refreshTokens, isEmpty);
    expect(second.manager.snapshot.loginEmail, 'account-b@example.com');
    expect(
      second.manager.snapshot.status,
      IdentitySessionStatus.waitingForLoginLink,
    );
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
      ..value = PendingLoginLinkRequest(
        requestId: _requestId,
        email: 'person@example.com',
        pollToken: _pollToken,
        codeVerifier: _verifier,
        state: _state,
        createdAt: DateTime.utc(2026, 8, 9, 12),
        expiresAt: DateTime.utc(2026, 8, 9, 12, 15),
        pollInterval: const Duration(seconds: 30),
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
    first.transport.status = LoginLinkRequestStatus.approved;
    second.transport.status = LoginLinkRequestStatus.approved;
    await Future.wait<void>(<Future<void>>[
      first.manager.restore(),
      second.manager.restore(),
    ]);

    await Future.wait<void>(<Future<void>>[
      first.manager.pollLoginLinkNow(),
      second.manager.pollLoginLinkNow(),
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
    await fixture.manager.requestLoginLink('person@example.com');
    hub.failGrantPublication = true;
    fixture.transport.status = LoginLinkRequestStatus.approved;

    await fixture.manager.pollLoginLinkNow();

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
      await fixture.manager.requestLoginLink('person@example.com');
      fixture.transport.status = LoginLinkRequestStatus.approved;
      await fixture.manager.pollLoginLinkNow();
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
      await fixture.manager.requestLoginLink('person@example.com');
      fixture.transport.status = LoginLinkRequestStatus.approved;
      await fixture.manager.pollLoginLinkNow();
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
    await first.manager.requestLoginLink('person@example.com');
    first.transport.status = LoginLinkRequestStatus.approved;
    await first.manager.pollLoginLinkNow();
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
          kind: BrowserCookieMutationKind.loginLinkExchange,
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
      await fixture.manager.requestLoginLink('person@example.com');
      fixture.transport.status = LoginLinkRequestStatus.approved;

      await fixture.manager.pollLoginLinkNow();

      expect(observedKind, BrowserCookieMutationKind.loginLinkExchange);
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
      await first.manager.requestLoginLink('a@example.com');
      sharedStore
        ..cookieClearGate = Completer<void>()
        ..cookieClearRead = Completer<void>();
      first.transport.status = LoginLinkRequestStatus.approved;
      var firstCompleted = false;
      final firstPoll = first.manager.pollLoginLinkNow().whenComplete(
        () => firstCompleted = true,
      );
      await sharedStore.cookieClearRead!.future;

      final secondStart = second.manager.requestLoginLink('b@example.com');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(firstCompleted, isFalse);
      expect(second.transport.started, isEmpty);
      expect(
        sharedStore.cookieMutation?.kind,
        BrowserCookieMutationKind.loginLinkExchange,
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
      pendingLoginLinkStore: pendingStore,
      loginLinkRequestFactory: _DeterministicRequestFactory(requestId),
      sessionCoordination: sessionCoordination,
      device: DeviceDescriptor(
        id: _deviceId,
        name: 'Test device',
        platform: 'linux',
      ),
      clock: () => this.clock.value,
      defaultPollInterval: const Duration(seconds: 30),
      maximumPollInterval: const Duration(seconds: 30),
      requestTimeout: requestTimeout,
    );
    transport.clock = this.clock;
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

final class _DeterministicRequestFactory implements LoginLinkRequestFactory {
  const _DeterministicRequestFactory(this.requestId);

  final String requestId;

  @override
  String challenge(String secret) =>
      secret == _pollToken ? _pollChallenge : _codeChallenge;

  @override
  PendingLoginLinkRequest create({
    required String email,
    required DateTime createdAt,
    required DateTime expiresAt,
    required Duration pollInterval,
  }) => PendingLoginLinkRequest(
    requestId: requestId,
    email: email,
    pollToken: _pollToken,
    codeVerifier: _verifier,
    state: _state,
    createdAt: createdAt,
    expiresAt: expiresAt,
    pollInterval: pollInterval,
  );
}

final class _MemoryPendingStore implements PendingLoginLinkStore {
  _MemoryPendingStore({this.writeFailsAfter});
  final int? writeFailsAfter;
  PendingLoginLinkRequest? value;
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
  Future<void> clear({PendingLoginLinkRequest? request}) async {
    if (request != null && value?.requestId != request.requestId) return;
    if (clearFails) throw StateError('secure store clear unavailable');
    value = null;
  }

  @override
  Future<void> invalidate(PendingLoginLinkRequest request) async {
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
  Future<PendingLoginLinkRequest?> read() async => value;

  @override
  Future<void> write(
    PendingLoginLinkRequest request, {
    required bool activate,
  }) async {
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
  LoginLinkRequestStatus status = LoginLinkRequestStatus.pending;
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
  Completer<LoginLinkStartReceipt>? startGate;
  Completer<LoginLinkStatusView>? statusGate;
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
  PendingLoginLinkRequest? lastExchange;
  final List<LoginLinkStartCommand> started = <LoginLinkStartCommand>[];
  final List<String?> refreshTokens = <String?>[];

  @override
  Future<LoginLinkStartReceipt> startLoginLink(
    LoginLinkStartCommand command,
  ) async {
    started.add(command);
    if (startGate case final gate?) return gate.future;
    if (startError case final error?) throw error;
    expiresAt = clock.value.add(const Duration(minutes: 15));
    return LoginLinkStartReceipt(
      requestId: command.requestId,
      expiresAt: expiresAt,
      pollInterval: const Duration(seconds: 30),
    );
  }

  @override
  Future<LoginLinkStatusView> getLoginLinkStatus({
    required String requestId,
    required String pollToken,
  }) async {
    statusCalls++;
    if (statusGate case final gate?) return gate.future;
    if (statusError case final error?) throw error;
    return LoginLinkStatusView(
      requestId: requestId,
      status: status,
      expiresAt: expiresAt,
      approvedAt: status == LoginLinkRequestStatus.approved
          ? clock.value
          : null,
    );
  }

  @override
  Future<SessionGrant> exchangeLoginLink({
    required PendingLoginLinkRequest request,
  }) async {
    exchangeCalls++;
    lastExchange = request;
    onExchange?.call();
    if (exchangeGate case final gate?) return gate.future;
    if (exchangeError != null) throw exchangeError!;
    return exchangeGrant ?? _grant(clock.value, transport: sessionTransport);
  }

  @override
  Future<void> cancelLoginLink({
    required String requestId,
    required String pollToken,
  }) async {
    cancelCalls++;
    if (cancelGate case final gate?) await gate.future;
    if (cancelError case final error?) throw error;
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
  String userId = _userId,
  String? activeHomeId,
  String csrfToken = 'csrf-token',
}) => SessionGrant(
  metadata: SessionMetadata(
    sessionId: sessionId,
    deviceId: deviceId,
    userId: userId,
    accessExpiresAt: now.add(const Duration(minutes: 15)),
    refreshExpiresAt: now.add(
      Duration(days: transport == ClientSessionTransport.webCookie ? 30 : 60),
    ),
    idleExpiresAt: now.add(
      Duration(days: transport == ClientSessionTransport.webCookie ? 30 : 60),
    ),
    refreshIdleTtl: Duration(
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
