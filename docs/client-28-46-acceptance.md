# Client issues 28–46: acceptance scope and release evidence

This change set belongs to the homeowner Client. It does not modify or deploy
the backend or Admin application. Source tests, packaged builds and acceptance
of an installed Client/backend pair are separate evidence levels. Client #46
remains open until the installed checks below have recorded results.

## Scope and evidence ownership

| Client issue | Client behavior to verify | Relevant evidence |
| --- | --- | --- |
| #28 | A stock-photo resource/permission failure retains the home and queued work; only a verified membership denial authorizes revocation. | Production home-revocation composition and AI transport tests. |
| #29 | Signed stock remains readable; missing metadata and loading errors are distinguishable from empty inventory. | Inventory source/domain/controller tests and `supported_evidence_projection_test.dart`. |
| #30 | Existing-home recovery preserves saved-operation identity, ordering, payload, blocker and original account/device binding through restart. | `synchronization_recovery_test.dart`, `session_bound_sync_gateway_test.dart` and recovery UI. |
| #31 | Stock entry receives focus and private/catalog product opening quantities are queued once. | Inventory workflow and `opening_product_quantity_test.dart`. |
| #32 | Count observation time, reliability, scope and unit evidence survive saves; a count replaces stock only after authoritative eligible readback. | `count_evidence_review_test.dart`, `count_acknowledgement_test.dart`, count evidence dialog and photo acknowledgement tests. |
| #33 | Reports distinguish unknown, recorded zero, signed ledger balance, uncertain stock and pending chronology. | Report adapter/widget fixtures and household isolation tests. |
| #34 | Shopping quantities retain pack/stock-unit meaning; pack selection and product relinking are deliberate revision-checked operations. | `shopping_pack_relink_test.dart`, shopping product-entry and relink workflows. |
| #35 | Ordinary unit edits preserve units already used by quantities/history, including when offline evidence is incomplete. | Unit eligibility, pending unit-readback and metadata round-trip tests. |
| #36 | Home counters describe the records actually counted. | `overview_navigation_test.dart` and application tests. |
| #37 | Reports and account settings are reachable from the homeowner navigation. | Overview/navigation and protected-route composition tests. |
| #38 | Browser identity lifecycle and authenticated requests select homeowner cookies; reauthentication preserves saved work and cannot rebind it to another account. | Namespace transport tests, `browser_namespace_saved_work_test.dart`, browser session helper tests and deployed browser harness. |
| #39 | Frozen API archive, lock, generated homeowner bindings and handwritten adapters agree; additive evidence is preserved. | Canonical generation/materialization checks, architecture tests, `supported_contract_generation.test.mjs`, `supported_backend_capability_failure_test.dart` and production adapter fixtures. |
| #40 | Editing receipt total, store or notes preserves its calendar purchase day without a timezone shift. | Calendar metadata tests, including runs in positive and negative UTC offsets. |
| #41 | Receipt entry accepts a purchase day; historical date correction uses the supported audited command with retained identity/revisions. | Purchase calendar/date correction repository, dialog and persistence tests. |
| #42 | Unrelated receipt metadata can be corrected while retaining an archived historical store. | Receipt metadata/store fixtures and editor tests. |
| #43 | Finished receipts support omitted/resolved purchases and actionable unresolved lines without replaying applied stock; uncertain stock results remain blocked. | Finished correction, response-loss, operation-status and restart tests. The deployed backend must also support the narrow unresolved no-stock edit/remove transition. |
| #44 | Empty and cancelled receipts remain discoverable; cancellation is explicit and audited, with stock effects governed by the supported command. | Receipt history/cancellation, pending readback and persistence tests. |
| #45 | Receipt spend prefers a declared header, uses complete eligible line totals otherwise, discloses partial pricing, separates currencies and preserves discounts. | Receipt amount/spend and report fixtures. |
| #46 | Exact installed source, contract and migration evidence accompanies the native/web workflows and two-device readback. | Installed acceptance record, described below; source CI alone is insufficient. |

The table identifies where evidence belongs. It does not certify an installed
application or imply that a feature's server companion has been deployed.

## Supported contract and source provenance

