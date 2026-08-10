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

- Client OpenAPI version: `1.11.1`
- Contract SHA-256:
  `56933d2caebc66e238091762398880c8e92a9a9649ba1b7fafdc64b4b96552ef`
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

Session responses keep two UUIDs distinct. `installationId` is the stable UUID
created by this app installation and is used to reject a grant issued for a
different installation. `deviceId` is the backend's account-scoped UUID and is
retained for session identity, device management, and synchronization.

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
