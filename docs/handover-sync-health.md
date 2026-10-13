# Synchronization health and failure boundaries

A completed download is not proof that saved uploads succeeded. The coordinator
reports `uploadsBlocked` for a rejected/binding-blocked predecessor and
`uploadsPending` for work still queued or delayed. Both can have
`pullCompleted: true`; only an empty unresolved queue and a completed pull
produce full success. The existing dependency barrier is retained.

Device-binding mismatch is a dedicated binding failure, never an expired-login
signal. No operation ID, payload or device is rewritten. Only the explicit
backend `sync_home_access_denied` machine type may enter revoked-home handling.
Generic HTTP 403/404, missing referenced records, permission changes and wrong
endpoints retain saved work. English error text is never treated as proof of
membership loss. Older servers without machine classifications need a deployment
or permission check, not destructive cache or queue clearing.

The generated adapter now retains result codes and protocol-v2 command result
projections rather than dropping them. Existing scoped operation receipts and
exact retries remain the only automatic ambiguous-outcome recovery path. This
change does not establish authorship or repair a historical schema-2 queue.

The later API 2.2.0 household feature completion is documented in [Household workflows](household-workflows.md). Category-refresh failures retain completed-pull evidence, pending/blocked upload status and the unresolved upload count; they never turn a blocked queue into full synchronization success.

The Home status card has a labelled **Sync now** action and displays the last
successful refresh time for the current workspace session. It runs the existing
home synchronization and complete item-master/category refresh together. Linked
canonical product names, brands and pack details are therefore refreshed through
the same verified cache path. Private home overrides continue to take precedence.
A failed catalog refresh remains visible even when the local upload-summary
stream emits another update; a new successful run clears the failure.

An existing pull cursor rejected with the backend's typed HTTP 422
`sync_cursor_invalid`, or HTTP 410 `sync_resync_required`, requests one authorized
snapshot replacement per synchronization run. Snapshot recovery preserves queued
operation IDs, account/device bindings, local-only caches and unsynchronized
purchase projections. Repeated failure stops with a retryable message. Generic
validation errors, absent cursors and wrong-home cursor denials do not trigger
this recovery. This requires the coordinated backend update; English error text
alone never authorizes recovery.

Quick purchases, applied-line corrections/removal, receipt cancellation and
receipt commit can project stock locally before network confirmation. Pending
commands protect their affected stock balances and parent receipt against older
feed events and snapshot replacement. Once the commands are acknowledged, the
authoritative absolute balance replaces the local projection. The client never
adds the optimistic purchase again during readback, including response-loss
recovery and another device's stock changes.