The frozen canonical input is API `2.4.0`, SHA-256
`2b7b38490dc42ad967cfff7e32dd56db41d30842a7d39845b9beecb7f7d4e254`.
`contracts/supported-backend.json` records its exact backend artifact source,
`769518dc50e89004db1e1718417e8daad378618e`, and required migration
`Providentia\Migrations\Version20261026000100`. This artifact source is not a
claim that every runtime behavior was implemented at that revision. Record the
actual deployed backend build separately and exercise the required operations.

CI writes `build/compliance/client-compatibility.json`; the web build embeds
`build-provenance.json` and compiles the same identity into the running Dart
application. The browser harness compares that running identity with the served
artifact, so an old service-worker cache cannot be mistaken for the current
deployment. The web release and CI pass `--dart-define-from-file=web/build-provenance.json`
after generating the identity from a clean committed checkout. Release manifests and checksums identify native
packages. Compare the installed executable/PWA evidence, not a version label
or the current repository branch. An absent revision, contract mismatch,
unapplied migration, unknown migration or unavailable diagnostics leaves the
pair unverified.

The installed-pair validator requires exact Client/backend revision evidence,
the agreed contract hash, a matching backend lock, current migrations and the
required migration. It does not infer compatibility solely from the common
`v1` route prefix. The backend artifact source and actual runtime revision may
differ; both must remain visible in the release evidence.

## Older-server capability failures

An older server may reject a new command with an untyped HTTP 400/422. The
Client preserves it as a validation block and directs the user to check both
the saved entry and the supported API 2.4.0 command/payload capability. That
status alone does not establish which version is installed. Explicit
unsupported-operation, command, schema or protocol machine codes receive
supported-server guidance through ordinary push and response-loss status
readback. Payloads, original operation IDs, account/device provenance and queue
order remain intact; compatibility rejection does not authorize home purge or
purchase recreation.

No startup-wide version probe is introduced. The public system-info
`apiVersion` identifies the route generation (`v1`), not the full contract
version, and home synchronization diagnostics requires an authorized home.
Gating unrelated reads on that endpoint would incorrectly turn unavailable
recovery/diagnostic permission into an application-wide outage. Capability
readback, explicit command rejections and the installed-pair release gate have
distinct roles.

## Reproducible source checks

Use the canonical contributor setup from `AGENTS.md` and the pinned Flutter,
Dart and Node versions. Preserve the existing format, analysis, coverage,
architecture, platform-build and clean-package gates. Do not change their
thresholds when a host lacks native packages.

```bash
bash tools/agent-setup.sh
source .agent-env
node tool/generate_api_client.mjs --check
bash tool/materialize-openapi-contract.sh
node tool/verify_structure.mjs
node --test tool/*.test.mjs
dart format --output=none --set-exit-if-changed lib test contracts/generated/providentia_api_client/lib
flutter analyze --fatal-infos --fatal-warnings
flutter test --coverage
node tool/check_coverage.mjs coverage/lcov.info 80
```

The focused `browser_namespace_saved_work_test.dart` uses a saved SQLite file,
production identity/home transports, `IdentitySessionManager`, the production
route-security boundary and `SessionBoundSyncGateway`. A legacy-only browser
session requires fresh homeowner sign-in. Original records, outbox bytes,
operation IDs, sequence, authorization blocker and account/device provenance
survive sign-in and database reopening. A different account cannot send the
old queue. This is a synthetic transport/persistence test. It does not establish
encrypted IndexedDB behavior, real HttpOnly cookie behavior or installed
browser acceptance.

`tool/browser_security/run_probe.sh` supplies the separate Chromium/WebCrypto
and encrypted IndexedDB persistence proof in CI. Its synthetic vault results
are independent of the deployed authentication and household scenarios.

## Installed native acceptance

Use a dedicated synthetic household and two existing authorized installations.
Keep real household records, source media, credentials and raw queue payloads
out of issues and published artifacts. Retain the original installation/device
identity and its protected local-data key. Do not create another home or
re-enter purchases to simulate restoration.

1. Record the installed package checksum, release source commit, platform,
   Client contract hash, local database schema version and backend build,
   contract/migration diagnostics. The current local schema is version 3;
   verify an older preserved test database actually migrates and retains its
   rows rather than assuming a new database proves migration.
