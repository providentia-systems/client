#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {mkdir, readFile, readdir, stat, writeFile} from 'node:fs/promises';
import path from 'node:path';

const options = parseArguments(process.argv.slice(2));
for (const name of ['artifacts', 'output', 'platform', 'version']) {
  if (!options[name]) {
    throw new Error(`--${name} is required.`);
  }
}
if (!/^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$/u.test(options.version)) {
  throw new Error('Release version must be a semantic version without a v prefix.');
}

const artifactRoot = path.resolve(options.artifacts);
const outputRoot = path.resolve(options.output);
await mkdir(outputRoot, {recursive: true});

const artifactFiles = (await walk(artifactRoot)).sort();
if (artifactFiles.length === 0) {
  throw new Error('The artifact directory is empty.');
}

const subjects = [];
for (const file of artifactFiles) {
  const bytes = await readFile(file);
  subjects.push({
    name: path.relative(artifactRoot, file).split(path.sep).join('/'),
    digest: {sha256: createHash('sha256').update(bytes).digest('hex')},
    size: bytes.length,
  });
}

await writeFile(
  path.join(outputRoot, 'SHA256SUMS'),
  subjects.map((entry) => `${entry.digest.sha256}  ${entry.name}`).join('\n') + '\n',
  'utf8',
);

const dependencies = options.dependencies
  ? JSON.parse(await readFile(path.resolve(options.dependencies), 'utf8'))
  : {packages: []};
const packages = Array.isArray(dependencies.packages) ? dependencies.packages : [];
const components = packages
  .filter((entry) => typeof entry?.name === 'string')
  .map((entry) => ({
    type: 'library',
    'bom-ref': `pkg:pub/${entry.name}@${entry.version ?? 'unknown'}`,
    name: entry.name,
    version: String(entry.version ?? 'unknown'),
    purl: `pkg:pub/${entry.name}@${entry.version ?? 'unknown'}`,
    properties: [
      {name: 'providentia:dependency-kind', value: String(entry.kind ?? 'transitive')},
      {name: 'providentia:dependency-source', value: String(entry.source ?? 'unknown')},
    ],
  }))
  .sort((left, right) => left.name.localeCompare(right.name));

const timestamp = new Date().toISOString();
const repository = process.env.GITHUB_REPOSITORY ?? 'local/providentia-flutter';
const commit = process.env.GITHUB_SHA ?? 'local-uncommitted-build';
const runId = process.env.GITHUB_RUN_ID ?? 'local';
const runAttempt = process.env.GITHUB_RUN_ATTEMPT ?? '1';
const sourceUrl = process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY
  ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}`
  : 'local';

const sbom = {
  bomFormat: 'CycloneDX',
  specVersion: '1.5',
  serialNumber: `urn:uuid:${deterministicUuid(`${repository}:${commit}:${options.platform}:${options.version}`)}`,
  version: 1,
  metadata: {
    timestamp,
    component: {
      type: 'application',
      'bom-ref': `pkg:generic/providentia@${options.version}?platform=${options.platform}`,
      name: 'Providentia',
      version: options.version,
      supplier: {name: 'Vast Development Method'},
      properties: [{name: 'providentia:distribution', value: 'proprietary'}],
    },
  },
  components,
};
await writeJson(path.join(outputRoot, 'cyclonedx-sbom.json'), sbom);

const materials = [];
for (const material of [
  'pubspec.lock',
  'toolchain.json',
  'contracts/contract.lock.json',
  'contracts/design-tokens/contract.lock.json',
]) {
  try {
    const bytes = await readFile(material);
    materials.push({uri: `${sourceUrl}/blob/${commit}/${material}`, digest: {sha256: sha256(bytes)}});
  } catch {
    // A release checkout is expected to contain all materials. Local unit
    // fixtures may omit them without changing artifact digest generation.
  }
}

const provenance = {
  _type: 'https://in-toto.io/Statement/v1',
  subject: subjects.map(({name, digest}) => ({name, digest})),
  predicateType: 'https://slsa.dev/provenance/v1',
  predicate: {
    buildDefinition: {
      buildType: 'https://github.com/vast-development-method/providentia-flutter/release-workflow/v1',
      externalParameters: {
        platform: options.platform,
        version: options.version,
        ref: process.env.GITHUB_REF ?? 'local',
      },
      internalParameters: {
        workflow: process.env.GITHUB_WORKFLOW ?? 'local',
        runId,
        runAttempt,
      },
      resolvedDependencies: materials,
    },
    runDetails: {
      builder: {id: `${sourceUrl}/actions/runs/${runId}`},
      metadata: {
        invocationId: `${runId}-${runAttempt}`,
        startedOn: timestamp,
        finishedOn: timestamp,
      },
    },
  },
};
await writeFile(
  path.join(outputRoot, 'provenance.intoto.jsonl'),
  `${JSON.stringify(provenance)}\n`,
  'utf8',
);

await writeJson(path.join(outputRoot, 'release-manifest.json'), {
  schemaVersion: 1,
  product: 'Providentia',
  distribution: 'proprietary',
  platform: options.platform,
  version: options.version,
  source: {repository, commit, ref: process.env.GITHUB_REF ?? 'local'},
  workflow: {runId, runAttempt, name: process.env.GITHUB_WORKFLOW ?? 'local'},
  generatedAt: timestamp,
  artifacts: subjects,
});

process.stdout.write(`Release evidence generated for ${subjects.length} artifact(s).\n`);

function parseArguments(arguments_) {
  const parsed = {};
  for (let index = 0; index < arguments_.length; index += 2) {
    const key = arguments_[index];
    const value = arguments_[index + 1];
    if (!key?.startsWith('--') || value === undefined) {
      throw new Error(`Invalid argument near ${key ?? '<end>'}.`);
    }
    parsed[key.slice(2)] = value;
  }
  return parsed;
}

async function walk(directory) {
  const files = [];
  for (const entry of await readdir(directory, {withFileTypes: true})) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await walk(absolute)));
    } else if (entry.isFile() && (await stat(absolute)).size >= 0) {
      files.push(absolute);
    }
  }
  return files;
}

async function writeJson(file, value) {
  await writeFile(file, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function deterministicUuid(value) {
  const hash = sha256(value);
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-4${hash.slice(13, 16)}-a${hash.slice(17, 20)}-${hash.slice(20, 32)}`;
}
