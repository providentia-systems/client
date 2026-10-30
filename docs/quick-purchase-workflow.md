# Recording purchases and correcting receipts

Purchases offers a direct manual entry path: start a receipt, set its purchase
day (defaulting to the local calendar day), choose an existing
home product, select a published pack or the product's stock measurement, enter
the bought quantity and a unit price or line total, then press **Add purchase**.
The deliberate product selection and Add action confirm that line. There is no
second matching step. The line, exact stock addition and durable
`purchasing.receipt-line.purchase` operation are saved together in one local
transaction. The next product can be entered immediately.

Stock is an addition to the current balance. Buying 5 kg with 2 kg recorded
shows 7 kg locally while synchronization is pending when no accepted count
checkpoint constrains the history. For a counted product the existing factual
balance remains visible and the new effect is shown separately until the server
places the purchase in the chronology; an older receipt is not added over a
later accepted count. A selected 1 kg pack purchased
four times and a selected 4 kg pack purchased once both add 4 kg when stock is
tracked in kg; each line preserves its selected pack, bought pack count, price,
converted stock quantity and conversion snapshot. Future changes to catalog
packs do not change the conversion of past purchases or their corrections.

Choose **Quantity in kg/g/ml/l/units** for unpackaged or custom-pack purchases.
Packaging text is retained as description and never parsed into a conversion.
Canonical pack conversion requires a published pack of the same product and a
compatible stock measurement. The queued command carries the expected stock
unit and exact conversion factor; a changed server unit or pack conversion
returns a conflict instead of silently reinterpreting offline purchases. A home tracked in `units` with a selected base pack converts compatible
packs to that base pack: one 4 kg purchase adds four 1 kg stock units. A home
without a base pack accepts canonical count packs in units; mass/volume packs
require an explicit stock measurement. Different units must not be silently mixed. Exact decimal
arithmetic rejects quantities that require more than eight fractional digits.

Receipts coexist. **Receipts** switches between saved active, finished and
cancelled headers; **Start another
receipt** works while a previous receipt awaits confirmation. **Add store** is
visible beside the receipt store selection. Store management remains available
from the Purchases header. **Edit receipt** can correct store, notes and total
while work is pending and after submission. Date and currency cannot change
after stock has been applied. **Edit line** adjusts stock by the difference;
**Remove line** reverses that purchase. Cancelling an open receipt reverses its
applied lines and retains the server's immutable movement history. Applied lines in finished receipts also expose Edit and Remove.
Older approved lines use their original quantity with a factor of one only
after both the receipt and line have been confirmed by authoritative readback.
A locally pending older commit receives no inferred stock or confirmation;
refresh its details before attempting a correction. Retrying corrections to a
previously confirmed finished receipt synchronizes those corrections without
creating another commit. Historical corrections and cancellations preserve a
signed ledger even when the original stock has since been consumed. A negative
result is shown with uncertainty and must not be read as a negative physical
count. Observation/count inputs remain non-negative.

On a confirmed finished receipt whose backend advertises line corrections,
**Add omitted purchase** opens an audited correction editor. Choose an existing
active home product and a published pack or stock measurement, enter the
quantity and a correction reason, and save. Missing prices may remain blank;
an explicit line total preserves discounts and rounding. This creates one new
line and adds only that line's stock. The receipt remains finished and its
original identity, date and already-applied lines are retained.

An intentionally unresolved finished line offers **Edit line**, **Remove line**
and **Resolve purchase**. Editing its description, quantity or prices keeps it
unresolved and does not change stock. Its missing prices can remain blank;
ordinary entry and applied-line edits retain their existing price requirement.
Removing it excludes it without a stock reversal. Resolving explicitly selects a home product/measurement and records
that purchase once. A committed approved line with unconfirmed stock remains
blocked until authoritative refresh; it is not treated as an unresolved line.

The correction editor retains typed values on local validation or revision
failure. A successful local save writes its stock projection and immutable
`purchasing.receipt-line.correct` command atomically, including the original
home/device/account binding, parent receipt revision, optional existing line
revision, correction ID and reason. Restart and network retries retain that
saved operation. Pending confirmation is displayed separately from accepted
readback; a rejected/conflicting operation remains visible in synchronization
review and must not be recreated with a new identity to force it through.
Older backend responses without the correction capability show a refresh
instruction instead of exposing an unsupported finish transition.

Receipt days are calendar labels. The metadata editor, creation requests,
local projection and queued commands preserve the selected `YYYY-MM-DD`
without converting local midnight to UTC. Saving store, notes or total cannot
shift the purchase day across a month/year boundary, and repeated saves retain
that day. Known older local ISO date representations normalize to their
recorded day before ordinary history checks; malformed dates remain errors.
Ordinary metadata saves still reject a real date/currency change once stock
history exists or the receipt is finished.

The application-owned `PurchaseReceiptDateCorrectionRepository` exposes the
separate audited `purchasing.receipt.correct-date` operation with a parent
revision and reason. Its local projection updates the calendar day while
retaining all line identities and stock amounts. Affected balances show
chronology as pending until authoritative readback reconciles the purchase
against counts. Restart/retry uses the existing immutable outbox identity.
**Correct purchase day** opens the dedicated audited flow for eligible saved
receipts, including finished receipts and drafts whose formerly applied lines
have since been removed. It shows the existing and proposed day, requires a
reason of 1–500 characters, and retains the opened revision and typed values on
failure. Refreshing does not silently resubmit against a newer revision.
The receipt's automatic creation time is displayed separately; where the saved
snapshot lacks it, **Refresh receipt creation and correction history** reads
and caches the server's immutable timestamp without substituting purchase day
or last-update time.

**Cancel receipt** on a finished receipt, or **Cancel draft**, requires a
confirmation explaining the whole-receipt stock reversal. Only remaining
applied lines reverse; unresolved lines do not change stock. The receipt is
retained, and repeated clicks/restarts use the original cancellation operation.
Queued cancellation, server acceptance awaiting readback, and synchronized
cancellation have different labels. Rejected/conflicting changes remain
visible with their saved context in correction history and synchronization.

Open **History** to filter all, active, finished, empty or cancelled receipts.
Expanding a receipt shows its header, removed lines and accepted/pending/failed
corrections. Removing the final line leaves an empty corrected receipt rather
than cancelling or deleting it. Cancelled receipts remain discoverable and are
excluded from active receipt spending. Historical creation/correction metadata
is cached in the existing protected local database; online refresh respects the
current household and account and never clears pending operations.

**Finish receipt** closes the group. It applies approved imported lines which
have not yet affected stock and skips manual lines already applied. Repeating
commit or synchronizing confirms the original operation; it never adds the
same purchase twice. Server execution confirmation remains distinct from
validated receipt readback, including the existing response-loss recovery.

**Import photo or PDF** opens the existing household AI intake route, where
permissions, ephemeral media, sanitization, consent, progress and extraction
errors remain visible. Extraction is a proposal. Reviewed intake creates an
ordinary home receipt; selected products and packs are reviewed before the
receipt is explicitly finished. Each imported line shows its bought quantity,
an explicit **Quantity refers to** pack/stock measurement choice, and the stock
addition which will occur on finish. Approval preserves the exact conversion
snapshot without changing stock; finishing applies it once. Importing does not itself change stock.

The implementation is covered by exact pack conversion, additive stock,
idempotent retry, correction/reversal, multiple-receipt selection, cross-unit
rejection, immutable receipt metadata and pending readback regression tests.
A deployment still needs the matching backend contract and normal acceptance
with a configured provider; source and CI tests do not prove credentials or a
live installation's extraction service.
