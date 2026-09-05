import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:providentia/core/networking/session_http_client.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_server_credential_provisioning.dart';
import 'package:providentia/features/ai_integration/infrastructure/sanitizing_image_media_preparer.dart';
import 'package:providentia/features/homes/application/home_ports.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/infrastructure/api11_home_transport.dart';
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/application/identity_session_manager.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia/features/identity/infrastructure/api11_identity_transport.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test(
    'email code request binds the originating application and installation',
    () async {
      late Map<String, Object?> body;
      final transport = Api11IdentityTransport(
        _client((request) async {
          expect(request.url.path, '/api/v1/auth/email-codes');
          body = jsonDecode(request.body) as Map<String, Object?>;
          return _json(<String, Object?>{
            'bindingToken': _pollToken,
            'challengeId': _requestId,
            'expiresAt': '2026-08-09T12:15:00Z',
            'resendAfterSeconds': 60,
          }, 202);
        }),
        sessionTransport: ClientSessionTransport.nativeBearer,
      );

      final receipt = await transport.requestEmailCode(
        email: 'person@example.com',
        device: DeviceDescriptor(
          id: _installationId,
          name: 'Test phone',
          platform: 'android',
        ),
      );

      expect(body['installationId'], _installationId);
      expect(body, isNot(contains('pollToken')));
      expect(body, isNot(contains('codeVerifier')));
      expect(receipt.requestId, _requestId);
      expect(receipt.bindingToken, _pollToken);
      expect(
        receipt.resendAt.difference(receipt.createdAt),
        const Duration(seconds: 60),
      );
    },
  );

  test(
    'email code conflict is reported without revealing credentials',
    () async {
      final transport = Api11IdentityTransport(
        _client(
          (_) async => _problem(409, 'Request identifier already exists.'),
        ),
        sessionTransport: ClientSessionTransport.nativeBearer,
      );

      await expectLater(
        transport.requestEmailCode(
          email: 'person@example.com',
          device: DeviceDescriptor(
            id: _deviceId,
            name: 'Test phone',
            platform: 'android',
          ),
        ),
        throwsA(
          isA<IdentityTransportException>().having(
            (error) => error.kind,
            'kind',
            IdentityFailureKind.conflict,
          ),
        ),
      );
    },
  );

  test('native exchange maps sliding session metadata and secrets', () async {
    late Map<String, Object?> body;
    final transport = Api11IdentityTransport(
      _client((request) async {
        expect(request.url.path, '/api/v1/auth/email-codes/verify');
        body = jsonDecode(request.body) as Map<String, Object?>;
        return _json(_nativeSessionJson(), 200);
      }),
      sessionTransport: ClientSessionTransport.nativeBearer,
    );

    final grant = await transport.verifyEmailCode(
      request: _pending(),
      code: '12345678',
    );

    expect(body, <String, Object?>{
      'bindingToken': _pollToken,
      'challengeId': _requestId,
      'code': '12345678',
    });
    expect(grant.metadata.refreshIdleTtl, const Duration(days: 60));
    expect(grant.metadata.idleExpiresAt, DateTime.utc(2026, 10, 8, 12));
    expect(grant.metadata.deviceId, _deviceId);
    expect(grant.metadata.installationId, _installationId);
    expect(grant.secrets.refreshToken, 'refresh-secret');
  });

  test(
    'durable exchange maps null expiry to a session without a ceiling',
    () async {
      final transport = Api11IdentityTransport(
        _client(
          (_) async => _json(<String, Object?>{
            ..._nativeSessionJson(),
            'refreshExpiresAt': null,
            'idleExpiresAt': null,
            'refreshIdleTtlSeconds': null,
          }, 200),
        ),
        sessionTransport: ClientSessionTransport.nativeBearer,
      );

      final grant = await transport.verifyEmailCode(
        request: _pending(),
        code: '12345678',
      );

      expect(grant.metadata.refreshExpiresAt, isNull);
      expect(grant.metadata.idleExpiresAt, isNull);
      expect(grant.metadata.refreshIdleTtl, isNull);
      expect(grant.metadata.isDurable, isTrue);
      expect(grant.metadata.isExpiredAt(DateTime.utc(2036, 8, 9, 12)), isFalse);
      expect(grant.metadata.accessExpiresAt, DateTime.utc(2026, 8, 9, 12, 15));
      expect(grant.secrets.refreshToken, 'refresh-secret');
    },
  );

  test('session grant missing its expiry declaration is rejected', () async {
    for (final omittedField in <String>[
      'refreshExpiresAt',
      'idleExpiresAt',
      'refreshIdleTtlSeconds',
    ]) {
      final transport = Api11IdentityTransport(
        _client(
          (_) async => _json(
            <String, Object?>{..._nativeSessionJson()}..remove(omittedField),
            200,
          ),
        ),
        sessionTransport: ClientSessionTransport.nativeBearer,
      );

      await expectLater(
        transport.verifyEmailCode(request: _pending(), code: '12345678'),
        throwsA(
          isA<IdentityTransportException>().having(
            (error) => error.kind,
            'kind',
            IdentityFailureKind.validation,
          ),
        ),
        reason: omittedField,
      );
    }
  });

  test('device session list parses durable and bounded entries', () async {
    final transport = Api11IdentityTransport(
      _client(
        (_) async => _json(<String, Object?>{
          'data': <Object?>[
            _deviceSessionJson(),
            <String, Object?>{
              ..._deviceSessionJson(),
              'id': _secondSessionId,
              'current': false,
              'refreshExpiresAt': null,
              'idleExpiresAt': null,
            },
          ],
        }, 200),
      ),
      sessionTransport: ClientSessionTransport.nativeBearer,
    );

    final sessions = await transport.listDeviceSessions(
      accessToken: 'access-secret',
    );

    final bounded = sessions.singleWhere((session) => session.current);
    final durable = sessions.singleWhere((session) => !session.current);
    expect(bounded.isDurable, isFalse);
    expect(bounded.idleExpiresAt, DateTime.utc(2026, 10, 8, 12));
    expect(durable.isDurable, isTrue);
    expect(durable.refreshExpiresAt, isNull);
    expect(durable.idleExpiresAt, isNull);
    expect(durable.isActiveAt(DateTime.utc(2036, 8, 9, 12)), isTrue);
  });

  test('device session missing its expiry declaration is rejected', () async {
    final transport = Api11IdentityTransport(
      _client(
        (_) async => _json(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{..._deviceSessionJson()}..remove('idleExpiresAt'),
          ],
        }, 200),
      ),
      sessionTransport: ClientSessionTransport.nativeBearer,
    );

    await expectLater(
      transport.listDeviceSessions(accessToken: 'access-secret'),
      throwsA(
        isA<IdentityTransportException>().having(
          (error) => error.kind,
          'kind',
          IdentityFailureKind.validation,
        ),
      ),
    );
  });

  test('web grant without required CSRF token is rejected safely', () async {
    final transport = Api11IdentityTransport(
      _client(
        (_) async => _json(
          <String, Object?>{..._webSessionJson()}..remove('csrfToken'),
          200,
        ),
      ),
      sessionTransport: ClientSessionTransport.webCookie,
    );

    await expectLater(
      transport.verifyEmailCode(request: _pending(), code: '12345678'),
      throwsA(
        isA<IdentityTransportException>().having(
          (error) => error.kind,
          'kind',
          IdentityFailureKind.validation,
        ),
      ),
    );
  });

  test(
    'web grant rejects bearer credentials even when CSRF is present',
    () async {
      final transport = Api11IdentityTransport(
        _client(
          (_) async => _json(<String, Object?>{
            ..._webSessionJson(),
            'accessToken': 'should-never-cross-the-browser-boundary',
            'refreshToken': 'should-never-cross-the-browser-boundary',
          }, 200),
        ),
        sessionTransport: ClientSessionTransport.webCookie,
      );

      await expectLater(
        transport.verifyEmailCode(request: _pending(), code: '12345678'),
        throwsA(
          isA<IdentityTransportException>().having(
            (error) => error.kind,
            'kind',
            IdentityFailureKind.validation,
          ),
        ),
      );
    },
  );

  test(
    'real client failures are normalized at the identity boundary',
    () async {
      final transport = Api11IdentityTransport(
        _client((request) async => throw http.ClientException('offline')),
        sessionTransport: ClientSessionTransport.nativeBearer,
      );

      await expectLater(
        transport.requestEmailCode(
          email: 'person@example.com',
          device: DeviceDescriptor(
            id: _deviceId,
            name: 'Test phone',
            platform: 'android',
          ),
        ),
        throwsA(
          isA<IdentityTransportException>().having(
            (error) => error.kind,
            'kind',
            IdentityFailureKind.network,
          ),
        ),
      );
    },
  );

  test('identity timeout aborts the underlying HTTP request', () async {
    final client = _AbortObservingClient();
    final transport = Api11IdentityTransport(
      ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: client,
      ),
      sessionTransport: ClientSessionTransport.webCookie,
      networkTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      transport.logout(csrfToken: 'csrf-secret'),
      throwsA(
        isA<IdentityTransportException>().having(
          (error) => error.kind,
          'kind',
          IdentityFailureKind.network,
        ),
      ),
    );
    await client.abortObserved.future.timeout(const Duration(seconds: 1));
  });

  test(
    'native logout uses rotating refresh credential as possession proof',
    () async {
      late http.Request captured;
      final transport = Api11IdentityTransport(
        _client((request) async {
          captured = request;
          return http.Response('', 204);
        }),
        sessionTransport: ClientSessionTransport.nativeBearer,
      );

      await transport.logout(
        accessToken: 'expired-access',
        refreshToken: 'rotating-refresh-credential-000000000000000000000',
      );

      expect(captured.url.path, '/api/v1/auth/logout');
      expect(captured.headers['Authorization'], 'Bearer expired-access');
      expect(jsonDecode(captured.body), <String, Object?>{
        'refreshToken': 'rotating-refresh-credential-000000000000000000000',
      });
    },
  );

  test(
    'web logout uses cookie transport and CSRF without a token body',
    () async {
      late http.Request captured;
      final transport = Api11IdentityTransport(
        _client((request) async {
          captured = request;
          return http.Response('', 204);
        }),
        sessionTransport: ClientSessionTransport.webCookie,
      );

      await transport.logout(csrfToken: 'csrf-secret');

      expect(captured.headers['X-CSRF-Token'], 'csrf-secret');
      expect(captured.body, isEmpty);
      expect(captured.headers, isNot(contains('Authorization')));
    },
  );

  for (final scenario in <({int status, IdentityFailureKind kind})>[
    (status: 401, kind: IdentityFailureKind.authentication),
    (status: 403, kind: IdentityFailureKind.forbidden),
  ]) {
    test('logout maps ${scenario.status} for bounded local cleanup', () async {
      final transport = Api11IdentityTransport(
        _client((_) async => _problem(scenario.status, 'Logout rejected.')),
        sessionTransport: ClientSessionTransport.nativeBearer,
      );

      await expectLater(
        transport.logout(
          refreshToken: 'rotating-refresh-credential-000000000000000000000',
        ),
        throwsA(
          isA<IdentityTransportException>().having(
            (error) => error.kind,
            'kind',
            scenario.kind,
          ),
        ),
      );
    });
  }

  test(
    'current-user bootstrap includes homes, role, and pending invitations',
    () async {
      final transport = Api11IdentityTransport(
        _client((request) async {
          expect(request.headers['Authorization'], 'Bearer access-secret');
          return _json(_currentUserJson(), 200);
        }),
        sessionTransport: ClientSessionTransport.nativeBearer,
      );

      final current = await transport.getCurrentUser(
        accessToken: 'access-secret',
      );

      expect(current.homes.single.name, 'My home');
      expect(current.homes.single.role, 'owner');
      expect(current.pendingInvitations.single.homeName, 'Shared pantry');
      expect(current.isPlatformAdministrator, isTrue);
      expect(current.platformRoles, contains(PlatformRole.billingOperator));
      expect(current.currentSession.current, isTrue);
    },
  );

  test('malformed nullable account fields fail closed', () async {
    final transport = Api11IdentityTransport(
      _client(
        (_) async => _json(<String, Object?>{
          ..._currentUserJson(),
          'displayName': 42,
        }, 200),
      ),
      sessionTransport: ClientSessionTransport.nativeBearer,
    );

    await expectLater(
      transport.getCurrentUser(accessToken: 'access-secret'),
      throwsA(
        isA<IdentityTransportException>().having(
          (error) => error.kind,
          'kind',
          IdentityFailureKind.validation,
        ),
      ),
    );
  });

  test(
    'recipient invitation 404 never masquerades as revoked active home',
    () async {
      final homes = Api11HomeTransport(
        _client((_) async => _problem(404, 'Invitation not found.')),
      );

      await expectLater(
        homes.acceptPendingInvitation(
          invitationId: _invitationId,
          expectedRevision: 1,
        ),
        throwsA(
          isA<HomeTransportException>()
              .having((error) => error.kind, 'kind', HomeFailureKind.conflict)
              .having((error) => error.homeId, 'homeId', isNull),
        ),
      );
    },
  );

  test(
    'target member and sent-invitation 404s are resource conflicts',
    () async {
      final homes = Api11HomeTransport(
        _client((_) async => _problem(404, 'Target not found.')),
      );

      for (final operation in <Future<void>>[
        homes.changeMembershipRole(
          homeId: _homeId,
          userId: _userId,
          role: HomeRole.viewer,
          expectedRevision: 1,
        ),
        homes.revokeInvitation(
          homeId: _homeId,
          invitationId: _invitationId,
          expectedRevision: 1,
        ),
      ]) {
        await expectLater(
          operation,
          throwsA(
            isA<HomeTransportException>()
                .having((error) => error.kind, 'kind', HomeFailureKind.conflict)
                .having((error) => error.homeId, 'homeId', _homeId),
          ),
        );
      }
    },
  );

  test('active-home switch 404 still proves revoked home access', () async {
    final homes = Api11HomeTransport(
      _client((_) async => _problem(404, 'Home not found.')),
    );

    await expectLater(
      homes.switchActiveHome(_homeId),
      throwsA(
        isA<HomeTransportException>().having(
          (error) => error.kind,
          'kind',
          HomeFailureKind.membershipRevoked,
        ),
      ),
    );
  });

  test(
    'home settings update carries expected revision and published fields',
    () async {
      late Map<String, Object?> body;
      final homes = Api11HomeTransport(
        _client((request) async {
          expect(request.url.path, '/api/v1/homes/$_homeId');
          expect(request.method, 'PATCH');
          body = jsonDecode(request.body) as Map<String, Object?>;
          return _json(_homeJson(name: 'Family pantry', revision: 2), 200);
        }),
      );

      final updated = await homes.updateHome(
        homeId: _homeId,
        name: 'Family pantry',
        locale: 'en-NA',
        currency: 'NAD',
        timezone: 'Africa/Windhoek',
        expectedRevision: 1,
      );

      expect(body['expectedRevision'], 1);
      expect(body['name'], 'Family pantry');
      expect(updated.revision, 2);
    },
  );

  test('home adapter maps multi-home roles and default settings', () async {
    final homes = Api11HomeTransport(
      _client(
        (_) async => _json(<String, Object?>{
          'data': <Object?>[
            _homeJson(name: 'Windhoek home', role: 'manager', revision: 3),
            _homeJson(id: _secondHomeId, name: 'Family home', role: 'viewer'),
          ],
        }, 200),
      ),
    );

    final result = await homes.listHomes();

    expect(result, hasLength(2));
    expect(result.first.role, HomeRole.manager);
    expect(result.last.role, HomeRole.viewer);
    expect(result.first.timezone, 'Africa/Windhoek');
  });

  test(
    'cloud credential is sent once to the home-scoped write-only vault',
    () async {
      final client = _client((request) async {
        expect(
          request.url.path,
          '/api/v1/homes/$_homeId/ai/credentials/openai',
        );
        expect(jsonDecode(request.body), <String, Object?>{
          'credential': 'sk-test-1234567890',
        });
        return _json(<String, Object?>{
          'provider': 'openai',
          'configured': true,
          'lastFour': '7890',
        }, 200);
      });

      await Api17ServerCredentialProvisioning(client).replaceCredential(
        homeId: _homeId,
        profileId: 'openai',
        secret: 'sk-test-1234567890',
      );
    },
  );

  test(
    'image preparation re-encodes bounded consent bytes and cleans them',
    () async {
      final sourceImage = image.Image(width: 8, height: 4)
        ..setPixelRgb(0, 0, 10, 20, 30);
      final bytes = image.encodePng(sourceImage);
      final asset = AiMediaAsset(
        id: 'image-1',
        homeId: _homeId,
        localReference: 'registered://image.png',
        purpose: AiExtractionKind.receipt,
        mimeType: 'image/png',
        byteLength: bytes.length,
        createdAt: DateTime.utc(2026, 8, 4),
      );
      final sources = RegisteredMediaSourceReader()..register(asset, bytes);
      final store = MemoryEphemeralPreparedMediaStore();
      final preparer = SanitizingImageMediaPreparer(
        sources: sources,
        prepared: store,
      );

      final batch = await preparer.prepare(
        homeId: _homeId,
        purpose: AiExtractionKind.receipt,
        assets: <AiMediaAsset>[asset],
      );
      final preparedBytes = await store.read(batch.media.single);

      expect(batch.media.single.mimeType, 'image/jpeg');
      expect(image.decodeJpg(preparedBytes), isNotNull);
      await preparer.discard(batch);
      await expectLater(store.read(batch.media.single), throwsStateError);
    },
  );

  test('authenticated client restores and adds bearer access', () async {
    final transport = _RestoringIdentityTransport();
    final manager = IdentitySessionManager(
      transport: transport,
      credentialStore: _MemoryCredentialStore(),
      pendingEmailCodeStore: _MemoryPendingStore(),

      device: DeviceDescriptor(
        id: _deviceId,
        name: 'Test device',
        platform: 'android',
      ),
      clock: () => DateTime.utc(2026, 8, 9, 12),
    );
    await manager.restore();
    final client = SessionHttpClient(
      inner: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer access-secret');
        return http.Response('{}', 200);
      }),
      sessions: manager,
    );

    final response = await client.get(
      Uri.parse('https://api.example.test/home'),
    );

    expect(response.statusCode, 200);
    expect(transport.refreshCalls, 1);
    client.close();
    await manager.dispose();
  });

  test('authenticated client force-rotates once after a real 401', () async {
    final transport = _RestoringIdentityTransport();
    final manager = IdentitySessionManager(
      transport: transport,
      credentialStore: _MemoryCredentialStore(),
      pendingEmailCodeStore: _MemoryPendingStore(),

      device: DeviceDescriptor(
        id: _deviceId,
        name: 'Test device',
        platform: 'android',
      ),
      clock: () => DateTime.utc(2026, 8, 9, 12),
    );
    await manager.restore();
    var sends = 0;
    final client = SessionHttpClient(
      inner: MockClient((request) async {
        sends++;
        expect(request.headers['Authorization'], 'Bearer access-secret');
        return http.Response('{}', sends == 1 ? 401 : 200);
      }),
      sessions: manager,
    );

    final response = await client.get(
      Uri.parse('https://api.example.test/home'),
    );

    expect(response.statusCode, 200);
    expect(sends, 2);
    expect(transport.refreshCalls, 2);
    client.close();
    await manager.dispose();
  });

  test('authenticated client preserves generated request abortion', () async {
    final transport = _RestoringIdentityTransport();
    final manager = IdentitySessionManager(
      transport: transport,
      credentialStore: _MemoryCredentialStore(),
      pendingEmailCodeStore: _MemoryPendingStore(),

      device: DeviceDescriptor(
        id: _deviceId,
        name: 'Test device',
        platform: 'android',
      ),
      clock: () => DateTime.utc(2026, 8, 9, 12),
    );
    addTearDown(manager.dispose);
    await manager.restore();
    final inner = _AbortObservingClient();
    final client = SessionHttpClient(inner: inner, sessions: manager);
    addTearDown(client.close);
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'PATCH',
      Uri.parse('https://api.example.test/homes/$_homeId'),
      abortTrigger: abort.future,
    )..body = '{}';

    final response = client.send(request);
    await Future<void>.delayed(Duration.zero);
    abort.complete();

    await expectLater(response, throwsA(isA<http.RequestAbortedException>()));
    await inner.abortObserved.future;
  });
}

