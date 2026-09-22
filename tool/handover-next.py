#!/usr/bin/env python3
"""Update the two remaining regressions for the intended safety semantics."""
from pathlib import Path
p = Path('test/app/revoked_home_sync_purge_test.dart')
s = p.read_text()
s = s.replace('real HTTP 404 quiesces production sync, purges caches, and routes away', 'verified home-denial HTTP 404 quiesces sync, purges caches, and routes away')
a = s.index("'verified home-denial HTTP 404")
b = s.index("  for (", a)
part = s[a:b].replace("'type': 'about:blank',", "'type': 'https://providentia.invalid/problems/sync_home_access_denied',")
s = s[:a] + part + s[b:]
p.write_text(s)
p = Path('test/core/synchronization/multi_device_synchronization_test.dart')
s = p.read_text().replace('    expect(deviceBOutcome.completed, isTrue);', '''    expect(deviceBOutcome.completed, isFalse);
    expect(deviceBOutcome.pullCompleted, isTrue);
    expect(deviceBOutcome.status, SyncRunStatus.uploadsBlocked);
    expect(deviceBOutcome.remainingUploads, 1);''')
p.write_text(s)
print('Conflict preservation and verified home-revocation routing assertions retained and strengthened.')
