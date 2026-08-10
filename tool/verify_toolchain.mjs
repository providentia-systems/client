#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const toolchain = JSON.parse(
  await readFile(path.join(root, 'toolchain.json'), 'utf8'),
);
const fvm = JSON.parse(await readFile(path.join(root, '.fvmrc'), 'utf8'));
const metadata = await readFile(path.join(root, '.metadata'), 'utf8');
const pubspec = await readFile(path.join(root, 'pubspec.yaml'), 'utf8');

assert(toolchain.flutter.version === '3.44.7', 'Flutter version is not pinned.');
assert(toolchain.dart.version === '3.12.2', 'Dart version is not pinned.');
assert(
  toolchain.flutter.frameworkRevision ===
    '84fc5cbb223bc12f83d65b647ff8a56caf779ffd',
  'Unexpected Flutter framework revision.',
);
assert(fvm.flutter === toolchain.flutter.version, '.fvmrc is inconsistent.');
assert(
  metadata.includes(`revision: "${toolchain.flutter.frameworkRevision}"`),
  '.metadata is inconsistent.',
);
assert(
  pubspec.includes(
    `flutter: '>=${toolchain.flutter.version} <4.0.0'`,
  ) &&
    pubspec.includes(`sdk: '>=${toolchain.dart.version} <4.0.0'`),
  'pubspec SDK compatibility range is inconsistent.',
);

const archiveArgument = process.argv[2];
if (archiveArgument) {
  const archivePath = path.resolve(archiveArgument);
  const archiveName = path.basename(archivePath);
  const archive = Object.values(toolchain.archives).find(
    (candidate) => path.basename(candidate.path) === archiveName,
  );
  assert(archive, `Archive ${archiveName} is not pinned.`);
  const digest = createHash('sha256')
    .update(await readFile(archivePath))
    .digest('hex');
  assert(
    digest === archive.sha256,
    `SHA-256 mismatch for ${archiveName}: ${digest}`,
  );
  process.stdout.write(`${archiveName}: SHA-256 verified.\n`);
}

process.stdout.write(
  `Flutter ${toolchain.flutter.version} / Dart ${toolchain.dart.version} pins verified.\n`,
);

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
