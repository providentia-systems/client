# Phases 5–8 backend contract release plan

> Historical API 1.13.2 plan retained for decision traceability. The active
> contract is API 1.19.0; use `docs/contracts.md` for current operations,
> checksums, and the homeowner-only generation boundary.

## Decision

The Flutter client must not invent transport operations that are absent from
the backend-owned OpenAPI artifact. This release pins API `1.13.2`, SHA-256
`1b6b7f09240ace0ba6b7e7279259687569dfbacb112ea7dbd4094fe27ccd0108`,
from the companion backend release. The generic synchronization
allowlist remains limited to `home-preference` and `private-note`.

All of these domains remain behind application-owned ports. Inventory,
purchasing, and shopping synchronize only through the deliberately adopted
typed protocol-v2 command adapter. Any further AI, catalog, or reporting
resource still requires an explicit compatible adapter. The current contract's
catalog consent/contribution/moderation, reporting, data-governance, and
household-AI resources now have application-owned adapters and production
composition. Live backend, provider, cross-device, and supported-platform
acceptance remain separate release gates. No domain may be sent as a made-up
entity type through the generic protocol-v1 synchronization endpoint;
generated operations alone do not make a workflow reachable.

The generated operation-status lookup is now connected to coordinator
response-loss recovery. Known immutable results are applied once; unknown
operations exact-retry with the same IDs; unavailable or malformed status is
deferred safely; and HTTP 403/404 is a purge-class authorization outcome.

This is a fail-closed compatibility rule, not a reason to put HTTP calls in
widgets or to hand-edit the generated Dart client.

## Required release order

1. Implement and test the resource in
   `providentia-systems/backend`.
2. Publish a semantically versioned, immutable OpenAPI artifact.
3. Prove server conformance, tenant authorization, idempotency, pagination,
   revision, and Problem Details behavior.
4. Copy the exact tagged artifact into this repository and update
   `contracts/contract.lock.json`.
5. Extend `tool/generate_api_client.mjs`; never hand-edit generated Dart.
6. Generate the Dart client and add transport-contract tests.
7. Implement a narrow Flutter infrastructure adapter for the existing
   application port.
8. Release the backend before the compatible Flutter client.

## Phase 5 typed resources

| Capability | Required contract behavior |
|---|---|
| Active-home dashboard | Home-scoped counts and recent activity; no private values in operational metrics |
| Catalog and item master | Typed, paginated product/pack/alias/category search with catalog revisions |
| Inventory | Home/location-scoped balances plus append-only movements; balances are projections, never client mutation commands |
| Manual adjustment | Idempotent command with reason, expected revision, unit/pack identity, and audited movement result |
| Count sessions | Create, update lines, attach local-media metadata, review duplicate candidates, and idempotently close into variance movements |
| Purchases | Typed receipt/history reads preserving raw descriptions and canonical links |
| Shopping lists | List/line CRUD, check state with expected revision, tombstones, and home authorization |
| Baseline migration | Idempotent import session, dry-run reconciliation, explicit unresolved records, and a machine-readable final report |

The baseline import must preserve the verified 292/60/16/452/261 record
sets and must not silently resolve the eight unresolved descriptions.

## Phase 6 typed resources

| Capability | Required contract behavior |
|---|---|
| Provider profile | Metadata CRUD without returning plaintext credentials |
| Credential lifecycle | Set/replace/delete through the encrypted server vault; credential value is write-only |
| Provider probe | Capability and configuration check without user media |
| Extraction | Bounded, authenticated request accepting only sanitized transient media and returning a typed proposal |
| Receipt approval | Idempotent ordinary-domain command that creates approved receipt lines, price observations, and stock-in movements once |
| Stock-count approval | Idempotent close command that creates auditable variance adjustments once |

Cloud OpenAI and remote OpenAI-compatible credentials belong on the backend.
The Flutter client may directly call a verified self-hosted/local endpoint only
under the strict-local policy. The cloud proxy must set the provider's
non-storage option where supported, apply quotas and timeouts, avoid logging
media or extracted text, and return structured proposals rather than domain
mutations.

The production client currently composes ordered one-to-eight-page receipt
intake with local rotate/crop and ordinary draft/match/explicit commit, plus
one-to-eight-image stock counting through ordinary count commands. Stock may
use a verified direct-local native route when explicitly selected; that route
fails closed when unavailable or invalid, and server-proxy use requires an
explicit switch. Receipt direct-local extraction is not composed; an Ollama
receipt profile may instead be server-proxied. Neither workflow mutates a
balance from an AI proposal.

## Phase 7 typed resources

| Capability | Required contract behavior |
|---|---|
| Private home product | Immediately usable in one home without global publication |
| Sanitized proposal | Explicit per-item opt-in and an exact allowlisted DTO |
| Moderation queues | Capability-scoped, paginated proposal/duplicate/alias/barcode/pack/category/icon queues |
| Review command | Reason, expected revision, idempotency key, and sanitized audit result |
| Merge preview | Revision-bound global reference impact without exposing home rows or identities |
| Merge/reversal | Elevated capability, typed confirmation, idempotency, transactional relinking, audit event, and fresh reversal preview |
| Audit history | Sanitized catalog-only events; platform/catalog roles do not imply home-data access |

The proposal DTO must exclude home/user identity, price, quantity, store,
receipt number, raw receipt description, private aliases/notes, media
references, and AI metadata by construction.

Direct per-item product-identity contribution and role-scoped moderation do
not complete the general proposal workflow. Receipt/stock matching does not
yet create a sanitized catalog proposal or publish a global alias; those remain
Phase 7 implementation work.

## Phase 8 typed resources

| Capability | Required contract behavior |
|---|---|
| Movement ledger | Authoritative sequence, idempotent source identity, transfers, compensating reversals, and as-of pagination |
| Consumption evidence | Eligible count intervals and exclusion reasons; no fabricated rate when evidence is insufficient |
| Suggestion runs | Model version, evidence coverage, limitations, explanation, confidence facts, and deterministic quantity |
| Suggestion feedback | Accept/edit/dismiss/snooze/always/never/preferred-pack with immutable run linkage |
| Price observations | Same-home, currency and normalized-unit safe comparisons with count/date coverage |
| Reports | Home-scoped balance, movement, purchases, variance, price, unresolved, suggestion, and evaluation datasets |
| Backtesting | Rolling-origin evaluation with coverage and no future leakage |

Verified suggestion reads, explanations, offline cache, and explicit Add to
list are production-composed. Suggestion feedback, edits to existing list-line
quantity, and authoritative cross-device suggestion provenance remain deferred
until their retry-safe ordinary-command boundary is adopted.

## Required authorization tests

Every private resource requires:

- horizontal object-identity denial within the same home;
- cross-home denial even when an ID is guessed;
- role and capability denial;
- revoked-membership behavior;
- home-switch cache reset;
- non-disclosing `403`/`404` behavior according to server policy;
- server-derived home authorization rather than trust in a path/body value.

Catalog administrators must be unable to query stock, purchases, lists,
prices, AI settings, private media, or raw extraction records unless they are
separately an authorized member of that home.

## Client behavior before the contract release

The client may provide pure domain logic, tested controllers, local drafts,
review screens, deterministic calculations, and port-based presentation. A
production composition must show an explicit unavailable-capability state for
online-only work. It must not display fake success, silently keep an
online-only command in memory, or claim synchronization for an unsupported
record.
