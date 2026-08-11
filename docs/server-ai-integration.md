# Server AI integration

Status: production-composed and covered by focused client tests against the
pinned API 1.12 contract. The route is available from Account & access only
for an authenticated user whose active home grants the exact `ai.read`
permission. Composition does not make AI review an automatic inventory
integration.

## User outcome

The household AI workspace can now load revisioned settings, provider profiles,
and orchestration policy; provision a provider credential through a write-only
request; sanitize one image; bind consent to the exact provider revision,
privacy route, purpose, and prepared-media digest; run receipt or stock-photo
extraction through the backend proxy; and record an explicit accept/reject
decision for every returned candidate.

AI review does **not** create a receipt, product, price, stock movement, count,
or shopping line. A completed review produces `AiReviewHandoff`, whose
`requiresOrdinaryDomainCommand` flag is always true. The production route
reports that accepted candidates still require an ordinary purchasing or
inventory command with that domain's permission, revision, idempotency, and
final user-confirmation checks. The AI feature deliberately has no dependency
on those mutation ports.

## Authorization and privacy boundaries

`AiHomeCapabilities.fromPermissions` derives each capability independently
from the backend's exact permission strings:

| Permission | Client surface |
| --- | --- |
| `ai.read` | Load settings, profiles, policy, and extraction review |
| `ai.use` | Prepare media, confirm transmission, extract, and decide candidates |
| `ai.manage` | Change revisioned settings/policy and provider profiles or credentials |

`ai.manage` does not imply `ai.read`, and `ai.read` does not imply `ai.use`.
Changing the active home or losing read/use permission increments the
controller authorization epoch, discards prepared bytes, clears consent and
review state, and ignores any stale asynchronous response. The backend remains
the authorization authority for every request.

Only a re-encoded JPEG from `SanitizingImageMediaPreparer` is eligible for the
current page. EXIF/GPS metadata is removed, dimensions are bounded, and the
gateway verifies both byte length and SHA-256 immediately before transmission.
The original local reference never enters the API request. Credentials are
accepted only as method arguments, passed directly to the write-only contract
field, ignored if a server response attempts to include them, and never placed
in controller or presentation state, logs, errors, or models.

The API adapter rejects malformed enums/revisions, duplicate identities,
unknown policy references, nested foreign `homeId` values, stale review
responses, and create/fetch extraction identity, kind, media, schema, or
candidate-count mismatches. Problem details are normalized into a small safe
failure vocabulary and server detail is never rendered.

## Production composition

The application root constructs a route-owned `ServerAiWorkspaceController`
with:

1. `GeneratedServerAiRepository` using the authenticated generated API client;
2. `SanitizingImageMediaPreparer` backed by the registered source reader and an
   ephemeral prepared-media store;
3. `Api17AiGateway` (the historical class name is retained for compatibility,
   but its enforced contract is now API 1.12);
4. a UUID-backed `AiIdentifierFactory`;
5. `AiHomeCapabilities` from `HomeSessionSnapshot.activeHome.id` and the exact
   `effectivePermissions`;
6. a single-image picker callback that registers bytes as `AiMediaAsset`; and
7. the protected-route registry used by the dual-navigator security boundary.

The Account & access tile checks only `ai.read`; platform roles never grant
household AI access. Session loss, active-home change, or any home-permission
loss dismisses both the outer and nested workspace navigators and clears every
registered protected route before its controller is disposed. The AI route
invalidates the controller capability epoch, removes picker-owned source bytes,
and discards prepared bytes. Its preparation adapter also removes each original
immediately after sanitization succeeds or fails. Late preparation and server
responses therefore cannot repopulate route state after revocation or disposal.

`onReviewHandoff` is intentionally informational in the production
composition. It neither navigates to nor invokes a mutation port; ordinary
purchasing/inventory command integration remains a separately authorized,
explicitly confirmed action.

## Verification surfaces

- `generated_server_ai_repository_test.dart`: contract mapping, revision
  binding, cross-home rejection, write-only credential behavior, safe errors,
  and AI-only candidate decision routes.
- `server_ai_workspace_controller_test.dart`: exact capability derivation,
  sanitization/consent lifecycle, role loss, review handoff, no mutation, and
  widget interaction.
- `api17_ai_gateway_test.dart`: provider-profile/provider-kind routing,
  same-length digest tampering, scope binding, extraction lifecycle, schema
  parsing, quarantine, and safe failures.
- `identity_home_presentation_test.dart`: exact `ai.read` discovery with no
  account-only or similarly named permission bypass.
- `production_bootstrap_security_test.dart` and
  `production_household_composition_test.dart`: route composition, dual
  navigator dismissal, UUIDv4 extraction IDs, source-byte cleanup, and the
  absence of inventory/purchase commit ports.
- architecture tests and `tool/verify_structure.mjs`: generated transport stays
  confined to the approved infrastructure adapter.

Full Flutter analysis and tests remain CI gates. Backend provider credentials,
provider reachability, and operator retention/backup evidence remain deployment
acceptance concerns rather than claims made by this client implementation.
