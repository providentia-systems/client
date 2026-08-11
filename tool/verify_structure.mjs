#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readdir, readFile, stat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const requiredDirectories = [
  'android',
  'ios',
  'linux',
  'macos',
  'web',
  'windows',
  'lib/core/database',
  'lib/core/networking',
  'lib/core/synchronization',
  'lib/core/security',
  'lib/core/design_system',
  'lib/features/identity',
  'lib/features/homes',
  'lib/features/catalog',
  'lib/features/inventory',
  'lib/features/purchasing',
  'lib/features/shopping',
  'lib/features/ai_integration',
  'lib/features/administration',
  'lib/features/data_governance',
  'lib/features/reporting',
];
const requiredFiles = [
  'android/app/build.gradle.kts',
  'android/gradlew',
  'android/gradlew.bat',
  'android/gradle/wrapper/gradle-wrapper.jar',
  'android/app/src/main/kotlin/com/vastdevelopmentmethod/providentia/MainActivity.kt',
  'android/app/src/main/res/values/styles.xml',
  'ios/Runner.xcodeproj/project.pbxproj',
  'linux/CMakeLists.txt',
  'macos/Runner.xcodeproj/project.pbxproj',
  'web/index.html',
  'web/manifest.json',
  'web/sqlite3.wasm',
  'web/drift-assets.lock.json',
  'web/icons/Icon-192.png',
  'web/icons/Icon-512.png',
  'windows/CMakeLists.txt',
  'windows/runner/resources/app_icon.ico',
  'contracts/providentia-v1.json',
  'contracts/contract.lock.json',
  'contracts/design-tokens/providentia-v1.json',
  'contracts/design-tokens/contract.lock.json',
  'contracts/generated/providentia_api_client/lib/providentia_api_client.dart',
];

for (const relativePath of requiredDirectories) {
  const info = await stat(path.join(root, relativePath));
  assert(info.isDirectory(), `${relativePath} must be a directory.`);
}
for (const relativePath of requiredFiles) {
  const info = await stat(path.join(root, relativePath));
  assert(info.isFile(), `${relativePath} must be a file.`);
}

await assertContains(
  'android/app/build.gradle.kts',
  'applicationId = "com.vastdevelopmentmethod.providentia"',
);
await assertContains(
  'android/app/src/main/AndroidManifest.xml',
  'android:name=".MainActivity"',
);
await assertContains(
  'ios/Runner.xcodeproj/project.pbxproj',
  'PRODUCT_BUNDLE_IDENTIFIER = "com.vastdevelopmentmethod.providentia";',
);
await assertContains(
  'ios/Runner.xcodeproj/project.pbxproj',
  'IPHONEOS_DEPLOYMENT_TARGET = 13.0;',
);
await assertContains(
  'macos/Runner/Configs/AppInfo.xcconfig',
  'PRODUCT_BUNDLE_IDENTIFIER = com.vastdevelopmentmethod.providentia',
);
await assertContains(
  'macos/Runner.xcodeproj/project.pbxproj',
  'MACOSX_DEPLOYMENT_TARGET = 10.15;',
);
await assertContains(
  'linux/CMakeLists.txt',
  'set(APPLICATION_ID "com.vastdevelopmentmethod.providentia")',
);
await assertContains('windows/CMakeLists.txt', 'project(Providentia LANGUAGES CXX)');

const wrapper = await readFile(
  path.join(root, 'android/gradle/wrapper/gradle-wrapper.jar'),
);
assert(
  createHash('sha256').update(wrapper).digest('hex') ===
    '7d3a4ac4de1c32b59bc6a4eb8ecb8e612ccd0cf1ae1e99f66902da64df296172',
  'Unexpected Gradle 8.14 wrapper JAR.',
);
const sqliteWasm = await readFile(path.join(root, 'web/sqlite3.wasm'));
assert(
  createHash('sha256').update(sqliteWasm).digest('hex') ===
    '41cf968998241465d8b1dfffb1eb60dd10c35de5022a3647e14174ea3af84143',
  'Unexpected Drift 2.34.3 sqlite3.wasm.',
);
for (const binaryAsset of [
  'windows/runner/resources/app_icon.ico',
  'web/favicon.png',
  'web/icons/Icon-192.png',
  'web/icons/Icon-512.png',
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
]) {
  const info = await stat(path.join(root, binaryAsset));
  assert(info.size > 0, `${binaryAsset} cannot be empty.`);
}

const webManifest = JSON.parse(
  await readFile(path.join(root, 'web/manifest.json'), 'utf8'),
);
for (const icon of webManifest.icons ?? []) {
  const info = await stat(path.join(root, 'web', icon.src));
  assert(info.size > 0, `Web icon ${icon.src} is missing or empty.`);
}

