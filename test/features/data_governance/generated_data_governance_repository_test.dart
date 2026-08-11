import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/data_governance/application/data_governance_service.dart';
import 'package:providentia/features/data_governance/domain/data_governance_models.dart';
import 'package:providentia/features/data_governance/infrastructure/generated_data_governance_repository.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test(
    'maps all request/list operations and sends revision-safe cancel',
    () async {
      Map<String, Object?>? cancelBody;
      final repository = GeneratedDataGovernanceRepository(
        _client((request) async {
          expect(request.url.queryParameters['limit'], anyOf(isNull, '50'));
          expect(request.url.queryParameters['offset'], anyOf(isNull, '0'));
          if (request.url.path.endsWith('/cancel')) {
            cancelBody = _requestObject(request);
            return http.Response('', 204);
          }
          if (request.method == 'GET') {
            final isHome = request.url.path.contains('/homes/');
            return _json(<String, Object?>{
              'data': <Object?>[
                _governanceJson(
                  kind: isHome ? 'home_export' : 'account_export',
                  scope: isHome ? 'home' : 'account',
                  homeId: isHome ? _homeId : null,
                  includeRawStorageFields: true,
                ),
              ],
            });
          }
          final path = request.url.path;
          final kind = path.endsWith('/data-exports')
              ? (path.contains('/homes/') ? 'home_export' : 'account_export')
              : (path.contains('/homes/') ? 'home_erasure' : 'account_erasure');
          return _json(
            _governanceJson(
              kind: kind,
              scope: path.contains('/homes/') ? 'home' : 'account',
            ),
            status: 202,
          );
        }),
      );

      expect(
        (await repository.requestAccountExport()).kind,
        DataGovernanceRequestKind.accountExport,
      );
      expect(
        (await repository.requestAccountErasure()).kind,
        DataGovernanceRequestKind.accountErasure,
      );
      final homeExport = await repository.requestHomeExport(homeId: _homeId);
      expect(homeExport.kind, DataGovernanceRequestKind.homeExport);
      expect(homeExport.homeId, _homeId);
      expect(
        (await repository.requestHomeErasure(homeId: _homeId)).kind,
        DataGovernanceRequestKind.homeErasure,
      );

      final accountList = await repository.listAccountRequests();
      expect(accountList.single.scope, DataGovernanceScope.account);
      expect(accountList.single.homeId, isNull);
      final homeList = await repository.listHomeRequests(homeId: _homeId);
      final listed = homeList.single;
      expect(listed.scope, DataGovernanceScope.home);
      expect(listed.homeId, _homeId);
      expect(listed.status, DataGovernanceRequestStatus.failed);
      expect(listed.retainedDataDisclosure.single.category, 'tax_record');
      expect(listed.toString(), isNot(contains(_privateFailureReason)));

      await repository.cancelRequest(
        requestId: _requestId,
        expectedRevision: 7,
      );
      expect(cancelBody, <String, Object?>{'expectedRevision': 7});
    },
  );

  test('rejects nested cross-home attribution in home list', () async {
    final repository = GeneratedDataGovernanceRepository(
      _client(
        (_) async => _json(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              ..._governanceJson(
                kind: 'home_export',
                scope: 'home',
                homeId: _homeId,
              ),
              'futureMetadata': <String, Object?>{
                'items': <Object?>[
                  <String, Object?>{'homeId': _otherHomeId},
                ],
              },
            },
          ],
        }),
      ),
    );

    await expectLater(
      repository.listHomeRequests(homeId: _homeId),
      throwsA(
        isA<DataGovernanceRepositoryException>().having(
          (error) => error.kind,
          'kind',
          DataGovernanceFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test('normalizes private HTTP problems into detail-free failures', () async {
    final repository = GeneratedDataGovernanceRepository(
      _client(
        (_) async => _json(<String, Object?>{
          'type': 'https://example.test/problems/conflict',
          'title': 'Conflict',
          'status': 409,
          'requestId': _requestId,
          'detail': _privateFailureReason,
        }, status: 409),
      ),
    );

    try {
      await repository.requestAccountExport();
      fail('Expected a normalized conflict.');
    } on DataGovernanceRepositoryException catch (error) {
      expect(error.kind, DataGovernanceFailureKind.conflict);
      expect(error.toString(), isNot(contains(_privateFailureReason)));
    }
  });

  test('validates then discards backend failure detail', () async {
    final repository = GeneratedDataGovernanceRepository(
      _client(
        (_) async => _json(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              ..._governanceJson(kind: 'account_export', scope: 'account'),
              'failureReason': 123,
            },
          ],
        }),
      ),
    );

    await expectLater(
      repository.listAccountRequests(),
      throwsA(
        isA<DataGovernanceRepositoryException>().having(
          (error) => error.kind,
          'kind',
          DataGovernanceFailureKind.invalidResponse,
        ),
      ),
    );
  });
}

Map<String, Object?> _governanceJson({
  required String kind,
  required String scope,
  String? homeId,
  bool includeRawStorageFields = false,
}) => <String, Object?>{
  'id': _requestId,
  'requestKind': kind,
  'scopeType': scope,
  'status': includeRawStorageFields ? 'failed' : 'queued',
  'revision': includeRawStorageFields ? 7 : 1,
  'retainedDataDisclosure': <Object?>[
    <String, Object?>{
      'category': 'tax_record',
      'treatment': 'retained',
      'reason': 'Required by law.',
    },
  ],
  if (includeRawStorageFields) ...<String, Object?>{
    'homeId': homeId,
    'subjectUserId': scope == 'account' ? _subjectUserId : null,
    'requestedByUserId': _subjectUserId,
    'artifactReference': 'PRIVATE-storage-path',
    'artifactNonce': 'PRIVATE-nonce',
    'failureReason': _privateFailureReason,
    'createdAt': '2026-08-11T10:00:00Z',
    'updatedAt': '2026-08-11T10:01:00Z',
  },
};

ProvidentiaApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => ProvidentiaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(handler),
);

Map<String, Object?> _requestObject(http.Request request) {
  final value = jsonDecode(request.body);
  if (value is! Map<String, Object?>) {
    throw StateError('Expected an object request body.');
  }
  return value;
}

http.Response _json(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{'content-type': 'application/json'},
);

const String _homeId = '01912345-6789-7abc-8def-0123456789ab';
const String _otherHomeId = '01912345-6789-7abc-8def-1123456789ab';
const String _requestId = '01912345-6789-7abc-8def-2123456789ab';
const String _subjectUserId = '01912345-6789-7abc-8def-3123456789ab';
const String _privateFailureReason =
    'PRIVATE worker stack, storage reference, and household facts';
