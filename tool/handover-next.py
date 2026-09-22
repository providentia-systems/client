#!/usr/bin/env python3
"""Add conservative schema-3 outbox provenance without rewriting old intent."""
from pathlib import Path
import re

p = Path('lib/core/database/app_database.dart')
s = p.read_text()
if 'class LocalOperationSequences' not in s:
    s = s.replace('class LocalSyncCursors extends Table {', '''/// A database-local monotonic order, independent of clocks and UUID ordering.
class LocalOperationSequences extends Table {
  IntColumn get id => integer()();
  IntColumn get nextSequence => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class LocalSyncCursors extends Table {''')
    s = s.replace('class ClientOperations extends Table {', '''class ClientOperations extends Table {
  /// Null means historical authorship is unknown, not the signed-in account.
  TextColumn get originatingAccountId => text().nullable()();
  IntColumn get enqueueSequence => integer().nullable()();
  TextColumn get safeFailureCode => text().nullable()();
  TextColumn get requestCorrelationId => text().nullable()();''')
    s = s.replace('    ClientOperations,', '    ClientOperations,\n    LocalOperationSequences,', 1)
    s = s.replace('int get schemaVersion => 2;', 'int get schemaVersion => 3;')
    marker = '    },\n    beforeOpen:'
    s = s.replace(marker, '''      if (from < 3) {
        // Do not infer the creator, device, execution state or dependency order
        // of historical rows. Their original operation envelopes stay intact.
        await migrator.addColumn(clientOperations, clientOperations.originatingAccountId);
        await migrator.addColumn(clientOperations, clientOperations.enqueueSequence);
        await migrator.addColumn(clientOperations, clientOperations.safeFailureCode);
        await migrator.addColumn(clientOperations, clientOperations.requestCorrelationId);
        await migrator.createTable(localOperationSequences);
      }
''' + marker, 1)
    pos = s.index('  @override\n  MigrationStrategy get migration')
    s = s[:pos] + '''  /// Call inside the same transaction as the optimistic record and outbox row.
  /// Nested Drift transactions preserve rollback and serialize concurrent writers.
  Future<int> allocateOperationSequence() => transaction(() async {
    await into(localOperationSequences).insert(
      LocalOperationSequencesCompanion.insert(id: const Value(1), nextSequence: 1),
      mode: InsertMode.insertOrIgnore,
    );
    final current = await (select(localOperationSequences)
      ..where((row) => row.id.equals(1))).getSingle();
    await (update(localOperationSequences)..where((row) => row.id.equals(1))).write(
      LocalOperationSequencesCompanion(nextSequence: Value(current.nextSequence + 1)),
    );
    return current.nextSequence;
  });

''' + s[pos:]
p.write_text(s)

p = Path('lib/core/synchronization/sync_models.dart')
s = p.read_text()
a = s.index('final class LocalMutation {')
b = s.index('final class PushOperationResult', a)
part = s[a:b]
if 'originatingAccountId' not in part:
    part = part.replace('    required String deviceId,', '    required String deviceId,\n    String? originatingAccountId,', 1)
    part = part.replace("    _requireNonEmpty(deviceId, 'deviceId');", "    _requireNonEmpty(deviceId, 'deviceId');\n    if (originatingAccountId != null) _requireNonEmpty(originatingAccountId, 'originatingAccountId');", 1)
    part = part.replace('      deviceId: deviceId,', '      deviceId: deviceId,\n      originatingAccountId: originatingAccountId,', 1)
    part = part.replace('    required this.deviceId,', '    required this.deviceId,\n    this.originatingAccountId,')
    part = part.replace('  final String deviceId;', '  final String deviceId;\n  final String? originatingAccountId;')
    c = part.index('final class PendingClientOperation')
    part = part[:c] + part[c:].replace('    required this.retryCount,', '    required this.retryCount,\n    this.enqueueSequence,').replace('  final int retryCount;', '  final int retryCount;\n  final int? enqueueSequence;')
    s = s[:a] + part + s[b:]
