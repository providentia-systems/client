from pathlib import Path
import gzip
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[1]
model = root / 'lib/features/inventory/domain/inventory_models.dart'
if 'const householdStockUnits' not in model.read_text():
    for stage in ('data', 'base', 'ui'):
        subprocess.run(['python3', str(root / f'tool/client-household-{stage}-stage.py')], cwd=root, check=True)
p = root / 'lib/features/inventory/presentation/inventory_controller.dart'
s = p.read_text()
if 'unawaited(_publishedCategoriesSubscription?.cancel())' not in s:
    s = s.replace('    unawaited(_categoriesSubscription?.cancel());', '    unawaited(_categoriesSubscription?.cancel());\n    unawaited(_publishedCategoriesSubscription?.cancel());')
p.write_text(s)
archive = (root.parent / 'paired-backend/contracts/source/providentia-v1.json.gz').read_bytes()
raw = gzip.decompress(archive)
expected = 'ef5714a6298326d6fb449b966117e8b61c74de67d1bfc274ad8ec431aecd802d'
compressed = 'd20ba3f9b769b5e30e59f38ecb83816ff6825a9bb646509440fb731cfc012ff1'
assert hashlib.sha256(raw).hexdigest() == expected
assert hashlib.sha256(archive).hexdigest() == compressed
(root / 'contracts/source/providentia-v1.json.gz').write_bytes(archive)
(root / 'contracts/providentia-v1.json').write_bytes(raw)
p = root / 'contracts/contract.lock.json'
lock = json.loads(p.read_text()); lock['version'] = '2.2.0'; lock['sha256'] = expected
p.write_text(json.dumps(lock, indent=2) + '\n')
for name in ('tool/generate_api_client.mjs', 'tool/materialize-openapi-contract.sh', 'tool/verify_structure.mjs', 'test/contracts/generated_client_test.dart'):
    p = root / name
    s = p.read_text().replace('2.1.0', '2.2.0').replace('13ccdc2d37e73955394a7b7c52da6d9ff7aeefdfd763ac809876737867d15c44', expected).replace('bd106bdfd980823459ec3c769e8aad14cf6c2a2473b38c4708f9e59e635b34cd', compressed)
    p.write_text(s)
subprocess.run(['node', 'tool/generate_api_client.mjs'], cwd=root, check=True)
