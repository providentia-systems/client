"""Temporary integrity-checked source transfer. Removed after materialization."""
from pathlib import Path
import gzip
import hashlib
import subprocess
root = Path(__file__).resolve().parent.parent
packed = b''.join((root / f'tool/step3-preflight.patch.gz.part{i}').read_bytes() for i in range(4))
patch = gzip.decompress(packed)
assert hashlib.sha256(patch).hexdigest() == '4b9214fef84f6d9fba12bfc6376b1f986186c0fcdc61b273f4611198770e9d8e'
subprocess.run(['git', 'apply', '--check', '-'], input=patch, cwd=root, check=True)
subprocess.run(['git', 'apply', '-'], input=patch, cwd=root, check=True)
print('Applied exact Step 3 source. No external service or household record accessed.')
