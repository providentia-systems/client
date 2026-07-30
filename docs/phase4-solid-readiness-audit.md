# Phase 4 SOLID and clean-code readiness audit

## Decision

The Flutter client is a well-structured Phase 3–4 prototype, not spaghetti
code. Its composition root, generated transport boundary, Drift transactions,
immutable synchronization models, strict analyzer configuration, deterministic
generation, and six-platform CI matrix are strong foundations.

The pre-audit `main` branch was nevertheless **not ready to be described as a
completed Phase 4 implementation**. Several correctness and dependency defects
were outside the existing 59 tests, and the controlling implementation prompt
still requires live multi-device acceptance and operational metrics.

This hardening change makes the code foundation suitable for Phase 5 feature
work once its complete CI matrix passes and the pull request is merged. It does
not make a production-release or full Phase 4 acceptance claim.

## Evidence inspected

- `main` at `8083d0d442406960cfec4abc1181b1d25480176c`;
- merged Phase 3–4 pull request and its stated scope boundary;
- every handwritten Dart file under `lib/` and every test under `test/`;
- generated Drift and OpenAPI boundaries, but not generated code as if it were
  handwritten design evidence;
- analyzer, formatting, deterministic-generation, schema, web persistence, and
  six-platform workflow definitions;
- the Phase 0 evidence, architecture decisions, synchronization contract, and
  controlling master implementation prompt;
- Flutter CI run 33 and its coverage/dependency artifact.

The baseline run passed 59 tests. Raw coverage was 1,604 of 3,563 lines
(45.02%) because generated Drift code dominated the denominator. Excluding
`.g.dart` generated output, handwritten production coverage was 924 of 1,146
lines (80.63%). The baseline workflow uploaded coverage but did not enforce a
minimum.

## SOLID assessment

| Principle | Assessment after hardening | Evidence |
|---|---|---|
| Single responsibility | Pass with a monitored adapter-size risk | Presentation, orchestration, transport mapping, retry policy, and persistence remain separate classes. The Drift adapter is large, but its single reason to change is the local synchronization persistence model; feature consumers now receive narrower ports. |
| Open/closed | Pass for the current protocol | Generated transport details are adapted at one boundary, retry and metrics policies are injected, and exhaustive enums make unsupported protocol additions fail visibly. A protocol-version or new-result change requires an intentional adapter update rather than scattered widget changes. |
| Liskov substitution | Pass for current ports | Controller and coordinator tests use substitutes through application-owned interfaces. Implementations preserve the stated outcomes and do not strengthen input requirements beyond documented protocol invariants. |
| Interface segregation | Pass after refactor | `AppSynchronization`, `LocalMutationRepository`, and `LocalSyncStore` replace presentation dependence on the concrete coordinator and prevent feature writers from receiving cursor, recovery, and transport operations they do not use. |
| Dependency inversion | Pass after refactor | `AppController` depends on `AppSynchronization`; `SyncCoordinator` depends on local, remote, connectivity, authentication, metrics, retry, and clock abstractions. Only the composition root selects Drift and the generated API adapters. Static architecture gates enforce this direction. |

## Confirmed findings and disposition

| Severity | Finding | Disposition |
|---|---|---|
| High | Synchronization summaries counted operations from every home, so active-home presentation could expose another home’s operational status. | Summary streams are now explicitly home-scoped and covered by repository and controller tests. |
| High | Manual retry accepted an operation ID without preserving the caller’s home scope. | The retry port, coordinator, and Drift predicate now require both home and operation identity; a cross-home regression test proves isolation. |
| High | Once an operation entered `blocked_conflict`, a later remote change no longer counted it as local intent and could overwrite the local representation before resolution. | All unacknowledged states remain protected; later remote revisions update conflict evidence while preserving local intent. |
| High | Push responses could omit, duplicate, or invent operation results. Missing results could leave operations stranded while the run continued. | The generated-client adapter now requires a one-to-one operation/result set and rejects cross-home, duplicate-operation, and mixed-device batches. |
| High | A server could return `hasMore=true` without advancing its cursor, change the high-water boundary mid-run, or produce an effectively unbounded pull loop. | Cursor advancement, stable high-water boundaries, and a configurable maximum page count are enforced before a page commits. |
| Medium | Two overlapping controller refreshes could race before the observable summary entered a synchronizing state. | Refreshes are serialized independently of stream timing and tested with a controlled asynchronous gate. |
| Medium | Controller and cursor audit timestamps used ambient wall-clock time, limiting deterministic verification. | Clocks are injected at orchestration, presentation, and Drift adapter boundaries. |
| Medium | Local mutations accepted empty durable identities and invalid revision/schema numbers until a later layer failed. | The domain constructor now rejects empty identifiers, negative base revisions, and payload schema versions below one before persistence. |
| Medium | Broad `Object` catches could turn programming errors into apparently ordinary connectivity failures. | Ordinary `Exception` values remain safely classified; `Error` values are no longer silently disguised. |
| Medium | Coverage was evidence-only and could regress without failing CI. | A tested LCOV policy now excludes generated Dart and enforces an 80% handwritten-production floor. |
| Medium | Existing tests exercised one local database at a time, despite Phase 4 requiring multi-device behavior. | A deterministic two-database/one-authoritative-server test now proves convergence for independent edits and preservation of both sides of a same-entity conflict. |

## Test and quality gates

The branch must pass all of these before merge:

- source-only toolchain, contract-generation, structure, naming, and dependency
  inversion checks;
- Node unit tests for the coverage policy;
- deterministic generated OpenAPI formatting;
- Drift implementation regeneration and exported-schema comparison;
- web worker regeneration and pinned SQLite WASM checksum;
- Dart formatting and strict Flutter analysis with warnings and infos fatal;
- Flutter unit, database, synchronization, two-device, widget, accessibility,
  adaptive-layout, and golden tests with coverage;
- the 80% handwritten-production coverage floor;
- Android, iOS, Linux, macOS, web, and Windows build proofs.

Coverage is a regression floor, not a substitute for behavior tests. Generated
code remains verified by deterministic regeneration and contract tests rather
than being rewarded as handwritten coverage.

## Remaining Phase 4 acceptance blockers

These are not defects that a larger unit-test count can honestly erase:

1. two real authenticated clients against the running backend, including an
   explicit user conflict-resolution workflow;
2. lost-response and identical-retry proof against server-side operation and
   batch idempotency;
3. high-water pagination, tombstones, cursor expiry, and bootstrap replacement
   against the production MySQL and Redis profile;
4. process termination during push and pull, restart recovery, foreground
   resume, and network-transition testing on real/emulated clients;
5. revoked membership versus expired-token behavior through real sessions;
6. browser reload persistence and OPFS/IndexedDB fallback verification;
7. upgrade from an installed Drift v1 database containing pending operations;
8. a production operational-metrics adapter and sink with privacy-safe labels;
9. production authentication, secure credential storage, and active-home
   selection, replacing the loopback development bootstrap.

The generated Flutter client also still binds only 7 of the backend contract’s
28 operations. The remaining identity, session, home, membership, invitation,
ownership-transfer, and catalog operations must be generated and adapted as
their feature slices begin.

## Phase 5 recommendation

Phase 5 may begin after this pull request is green and merged, provided work is
performed as vertical slices through the new ports and does not reinterpret
that start as Phase 4 production acceptance. Start with authenticated active
home selection and read-only catalog/inventory repositories, then add atomic
local mutations and outbox operations. Every slice should include domain tests,
Drift adapter tests, controller/widget tests, cross-home isolation, and a
contract or integration proof before the next slice begins.
