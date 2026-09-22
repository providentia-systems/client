#!/usr/bin/env python3
"""Assert enqueue sequence, not fabricated timestamps, as dependency order."""
from pathlib import Path
import re
p = Path('lib/core/database/drift_local_sync_repository.dart')
s = p.read_text().replace('clientTimestamp: row.clientTimestamp,', 'clientTimestamp: row.clientTimestamp.toUtc(),')
p.write_text(s)
p = Path('test/core/database/drift_household_repository_test.dart')
s = p.read_text()
s = s.replace('(row) => OrderingTerm.asc(row.clientTimestamp),', '(row) => OrderingTerm.asc(row.enqueueSequence),')
s, count = re.subn(r'operations\[index\]\.clientTimestamp\.isAfter\(\s*operations\[index - 1\]\.clientTimestamp,\s*\)', 'operations[index].enqueueSequence! > operations[index - 1].enqueueSequence!', s)
assert count == 2, 'Expected the two historical timestamp-based dependency assertions.'
p.write_text(s)
p = Path('test/core/database/drift_local_sync_repository_test.dart')
s = p.read_text()
a = s.index("  test('resync replays multiple intents in deterministic order'")
b = s.index('\n  test(', a + 8)
part = s[a:b].replace('resync replays multiple intents in deterministic order', 'resync replays enqueue order even when the clock moves backwards')
part = part.replace("expect(jsonDecode(record.payload), <String, Object?>{'quantity': 13});", "expect(jsonDecode(record.payload), <String, Object?>{'quantity': 12});")
part = part.replace('    final record = await database.select(database.localRecords).getSingle();', '''    final replayed = await repository.pendingOperations(homeId: 'home-1', now: clock);
    expect(replayed.map((row) => row.operationId), ['operation-z', 'operation-a']);
    expect(replayed.map((row) => row.enqueueSequence), [1, 2]);
    expect(replayed.first.clientTimestamp.toUtc(), DateTime.utc(2026, 7, 29, 13));
    expect(replayed.last.clientTimestamp.toUtc(), DateTime.utc(2026, 7, 29, 12));
    final record = await database.select(database.localRecords).getSingle();''', 1)
s = s[:a] + part + s[b:]
p.write_text(s)
print('Counts, receipts and bootstrap now assert immutable timestamps plus monotonic replay order.')
