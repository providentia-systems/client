import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/app/production_bootstrap_app.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/networking/session_http_client.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/session_bound_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/homes/application/home_session_manager.dart';
import 'package:providentia/features/homes/infrastructure/api11_home_transport.dart';
import 'package:providentia/features/homes/infrastructure/drift_active_home_store.dart';
import 'package:providentia/features/homes/presentation/homes_controller.dart';
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/application/identity_session_manager.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia/features/identity/infrastructure/api11_identity_transport.dart';
import 'package:providentia_api_client/providentia_api_client.dart' as api;

// This exercises production Dart transport/session/security/persistence paths.
// It is not an encrypted IndexedDB or installed-browser acceptance result.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final sameAccount in <bool>[true, false]) {
    test(
      'legacy browser reauthentication preserves saved work for '
      '${sameAccount ? 'the original account' : 'a different account'}',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'providentia-web-transition-',
        );
        final file = File('${directory.path}/synthetic.sqlite');
        var database = AppDatabase(NativeDatabase(file));
        var local = DriftLocalSyncRepository(database);
        final now = DateTime.now().toUtc();
        for (var i = 0; i < 2; i++) {
          await local.commitLocalMutation(
            LocalMutation(
              operationId: _id(20 + i),
              deviceId: _device,
              originatingAccountId: _account,
              homeId: _home,
              entityType: 'inventory-location',
              entityId: _id(30 + i),
              operationType: 'inventory.location.create',
              clientTimestamp: now.add(Duration(microseconds: i)),
              payloadSchemaVersion: 1,
              payload: <String, Object?>{
                'name': 'Synthetic shelf $i',
                'kind': 'pantry',
              },
            ),
          );
        }
        await local.applyPushResults(
          results: <PushOperationResult>[
            PushOperationResult(
              operationId: _id(20),
              kind: PushResultKind.authorizationFailure,
              code: 'device_binding_mismatch',
            ),
          ],
          now: now,
          retryPolicy: RetryPolicy(),
        );
        await DriftActiveHomeStore(database).write(_home);
        final savedRecords = await _homeRecords(database);
        final savedOperations = await database
            .select(database.clientOperations)
            .get();

        final server = _BrowserSessionServer(
          now,
          account: sameAccount ? _account : _otherAccount,
          device: sameAccount ? _device : _otherDevice,
        );
        final raw = MockClient(server.send);
        final identityApi = api.ProvidentiaApiClient(
          baseUri: Uri.parse('https://synthetic.example.test'),
          httpClient: raw,
        );
        final identity = IdentitySessionManager(
          transport: Api11IdentityTransport(
            identityApi,
            sessionTransport: ClientSessionTransport.webCookie,
          ),
          credentialStore: _NoBrowserBearerStore(),
          pendingEmailCodeStore: _PendingStore(),
          device: DeviceDescriptor(
            id: _installation,
            name: 'Synthetic browser',
            platform: 'web',
          ),
          clock: () => now,
        );
        final authorizedTransport = SessionHttpClient(
          inner: raw,
          sessions: identity,
          closeInner: false,
        );
        final authorizedApi = api.ProvidentiaApiClient(
          baseUri: Uri.parse('https://synthetic.example.test'),
          httpClient: authorizedTransport,
        );
        var revocations = 0;
        final homes = HomeSessionManager(
          transport: Api11HomeTransport(authorizedApi),
          activeHomeStore: DriftActiveHomeStore(database),
          onHomeAccessRevoked: (_) => revocations++,
        );
        final controller = HomesController(homes);
        var protectedClears = 0;
        final boundary = ProductionSessionSecurityBoundary(
          rootNavigatorKey: GlobalKey<NavigatorState>(),
          workspaceNavigatorKey: GlobalKey<NavigatorState>(),
          homesController: controller,
          clearProtectedRouteState: () => protectedClears++,
        );
        final subscription = identity.states.listen(
          boundary.handleIdentitySession,
        );
        try {
          // The server has a legacy cookie namespace only. The new namespace
          // requires sign-in; this is authentication loss, never home revocation.
          await identity.restore();
          expect(identity.snapshot.isAuthenticated, isFalse);
          expect(server.homeownerSession, isFalse);
          expect(server.legacyCookie, 'synthetic-old-namespace-proof');
          expect(protectedClears, greaterThan(0));
          expect(revocations, 0);
          expect(await _homeRecords(database), savedRecords);
          expect(
            await database.select(database.clientOperations).get(),
            savedOperations,
          );

          await identity.requestEmailCode('acceptance@example.test');
          await identity.verifyEmailCode('12345678');
          expect(identity.snapshot.isAuthenticated, isTrue);
          await homes.load(sessionActiveHomeId: _home);
          expect(homes.snapshot.activeHome?.id, _home);
          expect(server.legacyCookie, 'synthetic-old-namespace-proof');
          expect(server.headers.every((value) => value == 'homeowner'), isTrue);
          expect(server.pushes, 0);
          expect(revocations, 0);
          expect(await _homeRecords(database), savedRecords);
          expect(
            await database.select(database.clientOperations).get(),
            savedOperations,
          );

          final operation = (await local.recoveryOperations(
            homeId: _home,
          )).first.operation;
          final binding = SessionBoundSyncGateway(
            delegate: GeneratedSyncGateway(authorizedApi),
            homeId: _home,
            deviceId: identity.snapshot.session!.deviceId,
            accountId: identity.snapshot.session!.userId,
            isCurrent: () => identity.snapshot.isAuthenticated,
          );
          if (sameAccount) {
            expect(
              () => binding.validateOperationBinding(operation),
              returnsNormally,
            );
          } else {
            await expectLater(
              binding.push(
                homeId: _home,
                lastPulledCursor: null,
                operations: <PendingClientOperation>[operation],
              ),
              throwsA(isA<BindingSyncException>()),
            );
          }
          expect(
            server.pushes,
            0,
            reason: 'Sign-in must not rewrite or replay old queued work.',
          );
        } finally {
          await subscription.cancel();
          controller.dispose();
          await homes.dispose();
          await identity.dispose();
          authorizedTransport.close();
          raw.close();
        }
        await database.close();
        database = AppDatabase(NativeDatabase(file));
        local = DriftLocalSyncRepository(database);
        try {
          expect(await _homeRecords(database), savedRecords);
          expect(
            await database.select(database.clientOperations).get(),
            savedOperations,
          );
          final retained = await local.recoveryOperations(homeId: _home);
          expect(retained.map((entry) => entry.operation.operationId), <String>[
            _id(20),
            _id(21),
          ]);
          expect(
            retained.first.state,
            ClientOperationState.blockedAuthorization,
          );
          expect(retained.first.blockedCode, 'device_binding_mismatch');
          expect(
            retained.every(
              (entry) =>
                  entry.operation.deviceId == _device &&
                  entry.operation.originatingAccountId == _account,
            ),
            isTrue,
          );
        } finally {
          await database.close();
          await directory.delete(recursive: true);
        }
      },
    );
  }
}

