import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:providentia/core/networking/session_http_client.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_server_credential_provisioning.dart';
import 'package:providentia/features/ai_integration/infrastructure/sanitizing_image_media_preparer.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/infrastructure/api17_home_transport.dart';
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/application/identity_session_manager.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia/features/identity/infrastructure/api17_identity_transport.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test(
    'API 1.7 password compatibility returns native rotating secrets',
    () async {
      final client = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/login');
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(body['deviceId'], '0198a0b1-c2d3-7e4f-8123-456789abcdef');
          expect(body['transport'], 'native');
          return http.Response(
            jsonEncode(<String, Object?>{
              'sessionId': 'session-1',
              'deviceId': body['deviceId'],
              'userId': 'user-1',
              'accessExpiresAt': '2026-08-04T12:30:00Z',
              'transport': 'native',
              'accessToken': 'access-secret',
              'refreshToken': 'refresh-secret',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      final transport = Api17IdentityTransport(
        client: client,
        sessionTransport: ClientSessionTransport.nativeBearer,
      );

      final grant = await transport.loginWithPassword(
        email: 'OWNER@EXAMPLE.TEST',
        password: 'not-logged',
        device: DeviceDescriptor(
          id: '0198a0b1-c2d3-7e4f-8123-456789abcdef',
          name: 'Test phone',
          platform: 'android',
        ),
      );

      expect(grant.metadata.sessionId, 'session-1');
      expect(grant.secrets.accessToken, 'access-secret');
      expect(grant.secrets.refreshToken, 'refresh-secret');
    },
  );

  test(
    'home adapter maps server locale, currency, timezone and manager role',
    () async {
      final client = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/homes');
          return http.Response(
            jsonEncode(<String, Object?>{
              'data': <Object?>[
                <String, Object?>{
                  'id': 'home-1',
                  'name': 'Windhoek home',
                  'defaultLocale': 'en-NA',
                  'defaultCurrency': 'NAD',
                  'defaultTimezone': 'Africa/Windhoek',
                  'role': 'manager',
                  'revision': 3,
                },
              ],
            }),
            200,
          );
        }),
      );

      final homes = await Api17HomeTransport(client).listHomes();

      expect(homes.single.role, HomeRole.manager);
      expect(homes.single.locale, 'en-NA');
      expect(homes.single.currency, 'NAD');
      expect(homes.single.timezone, 'Africa/Windhoek');
    },
  );

  test(
    'cloud credential is sent once to the home-scoped write-only vault',
    () async {
      final client = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          expect(
            request.url.path,
            '/api/v1/homes/home-1/ai/credentials/openai',
          );
          expect(request.method, 'PUT');
          expect(jsonDecode(request.body), <String, Object?>{
            'credential': 'sk-test-1234567890',
          });
          return http.Response(
            jsonEncode(<String, Object?>{
              'provider': 'openai',
              'configured': true,
              'lastFour': '7890',
            }),
            200,
          );
        }),
      );

      await Api17ServerCredentialProvisioning(client).replaceCredential(
        homeId: 'home-1',
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
        homeId: 'home-1',
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
        homeId: 'home-1',
        purpose: AiExtractionKind.receipt,
        assets: <AiMediaAsset>[asset],
      );
      final preparedBytes = await store.read(batch.media.single);

      expect(batch.media.single.mimeType, 'image/jpeg');
      expect(batch.media.single.sha256, hasLength(64));
      expect(image.decodeJpg(preparedBytes), isNotNull);
      await preparer.discard(batch);
      await expectLater(store.read(batch.media.single), throwsStateError);
    },
  );

  test(
    'authenticated client adds bearer and single-flights session state',
    () async {
      final transport = _RestoringIdentityTransport();
      final manager = IdentitySessionManager(
        transport: transport,
        credentialStore: _MemoryCredentialStore(),
        device: DeviceDescriptor(
          id: '0198a0b1-c2d3-7e4f-8123-456789abcdef',
          name: 'Test device',
          platform: 'android',
        ),
        clock: () => DateTime.utc(2026, 8, 4, 12),
      );
      await manager.restore();
      final client = SessionHttpClient(
        inner: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer access-1');
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
    },
  );
}

final class _MemoryCredentialStore implements SessionCredentialStore {
  StoredNativeSession? session = StoredNativeSession(
    sessionId: 'session-1',
    deviceId: '0198a0b1-c2d3-7e4f-8123-456789abcdef',
    refreshToken: 'refresh-0',
  );

  @override
  bool get supportsPersistentSecrets => true;

  @override
  Future<void> clear() async => session = null;

  @override
  Future<StoredNativeSession?> read() async => session;

  @override
  Future<void> write(StoredNativeSession session) async {
    this.session = session;
  }
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
        sessionId: 'session-1',
        deviceId: '0198a0b1-c2d3-7e4f-8123-456789abcdef',
        accessExpiresAt: DateTime.utc(2026, 8, 4, 13),
        transport: ClientSessionTransport.nativeBearer,
      ),
      secrets: const SessionSecrets(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
      ),
    );
  }

  @override
  Future<SessionGrant> completePasswordlessChallenge({
    required PasswordlessProof proof,
    required DeviceDescriptor device,
  }) => throw UnimplementedError();

  @override
  Future<List<DeviceSessionView>> listDeviceSessions({
    String? accessToken,
    String? csrfToken,
  }) async => const <DeviceSessionView>[];

  @override
  Future<void> logout({String? accessToken, String? csrfToken}) async {}

  @override
  Future<PasswordlessChallengeReceipt> requestPasswordlessChallenge({
    required String email,
  }) => throw UnimplementedError();

  @override
  Future<void> revokeDeviceSession({
    required String sessionId,
    String? accessToken,
    String? csrfToken,
  }) async {}
}
