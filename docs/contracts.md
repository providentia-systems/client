# Contract pinning and generation

The backend repository owns the API and design-token artifacts. This repository
contains versioned, checksum-pinned copies:

- `contracts/providentia-v1.json`
- `contracts/design-tokens/providentia-v1.json`

Their lock files record the source repository, semantic version, local path,
and SHA-256. `tool/generate_api_client.mjs` validates the required Phase 1
operations and RFC 9457 `ProblemDetails`, writes the lock files, and generates
the local `providentia_api_client` Dart package.

The generator currently proves:

- `GET /health/live`
- `GET /health/ready`
- `GET /api/v1/system/info`
- `GET /metrics`
- RFC 9457 error decoding with extension members and request IDs

Use:

```bash
node tool/generate_api_client.mjs
node tool/generate_api_client.mjs --check
```

`--check` does not write. It fails if the contract, token checksum, generated
source, package metadata, or generation manifest differs. Contract updates must
be copied from a tagged backend artifact, reviewed for compatibility, generated
here, and released after the compatible backend.

The design-token artifact is pinned but intentionally not consumed by Flutter
widgets until Phase 3.