const _requestId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const _deviceId = '0198a0b1-c2d3-7e4f-8123-456789abcdea';
const _installationId = '0198a0b1-c2d3-7e4f-8123-456789abcd00';
const _sessionId = '0198a0b1-c2d3-7e4f-8123-456789abcdeb';
const _secondSessionId = '0198a0b1-c2d3-7e4f-8123-456789abcd01';
const _userId = '0198a0b1-c2d3-7e4f-8123-456789abcdec';
const _homeId = '0198a0b1-c2d3-7e4f-8123-456789abcded';
const _secondHomeId = '0198a0b1-c2d3-7e4f-8123-456789abcdee';
const _invitationId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const _pollToken = 'poll-token-000000000000000000000000000000000';
const _verifier =
    'code-verifier-000000000000000000000000000000000000000000000000';
const _state = 'login-state-000000000000000000000000000000000';
const _challengeA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _challengeB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

ProvidentiaApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => ProvidentiaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(handler),
);

http.Response _json(Map<String, Object?> body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{'content-type': 'application/json'},
);

http.Response _problem(int status, String detail) => _json(<String, Object?>{
  'type': 'about:blank',
  'title': 'Request failed',
  'status': status,
  'detail': detail,
  'requestId': 'test-request',
}, status);

PendingEmailCode _pending() => PendingEmailCode(
  requestId: _requestId,
  email: 'person@example.com',
  createdAt: DateTime.utc(2026, 8, 9, 12),
  expiresAt: DateTime.utc(2026, 8, 9, 12, 15),
  bindingToken: _pollToken,
  resendAt: (DateTime.utc(2026, 8, 9, 12)).add(const Duration(seconds: 60)),
);