2. Close the application before any deployment-specific profile snapshot.
   Preserve the encrypted synthetic database and its authorized OS key-store
   context together using the platform's approved preservation procedure.
   A copied database alone may be unreadable elsewhere. The Client does not
   provide a general export/restore button for its encrypted local outbox.
3. Reopen the same installation offline, create one synthetic purchase and
   capture its pending state. Restart while offline. Confirm the receipt,
   quantities, calendar day and pending operation remain; no stock is sent or
   account/device identity replaced.
4. Reconnect and sign in with the original account. Use Account & access →
   Recover this home → Verify session. Inspect the server revision, contract,
   migration state and saved/blocked operation counts. If needed use Review
   blocked work, then Refresh saved records. Interrupt/restart once before
   final synchronization. Original operations must retain their identities,
   payloads and order; an already accepted operation must not execute twice.
5. On the second installation, refresh the same existing home. Verify one
   receipt/purchase and the expected stock readback. Correct its header,
   purchase day and an applied line; resolve an unresolved line and add an
   omitted purchase. Retry an interrupted correction and confirm only its new
   effect appears. Verify no-stock unresolved edit/remove against the actual
   supported backend; a preserved rejection is not a successful correction.
6. Verify archived-store metadata edits, header-only/empty/cancelled receipt
   history, declared discounts, missing prices, genuine zero and separate
   currency totals. Verify signed/uncertain inventory and pending chronology;
   an unassessed or partial count must not silently certify a physical balance.
   Complete one explicitly assessed count and inspect authoritative readback.
7. Verify an independent shopping pack/relink, unit-in-use rejection, and stock
   photo permission/resource failure. Retained input and pending work must
   survive rejection. In a separate synthetic scenario verify true membership
   revocation denies access through its intended boundary. Do not use the
   recovery scenario's only preserved profile for a destructive revocation test.
8. Record each observed result and failure with the exact installed pairing.
   Redact credentials, mailbox contents, private media and raw household data.
   Retain a protected synthetic failure profile when follow-up is needed.

The Linux release/package/launch workflow remains the native clean-host gate.
Its successful launch is build evidence; it does not replace the authenticated
scenario above or prove another native platform. Physical Android/iOS/macOS/
Windows acceptance requires its own installed artifact and platform evidence.

## Installed browser acceptance

Dispatch `.github/workflows/browser-acceptance.yml` for the deployed HTTPS PWA
with `require_auth=true`. Its protected `production-acceptance` environment
requires the synthetic API/account and TLS IMAP mailbox configuration documented
in `docs/release/phase-09-10-release-engineering.md`. Do not insert credentials
in the workflow, request text, logs or source tree.

The harness records installed Client provenance and authenticated backend
revision/contract/migrations; it checks homeowner refresh/logout, another
application's cookie isolation and preservation of legacy cookies. Chrome runs
the controlled mailbox flow; the other configured engines exercise PWA and
persistence behavior. WebKit engine results are not physical Safari acceptance.
A deliberately unauthenticated run cannot satisfy authenticated acceptance.

Use a preserved synthetic encrypted browser profile to repeat the pending
purchase, restart, sign-in transition, account/device mismatch and second-device
readback scenarios described for native acceptance. Also test old unnamespaced
and Admin cookies alongside homeowner cookies. Sign-in must preserve local
work; another account must not receive the old queue. Retain the local-data
passphrase separately and do not clear site data as a repair step. The mailbox
and cookie harness alone does not exercise these full homeowner workflows.

## Outstanding installed evidence

No deployed PWA URL, installed native package/profile or controlled synthetic
account/mailbox credentials were supplied for this work. Therefore no actual
installed household recovery, deployed browser authentication, two-device live
convergence or production migration result is claimed. Client #46 remains an
installed-acceptance gate. Source tests and local builds must be reported with
their own exact results, and never presented as recovery of the user's data.

## Managed-host limits observed during development

The full source/persistence checks run with the pinned SDK. Local native Linux
packaging cannot complete without the GStreamer development modules; host APT
cache and privilege restrictions prevented their installation. A downloaded
Chromium reached launch but this managed host denied its process-singleton Unix
socket. These host failures do not satisfy either native or browser acceptance.
The required platform/package and Chromium security gates remain enabled in CI.