p.write_text(s)

p = Path('lib/core/synchronization/sync_ports.dart')
s = p.read_text()
if 'abstract interface class SyncOperationBindingValidator' not in s:
    s += '''
/// Local provenance is checked before receipt lookup as well as command push.
abstract interface class SyncOperationBindingValidator {
  void validateOperationBinding(PendingClientOperation operation);
}
'''
p.write_text(s)
p = Path('lib/core/synchronization/session_bound_sync_gateway.dart')
s = p.read_text()
if 'this.accountId' not in s:
    s = s.replace('implements SyncRemoteGateway {', 'implements SyncRemoteGateway, SyncOperationBindingValidator {')
    s = s.replace('    required String deviceId,', '    required String deviceId,\n    String? accountId,', 1)
    s = s.replace('SessionBoundSyncGateway._(delegate, homeId, deviceId, isCurrent)', 'SessionBoundSyncGateway._(delegate, homeId, deviceId, isCurrent, accountId)')
    s = s.replace('    this._isCurrent,', '    this._isCurrent,\n    this.accountId,', 1)
    s = s.replace('  final String deviceId;', '  final String deviceId;\n  final String? accountId;', 1)
    pos = s.index('  Future<T> _bound<T>')
    s = s[:pos] + '''  @override
  void validateOperationBinding(PendingClientOperation operation) {
    _requireCurrent(operation.homeId);
    _requireDevice(operation.deviceId);
    if (accountId == null) return;
    if (operation.originatingAccountId == null) {
      throw const BindingSyncException(
        'The creator of this historical saved operation is unknown. '
        'It needs explicit recovery review and has not been reassigned or sent.',
        code: 'origin_account_unknown',
      );
    }
    if (operation.originatingAccountId != accountId) {
      throw const BindingSyncException(
        'This saved operation belongs to another account. '
        'It has not been reassigned, queried or sent.',
        code: 'account_binding_mismatch',
      );
    }
  }

''' + s[pos:]
    s = s.replace('      _requireCurrent(operation.homeId);\n      _requireDevice(operation.deviceId);', '      validateOperationBinding(operation);')
p.write_text(s)
p = Path('lib/core/synchronization/sync_coordinator.dart')
s = p.read_text()
if 'validator.validateOperationBinding(operation)' not in s:
    marker = '        try {\n'
    a = s.index('for (final operation in operations)')
    b = s.index(marker, a)
    s = s[:b] + s[b:].replace(marker, '''        try {
          final validator = _remote;
          if (validator is SyncOperationBindingValidator) {
            validator.validateOperationBinding(operation);
          }
''', 1)
p.write_text(s)

