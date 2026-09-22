# Durable outbox provenance — local schema 3

New production commands record the authenticated account, original device and a
transactionally allocated monotonic sequence. Clock adjustments and random UUID
ordering do not reorder parent/child commands or alter their event timestamps.
The counter and optimistic writes roll back together. Explicit conflict
reapplication retains the original logical position and verified provenance;
it does not silently claim historical work for the current user.

Schema 1/2 upgrades add nullable metadata without rewriting operation IDs,
payloads, device IDs, timestamps, receipts or unknown authorship. A null account
is **unknown**, not the current account. Production validates the original
account/home/device before receipt lookup and push. Unknown or mismatching
operations become durable review blockers, never automatic replacement commands.

Production local writers guard both ends of asynchronous transactions against
account/home/permission changes. Late network responses cannot commit into a
retired workspace. Request correlation identifiers are persisted only when UUID
shaped, and failure codes are restricted to the fixed safe vocabulary. No raw
command payload is added to diagnostic summaries.

The local database schema number is independent of the server feed generation;
existing server feed generation 2 cursor bindings are unchanged. This upgrade
preserves historical work but does not by itself establish its creator or prove
that an old command never executed. Historical recovery still requires verified
receipt/provenance evidence or explicit owner review.
