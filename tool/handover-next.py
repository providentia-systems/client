#!/usr/bin/env python3
from pathlib import Path
p = Path('test/core/synchronization/sync_coordinator_test.dart')
s = p.read_text().replace('pushHandler: (_, __) async =>', 'pushHandler: (_, _) async =>')
p.write_text(s)
print('Dart wildcard parameter formatting corrected.')