# The local writer guards both sides of asynchronous transactions. A response
# arriving after an account/home switch cannot commit into the retired workspace.
p = Path('lib/core/database/drift_local_sync_repository.dart')
s = p.read_text()
if 'String? accountId,' not in s:
    s = s.replace('    DateTime Function()? clock,', '    DateTime Function()? clock,\n    String? accountId,\n    bool Function()? isCurrent,', 1)
    s = s.replace('}) : _clock = clock ?? DateTime.now;', '}) : _clock = clock ?? DateTime.now, _accountId = accountId, _isCurrent = isCurrent;', 1)
    s = s.replace('  final AppDatabase _database;', '  final AppDatabase _database;\n  final String? _accountId;\n  final bool Function()? _isCurrent;', 1)
    s = s.replace('_database.transaction(', '_transaction(')
    pos = s.index('  @override')
    s = s[:pos] + '''  void _requireCurrent() {
    if (_isCurrent != null && !_isCurrent()) {
      throw const AuthenticationSyncException('The synchronization workspace changed. Reopen the current home.');
    }
  }

  Future<T> _transaction<T>(Future<T> Function() action) => _database.transaction(() async {
    _requireCurrent();
    final value = await action();
    _requireCurrent();
    return value;
  });

''' + s[pos:]
    s = s.replace('      await _upsertLocalRecord(', '''      if (_accountId != null && mutation.originatingAccountId != null &&
          mutation.originatingAccountId != _accountId) {
        throw const BindingSyncException('The command belongs to another account.', code: 'account_binding_mismatch');
      }
      final sequence = await _database.allocateOperationSequence();
      await _upsertLocalRecord(''', 1)
    s = s.replace('              operationId: mutation.operationId,', '''              operationId: mutation.operationId,
              originatingAccountId: Value(_accountId ?? mutation.originatingAccountId),
              enqueueSequence: Value(sequence),''', 1)
    # Legacy null sequences intentionally remain ahead of new proven operations.
    s = re.sub(r'(\(row\) => OrderingTerm.asc\(row.clientTimestamp\),)', '(row) => OrderingTerm.asc(row.enqueueSequence),\n                      \\1', s)
    s = s.replace('          operationId: row.operationId,', '          operationId: row.operationId,\n          originatingAccountId: row.originatingAccountId,\n          enqueueSequence: row.enqueueSequence,', 1)
    s = s.replace('                lastSafeError: Value<String?>(result.safeMessage),', '''                lastSafeError: Value<String?>(result.safeMessage),
                safeFailureCode: Value(sanitizedSyncFailureCode(result.code)),
                requestCorrelationId: Value(result.requestId != null && isUuid(result.requestId!) ? result.requestId : null),''', 1)
    s = s.replace('              deviceId: context.operation.deviceId,', '''              deviceId: context.operation.deviceId,
              originatingAccountId: Value(context.operation.originatingAccountId),
              enqueueSequence: Value(context.operation.enqueueSequence),''', 1)
    # Unknown provenance is not made known by selecting an old conflict.
    marker = '      _validateReapplicationIntent(context.operation);'
    s = s.replace(marker, '''      if (_accountId != null && context.operation.originatingAccountId != _accountId) {
        throw const SyncConflictResolutionException('The original account binding is not verified. Review recovery before creating a replacement.');
      }
''' + marker, 1)
    # The summary exposes the first actual unresolved error, not stale acknowledged rows.
    s = s.replace('final safeErrors = rows', '''final orderedRows = [...rows]..sort((a, b) {
        if (a.enqueueSequence == null && b.enqueueSequence != null) return -1;
        if (a.enqueueSequence != null && b.enqueueSequence == null) return 1;
        final sequence = (a.enqueueSequence ?? 0).compareTo(b.enqueueSequence ?? 0);
        if (sequence != 0) return sequence;
        final timestamp = a.clientTimestamp.compareTo(b.clientTimestamp);
        return timestamp != 0 ? timestamp : a.operationId.compareTo(b.operationId);
      });
      final safeErrors = orderedRows.where((row) =>
          row.state != ClientOperationState.acknowledged.storageValue &&
          row.state != ClientOperationState.superseded.storageValue)''')
p.write_text(s)

