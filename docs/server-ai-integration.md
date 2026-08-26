# Server AI integration

Status: production-composed for testing against API `1.19.0`, SHA-256
`7e13d550e7a4438297766f654fadbd1e75894efac989229da6fcd0d9f7f97dda`.
This is not live-provider or production-acceptance evidence.

## Delivered user paths

The active-home AI workspace loads revisioned settings, provider profiles, and
orchestration policy; provisions write-only provider credentials; prepares
privacy-bounded media; binds consent to the provider revision, privacy route,
purpose, and every ordered prepared-media digest; and records explicit review
decisions for typed proposals.

Receipt intake supports one to eight ordered photo pages or a locally
rasterized PDF of up to eight pages. Raw PDF bytes are bounded, validated,
never registered for transmission, and cleared after rendering. Before
preparation, the user sees local previews and can rotate a page clockwise by
90 degrees or apply a bounded crop. Each edited page is re-encoded locally. The ordinary
sanitizer then bakes orientation, bounds dimensions, strips embedded metadata,
re-encodes JPEG bytes, and computes the digest used for consent and transport.
All ordered sanitized previews remain visible during proposal review.

After receipt review, a second explicit confirmation may create an ordinary
home-private receipt draft and unreviewed receipt lines. Matching remains a
separate purchasing action. It searches the verified offline item master,
including selected home products, unselected published packs, private rows,
canonical names, brands, categories, packs, and approved aliases. The user may
approve an existing home product, add a published pack to the home and then
approve it, create a private home product and approve it, or leave the line
unresolved. Receipt commit is a further explicit action. Only that ordinary,
idempotent purchasing workflow may create purchase effects or stock-in
movements.

The Inventory workspace also composes stock-photo counting. It opens an
ordinary count session first, accepts one to eight ordered sanitized photos,
deduplicates exact images and duplicate candidates, requires the user to match
and enter a concrete quantity, and persists only ordinary outbox-backed count
lines. Count close remains explicit and applies only reviewed variance;
cancellation is terminal and creates no movement.

AI output alone never creates a receipt, product, price, shopping line, count
line, balance, or stock movement.

## Routes and provider boundaries

The server AI workspace uses `GeneratedServerAiRepository` and
`Api17AiGateway` (the historical class name remains, but the enforced contract
pin is API `1.19.0`). Cloud media goes through the authenticated server proxy.
OpenAI credentials remain server-owned and write-only.

The production stock-photo workflow uses an active, verified direct-local
Ollama or OpenAI-compatible route when the user selects one on a supported
native platform. A selected local route that is unavailable, dangling, or
misconfigured fails closed before consent and never falls back to cloud or the
server proxy; the user must explicitly switch routes. Route-specific consent is
bound before bytes are sent. Direct strict-local networking is denied on web
because browser APIs cannot prove the connected peer or reliably disable
redirects.

Direct-local receipt extraction is **not** production-composed. A receipt may
use an Ollama profile only when that profile is reached through the configured
server-proxy AI workspace. Do not describe this as direct-device or guaranteed
local processing.

## Authorization and privacy

`AiHomeCapabilities.fromPermissions` derives each capability independently:

| Permission | Client surface |
| --- | --- |
| `ai.read` | Load settings, profiles, policy, and extraction review |
| `ai.use` | Prepare media, confirm transmission, extract, and review candidates |
| `ai.manage` | Change revisioned settings/policy and provider profiles or credentials |

`ai.manage` does not imply `ai.read`, and `ai.read` does not imply `ai.use`.
Changing home, losing membership or permission, or disposing the route clears
picker sources, local edit previews, prepared bytes, consent, proposals, and
review state. Late preparation or network responses cannot repopulate a
revoked route. Backend non-disclosing revoked-home responses are normalized to
authorization loss and trigger the protected-home purge/route boundary.

Direct extraction uploads are transient request staging, not durable
Providentia media retention. Optional encrypted private-media retention is a
separate, explicit policy path. The client does not log media bytes, extracted
receipt text, provider secrets, home identifiers in AI metrics, or local file
paths.

The adapters reject malformed enums/revisions, duplicate identities, unknown
policy references, cross-home payloads, stale reviews, mismatched media
bindings, aggregate byte/digest/count mismatches, and unsafe provider routes.
Legitimate duplicate receipt lines remain separate review candidates; only
stock-photo duplicate candidates are collapsed or flagged.

## Verification and remaining evidence

Focused tests cover multi-page ordering, local rotation/crop, sanitization,
ordered digest consent, multipart transport, duplicate receipt-line
preservation, stock duplicate protection, no automatic mutation, ordinary
draft/count handoff, lost-response convergence, cleanup, disposal, revocation,
and cross-home denial.

Repository tests and simulated adapters do not establish production
acceptance. Live server/provider configuration, native peer-verification,
physical-device media acquisition and PDFium packaging, two-device convergence, retention controls,
backup/restore, monitoring, incident rehearsal, signing, and supported-platform
evidence remain operator-owned release gates.
