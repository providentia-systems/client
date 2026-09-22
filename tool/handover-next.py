#!/usr/bin/env python3
"""Complete exhaustive handling without weakening source acknowledgement checks."""
from pathlib import Path
p = Path('lib/core/database/drift_catalog_product_source_preparation.dart')
s = p.read_text()
if 'case SyncRunStatus.uploadsBlocked:' not in s:
    s = s.replace('      case SyncRunStatus.completed:', '      case SyncRunStatus.uploadsBlocked:\n      case SyncRunStatus.uploadsPending:\n      case SyncRunStatus.completed:')
    s = s.replace('// A completed run may contain blocked operations; a catalog refresh', '// Other sources may still be blocked, and a catalog refresh')
p.write_text(s)
p = Path('test/core/synchronization/sync_coordinator_test.dart')
s = p.read_text().replace('final remote = _FakeGateway();', "final remote = _FakeGateway(\n        pushHandler: (_, __) async => throw StateError('A mismatched binding must never be dispatched.'),\n      );")
lines = s.splitlines()
indices = [i for i, line in enumerate(lines) if line.startswith("import 'package:")]
ordered = sorted(lines[i] for i in indices)
for i, line in zip(indices, ordered):
    lines[i] = line
p.write_text('\n'.join(lines) + '\n')
print('Partial sync source guards and binding-failure fixture corrected.')