p = Path('lib/core/database/drift_household_repository.dart')
s = p.read_text()
if 'String? originatingAccountId,' not in s:
    s = s.replace('    String? deviceId,', '    String? deviceId,\n    String? originatingAccountId,\n    bool Function()? isCurrent,', 1)
    s = s.replace('    if (deviceId != null && !isUuid(deviceId)) {', '''    if (originatingAccountId != null && !isUuid(originatingAccountId)) {
      throw ArgumentError.value(originatingAccountId, 'originatingAccountId', 'must be a UUID');
    }
    if (deviceId != null && !isUuid(deviceId)) {''', 1)
    s = s.replace('      stockPreferenceReader,\n    );', '      stockPreferenceReader,\n      originatingAccountId,\n      isCurrent,\n    );', 1)
    s = s.replace('    this._stockPreferenceReader,', '    this._stockPreferenceReader,\n    this._originatingAccountId,\n    this._isCurrent,', 1)
    s = s.replace('  final String? _deviceId;', '  final String? _deviceId;\n  final String? _originatingAccountId;\n  final bool Function()? _isCurrent;', 1)
    s = s.replace('_database.transaction(', '_transaction(')
    pos = s.index('  bool get _synchronizesMutations')
    s = s[:pos] + '''  Future<T> _transaction<T>(Future<T> Function() action) => _database.transaction(() async {
    _requireCurrentWriter();
    final result = await action();
    _requireCurrentWriter();
    return result;
  });

  void _requireCurrentWriter() {
    if (_isCurrent != null && !_isCurrent()) {
      throw const AuthenticationSyncException('The household workspace changed. Reopen the current home.');
    }
  }

''' + s[pos:]
    a = s.index('    final latestQuery = _database.select(_database.clientOperations)', s.index('Future<void> _insertCommand('))
    b = s.index('    await _database\n        .into(_database.clientOperations)', a)
    s = s[:a] + '    _requireCurrentWriter();\n    final sequence = await _database.allocateOperationSequence();\n' + s[b:]
    a = s.index('  Future<void> _insertCommand(')
    b = s.index('  String _nextUuid(', a)
    part = s[a:b].replace('            operationId: operationId,', '''            operationId: operationId,
            originatingAccountId: Value(_originatingAccountId),
            enqueueSequence: Value(sequence),''', 1)
    part = part.replace('// This timestamp is also the durable dependency order. UUIDv4 values\n            // are intentionally random and must never decide parent/child order.\n            clientTimestamp: enqueueAt,', '// Wall-clock metadata never decides dependency ordering.\n            clientTimestamp: at.toUtc(),')
    s = s[:a] + part + s[b:]
p.write_text(s)

p = Path('lib/app/production_bootstrap_app.dart')
s = p.read_text()
if 'accountId: widget.userId' not in s:
    s = s.replace('final localSync = DriftLocalSyncRepository(widget.database);', '''final localSync = DriftLocalSyncRepository(widget.database,
      accountId: widget.userId, isCurrent: () => _bindingIsCurrent);''', 1)
    a = s.index('final household = createProductionHouseholdRepository(')
    b = s.index('_syncGateway = SessionBoundSyncGateway(', a)
    part = s[a:b].replace('      database: widget.database,', '''      database: widget.database,
      originatingAccountId: widget.userId,
      isCurrent: () => _bindingIsCurrent,''', 1)
    s = s[:a] + part + s[b:]
    a = s.index('_syncGateway = SessionBoundSyncGateway(')
    b = s.index('    );', a)
    s = s[:a] + s[a:b].replace('      deviceId: widget.deviceId,', '      deviceId: widget.deviceId,\n      accountId: widget.userId,') + s[b:]
    a = s.index('DriftHouseholdRepository createProductionHouseholdRepository({')
    b = s.index('\n}', a) + 2
    part = s[a:b]
    part = part.replace('  required AppDatabase database,', '  required AppDatabase database,\n  String? originatingAccountId,\n  bool Function()? isCurrent,', 1)
    part = part.replace('    deviceId: deviceId,', '    deviceId: deviceId,\n    originatingAccountId: originatingAccountId,\n    isCurrent: isCurrent,', 1)
    assert 'originatingAccountId: originatingAccountId' in part, 'Production writer must explicitly receive provenance.'
    s = s[:a] + part + s[b:]
p.write_text(s)

