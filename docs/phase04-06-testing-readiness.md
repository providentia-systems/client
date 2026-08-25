# Phases 04–06 testing-readiness report

> Historical checkpoint (API 1.13.2). For the active API 1.18.0 contract,
> homeowner facade, and release boundary, use `docs/contracts.md` and the
> generated package manifest. This report is retained as implementation
> history, not current release status.

## Outcome

The Flutter application contains the client-owned capability required to test
the master prompt's Phase 04 synchronization, Phase 05 household parity, and
Phase 06 privacy-controlled receipt and stock-photo workflows. It pins backend
API `1.13.2` at SHA-256
`1b6b7f09240ace0ba6b7e7279259687569dfbacb112ea7dbd4094fe27ccd0108`
and generates all 158 declared operations.

The count-session crash is closed: cancelling an open synchronized count now
commits a local `cancelled` projection, queues the revision-bound
`inventory.count-session.cancel` command, retries idempotently after a lost
response, converges to another device, and creates no movement.

This is a testing-readiness statement. Live staging, provider, physical-device,
backup/restore, signing, and store-publication evidence remains operator-owned.

## Phase 04 — synchronization

- Durable per-home outbox, opaque cursors, tombstones, revisions, conflicts,
  retry scheduling, bootstrap replacement, and safe status presentation.
- Serialized startup/manual/app-resume synchronization, with rapid resume
  events coalesced and revoked or disposed homes prevented from reading or
  restarting private synchronization. Privacy-safe metrics expose only
  aggregate counts and durations.
- Home-scoped conflict review preserves both versions, enforces domain write
  permissions, supersedes stale operations without false acknowledgement, and
  offers either a fresh revision-bound reapplication or an explicit
  movement-free count reconciliation.
- Generated v1/v2 transport adapter with closed typed command validation and
  paged bootstrap/high-water enforcement.
- Lost-response idempotency, two-database convergence, compaction recovery,
  home revocation, malformed response, and metrics tests.
- Count cancellation has focused wire-format, Drift/outbox, retry, convergence,
  and no-movement coverage.
- Operation-status response-loss recovery applies a known immutable result once,
  exact-retries an unknown operation with its existing ID, defers unavailable or
  malformed status safely, and maps HTTP 403/404 to authorization loss. Focused
  recovery/gateway/database tests pass 62/62, coordinator/gateway tests pass
  38/38, and compatibility tests pass 7/7.

## Phase 05 — existing feature parity

- Responsive dashboard, typed paged item-master cache, item/stock search and
  filters, adding published packs to a home, manual adjustment, manual and
  photo-assisted counts, purchase history, receipt review, shopping lists,
  suggestions, and baseline-parity documentation.
- The complete verified catalog cache retains all 292 handover packs offline
  and joins canonical name, brand, category, pack, and approved aliases into
  selected and unselected projections. The operational home view additionally
  retains 28 distinct private opening-stock products (320 choices total),
  while the dashboard reports the 292 pack-backed catalog identities. Nine
  reviewed blank-pack rows link to their `Pack size pending` catalog packs
  rather than appearing again as private products.
- Production composition writes household mutations through Drift and the
  typed synchronization outbox; widgets do not call HTTP or SQLite directly.
- Production shows verified online suggestion feeds and explanations, while
  keeping candidates separate until explicit Add to list. Add-time quantity
  selection is available. Existing-line quantity editing, feedback actions,
  and authoritative cross-device suggestion provenance remain deferred;
  lost-response replay must not create duplicate feedback evidence.
- Count close creates only approved variance movements. Count cancel is a
  terminal status transition and never applies observations.

## Phase 06 — receipt and stock-photo intelligence

- Provider/profile settings for OpenAI, compatible endpoints, and Ollama;
  explicit cloud/server-proxy/strict-local privacy routes and consent binding.
  Production stock-photo counting uses a selected verified direct-local route
  on supported native platforms and fails closed when that selected route is
  unavailable or invalid. Server-proxy use requires an explicit route switch;
  there is no silent fallback. Direct-local receipt extraction is not composed;
  an Ollama receipt profile may instead be reached through the server proxy.
- Credential ownership boundaries, prepared-media lifecycle, schema-validated
  extraction, refusal/invalid-output handling, and review controllers.
- Receipt intake accepts one to eight ordered photos or locally rasterizes a
  bounded PDF into at most eight ordered pages. Raw PDFs never enter the media
  registry or gateway. Local previews remain visible, support 90-degree
  rotation and bounded crop, and bind consent to every sanitized page digest.
  A reviewed receipt needs a
  second confirmation before ordinary draft and unreviewed-line commands are
  queued. Matching can approve an existing home product, add a published pack,
  create a private product, or persist a revisioned `unresolved` decision.
  Approved and intentionally unresolved lines are terminal for review; only
  approved lines create purchase effects when the explicit receipt commit is
  confirmed, and an unresolved line can be reviewed and approved later.
- Stock-photo counting starts an ordinary count session first, accepts one to
  eight images, deduplicates images and cross-image candidates, searches the
  full offline item master, can add published/private home products, and
  requires a concrete user-confirmed quantity before an ordinary count-line
  command. Close remains explicit; cancel creates no movement.
- Receipt matching does not publish raw aliases or create sanitized global
  catalog proposals. That privacy-reviewed publication workflow remains Phase
  7 work.

## Paired-backend smoke path

1. Sign in by login link, select a disposable home, and verify initial paged
   bootstrap.
2. Create a product and manual adjustment offline; reconnect and verify exactly
   one movement after retry.
3. Open then cancel a count; verify the second device sees `cancelled` and the
   balance is unchanged.
4. Open another count, add confirmed lines, close it, and verify only variance
   movements are created.
5. Review a multi-page receipt extraction, confirm its ordinary draft handoff,
   approve or intentionally leave every ordinary receipt line unresolved,
   then explicitly commit and retry the pending commit; verify one inbound
   application for each approved line and none for unresolved lines.
6. Run synthetic receipt and stock-photo media through configured provider
   routes, review every proposal, and explicitly complete normal commands.
7. Revoke home membership and verify reads/writes fail and private projections
   are removed after synchronization quiesces.

## Release evidence still required

- CI on the paired backend/client pull requests;
- live two-device/browser persistence against the selected server profile;
- opt-in providers with synthetic or redacted media only;
- backup/restore, monitoring, load/failure, and incident-response rehearsal;
- signed distribution artifacts and independent platform acceptance.

Missing operator evidence keeps the build testing-ready, not
production-accepted.
