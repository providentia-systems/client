# Phase 5–8 implementation report

> Historical API 1.13.2 implementation checkpoint. It is not the current
> contract or release declaration; see `docs/contracts.md` and `README.md`.

Status: client implementation and testing readiness against API `1.13.2`,
SHA-256
`1b6b7f09240ace0ba6b7e7279259687569dfbacb112ea7dbd4094fe27ccd0108`.
This report does not claim live deployment or production acceptance.

## Authoritative reconciliation

The fail-closed baseline tooling preserves the handover evidence without
logging private rows:

| Evidence | Reconciled value |
| --- | ---: |
| Item-master product-and-pack rows | 292 |
| Current-stock rows | 60 |
| Current counted units/packs | 159 |
| Recent purchase lines | 16 |
| Historical purchase lines | 452 |
| Monthly summary rows | 261 |
| Alias groups / individual aliases | 13 / 19 |
| Product-identity rules | 19 |
| Unresolved current-stock descriptions | 8 |
| Recent receipt groups / spend | 4 / N$1,078.38 |

The importer is transactionally idempotent, preserves raw descriptions and
unresolved rows, and never forces an ambiguous catalog match.

## Phase 5 — household feature parity

Delivered in the production client composition:

- responsive inventory, purchasing, and shopping workspaces;
- typed protocol-v2 household mutations committed atomically with optimistic
  Drift projections and a durable outbox;
- complete paged item-master refresh and last-verified offline cache, including
  all 292 handover catalog packs plus 28 distinct private opening products;
- authoritative opening-stock identity projection with 32 linked catalog
  rows, all 60 counted rows / 159 units, and no duplicate private identity for
  the nine reviewed blank-pack-to-`Pack size pending` links;
- canonical name, approved alias, brand, category, and pack search across
  counted products and unselected published packs;
- ordinary creation of private home products and selection of published packs;
- reasoned adjustments, count-session open/line/close/cancel, duplicate count
  review, and variance-only close movements;
- recent receipt groups, raw descriptions, recent spend, monthly history, and
  an ordinary receipt draft/review/commit workflow;
- manual shopping lines plus production-composed, verified online suggestion
  feeds, explanations, last-verified offline suggestion cache, and explicit
  Add to list with an add-time quantity choice.

Suggestion feedback, edits to the quantity of an existing list line, and
authoritative cross-device suggestion provenance remain deferred. The UI must
not imply that those actions synchronized. A suggestion never mutates stock.

## Phase 6 — receipt and stock-photo intelligence

Delivered:

- revisioned provider/profile settings, write-only credentials, typed provider
  policy, and explicit server-proxy or strict-local privacy disclosure;
- ordered one-to-eight-page receipt intake with local preview, 90-degree
  rotation, bounded crop, metadata-stripping re-encoding, aggregate transport
  validation, and consent bound to every ordered digest;
- receipt schema validation, quarantine/refusal handling, legitimate duplicate
  line preservation, per-candidate human review, and a second confirmation
  before ordinary receipt draft/line commands;
- complete offline receipt matching against selected catalog products,
  unselected published packs, and private products, with canonical/brand/
  category/pack/approved-alias ranking and visible match reasons;
- explicit choices to approve an existing home product, add a published pack
  and approve it, create a private product and approve it, or persist a
  revisioned unresolved decision that survives reload and can later be
  reapproved;
- an explicit ordinary receipt commit after every line is approved or
  intentionally unresolved. Only approved lines create purchase effects;
  unresolved raw lines remain retained without prices or stock movements;
- production Inventory stock-photo counting that opens an ordinary session
  first, accepts one to eight sanitized photos, deduplicates exact media and
  cross-image candidates, searches the full item master, requires a concrete
  quantity, and writes only ordinary outbox-backed count lines;
- explicit count close and movement-free cancel, with access-loss and disposal
  cleanup of ephemeral media.

The stock workflow uses a verified direct-local Ollama or compatible route when
the user selects one on a supported native platform. A selected local route
that is unavailable or invalid fails closed; using the disclosed server proxy
requires an explicit route switch. Direct-local receipt extraction is not
production-composed. An Ollama receipt profile may be server-proxied; that is
not a local-device privacy claim.

## Phase 7 — catalog administration boundary

Role-scoped catalog consent, direct per-item product-identity contribution,
moderation reads/actions, icon metadata, and revision-bound merge/reversal
surfaces exist behind their independent permissions. They do not grant private
home access and still require live backend acceptance.

Automatic proposal creation from receipt/stock matching, a general sanitized
catalog-proposal handoff for an unknown private item, and global alias
publication are **not implemented**. Receipt text and private aliases remain
home-private. The purchasing UI explicitly directs a user to the separate
future catalog contribution workflow instead of fabricating an unsupported
write.

## Phase 8 — suggestions and reporting boundary

Deterministic demand/stock calculations, evidence explanations, price and
movement reporting models, and home-scoped generated report adapters are
present. Production composes verified suggestion reads and explanations but
keeps feedback and existing-line quantity edits disabled until an idempotent,
provenance-preserving cross-device command is adopted. The fixed prototype
`quantity <= 2` rule remains baseline evidence only, never production
intelligence.

## Synchronization and recovery

Phase 4 foundations used by these workflows include the per-home outbox,
closed command schemas, revisions, cursors, tombstones, bootstrap replacement,
retry, conflicts, app-resume synchronization, revoked-home purge, and
privacy-safe aggregate metrics. Operation-status response-loss recovery applies
known immutable results once, exact-retries unknown operations with the same
IDs, defers unavailable or malformed status safely, and treats HTTP 403/404 as
authorization loss.

## Verification and release gates

Focused suites cover baseline parity, all-page caching, offline search,
optimistic creation, lost-response retry, cross-home denial, count
cancellation, receipt/stock media lifecycle, duplicate protection, no automatic
mutation, explicit commit/close, and shopping suggestion boundaries.

Repository tests are not operator evidence. Paired live backend/client CI,
two-device persistence, configured provider tests with synthetic media,
physical-device capture, backup/restore, monitoring/load/failure rehearsal,
signed artifacts, and independent platform acceptance remain required. Until
those immutable artifacts and results are recorded, the project is
testing-ready rather than production-accepted.
