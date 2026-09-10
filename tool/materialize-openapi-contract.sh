#!/usr/bin/env bash

# Materialize the exact backend contract snapshot checked into this repository.
# The archive keeps connector transfers bounded while both checksums make the
# generated homeowner facade reproducible and independently auditable.

set -Eeuo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly archive="$root/contracts/source/providentia-v1.json.gz"
readonly output="$root/contracts/providentia-v1.json"
readonly archive_sha256='4840f22ac2638942d6407add7ec4414772e4f2a6927ce88c23b02b060803f9de'
readonly output_sha256='7b1f1be5d9efd311254e9840c4595e08575e8c97d35da766dab0d291c165bcae'

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
  if (contract.info?.version !== "2.0.0"
      || Object.keys(contract.paths ?? {}).length !== 174
      || operations !== 208
      || Object.keys(contract.components?.schemas ?? {}).length !== 239
      || contract.paths?.["/api/v1/auth/email-codes/verify"]?.post?.operationId
          !== "verifyEmailCode"
      || contract.paths?.["/api/v1/homes/{homeId}/memberships/{userId}"]?.delete?.operationId
          !== "removeHomeMembership"
      || contract.components?.schemas?.AiExtraction?.properties?.schemaVersion?.enum?.[0] !== 2) {
    throw new Error("The materialized OpenAPI document is not complete Providentia API 2.0.0.");
  }
' "$temporary"

mv "$temporary" "$output"
trap - EXIT
echo 'Materialized Providentia API 2.0.0 contract.'
