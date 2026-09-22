#!/usr/bin/env python3
"""Temporary applicator for reviewed sync health and classification changes."""
from pathlib import Path

p = Path('lib/core/synchronization/sync_models.dart')
s = p.read_text()
if 'uploadsBlocked' not in s:
    s = s.replace('enum SyncRunStatus {\n  completed,', 'enum SyncRunStatus {\n  completed,\n  uploadsPending,\n  uploadsBlocked,')
    s = s.replace('    this.pulledChangeCount = 0,', '    this.pulledChangeCount = 0,\n    this.pullCompleted = false,\n    this.remainingUploads = 0,', 1)
    s = s.replace('  final int pulledChangeCount;', '  final int pulledChangeCount;\n  final bool pullCompleted;\n  final int remainingUploads;', 1)
    a = s.index('final class PushOperationResult')
    b = s.index('final class PushResponse', a)
    part = s[a:b].replace('    this.safeMessage,', '    this.safeMessage,\n    this.code,\n    this.requestId,')
    part = part.replace('  final String? safeMessage;', '  final String? safeMessage;\n  final String? code;\n  final String? requestId;')
    s = s[:a] + part + s[b:]
    s = s.replace('  int get waiting => pending + syncing + retryWaiting;', '''  int get waiting => pending + syncing + retryWaiting;
  int get blocked => blockedConflicts + blockedValidation + blockedAuthorization;
  int get unresolved => waiting + blocked;''')
    s += '''
/// A saved command does not belong to this dispatch binding. This is not an
/// expired login, and must never trigger credential refresh or intent rebinding.
final class BindingSyncException implements Exception {
  const BindingSyncException(this.safeMessage, {required this.code});

  final String safeMessage;
  final String code;
}

/// Only documented classifications enter diagnostics. Server prose is not a code.
String? sanitizedSyncFailureCode(String? code) {
  if (code == null) return null;
  return const <String>{
    'device_binding_mismatch', 'account_binding_mismatch',
    'origin_account_unknown', 'home_access_denied', 'permission_denied',
    'resource_unavailable', 'revision_conflict', 'revision_mismatch',
    'operation_id_reuse', 'invalid_command', 'service_unavailable',
    'concurrent_write', 'unclassified_http_denial', 'unclassified_failure',
  }.contains(code) ? code : 'unclassified_failure';
}
'''
p.write_text(s)
p = Path('lib/core/synchronization/session_bound_sync_gateway.dart')
s = p.read_text()
s = s.replace("throw const AuthenticationSyncException(\n        'Saved work", "throw const BindingSyncException(\n        'Saved work")
s = s.replace("'It has not been reassigned or sent.',\n      );", "'It has not been reassigned or sent.',\n        code: 'device_binding_mismatch',\n      );")
p.write_text(s)

# Change the generator, not its generated output. The existing contract already
# permits result.code and the protocol-v2 result projection.
p = Path('tool/generate_api_client.mjs')
s = p.read_text()
a = s.index('final class SyncOperationResult {')
b = s.index('final class SyncPushResponse {', a)
part = s[a:b]
if 'this.code,' not in part:
    part = part.replace('    this.detail,', '    this.detail,\n    this.code,')
    part = part.replace('    Map<String, Object?>? conflict,', '    Map<String, Object?>? conflict,\n    Map<String, Object?>? commandResult,')
    part = part.replace('           : Map<String, Object?>.unmodifiable(conflict);', '''           : Map<String, Object?>.unmodifiable(conflict),
       commandResult = commandResult == null
           ? null
           : Map<String, Object?>.unmodifiable(commandResult);''')
    part = part.replace("      detail: _optionalString(json, 'detail'),", "      detail: _optionalString(json, 'detail'),\n      code: _optionalString(json, 'code'),\n      commandResult: _optionalObject(json, 'result'),")
    part = part.replace('  final String? detail;', '  final String? detail;\n  final String? code;\n  final Map<String, Object?>? commandResult;')
    s = s[:a] + part + s[b:]
p.write_text(s)

