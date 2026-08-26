import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/homes/application/home_ports.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/infrastructure/api11_home_transport.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test('required home fields never receive client-side defaults', () async {
    for (final field in <String>[
      'defaultLocale',
      'defaultCurrency',
      'defaultTimezone',
      'role',
    ]) {
      final home = _homeJson()..remove(field);
      final transport = Api11HomeTransport(
        _client(
          (_) async => _json(<String, Object?>{
            'data': <Object?>[home],
          }),
        ),
      );

      await expectLater(
        transport.listHomes(),
        throwsA(
          isA<HomeTransportException>()
              .having(
                (error) => error.kind,
                'kind',
                HomeFailureKind.unavailable,
              )
              .having(
                (error) => error.safeMessage,
                'safeMessage',
                contains('read safely'),
              ),
        ),
        reason: field,
      );
    }
  });

  test('malformed home UUID is rejected before it reaches routes', () async {
    final home = _homeJson()..['id'] = 'not-a-uuid';
    final transport = Api11HomeTransport(
      _client(
        (_) async => _json(<String, Object?>{
          'data': <Object?>[home],
        }),
      ),
    );

    await expectLater(
      transport.listHomes(),
      throwsA(
        isA<HomeTransportException>().having(
          (error) => error.kind,
          'kind',
          HomeFailureKind.unavailable,
        ),
      ),
    );
  });

  test('required permission list rejects null and duplicate values', () async {
    for (final permissions in <Object?>[
      null,
      <Object?>['home.read', 'home.read'],
    ]) {
      final transport = Api11HomeTransport(
        _client(
          (_) async => _json(<String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'role': 'member',
                'revision': 1,
                'permissions': permissions,
                'configurable': true,
              },
            ],
          }),
        ),
      );

      await expectLater(
        transport.listPermissionPolicies(_homeId),
        throwsA(
          isA<HomeTransportException>().having(
            (error) => error.kind,
            'kind',
            HomeFailureKind.unavailable,
          ),
        ),
      );
    }
  });

  test('http client failures are normalized without leaking details', () async {
    final transport = Api11HomeTransport(
      _client((request) async {
        throw http.ClientException('socket address and private detail');
      }),
    );

    await expectLater(
      transport.listHomes(),
      throwsA(
        isA<HomeTransportException>()
            .having((error) => error.kind, 'kind', HomeFailureKind.network)
            .having(
              (error) => error.safeMessage,
              'safeMessage',
              isNot(contains('private detail')),
            ),
      ),
    );
  });

  test('missing permission-policy home closes revoked workspace', () async {
    final transport = Api11HomeTransport(_client((_) async => _problem(404)));

    await expectLater(
      transport.putPermissionPolicy(
        homeId: _homeId,
        role: HomeRole.member,
        permissions: const <String>{'home.read'},
        expectedRevision: 1,
      ),
      throwsA(
        isA<HomeTransportException>().having(
          (error) => error.kind,
          'kind',
          HomeFailureKind.membershipRevoked,
        ),
      ),
    );
  });

  test('membership removal deletes with the expected revision query', () async {
    http.Request? seen;
    final transport = Api11HomeTransport(
      _client((request) async {
        seen = request;
        return http.Response('', 204);
      }),
    );

    await transport.removeHomeMembership(
      homeId: _homeId,
      userId: _userId,
      expectedRevision: 7,
    );

    expect(seen?.method, 'DELETE');
    expect(seen?.url.path, endsWith('/homes/$_homeId/memberships/$_userId'));
    expect(seen?.url.queryParameters, <String, String>{
      'expectedRevision': '7',
    });
    expect(seen?.body, isEmpty);
  });

  test(
    'membership removal conflict keeps the standard retry message',
    () async {
      final transport = Api11HomeTransport(_client((_) async => _problem(409)));

      await expectLater(
        transport.removeHomeMembership(
          homeId: _homeId,
          userId: _userId,
          expectedRevision: 3,
        ),
        throwsA(
          isA<HomeTransportException>()
              .having((error) => error.kind, 'kind', HomeFailureKind.conflict)
              .having(
                (error) => error.safeMessage,
                'safeMessage',
                'This member is no longer available. Refresh and try again.',
              ),
        ),
      );
    },
  );

  test('ownership transfers parse the contract schema strictly', () async {
    final transport = Api11HomeTransport(
      _client(
        (_) async => _json(<String, Object?>{
          'data': <Object?>[_transferJson()],
        }),
      ),
    );

    final transfers = await transport.listHomeOwnershipTransfers(_homeId);

    final transfer = transfers.single;
    expect(transfer.id, _transferId);
    expect(transfer.homeId, _homeId);
    expect(transfer.proposedByUserId, _ownerUserId);
    expect(transfer.targetUserId, _userId);
    expect(transfer.expectedTargetRevision, 4);
    expect(transfer.status, OwnershipTransferStatus.pending);
    expect(transfer.revision, 2);

    final malformed = Api11HomeTransport(
      _client(
        (_) async => _json(<String, Object?>{
          'data': <Object?>[_transferJson()..['status'] = 'stolen'],
        }),
      ),
    );
    await expectLater(
      malformed.listHomeOwnershipTransfers(_homeId),
      throwsA(
        isA<HomeTransportException>().having(
          (error) => error.kind,
          'kind',
          HomeFailureKind.unavailable,
        ),
      ),
    );
  });

  test(
    'ownership proposal posts the step-up token and target revision',
    () async {
      http.Request? seen;
      final transport = Api11HomeTransport(
        _client((request) async {
          seen = request;
          return _json(_transferJson());
        }),
      );

      final proposed = await transport.proposeHomeOwnershipTransfer(
        homeId: _homeId,
        targetUserId: _userId,
        expectedTargetRevision: 4,
        stepUpToken: _stepUpToken,
      );

      expect(proposed.status, OwnershipTransferStatus.pending);
      expect(seen?.url.path, endsWith('/homes/$_homeId/ownership-transfers'));
      expect(jsonDecode(seen?.body ?? ''), <String, Object?>{
        'targetUserId': _userId,
        'expectedTargetRevision': 4,
        'stepUpToken': _stepUpToken,
      });
    },
  );

  test('transfer decisions post revisions and normalize conflicts', () async {
    http.Request? seen;
    final transport = Api11HomeTransport(
      _client((request) async {
        seen = request;
        return http.Response('', 204);
      }),
    );

    await transport.acceptHomeOwnershipTransfer(
      homeId: _homeId,
      transferId: _transferId,
      expectedRevision: 2,
    );
    expect(
      seen?.url.path,
      endsWith('/homes/$_homeId/ownership-transfers/$_transferId/accept'),
    );
    expect(jsonDecode(seen?.body ?? ''), <String, Object?>{
      'expectedRevision': 2,
    });

    await transport.rejectHomeOwnershipTransfer(
      homeId: _homeId,
      transferId: _transferId,
      expectedRevision: 2,
    );
    expect(seen?.url.path, endsWith('/$_transferId/reject'));

    await transport.revokeHomeOwnershipTransfer(
      homeId: _homeId,
      transferId: _transferId,
      expectedRevision: 2,
    );
    expect(seen?.url.path, endsWith('/$_transferId/revoke'));

    final conflicted = Api11HomeTransport(_client((_) async => _problem(409)));
    await expectLater(
      conflicted.revokeHomeOwnershipTransfer(
        homeId: _homeId,
        transferId: _transferId,
        expectedRevision: 2,
      ),
      throwsA(
        isA<HomeTransportException>()
            .having((error) => error.kind, 'kind', HomeFailureKind.conflict)
            .having(
              (error) => error.safeMessage,
              'safeMessage',
              'This ownership transfer is no longer available. Refresh and try again.',
            ),
      ),
    );
  });

  test('step-up request is scoped to homeowner ownership transfer', () async {
    http.Request? seen;
    final transport = Api11HomeTransport(
      _client((request) async {
        seen = request;
        return _json(<String, Object?>{
          'accepted': true,
          'developmentStepUpToken': _stepUpToken,
        });
      }),
    );

    final receipt = await transport.requestStepUpLink();

    expect(seen?.url.path, endsWith('/auth/step-up-links'));
    expect(jsonDecode(seen?.body ?? ''), <String, Object?>{
      'applicationKind': 'homeowner',
      'action': 'ownership-transfer',
    });
    expect(receipt.developmentStepUpToken, _stepUpToken);

    final production = Api11HomeTransport(
      _client((_) async => _json(<String, Object?>{'accepted': true})),
    );
    expect(
      (await production.requestStepUpLink()).developmentStepUpToken,
      isNull,
    );

    final refused = Api11HomeTransport(
      _client((_) async => _json(<String, Object?>{'accepted': false})),
    );
    await expectLater(
      refused.requestStepUpLink(),
      throwsA(
        isA<HomeTransportException>().having(
          (error) => error.kind,
          'kind',
          HomeFailureKind.unavailable,
        ),
      ),
    );
  });

  test(
    'timed-out home switch is aborted before a later switch can land',
    () async {
      const delayedHomeId = '0198a0b1-c2d3-7e4f-8123-456789abcdaa';
      const currentHomeId = '0198a0b1-c2d3-7e4f-8123-456789abcdab';
      final landed = <String>[];
      final aborted = <String>[];
      final delayedRequestStarted = Completer<void>();
      final delayedAbortObserved = Completer<void>();
      final client = MockClient.streaming((request, _) async {
        final homesSegment = request.url.pathSegments.indexOf('homes');
        final homeId = request.url.pathSegments[homesSegment + 1];
        if (homeId == delayedHomeId) {
          delayedRequestStarted.complete();
          final abortTrigger = (request as http.Abortable).abortTrigger!;
          final outcome = await Future.any<String>(<Future<String>>[
            Future<String>.delayed(
              const Duration(seconds: 2),
              () => 'response',
            ),
            abortTrigger.then((_) => 'abort'),
          ]);
          if (outcome == 'abort') {
            aborted.add(homeId);
            delayedAbortObserved.complete();
            throw http.RequestAbortedException(request.url);
          }
        }
        landed.add(homeId);
        return _streamedJson(_homeJson()..['id'] = homeId);
      });
      final transport = Api11HomeTransport(
        ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: client,
        ),
        requestTimeout: const Duration(milliseconds: 250),
      );

      final delayedSwitch = transport.switchActiveHome(delayedHomeId);
      await delayedRequestStarted.future.timeout(const Duration(seconds: 1));
      await expectLater(
        delayedSwitch,
        throwsA(
          isA<HomeTransportException>().having(
            (error) => error.kind,
            'kind',
            HomeFailureKind.network,
          ),
        ),
      );
      await delayedAbortObserved.future.timeout(const Duration(seconds: 1));
      final selected = await transport.switchActiveHome(currentHomeId);

      expect(selected.id, currentHomeId);
      expect(aborted, <String>[delayedHomeId]);
      expect(landed, <String>[currentHomeId]);
    },
  );
}

