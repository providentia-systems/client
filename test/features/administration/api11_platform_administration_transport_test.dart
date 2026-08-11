import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/administration/application/platform_administration_controller.dart';
import 'package:providentia/features/administration/infrastructure/api11_platform_administration_transport.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test('malformed administrator domain values are normalized', () async {
    final transport = Api11PlatformAdministrationTransport(
      _client(
        (_) async => _json(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'id': _administratorId,
              'email': 'admin@example.com',
              'userId': 7,
              'status': 'active',
              'revision': 1,
              'grantedByUserId': null,
              'createdAt': '2026-08-09T12:00:00Z',
              'activatedAt': 'not-a-date',
            },
          ],
        }),
      ),
    );

    await expectLater(
      transport.listAdministrators(),
      throwsA(
        isA<PlatformAdministrationException>()
            .having(
              (error) => error.kind,
              'kind',
              PlatformAdministrationFailureKind.unavailable,
            )
            .having(
              (error) => error.safeMessage,
              'safeMessage',
              contains('read safely'),
            ),
      ),
    );
  });

  test('administrator http client failures are normalized', () async {
    final transport = Api11PlatformAdministrationTransport(
      _client((_) async => throw http.ClientException('private detail')),
    );

    await expectLater(
      transport.listAdministrators(),
      throwsA(
        isA<PlatformAdministrationException>()
            .having(
              (error) => error.kind,
              'kind',
              PlatformAdministrationFailureKind.unavailable,
            )
            .having(
              (error) => error.safeMessage,
              'safeMessage',
              isNot(contains('private detail')),
            ),
      ),
    );
  });

  test('timed-out administrator mutation aborts its HTTP request', () async {
    var requestCount = 0;
    final abortObserved = Completer<void>();
    final client = MockClient.streaming((request, _) async {
      requestCount++;
      if (requestCount == 1) {
        final abortTrigger = (request as http.Abortable).abortTrigger!;
        final outcome = await Future.any<String>(<Future<String>>[
          Future<String>.delayed(
            const Duration(milliseconds: 80),
            () => 'response',
          ),
          abortTrigger.then((_) => 'abort'),
        ]);
        if (outcome == 'abort') {
          if (!abortObserved.isCompleted) abortObserved.complete();
          throw http.RequestAbortedException(request.url);
        }
      }
      return _streamedJson(_administratorJson());
    });
    final transport = Api11PlatformAdministrationTransport(
      ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: client,
      ),
      requestTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      transport.grantAdministrator('first@example.com'),
      throwsA(
        isA<PlatformAdministrationException>().having(
          (error) => error.kind,
          'kind',
          PlatformAdministrationFailureKind.unavailable,
        ),
      ),
    );
    final granted = await transport.grantAdministrator('second@example.com');
    await abortObserved.future.timeout(const Duration(seconds: 1));

    expect(granted.id, _administratorId);
    expect(requestCount, 2);
    expect(abortObserved.isCompleted, isTrue);
  });
}

const String _administratorId = '0198a0b1-c2d3-7e4f-8123-456789abcd01';

ProvidentiaApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => ProvidentiaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(handler),
);

http.Response _json(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const <String, String>{'content-type': 'application/json'},
);

http.StreamedResponse _streamedJson(Map<String, Object?> body) =>
    http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );

Map<String, Object?> _administratorJson() => <String, Object?>{
  'id': _administratorId,
  'email': 'second@example.com',
  'userId': _administratorId,
  'status': 'active',
  'revision': 1,
  'grantedByUserId': null,
  'createdAt': '2026-08-09T12:00:00Z',
  'activatedAt': '2026-08-09T12:00:00Z',
};
