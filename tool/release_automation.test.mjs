#!/usr/bin/env node

import assert from 'node:assert/strict';
import {readFile, stat} from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '..');
const workflows = [
  '.github/workflows/release-android.yml',
  '.github/workflows/release-apple.yml',
  '.github/workflows/release-windows.yml',
  '.github/workflows/release-linux.yml',
  '.github/workflows/release-web.yml',
  '.github/workflows/browser-acceptance.yml',
];
const scripts = [
  'tool/release/generate_release_evidence.mjs',
  'tool/release/sign_android.sh',
  'tool/release/package_linux.sh',
  'tool/release/sign_linux_artifacts.sh',
  'tool/release/package_windows.ps1',
  'tool/release/prepare_apple_signing.sh',
  'tool/release/verify_web_runtime.mjs',
  'tool/release/login_link_acceptance_protocol.mjs',
];

test('release workflows are immutable, protected and artifact strict', async () => {
  for (const relative of workflows) {
    const source = await readFile(path.join(root, relative), 'utf8');
    assert.doesNotMatch(source, /continue-on-error\s*:/u, `${relative} cannot suppress release failures.`);
    assert.doesNotMatch(source, /flutter build[^\n]*--no-codesign/u, `${relative} cannot publish unsigned Apple output.`);
    assert.doesNotMatch(source, /app-debug|--debug/u, `${relative} cannot publish debug artifacts.`);
    for (const match of source.matchAll(/uses:\s*([^\s@]+)@([^\s]+)/gu)) {
      assert.match(match[2], /^[0-9a-f]{40}$/u, `${relative} must pin ${match[1]} by commit SHA.`);
    }
    if (source.includes('upload-artifact')) {
      assert.match(source, /if-no-files-found:\s*error/u, `${relative} must fail when evidence is absent.`);
    }
    assert.match(
      source,
      /environment:\s*production-(?:release|acceptance)/u,
      `${relative} must use a reviewer-protected GitHub environment.`,
    );
  }
});

