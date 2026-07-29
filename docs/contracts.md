# Contract pinning and generation

The backend repository owns the API and design-token artifacts. This repository
contains versioned, checksum-pinned copies:

- `contracts/providentia-v1.json`
- `contracts/design-tokens/providentia-v1.json`

Their lock files record the source repository, semantic version, local path,
and SHA-256. `tool/generate_api_client.mjs` validates the bounded client subset
and RFC 9457 `ProblemDetails`, writes the lock files, and generates the local
`providentia_api_client` Dart package.

The OpenAPI document currently declares 28 operations. The generator and
generated Dart client implement exactly 7 of those 28:

- `GET /health/live`
- `GET /health/ready`
- `GET /api/v1/system/info`
- `GET /metrics`
- `GET /api/v1/homes/{homeId}/sync/bootstrap`
- `POST /api/v1/homes/{homeId}/sync/push`
- `GET /api/v1/homes/{homeId}/sync/pull`

They also implement:

- RFC 9457 error decoding with extension members and request IDs

The other 21 operations remain present and checksum-protected in OpenAPI but
do not yet have generated Dart methods. In particular, this client does not
claim generated registration, login/refresh/logout, device-session,
home/membership/invitation, ownership-transfer, or catalog/search coverage.
Those methods must be added deliberately with transport, credential, and
presentation tests rather than inferred from the contract pin.

Use:

```bash
node tool/generate_api_client.mjs
node tool/generate_api_client.mjs --check
```

`--check` does not write. It fails if the contract, token checksum, generated
source, package metadata, or generation manifest differs. Contract updates must
be copied from a tagged backend artifact, reviewed for compatibility, generated
here, and released after the compatible backend.

The design-token artifact is pinned and its Fresh Market direction is consumed
by the Phase 3 application theme and adaptive shell.
