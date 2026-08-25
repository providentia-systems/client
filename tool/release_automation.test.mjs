#!/usr/bin/env node

import assert from 'node:assert/strict';
import {chmod, mkdtemp, mkdir, readFile, rm, stat, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
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
  const linuxPackageVerification = await readFile(
    path.join(root, 'tool/release/verify_linux_deb.sh'),
    'utf8',
  );
  const flutterCi = await readFile(path.join(root, '.github/workflows/ci.yml'), 'utf8');
  const binaryName = linuxCmake.match(/set\(BINARY_NAME\s+"([^"]+)"\)/u)?.[1];
  assert(binaryName, 'Linux BINARY_NAME must remain explicit.');
  assert.match(linuxPackage, new RegExp(`bundle/${binaryName}`, 'u'));
  assert.match(linuxPackage, /libcamera_desktop_plugin\.so/u);
  assert.match(linuxPackage, /ldd "\$camera_plugin"/u);
  for (const dependency of [
    'libegl1',
    'libgstreamer1.0-0',
    'libgstreamer-plugins-base1.0-0',
    'gstreamer1.0-plugins-base',
    'gstreamer1.0-plugins-good',
  ]) {
    assert.match(linuxPackage, new RegExp(dependency.replaceAll('.', '\\.'), 'u'));
    assert.match(
      linuxPackageVerification,
      new RegExp(dependency.replaceAll('.', '\\.'), 'u'),
    );
  }
  assert.match(linuxPackage, /PROVIDENTIA_LINUX_PACKAGE_FORMATS/u);
  assert.match(linuxPackageVerification, /libcamera_desktop_plugin\.so/u);
  assert.match(linuxPackageVerification, /PROVIDENTIA_LINUX_LAUNCH_SMOKE/u);
  assert.match(flutterCi, /Package Linux Debian proof/u);
  assert.match(flutterCi, /ubuntu:24\.04/u);
  assert.match(flutterCi, /providentia-linux-debian-package-proof/u);

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

test('agent bootstrap repairs SDK corruption and pins its executable tools', async () => {
  const setup = await readFile(path.join(root, 'tools/agent-setup.sh'), 'utf8');
  const flutterInstaller = await readFile(
    path.join(root, 'tool/install_flutter_linux.sh'),
    'utf8',
  );
  const nodeInstaller = await readFile(
    path.join(root, 'tools/install_node_linux.sh'),
    'utf8',
  );
  const requirements = JSON.parse(
    await readFile(path.join(root, 'tools/agent-requirements.json'), 'utf8'),
  );
  const lockWorkflow = await readFile(
    path.join(root, '.github/workflows/bootstrap-lockfile.yml'),
    'utf8',
  );

  assert.match(setup, /quarantine_tool/u);
  assert.match(setup, /--version --machine/u);
  assert.match(setup, /frameworkRevision/u);
  assert.match(setup, /ANALYZER_STATE_LOCATION_OVERRIDE/u);
  assert.match(flutterInstaller, /tar --no-same-owner/u);
  assert.match(flutterInstaller, /ANALYZER_STATE_LOCATION_OVERRIDE/u);
  assert.match(nodeInstaller, /--retry-all-errors/u);
  assert.match(nodeInstaller, /--strip-components=1/u);
  assert.match(
    nodeInstaller,
    new RegExp(requirements.nodeDistribution.linuxX64.sha256, 'u'),
  );
  assert.equal(requirements.runtime.node, '22.14.0');
  assert.equal(requirements.supportedHosts.development.includes('linux-arm64'), false);
  assert.match(lockWorkflow, /for attempt in 1 2 3/u);
  assert.match(lockWorkflow, /\.\/gradlew --no-daemon :generateLockfiles/u);
  assert.match(lockWorkflow, /failed after three bounded attempts/u);
});

test('Linux plugin linkage resolves the bundled Flutter sibling library', async (context) => {
  const fixtureRoot = await mkdtemp(path.join(tmpdir(), 'providentia-linkage-'));
  context.after(() => rm(fixtureRoot, {recursive: true, force: true}));
  const fixtureBin = path.join(fixtureRoot, 'bin');
  const pluginRoot = path.join(fixtureRoot, 'bundle', 'lib');
  const plugin = path.join(pluginRoot, 'libfile_selector_linux_plugin.so');
  const flutterLibrary = path.join(pluginRoot, 'libflutter_linux_gtk.so');
  await mkdir(fixtureBin, {recursive: true});
  await mkdir(pluginRoot, {recursive: true});
  await writeFile(plugin, 'fixture plugin');
  await writeFile(flutterLibrary, 'fixture sibling');
  const fakeLdd = path.join(fixtureBin, 'ldd');
  await writeFile(
    fakeLdd,
    `#!/usr/bin/env bash
set -euo pipefail
plugin_root=$(dirname -- "$1")
if [[ "\${LD_LIBRARY_PATH:-}" == "$plugin_root"* && -f "$plugin_root/libflutter_linux_gtk.so" ]]; then
  echo "libflutter_linux_gtk.so => $plugin_root/libflutter_linux_gtk.so"
else
  echo 'libflutter_linux_gtk.so => not found'
fi
`,
  );
  await chmod(fakeLdd, 0o755);
  const verifier = path.join(root, 'tool/release/verify_linux_deb.sh');
  const environment = {
    ...process.env,
    PATH: `${fixtureBin}:${process.env.PATH}`,
  };

  const resolved = spawnSync(
    'bash',
    ['-c', 'source "$1"; verify_linkage "$2" "$3"', 'fixture', verifier, plugin, pluginRoot],
    {encoding: 'utf8', env: environment},
  );
  assert.equal(resolved.status, 0, resolved.stderr);

  const unresolved = spawnSync(
    'bash',
    ['-c', 'source "$1"; verify_linkage "$2"', 'fixture', verifier, plugin],
    {encoding: 'utf8', env: environment},
  );
  assert.equal(unresolved.status, 66);
  assert.match(unresolved.stderr, /libflutter_linux_gtk\.so => not found/u);
});

test('Linux resolution excludes Android JNI native assets', async () => {
  const pubspec = await readFile(path.join(root, 'pubspec.yaml'), 'utf8');
  const lock = await readFile(path.join(root, 'pubspec.lock'), 'utf8');
  const packager = await readFile(path.join(root, 'tool/release/package_linux.sh'), 'utf8');
  const verifier = await readFile(
    path.join(root, 'tool/release/verify_linux_deb.sh'),
    'utf8',
  );
  assert.match(pubspec, /path_provider_android:\s+2\.2\.23/u);
  assert.match(
    lock,
    /^  path_provider_android:\n[\s\S]*?^    version: "2\.2\.23"$/mu,
  );
  for (const packageName of ['jni', 'jni_flutter', 'jni_util']) {
    assert.doesNotMatch(lock, new RegExp(`^  ${packageName}:$`, 'mu'));
  }
  assert.match(packager, /libdartjni\.so/u);
  assert.match(verifier, /libdartjni\.so/u);
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