Future<List<LocalRecord>> _homeRecords(AppDatabase database) =>
    (database.select(database.localRecords)
          ..where((r) => r.homeId.equals(_home))
          ..orderBy(<OrderingTerm Function(LocalRecords)>[
            (r) => OrderingTerm.asc(r.entityId),
          ]))
        .get();

String _id(int n) => '10000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
const _home = '10000000-0000-4000-8000-000000000001';
const _account = '10000000-0000-4000-8000-000000000002';
const _device = '10000000-0000-4000-8000-000000000003';
const _installation = '10000000-0000-4000-8000-000000000004';
const _session = '10000000-0000-4000-8000-000000000005';
const _otherAccount = '10000000-0000-4000-8000-000000000006';
const _otherDevice = '10000000-0000-4000-8000-000000000007';

final class _BrowserSessionServer {
  _BrowserSessionServer(
    this.now, {
    required this.account,
    required this.device,
  });
  final DateTime now;
  final String account;
  final String device;
  final String legacyCookie = 'synthetic-old-namespace-proof';
  final List<String?> headers = <String?>[];
  bool homeownerSession = false;
  int pushes = 0;

  Future<http.Response> send(http.Request request) async {
    headers.add(request.headers['X-Providentia-Application']);
    expect(request.headers['X-Providentia-Application'], 'homeowner');
    expect(request.headers, isNot(contains('Authorization')));
    final path = request.url.path;
    if (path.endsWith('/sync/push')) pushes++;
    if (path == '/api/v1/auth/logout') {
      homeownerSession = false;
      return http.Response('', 204);
    }
    if (path == '/api/v1/auth/email-codes') {
      return _json(<String, Object?>{
        'challengeId': _id(40),
        'bindingToken': 'synthetic-private-bound-proof-01234567890123456789',
        'expiresAt': now.add(const Duration(minutes: 10)).toIso8601String(),
        'resendAfterSeconds': 60,
      }, 202);
    }
    if (path == '/api/v1/auth/email-codes/verify') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['code'], '12345678');
      homeownerSession = true;
      return _json(_grant());
    }
    if (!homeownerSession) {
      return _json(<String, Object?>{
        'type':
            'https://synthetic.example.test/problems/authentication_required',
        'title': 'Sign in required',
        'status': 401,
        'requestId': 'synthetic-auth',
      }, 401);
    }
    if (path == '/api/v1/auth/refresh') return _json(_grant());
    if (path == '/api/v1/me') {
      return _json(<String, Object?>{
        'userId': account,
        'profile': <String, Object?>{},
        'email': 'acceptance@example.test',
        'emailVerified': true,
        'activeHomeId': _home,
        'homes': <Object?>[_homeJson()],
        'pendingInvitations': <Object?>[],
        'platformRoles': <Object?>[],
        'currentSession': <String, Object?>{
          'id': _session,
          'deviceId': device,
          'deviceName': 'Synthetic browser',
          'platform': 'web',
          'transport': 'web',
          'current': true,
          'activeHomeId': _home,
          'createdAt': now.toIso8601String(),
          'lastSeenAt': now.toIso8601String(),
          'accessExpiresAt': now
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'refreshExpiresAt': now
              .add(const Duration(days: 30))
              .toIso8601String(),
          'idleExpiresAt': now.add(const Duration(days: 30)).toIso8601String(),
        },
      });
    }
    if (path == '/api/v1/homes') {
      return _json(<String, Object?>{
        'data': <Object?>[_homeJson()],
      });
    }
    if (path == '/api/v1/me/home-invitations') {
      return _json(<String, Object?>{'data': <Object?>[]});
    }
    if (path.startsWith('/api/v1/homes/')) return _json(_homeJson());
    throw StateError('Unexpected synthetic API path');
  }

  Map<String, Object?> _grant() => <String, Object?>{
    'sessionId': _session,
    'deviceId': device,
    'installationId': _installation,
    'userId': account,
    'transport': 'web',
    'activeHomeId': _home,
    'csrfToken': 'synthetic-csrf-proof',
    'accessExpiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
    'refreshExpiresAt': now.add(const Duration(days: 30)).toIso8601String(),
    'idleExpiresAt': now.add(const Duration(days: 30)).toIso8601String(),
    'refreshIdleTtlSeconds': 2592000,
  };
}

