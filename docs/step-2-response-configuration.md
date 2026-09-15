# Step 2 household response and configuration handoff

Companions: backend PR #23 and Admin PR #11. This batch implements CAT-01,
INV-01, AI-01 and AI-02 on the existing Step 1 branch. It does not complete the
remaining Step 1 lifecycle work or start Steps 3 and 4.

## Canonical contract and generation

JSON SHA-256: `d8263a996b1382a0b0742ba4b3ca232e1d6f291644a2659d966e95b2abb038fc`.
The backend owns this document; the archived source, generated facade, locks,
materialization script and verification pins were regenerated together.

```sh
bash tool/materialize-openapi-contract.sh
node tool/generate_api_client.mjs
flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
node tool/verify_structure.mjs
flutter analyze --no-pub --fatal-infos --fatal-warnings
flutter test
```

## CAT-01

The catalog-sharing parser continues to require actual JSON booleans and an
integer revision. The backend normalizes persisted SQL values; the client does
not add truthy/integer coercion. All three flags remain independent and off by
default. Backend tests cover all combinations, contribution consumers and
withdrawal. The live response lane saves all combinations through real HTTP,
reloads through GeneratedCatalogContributionRepository, and checks persisted
withdrawal after restarting the API process.

## INV-01

Private inventory has neither global product nor pack. A product-family record
may have a product ID and no selected pack; it is retained and visibly labeled
`Catalog pack not selected`. An explicitly resolved pack has its actual parent
product. A pack without a parent in a response remains invalid; ordinary
pack-only creation must be normalized by the backend before synchronization.

Drift projection preserves the family record's home-product ID, canonical name,
original pack wording and balance without merging it with the global pack
namespace. Reopening the database must not hide that record or choose a pack.
No local database migration, operation-ID rewrite or data reset is introduced.
The backend's bounded dry-run reconciliation repairs uniquely determined
historical pack parents and appends corrective events; unresolved cases require
review rather than guessed identities or deleted history.

## AI-01 and AI-02

GeneratedServerAiRepository reads settings, viewer-visible profiles, sanitized
shared policy and transmission plan from one backend snapshot. Missing setup,
disabled adapters, unavailable vaults or unusable policies produce a null plan
and an actionable management page, not a malformed whole-workspace response.
Receipt/stock extraction stays disabled until a safely executable plan exists.

Shared policies contain shared-profile IDs only. A member's allowed personal
same-provider override is resolved separately and must appear as the actual
saved, revisioned recipient in that member's consent plan. Another member's
private profile, endpoint and hidden policy reference remain undisclosed.
Private profiles cannot be selected into the shared policy. Selecting a
management profile cannot silently replace the plan's primary extraction
recipient. Null/unsaved recipient IDs and mismatched revisions remain rejected.

The regression file `test/integration/step_2_configuration_contract_test.dart`
was introduced before source fixes: six positive regressions failed and three
negative checks already passed. After implementation all nine passed; three
additional saved-recipient rejection cases were added. The full Flutter suite
also exercises identity, onboarding, synchronization and AI execution guards.
Actual widget render evidence is captured from
`server_ai_workspace_controller_test.dart`, not a designed mockup. The separate
backend live lane copies `tests/Acceptance/step2-live-http.dart` into an isolated
client test checkout and uses these production adapters against SQLite, MySQL
and MariaDB with a real bearer session and real server/local database reopen.
It does not replace HTTP responses with handwritten fixtures.

## Release, rollback and stopping point

Deploy the paired backend before this Client: the new loader requires the
embedded settings snapshot. Back up the database and preserve prior image/build
identifiers. Roll back an incompatible backend/client pair together. Never
clear household data or rewrite append-only correction history as a rollback.
Only remove a temporary source-file consent/AI override after confirming the
specific permanent fix in the deployed image and checking a saved-state reload.
Do not remove unrelated onboarding/Step 1 overrides based on this batch.

No merge, deployment, paid AI request, production-data reconciliation or user
server modification is performed. Step 3 must consume these identity and shared
policy contracts without inventing packs or exposing private configuration.
The existing SYNC-01/SYNC-02/SYNC-03 release blockers remain recorded on PR #19;
Step 2 passing does not certify the entire synchronization lifecycle.
