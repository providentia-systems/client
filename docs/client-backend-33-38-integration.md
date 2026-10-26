# Client integration for backend issues 33–38

This branch implements the homeowner Client companions to backend issues 33–38.
Backend changes are reviewed in providentia-systems/backend#39; operator Stock
metadata is consumed by providentia-systems/admin#22.

| Backend requirement | Client work in this PR |
| --- | --- |
| #33 Finished receipt corrections | #43 dedicated omitted/unresolved purchase correction, revision checks, durable operation identity, no replay of prior purchases, retained invalid inputs; existing no-stock unresolved edit/remove remains linked to the narrow backend companion. |
| #34 Purchase amount semantics | #45 receipt-aware spending, header precedence, exact per-line rounding, disclosed partial prices, separate currencies and entered-product subtotal, header-only receipt visibility. |
| #35 Truthful inventory reports | #33 nullable unknown quantity, signed recorded balance, uncertainty, pending amount, unit, limitations and checkpoint context; legacy evidence stays explicitly unavailable. |
| #36 Operator stock metadata | Admin owns this UI. The Client preserves compatible additive inventory evidence. |
| #37 Recovery and stock units | #30 Account & access → Recover this home, exact original-binding checks and atomic queue preservation; #35 unit-in-use guards and authoritative unit readback. AI resource errors do not authorize membership purge (#28). |
| #38 Supported adapter tests | #39 canonical API 2.4 generation, browser homeowner namespace, additive count/stock/shopping evidence, signed ledger values; #40 calendar-day metadata fix and audited date repository operation; #46 reproducible source/persistence evidence. |

## Canonical source

`contracts/supported-backend.json` records the exact committed source of the
canonical API 2.4.0 artifact: backend
`769518dc50e89004db1e1718417e8daad378618e`, SHA-256
`2b7b38490dc42ad967cfff7e32dd56db41d30842a7d39845b9beecb7f7d4e254`.
Deployment requires migration `Providentia\Migrations\Version20261026000100`.
The source pin establishes artifact provenance; the backend compatibility matrix
records the runtime/frontend pairing separately. It is not a claim that a user's
installed backend has that revision or migration.

## Validation and release boundary

The complete local Flutter suite passed 1,429 tests. Handwritten production
coverage was 81.46% (minimum 80%). Static analysis passed with fatal infos and
warnings enabled. Canonical materialization, generated-client verification,
source architecture and the 36 Node tests passed. Drift generation completed
without changing the checked-in generated database source. Focused calendar
metadata suites passed at UTC+02 and UTC−08; recovery and receipt correction
suites use real saved SQLite databases and production HTTP adapters.

CI records the exact checked-out Client revision, canonical source declaration
and contract digest in `build/compliance/client-compatibility.json`. Production
composition tests prove generic AI 403/404 failures preserve the original home,
records and pending commands; explicit typed membership denial still purges and
routes once. A response-loss correction test confirms operation-status recovery
without duplicating stock.

The canonical setup script was attempted. This managed host initially prevented
APT privilege changes and its native package cache remains inaccessible; a local
Linux build reached CMake but could not resolve GStreamer development modules.
The required cross-platform build and clean-package gates remain enabled in CI.

Installed/native recovery of a user's database, two-device live convergence,
backend migration state and deployed-browser acceptance require the actual
installed revisions and a synthetic acceptance environment. They were not
established by these source tests. The existing protected browser-acceptance
workflow remains the deployment harness. Do not clear storage, create another
home or re-enter purchases as a generic recovery step; already deleted local-only
operations cannot be reconstructed by a server export. Client #46 stays open
until the installed acceptance evidence exists.

This PR does not close separately scoped Client UI work for count assessment,
independent shopping relinking or the full purchase-date correction interface.
Their underlying contract fields and application-owned commands are preserved
here; existing linked feature issues retain their own acceptance requirements.