p = Path('lib/core/synchronization/generated_sync_gateway.dart')
s = p.read_text()
if 'Never _throwDeniedRequest(' not in s:
    s = s.replace('throw AuthorizationSyncException(_safeProblem(error));', '_throwDeniedRequest(error);')
    needle = '''      if (error.statusCode == 403 || error.statusCode == 404) {
        return PushResponse('''
    assert needle in s
    s = s.replace(needle, '''      if (error.statusCode == 403 || error.statusCode == 404) {
        final code = _denialCode(error);
        if (code == 'home_access_denied' || code == 'device_binding_mismatch') {
          _throwDeniedRequest(error);
        }
        return PushResponse(''', 1)
    s = s.replace('''                  kind: PushResultKind.authorizationFailure,
                  safeMessage: _safeProblem(error),''', '''                  kind: code == 'permission_denied'
                      ? PushResultKind.authorizationFailure
                      : PushResultKind.validationError,
                  code: code,
                  requestId: error.problem.requestId,
                  safeMessage: code == 'permission_denied'
                      ? 'This command needs a permission review. Saved work has been kept.'
                      : 'The server did not classify this denial. Check the API address and deployment; saved work has been kept.', ''', 1)
    s = s.replace('response.results.map(_pushResult).toList(growable: false)', 'response.results.map((result) => _pushResult(result, response.requestId)).toList(growable: false)')
    s = s.replace('PushOperationResult _pushResult(generated.SyncOperationResult result)', 'PushOperationResult _pushResult(generated.SyncOperationResult result, String requestId)')
    s = s.replace('      acceptedRevision: result.revision,', "      acceptedRevision: result.revision ?? _commandRevision(result.commandResult),\n      code: sanitizedSyncFailureCode(result.code),\n      requestId: requestId,")
    s = s.replace('remotePayload: result.representation ?? result.conflict,', 'remotePayload: result.representation ?? result.conflict ?? result.commandResult,')
    s = s.replace("      safeMessage: json['detail'] as String?,", "      safeMessage: json['detail'] as String?,\n      code: sanitizedSyncFailureCode(json['code'] as String?),")
    pos = s.index('  String _safeProblem(')
    s = s[:pos] + '''  int? _commandRevision(Map<String, Object?>? result) {
    final revision = result?['revision'];
    if (revision != null && (revision is! int || revision < 0)) {
      throw const FormatException('Command result revision must be a non-negative integer.');
    }
    return revision as int?;
  }

  String _denialCode(generated.ProvidentiaApiException error) => switch (error.problem.type) {
    'https://providentia.invalid/problems/sync_home_access_denied' => 'home_access_denied',
    'https://providentia.invalid/problems/sync_device_mismatch' => 'device_binding_mismatch',
    'https://providentia.invalid/problems/sync_permission_denied' => 'permission_denied',
    _ => 'unclassified_http_denial',
  };

  Never _throwDeniedRequest(generated.ProvidentiaApiException error) {
    final code = _denialCode(error);
    if (code == 'home_access_denied') {
      throw const AuthorizationSyncException('Access to this home is no longer available.');
    }
    if (code == 'device_binding_mismatch') {
      throw BindingSyncException(
        'Saved work has a different device binding and needs recovery. It has not been reassigned.',
        code: code,
      );
    }
    // Old servers and wrong endpoints may return a generic 403/404. Neither
    // establishes revoked membership or authorizes deletion of offline intent.
    throw const RetryableSyncException(
      'The server did not confirm home access. Check the API address, deployment and permissions; saved work has been kept.',
    );
  }

''' + s[pos:]
p.write_text(s)

