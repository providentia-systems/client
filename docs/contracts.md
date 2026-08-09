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

- Client OpenAPI version: `1.11.0`
- Contract SHA-256:
  `6535298b37f99edb19d13afe1a2d36b8987ab4c051b091419eefe3ae8dbc469c`
- Declared/generated operations: 155

The login-link onboarding and account-management surface is deliberately
adopted as one compatible boundary. Application-owned adapters compose:

- generic email-only login-link start/status/cancel/exchange with client-owned
  poll and PKCE proofs;
- web cookie and native bearer refresh/logout, current-user bootstrap, and
  device-session list/revoke;
- active-home selection, editable home settings, recipient invitations,
  memberships, roles, and permission policies; and
- platform-administrator list/grant/revoke with revision conflict handling.

Generated methods show what the pinned server contract can express; they do
not prove that every household operation is reachable from a visible screen.
The current inventory workspaces still include local projections while the
typed synchronization boundary is adopted incrementally. Sync protocol v2 and
paged bootstrap support are retained in the generated gateway.

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