Map<String, Object?> _nativeSessionJson() => <String, Object?>{
  'sessionId': _sessionId,
  'deviceId': _deviceId,
  'installationId': _installationId,
  'userId': _userId,
  'accessExpiresAt': '2026-08-09T12:15:00Z',
  'refreshExpiresAt': '2026-10-08T12:00:00Z',
  'idleExpiresAt': '2026-10-08T12:00:00Z',
  'refreshIdleTtlSeconds': 5184000,
  'transport': 'native',
  'activeHomeId': _homeId,
  'accessToken': 'access-secret',
  'refreshToken': 'refresh-secret',
};

Map<String, Object?> _webSessionJson() => <String, Object?>{
  'sessionId': _sessionId,
  'deviceId': _deviceId,
  'installationId': _installationId,
  'userId': _userId,
  'accessExpiresAt': '2026-08-09T12:15:00Z',
  'refreshExpiresAt': '2026-09-08T12:00:00Z',
  'idleExpiresAt': '2026-09-08T12:00:00Z',
  'refreshIdleTtlSeconds': 2592000,
  'transport': 'web',
  'activeHomeId': null,
  'csrfToken': 'csrf-secret',
};

Map<String, Object?> _currentUserJson() => <String, Object?>{
  'userId': _userId,
  'profile': <String, Object?>{},
  'email': 'person@example.com',
  'emailVerified': true,
  'activeHomeId': _homeId,
  'homes': <Object?>[_homeJson()],
  'pendingInvitations': <Object?>[
    <String, Object?>{
      'id': _invitationId,
      'homeId': _secondHomeId,
      'homeName': 'Shared pantry',
      'inviterUserId': _userId,
      'inviterDisplayName': 'Owner',
      'role': 'member',
      'status': 'pending',
      'expiresAt': '2026-08-20T12:00:00Z',
      'revision': 1,
    },
  ],
  'platformRoles': <Object?>['platform_administrator', 'billing_operator'],
  'currentSession': _deviceSessionJson(),
};