p = Path('lib/core/synchronization/sync_coordinator.dart')
s = p.read_text()
if 'status: SyncRunStatus.uploadsBlocked' not in s:
    # A binding failure from receipt lookup must not fall through to a push.
    s = s.replace('} on AuthenticationSyncException {\n', '} on BindingSyncException {\n              rethrow;\n            } on AuthenticationSyncException {\n')
    marker = '        } on AuthenticationSyncException catch (error) {'
    assert marker in s
    s = s.replace(marker, '''        } on BindingSyncException catch (error) {
          await _local.applyPushResults(
            results: <PushOperationResult>[
              PushOperationResult(
                operationId: operation.operationId,
                kind: PushResultKind.authorizationFailure,
                code: error.code,
                safeMessage: error.safeMessage,
              ),
            ],
            now: _clock().toUtc(),
            retryPolicy: _retryPolicy,
          );
          // Keep pulling authorized remote changes, but do not skip the blocked
          // predecessor or report the upload queue as successfully synchronized.
          break;
''' + marker, 1)
    s = s.replace('so this generic denial is not misreported', 'so this verified home denial is not misreported')
    marker = '      _metrics.recordSuccess('
    assert marker in s
    s = s.replace(marker, '''      final remaining = await _local.watchSummary(homeId: homeId).first;
      if (remaining.blocked > 0) {
        _metrics.recordFailure(classification: 'uploads_blocked');
        return SyncRunOutcome(
          status: SyncRunStatus.uploadsBlocked,
          pullCompleted: true,
          remainingUploads: remaining.unresolved,
          acknowledgedCount: acknowledged,
          pulledChangeCount: pulled,
          safeMessage: 'Downloads are current, but ${remaining.unresolved} saved upload(s) need attention. '
              '${remaining.lastSafeError ?? 'Review the first blocked operation before retrying.'}',
        );
      }
      if (remaining.unresolved > 0) {
        _metrics.recordFailure(classification: 'uploads_pending');
        return SyncRunOutcome(
          status: SyncRunStatus.uploadsPending,
          pullCompleted: true,
          remainingUploads: remaining.unresolved,
          acknowledgedCount: acknowledged,
          pulledChangeCount: pulled,
          safeMessage: 'Downloads are current; ${remaining.unresolved} saved upload(s) are still queued.',
        );
      }
      _metrics.recordSuccess(''', 1)
    s = s.replace('        status: SyncRunStatus.completed,', '        status: SyncRunStatus.completed,\n        pullCompleted: true,', 1)
p.write_text(s)
p = Path('lib/features/inventory/infrastructure/item_master_refreshing_synchronization.dart')
s = p.read_text().replace('if (!outcome.completed)', 'if (!outcome.completed && !outcome.pullCompleted)')
s = s.replace('if (outcome.status != SyncRunStatus.completed)', 'if (!outcome.completed && !outcome.pullCompleted)')
p.write_text(s)

p = Path('test/core/synchronization/sync_coordinator_test.dart')
s = p.read_text()
if "test('binding mismatch preserves" not in s:
    s = s.replace("import 'package:providentia/core/synchronization/sync_coordinator.dart';", "import 'package:providentia/core/synchronization/sync_coordinator.dart';\nimport 'package:providentia/core/synchronization/session_bound_sync_gateway.dart';")
    marker = '  tearDown(() => database.close());'
    addition = '''

  test('binding mismatch preserves intent, permits downloads and reports blocked uploads', () async {
    await local.commitLocalMutation(_mutation());
    final remote = _FakeGateway();
    final coordinator = SyncCoordinator(
      local: local,
      remote: SessionBoundSyncGateway(
        delegate: remote, homeId: 'home-1', deviceId: 'different-session-device',
        isCurrent: () => true,
      ),
      connectivity: const _OnlineProbe(),
      clock: () => now,
    );
    final first = await coordinator.synchronize('home-1');
    expect(first.status, SyncRunStatus.uploadsBlocked);
    expect(first.completed, isFalse);
    expect(first.pullCompleted, isTrue);
    expect(first.remainingUploads, 1);
    final saved = await database.select(database.clientOperations).getSingle();
    expect(saved.deviceId, 'device-1');
    expect(saved.operationId, 'operation-1');
    expect(saved.state, ClientOperationState.blockedAuthorization.storageValue);
    expect(remote.pushedOperationIds, isEmpty);
    expect(remote.statusOperationIds, isEmpty);
    // A later successful pull cannot hide the already blocked predecessor.
    final second = await coordinator.synchronize('home-1');
    expect(second.status, SyncRunStatus.uploadsBlocked);
    expect(second.pullCompleted, isTrue);
    expect(remote.pushedOperationIds, isEmpty);
  });

  test('a terminal validation result is not a successful synchronization', () async {
    await local.commitLocalMutation(_mutation());
    final coordinator = SyncCoordinator(
      local: local,
      remote: _FakeGateway(pushHandler: (_, operations) async => PushResponse(results: [
        PushOperationResult(operationId: operations.single.operationId,
            kind: PushResultKind.validationError, code: 'resource_unavailable',
            safeMessage: 'A referenced record needs review.'),
      ])),
      connectivity: const _OnlineProbe(), clock: () => now,
    );
    final result = await coordinator.synchronize('home-1');
    expect(result.status, SyncRunStatus.uploadsBlocked);
    expect(result.pullCompleted, isTrue);
    expect(result.remainingUploads, 1);
    expect(result.safeMessage, contains('referenced record'));
  });
'''
    s = s.replace(marker, marker + addition)
