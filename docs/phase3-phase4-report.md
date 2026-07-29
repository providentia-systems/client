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
- rejects cross-home changes and cursor mismatches;
- ignores older and duplicate revisions;
- prevents an old upsert from resurrecting a newer tombstone;
- preserves local and remote representations for explicit conflicts.
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

The exact backend OpenAPI `1.2.0` bytes are pinned at SHA-256
`9626cba71d368003ab069864c6f744414044f8d5c4baf8c7b69553cad435a8db`.
The generated adapter implements authorized bootstrap, push and pull; sends
`Idempotency-Key` equal to `batchId`; never repeats `homeId` inside an
operation; and maps all five server result classifications.

The shell intentionally contains no inventory count, receipt,
purchase-history, recommendation, or shopping-list behavior. Those remain
Phase 5; current workspace cards are labeled accordingly.
