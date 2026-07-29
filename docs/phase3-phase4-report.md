# Flutter Phase 3–4 implementation report

## Outcome

Providentia now has an inspectable Fresh Market application shell and a
local-first synchronization foundation without implementing Phase 5 product
workflows.

Owner decisions applied in this phase:

- permanent identifier `com.vastdevelopmentmethod.providentia`;
- proprietary project with no distribution licence yet;
- MySQL as preferred production backend database;
- Redis as preferred production queue/cache profile.

## Responsive design

The implementation follows the inspected approved
`fresh-market-selected-direction.png` evidence and pinned design tokens:

- warm cream canvas;
- forest and fresh-green accents;
- white compact panels with soft shadow;
- rounded touch-friendly controls;
- explicit warning and synchronization states;
- bottom navigation below 700 logical pixels;
- navigation rail from 700 through 1099 logical pixels;
- full sidebar at 1100 logical pixels and wider.

Widget tests cover phone, tablet, and desktop shells, offline state, manual
retry, keyboard focus, large text, semantics, and reduced motion. The golden
test produces a deterministic phone preview at
`test/goldens/providentia_fresh_market_phone.png`.

## Local database

The Drift v2 schema contains:

- `local_records`;
- `client_operations`;
- `local_sync_cursors`;
- `record_tombstones`;
- `local_media_metadata`;
- `sync_conflict_records`.

A local domain mutation and its client operation commit in one transaction.
The operation model preserves operation/device/home/entity identity, nullable
base revision, client timestamp, payload schema version, payload, retry count,
safe error, and the complete durable status lifecycle.

Schema v1-to-v2 migration adds `payload_schema_version` with a value of `1`,
preserves pending operations, and creates the cursor, tombstone, media, and
conflict tables. Exported Drift schema is a review and CI artifact.

No authentication token or provider credential belongs in these tables.

## Synchronization behavior

The coordinator:

- recovers operations stranded in `syncing` after process death;
- obtains an authorized snapshot and captured cursor for a new device;
- pushes stable operation IDs idempotently;
- retries classified failures with deterministic exponential backoff and
  bounded jitter;
- attempts credential refresh once for token expiry;
- distinguishes expired authentication from revoked authorization;
- applies every pull page and its cursor in one transaction;
- maps an expired/compacted cursor to authorized snapshot bootstrap and
  transactionally replaces synchronized cache state while replaying durable
  unacknowledged local intent;
- rejects cross-home changes and cursor mismatches;
- ignores older and duplicate revisions;
- prevents an old upsert from resurrecting a newer tombstone;
- preserves local and remote representations for explicit conflicts;
- returns an explicit completed/offline/authentication/retryable outcome so
  presentation cannot mark a failed synchronization as successful.

Statuses are `pending`, `syncing`, `retry_wait`, `blocked_conflict`,
`blocked_validation`, `blocked_authorization`, and `acknowledged` locally.
The generated backend adapter maps server status `accepted` to local
`acknowledged`.

## Web persistence

`AppDatabase.defaults()` uses `driftDatabase` with:

- native persistent application-document storage and shared-isolate support;
- `DriftWebOptions` with `web/sqlite3.wasm`;
- `web/drift_worker.dart.js`;
- OPFS-backed persistence where browser headers and features permit;
- IndexedDB-backed fallback on supported browsers.

Production hosting must send `application/wasm` for `.wasm` and evaluate:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

Browser reload persistence is an integration gate. Private browsing may force
a weaker storage implementation, which the application must surface rather
than describe as durable.

## Architecture boundary

The generated API client is the only HTTP implementation. Core networking maps
its typed synchronization DTOs to application-owned models. UI code consumes
only `AppController`, repositories, and synchronization summaries.

The exact backend OpenAPI `1.3.0` bytes are pinned at SHA-256
`2c5581964c7d3f23584c52ebd1ec4961b188990e4397aaed9322d98e34550024`.
The generated adapter implements authorized bootstrap, push and pull; sends
`Idempotency-Key` equal to `batchId`; never repeats `homeId` inside an
operation; and maps all five server result classifications.

This is deliberately bounded contract coverage. OpenAPI declares 28
operations; the generator/client implements only 7: four operational/system
reads and the three synchronization resources. The remaining 21 identity,
session, home, membership, invitation, ownership-transfer, and catalog
operations do not yet have generated Dart methods.

The first branch commit intentionally relies on the guarded GitHub workflows
to produce `pubspec.lock`, `app_database.g.dart`, `drift_schemas/*`,
`drift_worker.dart.js`, and the phone golden. Those reviewable artifacts are
not claimed as present until the exact-scope bot commit lands; ordinary CI
regenerates them and fails on modified or untracked output.

## Deferred Phase 4 and multi-device acceptance

The synchronization foundation and deterministic unit/widget tests are
implemented, but full Phase 4 acceptance is still deferred until all of the
following pass against running backend and client artifacts:

- two authenticated devices editing the same and different entities, including
  conflict review and a deliberate resolution;
- lost HTTP response, identical retry, and server-side operation/batch
  idempotency proof;
- high-water pagination, tombstone propagation, replay, cursor expiry, and
  authorized bootstrap replacement over real MySQL/Redis services;
- process termination during push and pull, restart recovery, foreground
  resume, network transition, and manual retry on physical/emulated clients;
- revoked membership versus expired-token behavior using real sessions;
- browser reload persistence and OPFS/IndexedDB fallback verification;
- migration from a previously installed Drift schema with retained pending
  operations;
- green generated-artifact, analysis, test, and six-platform build workflows.

No multi-device release-readiness claim is made before those gates complete.

The shell intentionally contains no inventory count, receipt,
purchase-history, recommendation, or shopping-list behavior. Those remain
Phase 5; current workspace cards are labeled accordingly.
