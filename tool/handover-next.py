#!/usr/bin/env python3
"""Complete construction paths and test additive, non-destructive outbox migration."""
from pathlib import Path
import re
p = Path('lib/core/database/drift_local_sync_repository.dart')
s = p.read_text()
a = s.index('  DriftLocalSyncRepository(')
b = s.index('\n\n', a)
s = s[:a] + '''  DriftLocalSyncRepository(
    this._database, {
    DateTime Function()? clock,
    String? accountId,
    bool Function()? isCurrent,
  }) : _clock = clock ?? DateTime.now,
       _accountId = accountId,
       _isCurrent = isCurrent;''' + s[b:]
a = s.index('  Future<void> commitLocalMutation(')
b = s.index('  @override', a + 8)
part = s[a:b]
if 'final sequence =' not in part:
    part = part.replace('return _transaction(() async {', '''return _transaction(() async {
      if (_accountId != null && mutation.originatingAccountId != null &&
          mutation.originatingAccountId != _accountId) {
        throw const BindingSyncException(
          'The command belongs to another account.', code: 'account_binding_mismatch');
      }
      final sequence = await _database.allocateOperationSequence();''', 1)
s = s[:a] + part + s[b:]
a = s.index('  Future<void> markSyncing(')
b = s.index('  @override', a + 8)
part = s[a:b]
if 'await _transaction' not in part:
    part = part.replace('    await (_database.update(', '    await _transaction(() async {\n    await (_database.update(', 1)
    last = part.rfind('\n  }')
    part = part[:last] + '\n    });' + part[last:]
s = s[:a] + part + s[b:]
if 'safeFailureCode: Value(' not in s:
    needle = '            lastSafeError: Value<String?>(result.safeMessage),'
    assert needle in s
    s = s.replace(needle, needle + '''
            safeFailureCode: Value(sanitizedSyncFailureCode(result.code)),
            requestCorrelationId: Value(result.requestId != null && isUuid(result.requestId!)
                ? result.requestId : null),''', 1)
p.write_text(s)
p = Path('lib/core/synchronization/sync_coordinator.dart')
s = p.read_text().replace('validator.validateOperationBinding(operation);', '(validator as SyncOperationBindingValidator).validateOperationBinding(operation);')
p.write_text(s)
p = Path('lib/core/synchronization/sync_models.dart')
s = p.read_text()
s = re.sub(r"    if \(originatingAccountId != null\)\s*_requireNonEmpty\(originatingAccountId, 'originatingAccountId'\);", "    if (originatingAccountId != null) {\n      _requireNonEmpty(originatingAccountId, 'originatingAccountId');\n    }", s)
p.write_text(s)
p = Path('lib/app/production_bootstrap_app.dart')
s = p.read_text()
old = 'final localSync = DriftLocalSyncRepository(widget.database);'
if old in s:
    s = s.replace(old, '''final localSync = DriftLocalSyncRepository(widget.database,
      accountId: widget.userId, isCurrent: () => _bindingIsCurrent);''', 1)
a = s.index('final household = createProductionHouseholdRepository(')
b = s.index('_household = household;', a)
part = s[a:b]
if 'originatingAccountId:' not in part:
    part = part.replace('      database: widget.database,', '''      database: widget.database,
      originatingAccountId: widget.userId,
      isCurrent: () => _bindingIsCurrent,''', 1)
s = s[:a] + part + s[b:]
a = s.index('_syncGateway = SessionBoundSyncGateway(')
b = s.index('    );', a)
part = s[a:b]
if 'accountId:' not in part:
    part = part.replace('      deviceId: widget.deviceId,', '      deviceId: widget.deviceId,\n      accountId: widget.userId,', 1)
s = s[:a] + part + s[b:]
a = s.index('DriftHouseholdRepository createProductionHouseholdRepository({')
b = s.index('\n}\n', a) + 2
part = s[a:b]
if 'String? originatingAccountId,' not in part:
    part = part.replace('  required AppDatabase database,', '''  required AppDatabase database,
  String? originatingAccountId,
  bool Function()? isCurrent,''', 1)
    part = part.replace('    deviceId: deviceId,', '''    deviceId: deviceId,
    originatingAccountId: originatingAccountId,
    isCurrent: isCurrent,''', 1)
assert 'originatingAccountId: originatingAccountId' in part, part
s = s[:a] + part + s[b:]
p.write_text(s)
p = Path('test/core/database/app_database_migration_test.dart')
s = p.read_text().replace('v1 to v2 preserves and rebases pending client operations', 'v1 to v3 preserves pending client operations without inventing provenance')
s = s.replace('expect(database.schemaVersion, 2);', '''expect(database.schemaVersion, 3);
    expect(pending.originatingAccountId, isNull);
    expect(pending.enqueueSequence, isNull);
    expect(pending.safeFailureCode, isNull);
    expect(pending.requestCorrelationId, isNull);''')
p.write_text(s)
Path('test/core/database/outbox_v2_migration_test.dart').write_text('''import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';

void main() {
  test('v2 outbox migration preserves every immutable envelope and execution state', () async {
    const states = ['pending', 'syncing', 'retry_wait', 'blocked_conflict',
      'blocked_validation', 'blocked_authorization', 'acknowledged', 'superseded'];
    final database = AppDatabase(NativeDatabase.memory(setup: (raw) {
      raw.execute(\'''CREATE TABLE client_operations (
        operation_id TEXT NOT NULL PRIMARY KEY, device_id TEXT NOT NULL,
        home_id TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
        operation_type TEXT NOT NULL, base_revision INTEGER NULL,
        client_timestamp INTEGER NOT NULL, payload_schema_version INTEGER NOT NULL DEFAULT 1,
        payload TEXT NOT NULL, retry_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER NULL, last_safe_error TEXT NULL, state TEXT NOT NULL,
        server_cursor TEXT NULL, acknowledged_at INTEGER NULL)\''');
      for (var i = 0; i < states.length; i++) {
        raw.execute(\'''INSERT INTO client_operations
          (operation_id, device_id, home_id, entity_type, entity_id, operation_type,
           base_revision, client_timestamp, payload, retry_count, state, server_cursor)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)\''',
          ['operation-$i', 'original-device-$i', 'home-$i', 'item', 'item-$i',
           'create', 4, 1234, '{"quantity":2}', 3, states[i], 'original-cursor']);
      }
      raw.execute('PRAGMA user_version = 2');
    }));
    addTearDown(database.close);
    final rows = await database.select(database.clientOperations).get();
    expect(database.schemaVersion, 3);
    expect(rows.length, states.length);
    for (var i = 0; i < states.length; i++) {
      final row = rows.singleWhere((row) => row.operationId == 'operation-$i');
      expect(row.deviceId, 'original-device-$i');
      expect(row.homeId, 'home-$i');
      expect(row.payload, '{"quantity":2}');
      expect(row.baseRevision, 4);
      expect(row.clientTimestamp.millisecondsSinceEpoch, 1234000);
      expect(row.retryCount, 3);
      expect(row.serverCursor, 'original-cursor');
      expect(row.state, states[i]);
      expect(row.originatingAccountId, isNull);
      expect(row.enqueueSequence, isNull);
      expect(row.safeFailureCode, isNull);
      expect(row.requestCorrelationId, isNull);
    }
    expect(await database.allocateOperationSequence(), 1);
    expect(await database.allocateOperationSequence(), 2);
  });
}
''')
print('Explicit production binding, metadata persistence, and v1/v2 migration regressions installed.')
