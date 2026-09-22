#!/usr/bin/env python3
"""Complete the actual production construction and transactional enqueue paths."""
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
# Guard the in-flight marker as a local write, not just transport dispatch.
a = s.index('  Future<void> markSyncing(')
b = s.index('  @override', a + 8)
part = s[a:b]
if 'await _transaction' not in part:
    part = part.replace('    await (_database.update(', '    await _transaction(() async {\n    await (_database.update(', 1)
    last = part.rfind('\n  }')
    part = part[:last] + '\n    });' + part[last:]
s = s[:a] + part + s[b:]
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
b = s.index('\n}', a) + 2
part = s[a:b]
if 'String? originatingAccountId,' not in part:
    part = part.replace('  required AppDatabase database,', '''  required AppDatabase database,
  String? originatingAccountId,
  bool Function()? isCurrent,''', 1)
    part = part.replace('    deviceId: deviceId,', '''    deviceId: deviceId,
    originatingAccountId: originatingAccountId,
    isCurrent: isCurrent,''', 1)
assert 'originatingAccountId: originatingAccountId' in part, 'Production factory must pass account provenance.'
s = s[:a] + part + s[b:]
p.write_text(s)
print('Production account/home binding and transactionally allocated outbox order are explicitly wired.')