Path('test/core/synchronization/outbox_provenance_test.dart').write_text('''import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/session_bound_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

const account = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
LocalMutation mutation(String id, DateTime at) => LocalMutation(
  operationId: id, deviceId: 'device', homeId: 'home', entityType: 'item',
  entityId: id, operationType: 'create', clientTimestamp: at,
  payloadSchemaVersion: 1, payload: {'quantity': 1},
);
PendingClientOperation pending(String? owner) => PendingClientOperation(
  operationId: 'op', deviceId: 'device', homeId: 'home', originatingAccountId: owner,
  entityType: 'item', entityId: 'item', operationType: 'create',
  clientTimestamp: DateTime.utc(2026), payloadSchemaVersion: 1, payload: {}, retryCount: 0,
);
void main() {
  test('enqueue order survives equal or backwards clocks and random UUID order', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final local = DriftLocalSyncRepository(db, accountId: account);
    final now = DateTime.utc(2026, 9, 22);
    await local.commitLocalMutation(mutation('z-parent', now));
    await local.commitLocalMutation(mutation('a-child', now.subtract(const Duration(days: 1))));
    final rows = await local.pendingOperations(homeId: 'home', now: now);
    expect(rows.map((row) => row.operationId), ['z-parent', 'a-child']);
    expect(rows.map((row) => row.enqueueSequence), [1, 2]);
    expect(rows.every((row) => row.originatingAccountId == account), isTrue);
    expect(rows.last.clientTimestamp, now.subtract(const Duration(days: 1)));
  });
  test('retired writer rolls back optimistic state and never consumes an order', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var checks = 0;
    final local = DriftLocalSyncRepository(db, accountId: account, isCurrent: () => ++checks == 1);
    await expectLater(local.commitLocalMutation(mutation('old', DateTime.utc(2026))),
        throwsA(isA<AuthenticationSyncException>()));
    expect(await db.select(db.clientOperations).get(), isEmpty);
    expect(await db.select(db.localRecords).get(), isEmpty);
    final current = DriftLocalSyncRepository(db, accountId: account);
    await current.commitLocalMutation(mutation('new', DateTime.utc(2026)));
    expect((await current.pendingOperations(homeId: 'home', now: DateTime.utc(2026))).single.enqueueSequence, 1);
  });
  test('account provenance is checked before transport or receipt recovery', () async {
    final gateway = SessionBoundSyncGateway(delegate: _NoTransport(), homeId: 'home',
      deviceId: 'device', accountId: account, isCurrent: () => true);
    for (final entry in {null: 'origin_account_unknown', 'another-account': 'account_binding_mismatch'}.entries) {
      expect(() => gateway.validateOperationBinding(pending(entry.key)),
          throwsA(isA<BindingSyncException>().having((e) => e.code, 'code', entry.value)));
      await expectLater(gateway.push(homeId: 'home', lastPulledCursor: null, operations: [pending(entry.key)]),
          throwsA(isA<BindingSyncException>()));
    }
    gateway.validateOperationBinding(pending(account));
  });
}
class _NoTransport implements SyncRemoteGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('No transport may be invoked by a provenance check.');
}
''')
Path('docs/outbox-provenance.md').write_text('''# Durable outbox provenance — local schema 3

New production commands record the authenticated account, original device and a
transactionally allocated monotonic sequence. Clock adjustments and random UUID
ordering do not reorder parent/child commands or alter their event timestamps.
The counter and optimistic writes roll back together. Explicit conflict
reapplication retains the original logical position and verified provenance;
it does not silently claim historical work for the current user.

Schema 1/2 upgrades add nullable metadata without rewriting operation IDs,
payloads, device IDs, timestamps, receipts or unknown authorship. A null account
is **unknown**, not the current account. Production validates the original
account/home/device before receipt lookup and push. Unknown or mismatching
operations become durable review blockers, never automatic replacement commands.

Production local writers guard both ends of asynchronous transactions against
account/home/permission changes. Late network responses cannot commit into a
retired workspace. Request correlation identifiers are persisted only when UUID
shaped, and failure codes are restricted to the fixed safe vocabulary. No raw
command payload is added to diagnostic summaries.

The local database schema number is independent of the server feed generation;
existing server feed generation 2 cursor bindings are unchanged. This upgrade
preserves historical work but does not by itself establish its creator or prove
that an old command never executed. Historical recovery still requires verified
receipt/provenance evidence or explicit owner review.
''')
print('Schema-3 provenance, monotonic ordering and production binding guards applied.')
