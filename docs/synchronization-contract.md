# Backend synchronization contract

## Ownership and scope

The Mezzio/Laminas repository owns the OpenAPI contract. Flutter pins the
published bytes, generates transport types, and adapts them to
`SyncRemoteGateway`. Widgets and feature presentation never import the
generated package.

Every request is scoped by the route `homeId`, authenticated user, registered
device, and current membership. Changing an identifier never grants access to
another household.

## Push protocols

`POST /api/v1/homes/{homeId}/sync/push`

The client chooses one closed protocol for each batch:

- protocol v1 carries generic allowlisted entities only (`home-preference` and
  `private-note`);
- protocol v2 carries the typed inventory, purchasing, and shopping commands
  declared by the pinned contract.

The two protocols may not be mixed in one batch. Protocol-v2 operations are
validated for UUID identity, projection type, payload schema, and the base
revision required by each command. The command set includes count creation,
line upsert, close, and movement-free cancellation; receipt creation, line
review, and commit; plus shopping-list creation, lines, and checked state.

The envelope contains a deterministic batch idempotency key, registered device
ID, optional last-pulled cursor, and durable operations. Every operation has a
stable operation ID. Repeating an accepted operation ID must return its stored
result without applying the domain action twice. A lost cancellation response
is therefore safe to retry: the server publishes one `cancelled` revision and
creates no inventory movement.

Each result is classified as accepted, conflict, validation failure,
authorization failure, or retryable failure. Later dependency-ordered
commands are not submitted after an earlier command is rejected or deferred.

## Bootstrap and pull

`GET /api/v1/homes/{homeId}/sync/bootstrap`

A fresh installation pages through one frozen snapshot. The client requires a
stable high-water cursor, advancing page cursors, no duplicate entity records,
and a snapshot cursor only on the final page. It then atomically replaces the
authorized home projection while replaying pending local intent.

`GET /api/v1/homes/{homeId}/sync/pull`

Incremental pull returns an ordered page of upserts or tombstones, the echoed
source cursor, page cursor, frozen high-water cursor, and `hasMore`. Flutter
commits the page and cursor in one Drift transaction. It treats cursor strings
as opaque and never sorts, compares, or synthesizes them.

HTTP 410 with `sync_resync_required` permits one authorized re-bootstrap in a
run. A second compaction response, a changed page boundary, or a cursor that
does not advance fails safely instead of looping.

## Local state and retries

Drift stores projections, durable operations, per-home cursors, conflicts, and
safe status metadata. Access and refresh credentials, provider secrets, and
private media bytes are never stored there.

Mutations commit locally before foreground synchronization. The coordinator
runs on start, resume, home switch, manual refresh, and committed foreground
mutations. Interrupted operations return to retry state with exponential
backoff. Authentication expiry permits one secure recovery attempt; revoked
membership is an authorization failure and does not trigger credential
refresh.

Conflict and validation results are terminal until corrected. Timeouts, 429,
classified 5xx responses, and lost responses remain retryable. Operational
metrics contain counts and classifications, never payloads or household data.

## Count-session terminal behavior

Closing a count explicitly applies approved variance through normal inventory
commands. Cancelling is different: it requires the current open-session
revision, changes the status to `cancelled`, removes it from the active-count
view, and never applies observations or creates movements. Both terminal states
converge through the ordinary change feed.
