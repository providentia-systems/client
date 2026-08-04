# Phase 9–10 production integration status

Date: 2026-08-04  
Flutter target: `1.0.0+10`  
Authoritative backend review: `providentia-laminas` main and draft PR #5,
read-only

## Corrected contract baseline

The earlier Phase 8 review was based on the Flutter repository's stale API
1.3.0 copy. Laminas main already publishes OpenAPI 3.1 contract version 1.7.0:

- source: `contracts/openapi/providentia-v1.json`
- SHA-256: `0d9f9472b1af44c0bde5dfcd18489dc8fc07cd2a783dadcd9496a13d5de97786`
- 86 operations and 101 component schemas
- online resources through inventory, counts, receipts, shopping, AI,
  catalog administration, intelligence, and reports

Flutter now pins those exact bytes, verifies the hash, and generates a
contract operation registry and callable method for every published operation.
The generated transport remains behind application-owned adapters because
several API 1.7 responses are intentionally free-form.

## Implemented in this phase

| Capability | Client implementation |
|---|---|
| API 1.7 | Exact contract pin, manifest/hash guard, 86-operation generated client |
| Current authentication | API 1.7 password compatibility, native bearer sessions, web cookie sessions |
| Approved authentication direction | Passwordless challenge/link/code application boundary and UI, ready for the forthcoming contract |
| Refresh security | Single-flight rotation; a concurrent native refresh cannot reuse and revoke the session |
| Native credentials | Refresh token only in OS secure storage; access token remains in memory |
| Browser credentials | Secure HttpOnly cookies; no bearer or refresh token in browser storage; CSRF header on mutations |
| Devices | Stable client device ID plus list/revoke session flows |
| Homes | List, create, select/switch, membership list, role change, invite, accept, leave |
| Revoked access | Active workspace closes and late responses are generation-fenced |
| Online household boundary | Authoritative API 1.7 home-stock reads and idempotent home-level adjustments, with strict cross-home response checks |
| AI credentials | Flutter entry to write-only, encrypted, home/provider-scoped Laminas vault |
| API 1.7 extraction | Concrete one-image server-proxy gateway with mandatory review response mapping |
| Media acquisition | Camera, gallery, supported file selection, and short-video capture boundary |
| Image privacy | Decode/re-encode, orientation normalization, resize, metadata removal, exact SHA-256 consent binding |
| Multi-page/media model | Ordered image/PDF-page/video-frame batches with bounded size/count/duration policies |
| Video policy | Audio excluded, deterministic quality selection, temporal spacing, near-duplicate removal |
| Multiple AI | Primary plus optional independent validator, deterministic field comparison, timeout/cost ceilings |
| Approval | Material disagreement and all successful extraction paths require human review; no automatic inventory mutation |
| Release engineering | Fail-closed signing/package/deployment workflows for Android, Apple, Windows, Linux, web, and browser acceptance |
| Supply chain | Checksums, CycloneDX SBOM, release manifest, and in-toto/SLSA-compatible provenance |

## Backend contract gates that Flutter cannot close

These are not optional client TODOs. They require a new released Laminas
contract, and this Flutter work intentionally does not invent them.

| Gate | API 1.7 state | Required backend change |
|---|---|---|
| Full offline Phase 5–8 sync | `SyncOperation.entityType` permits only `home-preference` and `private-note` | Typed sync payloads for inventory, counts, receipts, shopping, catalog proposals, preferences, private products, AI review, and feedback |
| Bootstrap at scale | Untyped, unpaged snapshot | Typed pagination and stable resume semantics |
| Lost response recovery | No operation-status lookup | Idempotency/operation status query |
| Passwordless identity | Password register/login/reset only | Challenge request and magic-link/code completion operations plus app/universal-link contract |
| Multiple provider profiles | One provider/model setting and credential per provider ID | Profile CRUD, same-provider instances, roles, permissions, primary/validator/failover, budgets and probe status |
| Batch AI media | One image, receipt or stock | Multi-photo/PDF/video-frame batch request and exact consent manifest |
| Queued AI | Synchronous extraction under a 30-second PHP limit | `202` job creation, status/recovery, cancellation and idempotency |
| Transactional AI approval | Candidate review is separate from receipt/count commands | Idempotent reviewed extraction-to-domain commit |
| Optional private media backup | Server never persists uploaded media | Retention, quota, export and deletion contract |
| Billing | No subscription/entitlement operations | Product, entitlement, subscription, invoice and webhook-backed state APIs |
| Invitation administration | Create/accept only | List and revoke operations |

Two current contract defects also need correction before replacing the
application-owned adapters with generated DTOs:

1. `SessionCredentials` marks returned access, refresh and CSRF tokens as
   `writeOnly`. They are response secrets and must remain readable by the
   native/web session adapter without ever being logged.
2. Cookie-authenticated mutation operations do not declare the required
   `X-CSRF-Token` header. The client supplies it, but the contract must describe
   it for independent clients and contract tests.

## Connected acceptance path available now

Against deployed API 1.7, the following path is implementable and is the first
live integration target:

1. Sign in with the API 1.7 password compatibility screen.
2. Restore/rotate a native session or restore a browser cookie session.
3. List authorized homes, create one if needed, and select its server-side
   active-home session.
4. Provision a cloud AI credential from Flutter into the encrypted Laminas
   vault. Flutter never reads it back.
5. Prepare one receipt or stock image, confirm the exact transmission, call the
   server proxy, and receive candidates for mandatory human review.
6. Use the published online inventory, count, receipt, shopping and reporting
   operations behind client repositories.

Step 6 is online-only until typed Phase 5–8 synchronization is released. Local
Phase 5–8 projections must not be described as cross-device authoritative in
that interim state.

The existing Phase 5 controller contracts are not identical to API 1.7. In
particular, they model location-scoped adjustments, richer count sessions, raw
purchase/price rows, atomic shopping-list replacement, and feedback without a
server suggestion identifier. The staged online repository therefore exposes
authoritative stock reads and the compatible home-level adjustment operation,
and fails every incompatible legacy method explicitly. Production composition
continues to use the local projection for those incompatible workflows until
the controller models and Laminas sync contract converge; it does not silently
drop location, revision, or idempotency semantics.

## Release evidence versus release automation

The repository now contains executable release automation. It does **not**
claim that signed or store-distributed artifacts exist. Production publication
remains fail-closed until the following external evidence is supplied through
reviewer-protected GitHub environments:

- Android upload/signing key and Play signing configuration
- Apple distribution certificate, provisioning profile, App Store Connect
  issuer/key, macOS Developer ID and notarization credentials
- Windows trusted code-signing certificate
- Linux signing identity and publication destination
- production web origin, deployment hook, TLS and same-site API topology
- privacy policy/support URLs and store metadata
- physical Android/iOS device evidence and real Safari/macOS validation

The production edge must not send `Permissions-Policy: camera=()` to the PWA.
The current Laminas PR #5 Caddy baseline does so; camera capture will fail if
the web client is served behind that header. Cookie auth also requires a
same-site PWA/API deployment because the cookies are Secure, host-only and
SameSite=Strict.

## Phase exit criteria

Phase 9 exits only when the API 1.7 connected path above passes against a live
Laminas deployment, including refresh, retry, revoked membership and
cross-home isolation.

Phase 10 exits only after the new backend contracts close the listed gates,
two-device offline tests prove no duplicate movements, queued AI recovery is
idempotent, and every selected platform has signed artifacts plus independent
device/browser acceptance evidence. Workflows and placeholders are not release
evidence.
