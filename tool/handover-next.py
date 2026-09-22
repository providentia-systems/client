#!/usr/bin/env python3
"""Close local mutation boundaries without changing operation payloads or identities."""
from pathlib import Path
p = Path('lib/core/database/drift_local_sync_repository.dart')
s = p.read_text()
for method in ['requeueRetryableOperations', 'requeueOperation']:
    a = s.index('  Future<void> ' + method + '(')
    b = s.index('  @override', a + 8)
    part = s[a:b]
    if 'return _transaction(' not in part:
        assert '}) async {' in part
        part = part.replace('}) async {', '}) {\n    return _transaction(() async {', 1)
        end = part.rfind('\n  }')
        assert end > 0
        part = part[:end] + '\n    });' + part[end:]
        s = s[:a] + part + s[b:]
needle = '    return (conflict: conflict, operation: operation);'
assert needle in s
s = s.replace(needle, '''    if (_accountId != null && operation.originatingAccountId != _accountId) {
      throw const SyncConflictResolutionException(
        'The original account binding is not verified. Review recovery before discarding or replacing saved intent.',
      );
    }
''' + needle, 1)
p.write_text(s)
Path('test/core/synchronization/outbox_resolution_binding_test.dart').write_text('''import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';

const owner = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const other = '0198a0b1-c2d3-7e4f-8123-456789abcdee';
LocalMutation mutation() => LocalMutation(
  operationId: 'operation', deviceId: 'device', homeId: 'home',
  entityType: 'inventory_balance', entityId: 'item', operationType: 'set_count',
  baseRevision: 1, clientTimestamp: DateTime.utc(2026, 9, 22),
  payloadSchemaVersion: 1, payload: {'quantity': 2},
);

void main() {
  for (final all in [false, true]) {
    test('a workspace retired during ${all ? 'bulk' : 'single'} retry rolls back the state change', () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final active = DriftLocalSyncRepository(database, accountId: owner);
      final now = DateTime.utc(2026, 9, 22);
      await active.commitLocalMutation(mutation());
      await active.applyPushResults(results: [PushOperationResult(
        operationId: 'operation', kind: PushResultKind.retryableFailure,
        safeMessage: 'Retry later.', code: 'service_unavailable',
      )], now: now, retryPolicy: RetryPolicy());
      final before = await database.select(database.clientOperations).getSingle();
      var checks = 0;
      final retired = DriftLocalSyncRepository(database, accountId: owner,
          isCurrent: () => ++checks == 1);
      final later = now.add(const Duration(days: 1));
      await expectLater(all
          ? retired.requeueRetryableOperations(homeId: 'home', now: later)
          : retired.requeueOperation(homeId: 'home', operationId: 'operation', now: later),
          throwsA(isA<AuthenticationSyncException>()));
      final after = await database.select(database.clientOperations).getSingle();
      expect(after, before);
      expect(after.state, ClientOperationState.retryWait.storageValue);
    });
  }

  for (final originalAccount in <String?>[null, other, owner]) {
    test('conflict acceptance respects recorded origin $originalAccount', () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final seed = DriftLocalSyncRepository(database, accountId: originalAccount);
      final now = DateTime.utc(2026, 9, 22);
      await seed.commitLocalMutation(mutation());
      await seed.applyPushResults(results: [PushOperationResult(
        operationId: 'operation', kind: PushResultKind.conflict,
        remoteRevision: 2, remotePayload: {'quantity': 3},
        safeMessage: 'The server record changed.', code: 'revision_conflict',
      )], now: now, retryPolicy: RetryPolicy());
      final conflict = (await seed.unresolvedConflicts(homeId: 'home')).single;
      final before = await database.select(database.clientOperations).getSingle();
      final recordBefore = await database.select(database.localRecords).getSingle();
      final current = DriftLocalSyncRepository(database, accountId: owner);
      final resolution = current.acceptRemoteConflict(homeId: 'home',
          conflictId: conflict.id, resolvedAt: now.add(const Duration(minutes: 1)));
      if (originalAccount != owner) {
        await expectLater(resolution, throwsA(isA<SyncConflictResolutionException>()));
        expect(await database.select(database.clientOperations).getSingle(), before);
        expect(await database.select(database.localRecords).getSingle(), recordBefore);
        expect(await current.unresolvedConflicts(homeId: 'home'), hasLength(1));
      } else {
        await resolution;
        expect((await database.select(database.clientOperations).getSingle()).state,
            ClientOperationState.superseded.storageValue);
        expect(await current.unresolvedConflicts(homeId: 'home'), isEmpty);
      }
    });
  }
}
''')
print('Retry writes and every conflict resolution retain the current workspace and original account boundaries.')