test('platform signing is real and independently verified', async () => {
  const android = await readFile(path.join(root, 'tool/release/sign_android.sh'), 'utf8');
  assert.match(android, /jarsigner -verify -strict/u);
  assert.match(android, /apksigner" verify/u);
  assert.match(android, /ANDROID_EXPECTED_CERT_SHA256/u);

  const windows = await readFile(path.join(root, 'tool/release/package_windows.ps1'), 'utf8');
  assert.match(windows, /signtool\.exe/u);
  assert.match(windows, /Get-AuthenticodeSignature/u);
  assert.match(windows, /certificate\.Subject/u);

  const apple = await readFile(path.join(root, '.github/workflows/release-apple.yml'), 'utf8');
  assert.match(apple, /notarytool submit/u);
  assert.match(apple, /stapler validate/u);
  assert.match(apple, /codesign --verify/u);

  const linux = await readFile(path.join(root, 'tool/release/sign_linux_artifacts.sh'), 'utf8');
  assert.match(linux, /--detach-sign/u);
  assert.match(linux, /gpg --batch --verify/u);

  const linuxCmake = await readFile(path.join(root, 'linux/CMakeLists.txt'), 'utf8');
  const linuxPackage = await readFile(path.join(root, 'tool/release/package_linux.sh'), 'utf8');
  const binaryName = linuxCmake.match(/set\(BINARY_NAME\s+"([^"]+)"\)/u)?.[1];
  assert(binaryName, 'Linux BINARY_NAME must remain explicit.');
  assert.match(linuxPackage, new RegExp(`bundle/${binaryName}`, 'u'));

  const browser = await readFile(path.join(root, 'tool/release/verify_web_runtime.mjs'), 'utf8');
  const browserWorkflow = await readFile(
    path.join(root, '.github/workflows/browser-acceptance.yml'),
    'utf8',
  );
  assert.match(browser, /auth\/login-links/u);
  assert.match(browser, /createLoginLinkProof/u);
  assert.match(browser, /extractApprovalLink/u);
  assert.match(browser, /Approve login/u);
  assert.match(browser, /scannerSafeReview/u);
  assert.match(browser, /api\/v1\/me/u);
  assert.match(browser, /auth\/refresh/u);
  assert.match(browser, /auth\/logout/u);
  assert.match(browser, /afterLogout\.status === 401 \|\| afterLogout\.status === 403/u);
  assert.match(browserWorkflow, /playwright@1\.54\.2/u);
  assert.match(browserWorkflow, /imapflow@1\.6\.6/u);
  assert.match(browserWorkflow, /npm install --ignore-scripts --no-save --no-package-lock/u);
  assert.match(browserWorkflow, /E2E_MAILBOX_IMAP_PASSWORD/u);
  assert.match(browserWorkflow, /E2E_PUBLIC_BASE_URL/u);
  assert.match(browserWorkflow, /authenticate: true/u);
  assert.match(browserWorkflow, /authenticate: false/u);
  assert.doesNotMatch(browser, /auth\/login(?:['"/])/u);
  assert.doesNotMatch(
    browserWorkflow,
    new RegExp(['E2E', 'USER', 'PASSWORD'].join('_'), 'u'),
  );
});

test('browser dispatch input never enters a shell script by interpolation', async () => {
  const relative = '.github/workflows/browser-acceptance.yml';
  const workflow = await readFile(path.join(root, relative), 'utf8');
  const lines = workflow.split('\n');
  const runScripts = [];
  for (let index = 0; index < lines.length; index += 1) {
    const run = lines[index].match(/^(\s*)(?:-\s+)?run:\s*\|\s*$/u);
    if (!run) continue;
    const indentation = run[1].length;
    const body = [];
    for (index += 1; index < lines.length; index += 1) {
      const line = lines[index];
      if (line.trim() && line.match(/^\s*/u)[0].length <= indentation) {
        index -= 1;
        break;
      }
      body.push(line);
    }
    runScripts.push(body.join('\n'));
  }

  assert(runScripts.length > 0, 'browser workflow must contain shell steps.');
  for (const script of runScripts) {
    assert.doesNotMatch(
      script,
      /\$\{\{\s*inputs\.target_url\s*\}\}/u,
      'workflow_dispatch target_url must cross into shell only through env.',
    );
  }
  assert.match(workflow, /^\s+TARGET_URL:\s*\$\{\{ inputs\.target_url \}\}\s*$/mu);
  assert.match(workflow, /^\s+BROWSER:\s*\$\{\{ matrix\.browser \}\}\s*$/mu);
  assert.match(workflow, /^\s+EVIDENCE_PATH:\s*build\/release\/browser-evidence\/\$\{\{ matrix\.browser \}\}\.json\s*$/mu);
  assert.match(workflow, /"\$TARGET_URL" "\$BROWSER" "\$EVIDENCE_PATH"/u);
});

test('release scripts pass local syntax checks', async () => {
  for (const relative of scripts.filter((entry) => entry.endsWith('.sh'))) {
    const result = spawnSync('bash', ['-n', path.join(root, relative)], {encoding: 'utf8'});
    assert.equal(result.status, 0, `${relative}: ${result.stderr}`);
  }
  for (const relative of scripts.filter((entry) => entry.endsWith('.mjs'))) {
    const result = spawnSync(process.execPath, ['--check', path.join(root, relative)], {encoding: 'utf8'});
    assert.equal(result.status, 0, `${relative}: ${result.stderr}`);
  }
});

test('proprietary distribution and external evidence are explicit', async () => {
  const document = await readFile(
    path.join(root, 'docs/release/phase-09-10-release-engineering.md'),
    'utf8',
  );
  assert.match(document, /proprietary software/u);
  assert.match(document, /physical iPhone/u);
  assert.match(document, /Real Safari testing/u);
  assert.match(document, /never converted into a passing checkbox/u);
  for (const relative of [...workflows, ...scripts]) {
    assert.equal((await stat(path.join(root, relative))).isFile(), true);
  }
});
