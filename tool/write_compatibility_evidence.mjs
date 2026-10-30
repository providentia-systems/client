import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const lock = JSON.parse(await readFile(path.join(root, 'contracts/contract.lock.json'), 'utf8'));
const manifest = JSON.parse(await readFile(path.join(root, 'contracts/generated/providentia_api_client/generation-manifest.json'), 'utf8'));
const supported = JSON.parse(await readFile(path.join(root, 'contracts/supported-backend.json'), 'utf8'));
const contract = await readFile(path.join(root, lock.path));
const digest = createHash('sha256').update(contract).digest('hex');
if (digest !== lock.sha256 || digest !== supported.contractSha256 || lock.version !== supported.apiVersion) {
  throw new Error('Canonical contract, lock and supported backend declaration differ.');
}
if (!/^[0-9a-f]{40}$/.test(supported.contractSourceRevision)) {
  throw new Error('The canonical backend source must be pinned to a full commit SHA.');
}
const output = path.resolve(root, process.argv[2] ?? 'build/compliance/client-compatibility.json');
const revision = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
const evidence = {
  schemaVersion: 1,
  clientRevision: revision,
  canonicalBackend: supported,
  contractVersion: lock.version,
  contractSha256: digest,
  generatedManifest: manifest,
  validationScope: 'synthetic-source-and-persistence',
  deploymentAcceptance: 'not-established-by-this-record',
  requiredInstalledEvidence: [
    'deployed Client and backend build revisions and contract digests',
    'backend migration status from authenticated synchronization diagnostics',
    'native persisted database restart and original-binding recovery',
    'deployed browser cookie isolation and encrypted persistence',
    'two-device authoritative receipt, stock and date readback',
  ],
};
await mkdir(path.dirname(output), { recursive: true });
await writeFile(output, `${JSON.stringify(evidence, null, 2)}\n`);
console.log(`Recorded Client ${revision}, API ${lock.version}, SHA256 ${digest}.`);
