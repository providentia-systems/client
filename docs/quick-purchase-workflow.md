# Recording purchases and correcting receipts

Purchases offers a direct manual entry path: start a receipt, choose an existing
home product, select a published pack or the product's stock measurement, enter
the bought quantity and a unit price or line total, then press **Add purchase**.
The deliberate product selection and Add action confirm that line. There is no
second matching step. The line, exact stock addition and durable
`purchasing.receipt-line.purchase` operation are saved together in one local
transaction. The next product can be entered immediately.

Stock is an addition to the current balance. Buying 5 kg with 2 kg recorded
shows 7 kg immediately, pending synchronization. A selected 1 kg pack purchased
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

Open receipts coexist. **Open receipts** switches between them; **Start another
receipt** works while a previous receipt awaits confirmation. **Add store** is
visible beside the receipt store selection. Store management remains available
from the Purchases header. **Edit receipt** can correct store, notes and total
while work is pending and after submission. Date and currency cannot change
after stock has been applied. **Edit line** adjusts stock by the difference;
**Remove line** reverses that purchase. Cancelling an open receipt reverses its
applied lines and retains the server's immutable movement history. Corrections
that exceed available stock are rejected locally and on the server.

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