const String _homeId = '0198a0b1-c2d3-7e4f-8123-456789abcded';
const String _userId = '0198a0b1-c2d3-7e4f-8123-456789abcd01';
const String _ownerUserId = '0198a0b1-c2d3-7e4f-8123-456789abcd02';
const String _transferId = '0198a0b1-c2d3-7e4f-8123-456789abcd03';
const String _stepUpToken =
    'development-step-up-token-0000000000000000000000000000000000000000';

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

http.Response _problem(int status) => http.Response(
  jsonEncode(<String, Object?>{
    'type': 'about:blank',
    'title': 'Not found',
    'status': status,
    'detail': 'The resource is unavailable.',
    'requestId': 'request-test',
  }),
  status,
  headers: const <String, String>{'content-type': 'application/problem+json'},
);

Map<String, Object?> _transferJson() => <String, Object?>{
  'id': _transferId,
  'homeId': _homeId,
  'proposedByUserId': _ownerUserId,
  'targetUserId': _userId,
  'expectedTargetRevision': 4,
  'status': 'pending',
  'expiresAt': '2030-01-01T00:00:00Z',
  'revision': 2,
};

Map<String, Object?> _homeJson() => <String, Object?>{
  'id': _homeId,
  'name': 'My home',
  'defaultLocale': 'en-NA',
  'defaultCurrency': 'NAD',
  'defaultTimezone': 'Africa/Windhoek',
  'role': 'member',
  'revision': 1,
};
