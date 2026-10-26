/** Reject incomplete installed evidence instead of inferring a deployed version. */
export function validateInstalledPair(client, diagnostics, expected) {
  const deployment = diagnostics?.deployment;
  if (client?.schemaVersion !== 1 || !/^[0-9a-f]{40}$/u.test(client.clientRevision ?? '')) {
    throw new Error('The installed Client does not expose a complete build revision.');
  }
  if (client.contractSha256 !== expected.contractSha256 || client.contractVersion !== expected.apiVersion) {
    throw new Error('The installed Client contract is outside the supported pairing.');
  }
  if (!/^[0-9a-f]{40}(?:[0-9a-f]{24})?$/u.test(deployment?.buildRevision ?? '') ||
      deployment.contractHash !== client.contractSha256 || deployment.contractMatchesLock !== true ||
      deployment.migrationStatus !== 'current' || !Array.isArray(deployment.appliedMigrations) ||
      !deployment.appliedMigrations.includes(expected.requiredMigration) ||
      !Array.isArray(deployment.pendingMigrations) || deployment.pendingMigrations.length !== 0 ||
      !Array.isArray(deployment.unknownMigrations) || deployment.unknownMigrations.length !== 0) {
    throw new Error('The installed backend revision, contract or migrations do not establish the supported pairing.');
  }
  return {
    clientRevision: client.clientRevision,
    backendRevision: deployment.buildRevision,
    contractVersion: client.contractVersion,
    contractSha256: client.contractSha256,
    migrationStatus: deployment.migrationStatus,
    appliedMigrationCount: deployment.appliedMigrations.length,
  };
}