const dartFiles = (await walk(path.join(root, 'lib'))).filter((file) =>
  file.endsWith('.dart'),
);
const violations = [];
const compositionRoots = new Set([
  'lib/main.dart',
  'lib/app/production_bootstrap_app.dart',
]);
for (const file of dartFiles) {
  const source = await readFile(file, 'utf8');
  const relativePath = path.relative(root, file).split(path.sep).join('/');
  const isFeature = relativePath.startsWith('lib/features/');
  const isInfrastructure = relativePath.includes('/infrastructure/');
  const isWidget = source.includes('package:flutter/');
  const isCompositionRoot = compositionRoots.has(relativePath);
  if (
    (!isFeature || isInfrastructure) &&
    (!isWidget || isCompositionRoot)
  ) {
    continue;
  }
  for (const forbidden of [
    'package:http/',
    'package:drift/',
    'package:sqlite3/',
    'package:sqflite/',
    'dart:io',
    'dart:html',
    'providentia_api_client',
  ]) {
    if (source.includes(forbidden)) {
      violations.push(`${relativePath}: ${forbidden}`);
    }
  }
}
assert(
  violations.length === 0,
  `Direct transport/database access from UI boundaries:\n${violations.join('\n')}`,
);

const dependencyViolations = [];
const generatedClientAdapters = new Set([
  'lib/app/production_bootstrap_app.dart',
  'lib/core/networking/api_client_factory.dart',
  'lib/core/networking/generated_api_connectivity_probe.dart',
  'lib/core/synchronization/generated_sync_gateway.dart',
  'lib/features/ai_integration/infrastructure/api17_ai_gateway.dart',
  'lib/features/ai_integration/infrastructure/api17_server_credential_provisioning.dart',
  'lib/features/ai_integration/infrastructure/generated_server_ai_repository.dart',
  'lib/features/administration/infrastructure/api11_platform_administration_transport.dart',
  'lib/features/administration/infrastructure/generated_catalog_administration_repository.dart',
  'lib/features/catalog/infrastructure/generated_catalog_contribution_repository.dart',
  'lib/features/data_governance/infrastructure/generated_data_governance_repository.dart',
  'lib/features/homes/infrastructure/api11_home_transport.dart',
  'lib/features/household_sync/infrastructure/api17_callback_household_gateway.dart',
  'lib/features/identity/infrastructure/api11_identity_transport.dart',
  'lib/features/reporting/infrastructure/generated_household_report_repository.dart',
]);
const synchronizationPolicyFiles = new Set([
  'lib/core/synchronization/sync_models.dart',
  'lib/core/synchronization/sync_ports.dart',
  'lib/core/synchronization/sync_coordinator.dart',
]);
for (const file of dartFiles) {
  const source = await readFile(file, 'utf8');
  const relativePath = path.relative(root, file).split(path.sep).join('/');
  if (
    relativePath.startsWith('lib/app/') &&
    !compositionRoots.has(relativePath)
  ) {
    for (const forbidden of [
      '/sync_coordinator.dart',
      '/database/',
      '/networking/',
    ]) {
      if (source.includes(forbidden)) {
        dependencyViolations.push(`${relativePath}: ${forbidden}`);
      }
    }
  }
  if (synchronizationPolicyFiles.has(relativePath)) {
    for (const forbidden of [
      'package:flutter/',
      'package:http/',
      'package:drift/',
      'providentia_api_client',
      '/database/',
      '/networking/',
    ]) {
      if (source.includes(forbidden)) {
        dependencyViolations.push(`${relativePath}: ${forbidden}`);
      }
    }
  }
  if (
    source.includes('providentia_api_client') &&
    !generatedClientAdapters.has(relativePath)
  ) {
    dependencyViolations.push(
      `${relativePath}: generated transport outside approved adapter`,
    );
  }
}
assert(
  dependencyViolations.length === 0,
  `Dependency inversion violations:\n${dependencyViolations.join('\\n')}`,
);

const allTextFiles = (await walk(root)).filter(
  (file) =>
    !file.includes(`${path.sep}.git${path.sep}`) &&
    !file.includes(`${path.sep}docs${path.sep}phase0${path.sep}`) &&
    !/\.(png|ico|jpe?g|jar|wasm)$/u.test(file),
);
const obsoleteNameViolations = [];
const obsoletePattern = new RegExp(
  `${['Stock', 'Home'].join('')}|${['stock', 'home'].join('')}`,
  'u',
);
for (const file of allTextFiles) {
  const source = await readFile(file, 'utf8');
  if (
    obsoletePattern.test(source) &&
    !file.endsWith(`${path.sep}docs${path.sep}project-memory.md`) &&
    !file.endsWith(
      `${path.sep}docs${path.sep}product${path.sep}` +
        'providentia_master_implementation_prompt_V1.md',
    )
  ) {
    obsoleteNameViolations.push(path.relative(root, file));
  }
}
assert(
  obsoleteNameViolations.length === 0,
  `Obsolete product name outside historical decision record:\n${obsoleteNameViolations.join('\n')}`,
);

process.stdout.write('Repository structure and architecture boundaries verified.\n');

async function walk(directory) {
  const files = [];
  for (const entry of await readdir(directory, {withFileTypes: true})) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await walk(entryPath)));
    } else if (entry.isFile()) {
      files.push(entryPath);
    }
  }
  return files;
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function assertContains(relativePath, expected) {
  const source = await readFile(path.join(root, relativePath), 'utf8');
  assert(source.includes(expected), `${relativePath} is missing: ${expected}`);
}
