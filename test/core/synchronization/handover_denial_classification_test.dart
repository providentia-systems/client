import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart'
    as generated;

void main() {
  const home = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
  const device = '0198a0b1-c2d3-7e4f-a345-6789abcdef01';
  const operation = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';
  GeneratedSyncGateway gateway(int status, String type) => GeneratedSyncGateway(
    generated.ProvidentiaApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'type': type,
            'title': 'Unavailable',
            'status': status,
            'detail':
                'Device mismatch and revoked home: prose must not classify.',
            'requestId': operation,
          }),
          status,
          headers: {'content-type': 'application/problem+json'},
        ),
      ),
    ),
  );

  for (final status in [403, 404]) {
    test(
      'unclassified HTTP $status never establishes purge authority',
      () async {
        final remote = gateway(status, 'about:blank');
        await expectLater(
          remote.pull(homeId: home, afterCursor: 'cursor'),
          throwsA(isA<RetryableSyncException>()),
        );
        await expectLater(
          remote.bootstrap(homeId: home),
          throwsA(isA<RetryableSyncException>()),
        );
        await expectLater(
          remote.operationStatuses(
            homeId: home,
            deviceId: device,
            operationIds: [operation],
          ),
          throwsA(isA<RetryableSyncException>()),
        );
      },
    );
  }
  test(
    'only the explicit home-access machine type permits revocation handling',
    () async {
      await expectLater(
        gateway(
          404,
          'https://providentia.invalid/problems/sync_home_access_denied',
        ).pull(homeId: home, afterCursor: 'cursor'),
        throwsA(isA<AuthorizationSyncException>()),
      );
    },
  );
  test(
    'device mismatch remains a recoverable binding issue, not expired login',
    () async {
      await expectLater(
        gateway(
          403,
          'https://providentia.invalid/problems/sync_device_mismatch',
        ).operationStatuses(
          homeId: home,
          deviceId: device,
          operationIds: [operation],
        ),
        throwsA(
          isA<BindingSyncException>().having(
            (e) => e.code,
            'code',
            'device_binding_mismatch',
          ),
        ),
      );
    },
  );
  test(
    'permission change does not falsely establish revoked membership',
    () async {
      await expectLater(
        gateway(
          404,
          'https://providentia.invalid/problems/sync_permission_denied',
        ).pull(homeId: home, afterCursor: 'cursor'),
        throwsA(isA<RetryableSyncException>()),
      );
    },
  );
  test('diagnostic codes are bounded to the known vocabulary', () {
    expect(sanitizedSyncFailureCode(null), isNull);
    expect(
      sanitizedSyncFailureCode('home_access_denied'),
      'home_access_denied',
    );
    expect(
      sanitizedSyncFailureCode('private household name'),
      'unclassified_failure',
    );
  });
  test(
    'generated results retain machine codes and protocol-v2 command data',
    () {
      final result = generated.SyncOperationResult.fromJson({
        'operationId': operation,
        'status': 'conflict',
        'code': 'revision_mismatch',
        'result': {'revision': 3, 'id': home},
      });
      expect(result.code, 'revision_mismatch');
      expect(result.commandResult?['revision'], 3);
      expect(
        () => result.commandResult!['revision'] = 4,
        throwsUnsupportedError,
      );
    },
  );
}