Map<String, Object?> _homeJson() => <String, Object?>{
  'id': _home,
  'name': 'Synthetic home',
  'defaultLocale': 'en-NA',
  'defaultCurrency': 'NAD',
  'defaultTimezone': 'Africa/Windhoek',
  'role': 'owner',
  'revision': 1,
};
http.Response _json(Map<String, Object?> value, [int status = 200]) =>
    http.Response(
      jsonEncode(value),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );

final class _NoBrowserBearerStore implements SessionCredentialStore {
  @override
  bool get supportsPersistentSecrets => false;
  @override
  Future<StoredNativeSession?> read() async => null;
  @override
  Future<void> write(StoredNativeSession session) =>
      throw StateError('Browser bearer persistence is forbidden');
  @override
  Future<void> clear() async {}
}

final class _PendingStore implements PendingEmailCodeStore {
  PendingEmailCode? pending;
  BrowserCookieMutationJournal? mutation;
  bool logoutIntent = false;
  @override
  Future<PendingEmailCode?> read() async => pending;
  @override
  Future<void> write(
    PendingEmailCode request, {
    required bool activate,
  }) async => pending = request;
  @override
  Future<void> invalidate(PendingEmailCode request) async {
    if (pending?.requestId == request.requestId) pending = null;
  }

  @override
  Future<void> clear({PendingEmailCode? request}) async {
    if (request == null || pending?.requestId == request.requestId) {
      pending = null;
    }
  }

  @override
  Future<bool> hasLogoutIntent() async => logoutIntent;
  @override
  Future<void> markLogoutIntent() async => logoutIntent = true;
  @override
  Future<void> clearLogoutIntent() async => logoutIntent = false;
  @override
  Future<BrowserCookieMutationJournal?> readCookieMutation() async => mutation;
  @override
  Future<void> beginCookieMutation(
    BrowserCookieMutationJournal journal,
  ) async => mutation = journal;
  @override
  Future<void> clearCookieMutation({
    BrowserCookieMutationJournal? journal,
  }) async {
    if (journal == null || mutation?.operationId == journal.operationId) {
      mutation = null;
    }
  }
}
