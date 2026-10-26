import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import test from 'node:test';

test('web provenance requires committed source and refuses mismatched contract bytes', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'providentia-provenance-'));
  try {
    await Promise.all(['tool', 'contracts', 'web'].map((name) => mkdir(path.join(root, name))));
    await copyFile(new URL('./write_web_build_provenance.mjs', import.meta.url), path.join(root, 'tool/write_web_build_provenance.mjs'));
    const contract = '{"openapi":"3.1.0"}\n';
    const digest = createHash('sha256').update(contract).digest('hex');
    await writeFile(path.join(root, 'contracts/source.json'), contract);
    await writeFile(path.join(root, 'contracts/contract.lock.json'), JSON.stringify({path: 'contracts/source.json', version: '2.4.0', sha256: digest}));
    await writeFile(path.join(root, '.gitignore'), '/web/build-provenance.json\n');
    const git = (...args) => execFileSync('git', args, {cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']}).trim();
    git('init', '-q');
    git('config', 'user.name', 'Synthetic acceptance');
    git('config', 'user.email', 'synthetic@example.invalid');
    git('add', '.');
    git('commit', '-qm', 'Synthetic committed fixture');
    const run = () => execFileSync(process.execPath, ['tool/write_web_build_provenance.mjs'], {cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']});
    run();
    const provenance = JSON.parse(await readFile(path.join(root, 'web/build-provenance.json'), 'utf8'));
    assert.equal(provenance.clientRevision, git('rev-parse', 'HEAD'));
    assert.equal(provenance.contractSha256, digest);
    assert.equal(provenance.PROVIDENTIA_BUILD_REVISION, provenance.clientRevision);
    assert.equal(provenance.PROVIDENTIA_CONTRACT_SHA256, digest);
    await writeFile(path.join(root, 'uncommitted.dart'), '// synthetic source change\n');
    assert.throws(run, /uncommitted source workspace/u);
    await assert.rejects(readFile(path.join(root, 'web/build-provenance.json')), {code: 'ENOENT'});
    git('add', '.');
    git('commit', '-qm', 'Synthetic additional source');
    await writeFile(path.join(root, 'contracts/source.json'), '{}\n');
    git('add', '.');
    git('commit', '-qm', 'Synthetic incompatible artifact');
    assert.throws(run, /mismatched contract/u);
  } finally {
    await rm(root, {recursive: true, force: true});
  }
});
