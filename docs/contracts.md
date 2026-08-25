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

- Client OpenAPI version: `1.18.0`
- Contract SHA-256:
  `fb7f18cc8d2e0f7aaf3ec9f1bd3039316c6f44af0023110936778a8d616a6759`
- Canonical backend operations: 177
- Generated homeowner operations: 145

The login-link onboarding, account-management, and current household
integration surfaces are deliberately adopted as one compatible boundary.
Application-owned adapters compose:

- generic email-only login-link start/status/cancel/exchange with client-owned
  poll and PKCE proofs, plus app-owned fragment-secret proof, review, and
  approve/deny handling for the exact homeowner link base;
- web cookie and native bearer refresh/logout, current-user bootstrap, and
  device-session list/revoke;
- active-home selection, editable home settings, recipient invitations,
  memberships, roles, and permission policies;
- revisioned, home-scoped catalog sharing consent and consent-bound sanitized
  product-identity and store-price contribution submission;
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

The canonical contract records the complete backend API. The generated client
is a default-deny homeowner facade and excludes platform administration,
operator, catalog-administration, webhook, and moderation methods. Generated
methods still do not prove that every homeowner operation is reachable from a
visible screen.
Inventory workspaces commit through local projections and the durable outbox.
Sync protocol v2, revision-bound stock-count cancellation, and paged bootstrap
support are retained in the generated gateway.

Production composes verified shopping-suggestion reads, explanations, and
explicit Add to list. Suggestion feedback, existing-line quantity edits, and
authoritative cross-device suggestion provenance remain deferred even where a
generated method exists; generation is not a retry/idempotency guarantee.

Direct product-identity and store-price contributions are distinct from
receipt-driven catalog publication. Each requires revisioned server opt-in, an
exact local review, a fresh per-submission confirmation, and a durable UUID
bound to the payload and consent revision. Receipt matching does not submit a
catalog contribution or publish a global alias.

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
