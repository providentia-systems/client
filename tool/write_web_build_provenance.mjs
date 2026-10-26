import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFile, rm, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const root = new URL('../', import.meta.url);
// Remove a previous ignored artifact before validating a new build workspace.
await rm(new URL('web/build-provenance.json', root), {force: true});
const dirty = execFileSync('git', ['status', '--porcelain', '--untracked-files=normal'], {cwd: fileURLToPath(root), encoding: 'utf8'}).trim();
if (dirty !== '') throw new Error('Refusing exact installed provenance for an uncommitted source workspace. Commit or restore the source first.');
const lock = JSON.parse(await readFile(new URL('contracts/contract.lock.json', root), 'utf8'));
const contract = await readFile(new URL(lock.path, root));
const hash = createHash('sha256').update(contract).digest('hex');
if (hash !== lock.sha256) throw new Error('Cannot package a mismatched contract.');
const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: fileURLToPath(root), encoding: 'utf8'}).trim();
if (!/^[0-9a-f]{40}$/u.test(revision)) throw new Error('A complete source revision is required.');
await writeFile(new URL('web/build-provenance.json', root), `${JSON.stringify({schemaVersion: 1, clientRevision: revision, contractVersion: lock.version, contractSha256: hash}, null, 2)}\n`);
console.log(`Embedded Client ${revision} and API ${lock.version} provenance.`);
