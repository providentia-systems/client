# Receipt confirmation and readback recovery

Receipt capture preserves two different facts: the immutable command result
confirms whether the server committed, while validated feed data confirms what
can be rendered as authoritative purchase history. An accepted commit with a
failed download says **commit confirmed; receipt details refreshing**. It never
creates another commit operation to repair a display error.

- Transport failures and malformed successful push responses query operation
  status with the original operation, device and home identifiers. Account and
  workspace binding checks run before lookup or dispatch and after responses.
- Process-death recovery and durable retry rows query status before dispatch.
  A known result is applied once. Only explicit `known: false` permits an exact
  retry. Unavailable, malformed or mismatching status defers the command and
  preserves the dependency barrier.
- Accepted and superseded outbox rows cannot be resurrected by late failures.
  Acknowledgement alone does not mark receipt projections as fully read back.
  Retrying an acknowledged receipt refreshes synchronization using the saved
  operation; it never allocates a new identifier.
- Bootstrap and pull validate receipt/line identity, revision, review state,
  required fields and decimal-string values before advancing the local cursor.
  Numeric money/quantity fields are not coerced into the pinned contract.
  Unreadable pages leave the previous usable local projection and cursor intact.
- Previously stored, synchronized receipt projections that fail validation
  trigger a fresh authorized home snapshot. The existing snapshot replacement
  retains pending local intent. This repairs caches populated by the earlier
  numeric serializer without discarding receipts or changing operation IDs.
  Local tombstones are excluded from this check.
- The capture stream watches durable commit acknowledgements as well as record
  changes. Successful readback clears obsolete capture-read errors, closes the
  completed capture and exposes synchronized purchase history. Other homes'
  records and acknowledgements never join this view.

Regression coverage: `receipt_confirmation_recovery_test.dart` drives real
Drift persistence and the generated HTTP adapter through a four-command receipt,
malformed commit response, immutable status recovery, invalid readback, actual
SQLite close/reopen and corrected readback. It verifies one simulated server
commit effect, unchanged operation identities/payloads, NAD 25 history, home
isolation, old-cache recovery and tombstones. Coordinator tests cover unknown,
unavailable, malformed and mismatched status; purchasing widget tests cover
truthful confirmed/readback display and stale-error clearing.

These deterministic tests do not replace the live backend/native acceptance
run. The backend receipt/feed serializer repair is still needed: invalid wire
responses deliberately remain rejected by the client.
