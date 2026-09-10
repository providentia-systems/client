#!/usr/bin/env node

import assert from 'node:assert/strict';
import {access, mkdtemp, readFile, rm} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const relativeScript = 'tools/setup-ubuntu-client.sh';
const script = path.join(root, relativeScript);

test('Ubuntu client setup has valid syntax and side-effect-free help', async () => {
  const syntax = spawnSync('bash', ['-n', script], {encoding: 'utf8'});
  assert.equal(syntax.status, 0, syntax.stderr);

  const temporary = await mkdtemp(path.join(tmpdir(), 'providentia-client-help-'));
  const toolRoot = path.join(temporary, 'tools');
  try {
    const help = spawnSync('bash', [script, '--help'], {
      encoding: 'utf8',
      env: {...process.env, PROVIDENTIA_CLIENT_TOOL_ROOT: toolRoot},
    });
    assert.equal(help.status, 0, help.stderr);
    assert.match(help.stdout, /--api-url URL/u);
    assert.match(help.stdout, /PROVIDENTIA_API_BASE_URL/u);
    assert.match(help.stdout, /--no-launch/u);
    await assert.rejects(access(toolRoot));
  } finally {
    await rm(temporary, {recursive: true, force: true});
  }
});

test('Ubuntu setup remains standalone and pins native build dependencies', async () => {
  const source = await readFile(script, 'utf8');
  for (const required of [
    'tools/install_node_linux.sh',
    'tool/install_flutter_linux.sh',
    "node_version='v22.14.0'",
    "flutter_version='3.44.7'",
    'frameworkRevision',
    'libgstreamer1.0-dev',
    'libgstreamer-plugins-base1.0-dev',
    'gstreamer1.0-plugins-base',
    'gstreamer1.0-plugins-good',
    'libsecret-1-dev',
    'PROVIDENTIA_API_BASE_URL',
    'health/ready',
    'node tool/verify_structure.mjs',
  ]) {
    assert.ok(source.includes(required), `missing ${required}`);
  }
  assert.doesNotMatch(source, /repos\/admin|\/admin\/|providentia_admin/u);
  assert.doesNotMatch(source, /providentia-dlqc|providentia\.our\.mx/u);
});

test('Ubuntu setup rejects unsafe origins and invalid ports before setup', () => {
  for (const origin of [
    'https://inventory.example.test:0',
    'https://inventory.example.test:65536',
    'https://user:secret@inventory.example.test',
    'https://inventory.example.test/api',
    'https://inventory.example.test?debug=1',
    'http://inventory.example.test',
  ]) {
    const result = spawnSync(
      'bash',
      [script, '--api-url', origin, '--skip-system-packages', '--no-launch'],
      {encoding: 'utf8'},
    );
    assert.notEqual(result.status, 0, `${origin} unexpectedly passed`);
    assert.match(result.stderr, /origin|development-only/u);
  }

  const productionLoopback = spawnSync(
    'bash',
    [
      script,
      '--api-url',
      'http://127.0.0.1:8080',
      '--environment',
      'production',
      '--skip-system-packages',
      '--no-launch',
    ],
    {encoding: 'utf8'},
  );
  assert.notEqual(productionLoopback.status, 0);
  assert.match(productionLoopback.stderr, /development environment/u);
});
