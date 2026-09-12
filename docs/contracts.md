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

- Client OpenAPI version: `2.1.0`
- Contract SHA-256:
  `40a8477521baa6c41cf2c5d872068f5ae1bf255a8d0bbccc97a05688d705ad57`
- Canonical backend operations: 235
- Generated homeowner operations: 167

API 2.1.0 replaces login links with `requestEmailCode` and `verifyEmailCode`,
adds country onboarding and policy records, account aliases and media, scoped
access groups, operator approval, and per-member permission overrides. The
generator rejects retired password and login-link routes. This is a pre-release
contract realignment; no deployed legacy clients require compatibility.

Application-owned adapters compose:

- bound numeric email-code request and verification, without callback URLs,
  polling, browser approval or build-time credentials;
- web cookie and native bearer refresh/logout, current-user bootstrap, and
  device-session list/revoke;
- active-home selection, editable home settings, recipient invitations,
  memberships, roles, and permission policies;
- revisioned, home-scoped catalog sharing consent and consent-bound sanitized
  product-identity, product-image, and store-price contribution submission;
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

Direct product-identity, product-image, and store-price contributions are
distinct from receipt-driven catalog publication. Each requires revisioned
server opt-in, an exact local review, a fresh per-submission confirmation, and
a durable UUID bound to the payload and consent revision. Product-image input
is bounded to JPEG, PNG, or WebP detected from bytes; camera, gallery, and file
paths share one transient preview and zeroization lifecycle. Receipt matching
does not submit a catalog contribution or publish a global alias. Moderation
and publication remain available only in the separate Admin client.

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