Map<String, Object?> _deviceSessionJson() => <String, Object?>{
  'id': _sessionId,
  'deviceId': _deviceId,
  'deviceName': 'Test phone',
  'platform': 'android',
  'transport': 'native',
  'current': true,
  'activeHomeId': _homeId,
  'createdAt': '2026-08-01T12:00:00Z',
  'lastSeenAt': '2026-08-09T12:00:00Z',
  'accessExpiresAt': '2026-08-09T12:15:00Z',
  'refreshExpiresAt': '2026-10-08T12:00:00Z',
  'idleExpiresAt': '2026-10-08T12:00:00Z',
  'revokedAt': null,
};

Map<String, Object?> _homeJson({
  String id = _homeId,
  String name = 'My home',
  String role = 'owner',
  int revision = 1,
}) => <String, Object?>{
  'id': id,
  'name': name,
  'defaultLocale': 'en-NA',
  'defaultCurrency': 'NAD',
  'defaultTimezone': 'Africa/Windhoek',
  'role': role,
  'revision': revision,
};

final class _MemoryCredentialStore implements SessionCredentialStore {
  StoredNativeSession? session = StoredNativeSession(
    sessionId: _sessionId,
    deviceId: _deviceId,
    refreshToken: 'refresh-0',
  );
  @override
  bool get supportsPersistentSecrets => true;
  @override
  Future<void> clear() async => session = null;
  @override
  Future<StoredNativeSession?> read() async => session;
  @override
  Future<void> write(StoredNativeSession session) async =>
      this.session = session;
}

