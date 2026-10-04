import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const probe = [join(root, 'tool/release/verify_first_frame.sh'), join(root, 'tool/verify_first_frame.sh')].find(existsSync);
assert.ok(probe, 'The repository must contain the first-frame probe.');

function exercise({ visible, application, expectedStatus, expectedText }) {
  const work = mkdtempSync(join(tmpdir(), 'providentia-first-frame-'));
  try {
    const bin = join(work, 'bin');
    mkdirSync(bin);
    const pidPath = join(work, 'app.pid');
    const executable = join(bin, 'application');
    writeFileSync(executable, `#!/bin/sh\nprintf '%s' "$$" > "$SMOKE_TEST_PID_FILE"\n${application}\n`, { mode: 0o755 });
    writeFileSync(join(bin, 'xwininfo'), `#!/bin/sh\nprintf '%s\\n' 'Map State: ${visible ? 'IsViewable' : 'IsUnMapped'}'\n`, { mode: 0o755 });
    // Eliminate elapsed time only in this synthetic fixture. The production
    // probe retains all 60 observations and its 0.25-second interval.
    writeFileSync(join(bin, 'sleep'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
    const result = spawnSync('bash', [probe, executable, 'Test window', join(work, 'application.log')], {
      encoding: 'utf8', timeout: 20_000,
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, SMOKE_TEST_PID_FILE: pidPath },
    });
    assert.equal(result.error, undefined);
    assert.equal(result.status, expectedStatus, result.stdout + result.stderr);
    assert.match(result.stdout + result.stderr, expectedText);
    if (existsSync(pidPath)) {
      const pid = Number(readFileSync(pidPath, 'utf8'));
      assert.throws(() => process.kill(pid, 0), { code: 'ESRCH' }, 'The probe must clean up its own child.');
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

test('visible frame without exceptions passes and cleans up', () => {
  exercise({ visible: true, application: 'exec /bin/sleep 60', expectedStatus: 0, expectedText: /Verified visible Flutter first frame/ });
});
test('an alive process without a visible frame fails', () => {
  exercise({ visible: false, application: 'exec /bin/sleep 60', expectedStatus: 70, expectedText: /No visible Flutter first frame/ });
});
test('a startup exception fails even with a visible window and live process', () => {
  exercise({ visible: true, application: "printf 'Unhandled Exception: synthetic directory failure\\n' >&2\nexec /bin/sleep 60", expectedStatus: 70, expectedText: /startup exception/ });
});
test('a process that exits immediately is not a successful launch', () => {
  exercise({ visible: true, application: 'exit 0', expectedStatus: 70, expectedText: /exited during startup/ });
});
