# Recover an existing home

Use **Account & access → Recover this home** in the authorized original home.
Do not create another home or re-enter purchases to repair an empty local view.
The first verification checks the current authenticated account, device and
home against the backend's member-only synchronization diagnostics. A different
account/device, unavailable evidence or expired sign-in stops recovery without
reassigning saved operations.

**Refresh saved records** obtains the backend's complete authorized bootstrap
snapshot and atomically replaces its local projections. Pending and blocked
work stays inside the existing protected local database, including original
operation IDs, raw payloads, originating account/device/home, enqueue order,
retry state and conflict records. The replacement verifies the queue did not
change. A failed/interrupted transaction rolls back, so retrying this control
does not create replacement purchases or stock movements. The item master is
refreshed separately; if that fetch fails, the last verified catalog remains.

**Review blocked work** submits the preserved commands, in queue order, to the
backend's read-only original-binding revalidation API. Accepted execution
receipts are confirmed through normal operation-status parsing and read back.
Only an eligible device-binding block under its original authenticated binding
may become retryable; the next **Sync now** uses the same operation ID and
payload. Later dependencies wait. Validation/conflict blocks, unknown authorship
and immutable-request mismatches remain preserved for review. Revalidation is
limited to the first 100 unresolved operations at a time and does not execute
commands itself. A response or catalog refresh failure is not proof that every
upload completed; inspect the normal synchronization status afterward.

This workflow preserves the queue in place; it does not provide a portable
plaintext outbox export or move work to another installation. A server data
export contains only server-saved data and is not a backup of unsynchronized
operations. Previously purged local-only work cannot be reconstructed by this
Client. Do not clear browser storage, delete the database, reset the device
identity or share credentials as a generic recovery procedure.

A verified membership revocation continues to deny access and purge scoped
records. Recovery participates in the same revocation barrier as synchronization,
so a late snapshot cannot restore data after that purge. Ordinary resource-level
permission failures do not establish membership revocation.

The dialog displays actual backend build, contract-hash and migration evidence
when available. This is source/transport verification, not evidence that a
specific deployed household has been recovered. Installed native and browser
acceptance must use synthetic accounts and retain their exact build/contract
revisions separately.
