# Phase 5–8 implementation report

## Scope and decision

This change implements the client-owned domain, application, presentation, and
local-projection work for Phases 5 through 8. It reconciles the authoritative
handover from source commit
`b01b5ef14783b4ad1c1bfc0be7ba0dba32629af8`.

The pinned backend contract remains API `1.3.0`. It has no typed inventory,
purchasing, shopping, AI, administration, or reporting resources. Those
features therefore remain behind typed client ports. Household feature records
are stored only in the local Drift projection and are deliberately excluded
from the generic synchronization outbox. Online-only capabilities fail closed.
The exact backend release work is recorded in
[phases5-8-contract-release-plan.md](phases5-8-contract-release-plan.md).

## Authoritative migration reconciliation

`tool/baseline_reconciliation.mjs` validates the handover without logging
private rows. It fails closed on count or aggregate differences and emits a
machine-readable report.

| Evidence | Reconciled value |
|---|---:|
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

The importer:

- is transactionally idempotent;
- preserves raw purchase descriptions and the monthly/rule source material;
- links stock only on an unambiguous exact normalized product-and-pack match;
- retains non-matches as home-private items instead of silently merging them;
- preserves the eight explicitly unresolved descriptions;
- writes no unsupported synchronization operation.

The handover has only 25 unambiguous current-stock product-and-pack matches.
The remaining 35 stock rows stay explicit rather than being forced onto the
item master. Twelve of the 16 recent lines also lack an unambiguous canonical
link.

## Phase 5 — existing feature parity

Delivered:

- responsive dashboard counts, quick actions, stock-attention rows, and four
  primary application areas;
- counted-stock and complete item-master views;
- canonical name, alias, brand, pack, and category search and filtering;
- reasoned manual adjustments with optimistic quantity checks;
- open/closed/cancelled count sessions and transactional close-to-movement
  application;
- receipt-derived groups, explicit inferred legacy grouping, recent spend, and
  monthly history summaries;
- manual lists, suggested-line representation, check-off, quantity changes,
  progress, explanation, and feedback ports;
- exact baseline reconciliation and local import adapter.

Stock balance remains a derived projection. Count completion and the resulting
append-only variance movements commit in one local transaction.

## Phase 6 — receipt and stock-photo intelligence

Delivered:

- immutable provider profiles, capability declarations, privacy modes, route
  policy, and consent bound to a prepared-media hash;
- cloud proxy-only OpenAI policy with non-storage capability requirements;
- strict-local OpenAI-compatible/Ollama policy with private-endpoint and
  cloud-model rejection;
- write-only credential provisioning and vault ports; controllers never retain
  provider secrets;
- bounded media metadata, preparation/discard contracts, and exact-key
  versioned receipt/stock JSON schemas;
- strict semantic decoding, classification quarantine, ambiguity/confidence
  handling, and proposal-only extraction;
- receipt and stock-photo review controllers and responsive review pages;
- explicit approval/close commands with durable idempotency outcomes;
- medical/unrelated rejection and no-automatic-mutation behavior.

No direct cloud key or cloud adapter is present in Flutter. The future backend
proxy owns cloud credentials, quotas, timeouts, non-storage flags, and
non-logging guarantees. Native strict-local media and credential adapters also
remain explicit infrastructure work; web is not allowed to masquerade as a
secure credential vault.

## Phase 7 — global catalog administration

Delivered:

- home-private product and sanitized global-proposal models;
- allowlisted transmission preview and explicit per-item consent;
- curator/reviewer queue models and capability checks;
- duplicate, alias, barcode, pack, category, and icon workbench states;
- sanitized catalog audit events;
- revision-bound merge preview, merge, and reversal commands;
- reason validation, stale revision rejection, idempotency digest checks,
  concurrent-request coalescing, and retry-safe failure behavior.

Proposal construction excludes home/user identity, price, quantity, store,
receipt identity, raw receipt description, private aliases/notes, media
references, and AI metadata. Catalog permissions never imply home-data access.

## Phase 8 — intelligence and reporting

Delivered:

- append-only movements and deterministic movement-based balance projection;
- reliable count-to-count consumption estimation with inconsistent-interval
  exclusion and honest insufficient-evidence results;
- demand, safety-stock, and lead-time suggestions with evidence explanations;
- deterministic pack waste/cost optimization;
- same-home price observations, normalization, statistics, and store ranking;
- suggestion confidence, accept/edit/dismiss/snooze feedback, and feedback
  summaries;
- rolling-origin MAE, bias, overbuy, and missed-demand backtesting;
- home-scoped balance, movement, purchase, consumption, count-variance, private
  price, unresolved, feedback, and evaluation reports;
- immediate report clearing on home switch and cross-home response rejection.

No fixed `quantity <= 2` rule is promoted as intelligence. Without reliable
count intervals or a user-configured minimum, the client explains that it has
insufficient evidence and suggests nothing.

## Test and quality evidence

The change adds 14 focused test files with 80 declared tests across the new
feature and Drift-adapter slices:

- 36 inventory, purchasing, and shopping tests plus two local-adapter tests;
- 22 AI policy, schema, orchestration, privacy, and widget tests;
- 22 catalog, administration, and reporting tests;
- baseline reconciliation and repository architecture checks.

Before pull-request review, CI must still run the repository-wide pinned
formatter, analyzer, Flutter suite with coverage floor, generated-contract
check, Drift schema checks, goldens, and six-platform build matrix. A green
client CI proves the client implementation; it does not remove the backend
contract release blockers above.
