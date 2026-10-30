import assert from 'node:assert/strict';
import test from 'node:test';
import {validateInstalledPair} from './release/installed_pair_contract.mjs';
const expected = {apiVersion: '2.4.0', contractSha256: 'a'.repeat(64), requiredMigration: 'Synthetic\\Migration'};
const client = {schemaVersion: 1, clientRevision: 'b'.repeat(40), contractVersion: expected.apiVersion, contractSha256: expected.contractSha256};
const diagnostics = {deployment: {buildRevision: 'c'.repeat(40), contractHash: expected.contractSha256, contractMatchesLock: true, migrationStatus: 'current', appliedMigrations: [expected.requiredMigration], pendingMigrations: [], unknownMigrations: []}};
test('installed evidence records exact pairing without account, device or payload data', () => {
  const result = validateInstalledPair(client, {...diagnostics, accountId: 'private', deviceId: 'private'}, expected);
  assert.equal(result.clientRevision, client.clientRevision);
  assert.equal(result.backendRevision, diagnostics.deployment.buildRevision);
  assert.equal(JSON.stringify(result).includes('private'), false);
});
test('missing revisions, incompatible digests and incomplete migrations fail acceptance', () => {
  assert.throws(() => validateInstalledPair({...client, clientRevision: null}, diagnostics, expected));
  assert.throws(() => validateInstalledPair({...client, contractSha256: 'd'.repeat(64)}, diagnostics, expected));
  for (const delta of [{buildRevision: null}, {contractMatchesLock: false}, {contractHash: 'd'.repeat(64)}, {migrationStatus: 'pending'}, {appliedMigrations: []}, {pendingMigrations: ['Synthetic']}, {unknownMigrations: ['Synthetic']}]) {
    assert.throws(() => validateInstalledPair(client, {deployment: {...diagnostics.deployment, ...delta}}, expected));
  }
});