final class _AbortObservingClient extends http.BaseClient {
  final Completer<void> abortObserved = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abortable = request as http.Abortable;
    await abortable.abortTrigger;
    if (!abortObserved.isCompleted) abortObserved.complete();
    throw http.RequestAbortedException(request.url);
  }
}

final class _MemoryPendingStore implements PendingEmailCodeStore {
  bool logoutIntent = false;
  BrowserCookieMutationJournal? cookieMutation;

  @override
  Future<void> clear({PendingEmailCode? request}) async {}

  @override
  Future<void> invalidate(PendingEmailCode request) async {}

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
    if (journal == null || cookieMutation?.operationId == journal.operationId) {
      cookieMutation = null;
    }
  }

  @override
  Future<PendingEmailCode?> read() async => null;
  @override
  Future<void> write(
    PendingEmailCode request, {
    required bool activate,
  }) async {}
}

final class _RestoringIdentityTransport implements IdentityTransportPort {
  int refreshCalls = 0;
  @override
  ClientSessionTransport get sessionTransport =>
      ClientSessionTransport.nativeBearer;
  @override
  Future<SessionGrant> refreshSession({String? refreshToken}) async {
    refreshCalls++;
    return SessionGrant(
      metadata: SessionMetadata(
        sessionId: _sessionId,
        deviceId: _deviceId,
        userId: _userId,
        accessExpiresAt: DateTime.utc(2026, 8, 9, 13),
        refreshExpiresAt: DateTime.utc(2026, 10, 8, 12),
        idleExpiresAt: DateTime.utc(2026, 10, 8, 12),
        refreshIdleTtl: const Duration(days: 60),
        transport: ClientSessionTransport.nativeBearer,
      ),
      secrets: const SessionSecrets(
        accessToken: 'access-secret',
        refreshToken: 'refresh-secret',
      ),
    );
  }

