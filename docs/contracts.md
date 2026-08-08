# Contract pinning and generation

The backend repository owns the API and design-token artifacts. This repository
contains versioned, checksum-pinned copies:

- `contracts/providentia-v1.json`
- `contracts/design-tokens/providentia-v1.json`

Their lock files record the source repository, semantic version, local path,
and SHA-256. `tool/generate_api_client.mjs` validates RFC 9457
`ProblemDetails`, writes the lock files, and deterministically generates the
local `providentia_api_client` Dart package.

## Current pin

- Client OpenAPI version: `1.7.0`
- Contract SHA-256:
  `0d9f9472b1af44c0bde5dfcd18489dc8fc07cd2a783dadcd9496a13d5de97786`
- Declared/generated operations: 86
- Backend `main` OpenAPI version at this handoff: `1.10.0`

The version difference is intentional and visible. Generated methods show what
the pinned server contract can express; they do not prove that an application
adapter or a reachable UI flow uses every operation. In the current composition,
password login, session restoration/logout, homes, memberships, health, and a
narrow synchronization path have adapters. Registration, verification,
password reset, user/invitation administration, and most newer household
resources are not reachable client workflows yet.

Use:

```bash
node tool/generate_api_client.mjs
node tool/generate_api_client.mjs --check
```

`--check` does not write. It fails if the contract, token checksum, generated
source, package metadata, or generation manifest differs. Contract updates
must be copied from a tagged backend artifact, reviewed for compatibility,
generated here, and released only with a compatible backend. Generated files
are never hand-edited.

The design-token artifact is separately pinned and its Fresh Market direction
is consumed by the application theme and adaptive shell.
