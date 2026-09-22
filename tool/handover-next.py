#!/usr/bin/env python3
"""Keep a named public factory and explicit private immutable bindings."""
from pathlib import Path
p = Path('lib/core/database/drift_local_sync_repository.dart')
s = p.read_text()
a = s.index('  DriftLocalSyncRepository(')
b = s.index('\n\n', a)
s = s[:a] + '''  factory DriftLocalSyncRepository(
    AppDatabase database, {
    DateTime Function()? clock,
    String? accountId,
    bool Function()? isCurrent,
  }) => DriftLocalSyncRepository._(database, clock ?? DateTime.now, accountId, isCurrent);

  DriftLocalSyncRepository._(
    this._database,
    this._clock,
    this._accountId,
    this._isCurrent,
  );''' + s[b:]
p.write_text(s)
print('Immutable repository construction follows the existing analyzer requirements.')