  @override
  Future<CurrentUserView> getCurrentUser({
    String? accessToken,
    String? csrfToken,
  }) async => CurrentUserView(
    userId: _userId,
    email: 'person@example.com',
    emailVerified: true,
    homes: const <CurrentUserHomeView>[],
    pendingInvitations: const <CurrentUserInvitationView>[],
    platformRoles: const <PlatformRole>{},
    currentSession: _deviceSession(DateTime.utc(2026, 8, 9, 12)),
  );
  @override
  Future<PendingEmailCode> requestEmailCode({
    required String email,
    required DeviceDescriptor device,
  }) => throw UnimplementedError();

  @override
  Future<SessionGrant> verifyEmailCode({
    required PendingEmailCode request,
    required String code,
  }) => throw UnimplementedError();

  @override
  Future<void> logout({
    String? accessToken,
    String? refreshToken,
    String? csrfToken,
  }) async {}
  @override
  Future<List<DeviceSessionView>> listDeviceSessions({
    String? accessToken,
    String? csrfToken,
  }) async => const <DeviceSessionView>[];
  @override
  Future<void> revokeDeviceSession({
    required String sessionId,
    String? accessToken,
    String? csrfToken,
  }) async {}
}

DeviceSessionView _deviceSession(DateTime now) => DeviceSessionView(
  id: _sessionId,
  deviceId: _deviceId,
  deviceName: 'Test device',
  platform: 'android',
  transport: ClientSessionTransport.nativeBearer,
  current: true,
  createdAt: now,
  lastSeenAt: now,
  accessExpiresAt: now.add(const Duration(minutes: 15)),
  refreshExpiresAt: now.add(const Duration(days: 60)),
  idleExpiresAt: now.add(const Duration(days: 60)),
);