p.write_text(s)

Path('test/core/synchronization/handover_denial_classification_test.dart').write_text('''import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart' as generated;

void main() {
  const home = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
  const device = '0198a0b1-c2d3-7e4f-a345-6789abcdef01';
  const operation = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';
  GeneratedSyncGateway gateway(int status, String type) => GeneratedSyncGateway(
    generated.ProvidentiaApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      httpClient: MockClient((_) async => http.Response(jsonEncode({
        'type': type, 'title': 'Unavailable', 'status': status,
        'detail': 'Device mismatch and revoked home: prose must not classify.',
        'requestId': operation,
      }), status, headers: {'content-type': 'application/problem+json'})),
    ),
  );

  for (final status in [403, 404]) {
    test('unclassified HTTP $status never establishes purge authority', () async {
      final remote = gateway(status, 'about:blank');
      await expectLater(remote.pull(homeId: home, afterCursor: 'cursor'),
          throwsA(isA<RetryableSyncException>()));
      await expectLater(remote.bootstrap(homeId: home),
          throwsA(isA<RetryableSyncException>()));
      await expectLater(remote.operationStatuses(homeId: home, deviceId: device, operationIds: [operation]),
          throwsA(isA<RetryableSyncException>()));
    });
  }
  test('only the explicit home-access machine type permits revocation handling', () async {
    await expectLater(gateway(404, 'https://providentia.invalid/problems/sync_home_access_denied')
        .pull(homeId: home, afterCursor: 'cursor'), throwsA(isA<AuthorizationSyncException>()));
  });
  test('device mismatch remains a recoverable binding issue, not expired login', () async {
    await expectLater(gateway(403, 'https://providentia.invalid/problems/sync_device_mismatch')
        .operationStatuses(homeId: home, deviceId: device, operationIds: [operation]),
        throwsA(isA<BindingSyncException>().having((e) => e.code, 'code', 'device_binding_mismatch')));
  });
  test('permission change does not falsely establish revoked membership', () async {
    await expectLater(gateway(404, 'https://providentia.invalid/problems/sync_permission_denied')
        .pull(homeId: home, afterCursor: 'cursor'), throwsA(isA<RetryableSyncException>()));
  });
  test('diagnostic codes are bounded to the known vocabulary', () {
    expect(sanitizedSyncFailureCode(null), isNull);
    expect(sanitizedSyncFailureCode('home_access_denied'), 'home_access_denied');
    expect(sanitizedSyncFailureCode('private household name'), 'unclassified_failure');
  });
  test('generated results retain machine codes and protocol-v2 command data', () {
    final result = generated.SyncOperationResult.fromJson({
      'operationId': operation, 'status': 'conflict', 'code': 'revision_mismatch',
      'result': {'revision': 3, 'id': home},
    });
    expect(result.code, 'revision_mismatch');
    expect(result.commandResult?['revision'], 3);
    expect(() => result.commandResult!['revision'] = 4, throwsUnsupportedError);
  });
}
''')
Path('docs/handover-sync-health.md').write_text('''# Synchronization health and failure boundaries

A completed download is not proof that saved uploads succeeded. The coordinator
reports `uploadsBlocked` for a rejected/binding-blocked predecessor and
`uploadsPending` for work still queued or delayed. Both can have
`pullCompleted: true`; only an empty unresolved queue and a completed pull
produce full success. The existing dependency barrier is retained.

Device-binding mismatch is a dedicated binding failure, never an expired-login
signal. No operation ID, payload or device is rewritten. Only the explicit
backend `sync_home_access_denied` machine type may enter revoked-home handling.
Generic HTTP 403/404, missing referenced records, permission changes and wrong
endpoints retain saved work. English error text is never treated as proof of
membership loss. Older servers without machine classifications need a deployment
or permission check, not destructive cache or queue clearing.

The generated adapter now retains result codes and protocol-v2 command result
projections rather than dropping them. Existing scoped operation receipts and
exact retries remain the only automatic ambiguous-outcome recovery path. This
change does not establish authorship or repair a historical schema-2 queue.
''')
print('Sync failure boundaries, upload/download health and regressions applied.')
