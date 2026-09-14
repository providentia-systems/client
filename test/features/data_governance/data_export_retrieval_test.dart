import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/data_governance/application/data_governance_service.dart';
import 'package:providentia/features/data_governance/domain/data_governance_models.dart';
import 'package:providentia/features/data_governance/infrastructure/generated_data_governance_repository.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  for (final scope in DataGovernanceScope.values) {
    test('retrieves ${scope.name} through body-only token and erases memory', () async {
      final calls = <http.Request>[];
      final repository = _repository((request) async {
        calls.add(request);
        if (request.method == 'GET') return _json({'data': [_row(scope)]});
        if (request.url.path.endsWith('/download-token')) {
          expect(jsonDecode(request.body), {'expectedRevision': 7});
          return _json({'token': _secret, 'revision': 8, 'expiresAt': _future});
        }
        expect(request.method, 'POST');
        expect(request.url.path.endsWith('/download'), isTrue);
        expect(jsonDecode(request.body), {'token': _secret});
        return _json(_artifact(scope));
      });
      final artifact = await repository.retrieveExport(_request(scope), isCurrent: () => true);
      expect(jsonDecode(utf8.decode(artifact.bytes)), _artifact(scope));
      expect(artifact.toString(), isNot(contains(_secret)));
      expect(artifact.filename, 'providentia-${scope.name}-export-$_id.json');
      expect(calls, hasLength(3));
      for (final call in calls) {
        expect(call.url.toString(), isNot(contains(_secret)));
        expect(call.headers.toString(), isNot(contains(_secret)));
      }
      final bytes = artifact.bytes;
      artifact.dispose();
      expect(bytes.every((value) => value == 0), isTrue);
      expect(() => artifact.bytes, throwsStateError);
    });
  }
  test('refreshes revision after a consumed token, never reuses that token', () async {
    var reads = 0;
    var issued = 0;
    final downloads = <String>[];
    final repository = _repository((request) async {
      if (request.method == 'GET') return _json({'data': [_row(DataGovernanceScope.account, revision: 7 + reads++)]});
      if (request.url.path.endsWith('/download-token')) {
        expect(jsonDecode(request.body), {'expectedRevision': 7 + issued});
        issued++;
        return _json({'token': 'token-$issued', 'revision': 7 + issued, 'expiresAt': _future});
      }
      downloads.add((jsonDecode(request.body) as Map<String, dynamic>)['token'] as String);
      if (downloads.length == 1) return _json({'status': 410}, status: 410);
      return _json(_artifact(DataGovernanceScope.account));
    });
    final artifact = await repository.retrieveExport(_request(DataGovernanceScope.account), isCurrent: () => true);
    expect(downloads, ['token-1', 'token-2']);
    expect(reads, 2);
    artifact.dispose();
  });
  for (final failure in ['cancelled', 'expired', 'foreign-requester', 'wrong-home', 'cacheable-token', 'cacheable-artifact', 'revoked']) {
    test('fails closed for $failure without exposing private error detail', () async {
      var current = true;
      var downloads = 0;
      final repository = _repository((request) async {
        if (request.method == 'GET') {
          final row = _row(DataGovernanceScope.home);
          if (failure == 'cancelled') row['status'] = 'cancelled';
          if (failure == 'expired') row['artifactExpiresAt'] = '2000-01-01T00:00:00Z';
          if (failure == 'foreign-requester') row['downloadEligible'] = false;
          return _json({'data': [row]});
        }
        if (request.url.path.endsWith('/download-token')) {
          if (failure == 'revoked') current = false;
          return _json({'token': _secret, 'revision': 8, 'expiresAt': _future}, noStore: failure != 'cacheable-token');
        }
        downloads++;
        final artifact = _artifact(DataGovernanceScope.home);
        if (failure == 'wrong-home') artifact['data'] = {'home': [{'id': '22222222-2222-4222-8222-222222222222'}]};
        return _json(artifact, noStore: failure != 'cacheable-artifact');
      });
      await expectLater(repository.retrieveExport(_request(DataGovernanceScope.home), isCurrent: () => current), throwsA(isA<DataGovernanceRepositoryException>().having((error) => error.toString(), 'safe message', isNot(contains(_secret)))));
      expect(downloads, failure == 'wrong-home' || failure == 'cacheable-artifact' ? 1 : 0);
    });
  }
}

GeneratedDataGovernanceRepository _repository(Future<http.Response> Function(http.Request) handle) => GeneratedDataGovernanceRepository(ProvidentiaApiClient(baseUri: Uri.parse('https://api.example.test'), httpClient: MockClient(handle)));
http.Response _json(Object body, {int status = 200, bool noStore = true}) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', if (noStore) 'cache-control': 'private, no-store'});
Map<String, Object?> _row(DataGovernanceScope scope, {int revision = 7}) => {'id': _id, 'scopeType': scope.name, 'requestKind': '${scope.name}_export', 'homeId': scope == DataGovernanceScope.home ? _home : null, 'status': 'completed', 'revision': revision, 'downloadEligible': true, 'artifactExpiresAt': _future, 'retainedDataDisclosure': <Object?>[]};
DataGovernanceRequest _request(DataGovernanceScope scope) => DataGovernanceRequest(id: _id, kind: scope == DataGovernanceScope.home ? DataGovernanceRequestKind.homeExport : DataGovernanceRequestKind.accountExport, scope: scope, status: DataGovernanceRequestStatus.completed, revision: 7, homeId: scope == DataGovernanceScope.home ? _home : null, downloadEligible: true, artifactExpiresAt: DateTime.parse(_future), retainedDataDisclosure: []);
Map<String, Object?> _artifact(DataGovernanceScope scope) => {'format': 'providentia-data-export-v1', 'requestId': _id, 'scope': scope.name, 'data': scope == DataGovernanceScope.home ? {'home': [{'id': _home}]} : {'account': <Object?>[]}};
const _id = '11111111-1111-4111-8111-111111111111';
const _home = '33333333-3333-4333-8333-333333333333';
const _secret = 'synthetic-private-body-only-token';
final _future = DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String();
