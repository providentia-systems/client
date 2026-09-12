#!/usr/bin/env bash

# Materialize the exact backend contract snapshot checked into this repository.
# The archive keeps connector transfers bounded while both checksums make the
# generated homeowner facade reproducible and independently auditable.

set -Eeuo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly archive="$root/contracts/source/providentia-v1.json.gz"
readonly output="$root/contracts/providentia-v1.json"
readonly archive_sha256='5e1e3f7224b85e52e09a298d2ad4c5a82d564c35d21d90e2b872bf33b3e9db8f'
readonly output_sha256='40a8477521baa6c41cf2c5d872068f5ae1bf255a8d0bbccc97a05688d705ad57'

sha256_file() {
  sha256sum "$1" | cut -d' ' -f1
}

if [[ "$(sha256_file "$archive")" != "$archive_sha256" ]]; then
  echo 'Pinned backend OpenAPI archive checksum mismatch.' >&2
  exit 1
fi

if [[ -f "$output" && "$(sha256_file "$output")" == "$output_sha256" ]]; then
  exit 0
fi

temporary="$(mktemp "$output.part.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
gzip --decompress --stdout "$archive" > "$temporary"

if [[ "$(sha256_file "$temporary")" != "$output_sha256" ]]; then
  echo 'Materialized backend OpenAPI checksum mismatch.' >&2
  exit 1
fi

node -e '
  const fs = require("node:fs");
  const contract = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const operations = Object.values(contract.paths ?? {}).reduce(
    (count, path) => count + ["get", "post", "put", "patch", "delete"]
      .filter((method) => path?.[method]).length,
    0,
  );
  if (contract.info?.version !== "2.1.0"
      || Object.keys(contract.paths ?? {}).length !== 194
      || operations !== 235
      || Object.keys(contract.components?.schemas ?? {}).length !== 285
      || contract.paths?.["/api/v1/auth/email-codes/verify"]?.post?.operationId
          !== "verifyEmailCode"
      || contract.paths?.["/api/v1/homes/{homeId}/memberships/{userId}"]?.delete?.operationId
          !== "removeHomeMembership"
      || contract.components?.schemas?.AiExtraction?.properties?.schemaVersion?.enum?.[0] !== 2) {
    throw new Error("The materialized OpenAPI document is not complete Providentia API 2.1.0.");
  }
' "$temporary"

mv "$temporary" "$output"
trap - EXIT
echo 'Materialized Providentia API 2.1.0 contract.'
