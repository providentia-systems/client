# Backend synchronization contract

## Ownership

The Mezzio/Laminas repository owns this OpenAPI contract. Flutter pins the
published bytes, generates transport types, and adapts them to
`SyncRemoteGateway`. Widgets and feature presentation never import the
generated package.

## Push

`POST /api/v1/homes/{homeId}/sync/push`

The route `homeId` is an integrity and resource-selection value. The server
still derives the authenticated user, membership, role, and allowed active
home; changing the route cannot grant access.

The request envelope contains:

- `protocolVersion`: integer `1`;
- `batchId`: client-generated idempotency identifier;
- `deviceId`: registered device identifier;
- optional `lastPulledCursor`;
- `operations`.

Each operation contains the durable client operation ID, entity type and ID,
operation type, nullable base revision for create/append operations, client
timestamp, payload schema version, and typed JSON payload. It does not repeat
`homeId`; the route owns that scope.

Every operation receives one result with status:

- `accepted`;
- `conflict`;
- `validation_error`;
- `authorization_failure`;
- `retryable_failure`.

Results use `revision`, `changeCursor`, and `representation` where applicable.
Repeating a previously accepted operation ID must return its stable result
without applying the domain mutation twice.

## Pull

`GET /api/v1/homes/{homeId}/sync/pull`

The request supplies the opaque current cursor and bounded page size. The
response includes protocol version, source cursor, request ID, changes, page
cursor, high-water cursor, and `hasMore`.

Each change has an opaque ordered cursor, entity identity, revision, server
timestamp, and operation `upsert` or `delete`. An upsert has a
`representation`; a delete has a `tombstone`.

Flutter advances the cursor only in the same local transaction that commits
the full page. It never sorts, synthesizes, or compares opaque cursor text.
HTTP 410 with problem type ending in `sync_resync_required` triggers one
authorized bootstrap. The replacement snapshot, captured cursor, and replay of
unacknowledged local intent commit atomically. A second 410 in the same run
fails safely instead of looping.

## Initial bootstrap

`GET /api/v1/homes/{homeId}/sync/bootstrap`

A fresh installation has no local cursor, so it first requests an authorized,
consistent snapshot. Flutter commits all snapshot records and the returned
`snapshotCursor` in one transaction, then starts ordinary pull requests from
that cursor. The client does not invent a zero cursor. For compatibility
diagnostics, if an initial pull is ever issued without a cursor, the repository
accepts the backend's encoded genesis `fromCursor` only while the local cursor
is absent; every later page must echo the committed cursor exactly.

## Authentication and failures

- HTTP 401/token expiry attempts one secure credential refresh. If refresh
  fails, local intent remains retryable and the app shows sign-in-required.
- HTTP 403/revoked membership never triggers credential refresh. Push maps it
  to `authorization_failure` and `blocked_authorization`; bootstrap/pull return
  an explicit authorization outcome and “access changed” presentation state.
- Conflict and validation results are not eligible for blind manual retry.
- Timeouts, 429, and classified 5xx responses remain in the durable outbox
  with exponential backoff and bounded jitter.
- Access and refresh tokens are never persisted in Drift.
- Browser requests use the backend's credentialed cookie session and CSRF
  contract. Native requests obtain their session through interactive sign-in;
  no bearer token or home identifier is injected at build time.
