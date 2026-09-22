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
