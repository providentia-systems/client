import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdtemp, mkdir, readFile, writeFile, rm, copyFile} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {gunzipSync} from 'node:zlib';
import test from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
const contractPath = 'contracts/providentia-v1.json';

async function verifyMutationRejected(mutate, expected) {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'providentia-contract-'));
  try {
    await mkdir(path.join(temporary, 'tool'), {recursive: true});
    await mkdir(path.join(temporary, 'contracts/design-tokens'), {recursive: true});
    await copyFile(path.join(root, 'tool/generate_api_client.mjs'), path.join(temporary, 'tool/generate_api_client.mjs'));
    await copyFile(path.join(root, 'contracts/design-tokens/providentia-v1.json'), path.join(temporary, 'contracts/design-tokens/providentia-v1.json'));
    const contract = JSON.parse(await readFile(path.join(root, contractPath), 'utf8'));
    mutate(contract);
    await writeFile(path.join(temporary, contractPath), JSON.stringify(contract));
    assert.throws(() => execFileSync(process.execPath, ['tool/generate_api_client.mjs'], {cwd: temporary, stdio: 'pipe'}), expected);
  } finally {
    await rm(temporary, {recursive: true, force: true});
  }
}

test('supported contract archive, lock and generated manifest agree exactly', async () => {
  const bytes = await readFile(path.join(root, contractPath));
  const archive = await readFile(path.join(root, 'contracts/source/providentia-v1.json.gz'));
  const lock = JSON.parse(await readFile(path.join(root, 'contracts/contract.lock.json'), 'utf8'));
  const manifest = JSON.parse(await readFile(path.join(root, 'contracts/generated/providentia_api_client/generation-manifest.json'), 'utf8'));
  assert.deepEqual(gunzipSync(archive), bytes);
  const digest = createHash('sha256').update(bytes).digest('hex');
  assert.equal(lock.sha256, digest);
  assert.equal(manifest.contractSha256, digest);
  assert.equal(lock.version, '2.4.0');
  assert.equal(manifest.contractVersion, lock.version);
});

test('generator rejects timestamp substitution for receipt calendar dates', async () => {
  await verifyMutationRejected(c => { c.components.schemas.Receipt.properties.purchaseDate.format = 'date-time'; }, /calendar-date semantics/);
});

test('generator rejects lost signed ledger semantics', async () => {
  await verifyMutationRejected(c => { c.components.schemas.InventoryBalance.properties.quantity.pattern = '^[0-9]+$'; }, /signed ledger quantities/);
});

test('generator rejects missing chronological evidence', async () => {
  await verifyMutationRejected(c => { delete c.components.schemas.InventoryBalance.properties.uncertain; }, /retain uncertain evidence/);
});

test('generator rejects a removed audited correction synchronization command', async () => {
  await verifyMutationRejected(c => { const p = c.components.schemas.SyncPantryCommand.properties.commandType; p.enum = p.enum.filter(x => x !== 'purchasing.receipt-line.correct'); }, /Supported synchronization command missing/);
});
