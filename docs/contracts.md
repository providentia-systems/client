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

- Client OpenAPI version: `1.13.2`
- Contract SHA-256:
  `1b6b7f09240ace0ba6b7e7279259687569dfbacb112ea7dbd4094fe27ccd0108`
- Declared/generated operations: 158

The login-link onboarding, account-management, and current household
integration surfaces are deliberately adopted as one compatible boundary.
Application-owned adapters compose:

- generic email-only login-link start/status/cancel/exchange with client-owned
  poll and PKCE proofs;
- web cookie and native bearer refresh/logout, current-user bootstrap, and
  device-session list/revoke;
- active-home selection, editable home settings, recipient invitations,
  memberships, roles, and permission policies; and
- platform-administrator list/grant/revoke with revision conflict handling;
- revisioned, home-scoped catalog sharing consent and consent-bound sanitized
  contribution submission; and
- attribution-free catalog review queues, platform-role moderation, icon
  metadata, and revision-bound reversible merge operations;
- home-scoped inventory, purchasing, shopping, reporting, and account/home
  data-governance operations with exact permission checks; and
- home-scoped AI settings, profiles, policy, sanitized extraction review, and
  non-mutating review handoffs. One to eight ordered receipt pages and stock
  photos use the bounded multipart extraction contract. A separate receipt
  confirmation may queue an ordinary draft, after which matching, product
  selection/private creation, approval, and explicit commit remain ordinary
  purchasing commands. Stock candidates become only ordinary count-line
  commands after a user supplies a concrete quantity.

These application-owned adapters are composed into the signed-in production
navigation and covered by focused transport, controller, privacy, and
revocation tests. Composition and generated methods do not by themselves
constitute live client/backend or supported-platform acceptance evidence.

Session responses keep two UUIDs distinct. `installationId` is the stable UUID
created by this app installation and is used to reject a grant issued for a
different installation. `deviceId` is the backend's account-scoped UUID and is
retained for session identity, device management, and synchronization.

Generated methods show what the pinned server contract can express; they do
not prove that every household operation is reachable from a visible screen.
Inventory workspaces commit through local projections and the durable outbox.
Sync protocol v2, revision-bound stock-count cancellation, and paged bootstrap
support are retained in the generated gateway.

Production composes verified shopping-suggestion reads, explanations, and
explicit Add to list. Suggestion feedback, existing-line quantity edits, and
authoritative cross-device suggestion provenance remain deferred even where a
generated method exists; generation is not a retry/idempotency guarantee.

Direct per-item product-identity contribution is distinct from receipt-driven
catalog publication. Receipt matching does not submit a sanitized catalog
proposal or publish a global alias. Those general Phase 7 workflows remain
unimplemented and may not be inferred from moderation or contribution methods
in the generated client.

The generated operation-status lookup is integrated into synchronization
response-loss recovery. A known immutable result is applied once, an unknown
operation is retried with the exact same operation ID, unavailable or malformed
status is deferred safely, and HTTP 403/404 is treated as a purge-class
authorization outcome.

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
