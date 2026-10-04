# October 2026 report rendering and Linux startup repairs

## Current report models

The live generated adapter loads the four API 2.2.0 household reports and supplies
`sourceReports`, `inventoryFacts`, `purchaseTotals`, `consumptionEstimates`,
`shoppingSuggestions` and `suggestionPriceComparisons`.

The page selects this representation by source metadata, not by whether any data
list is populated. Empty current reports remain current reports. Legacy report
collections are rendered only when the report has no current source metadata.
This preserves legacy fixture support without using it to mask empty API data.

Current inventory shows the available product-level factual quantity and pack
text. It does not invent location balances or a movement ledger. Purchase totals
remain separated by month, currency and supplied store metadata; different
currencies are never added together. Consumption values are explicitly estimates
and show confidence and limitations. Shopping suggestions remain suggestions,
with their status and confidence. Source timestamps and supplied quantity/currency
policies remain visible.

Malformed or cross-home responses still fail closed. Loading, forbidden access,
invalid responses and genuinely empty results are separate controller states.
Switching homes removes previously displayed household data.

`test/features/reporting/current_report_page_test.dart` exercises HTTP fixtures
through the real generated adapter, service, controller and page. It covers
populated reports, separate NAD/USD totals, populated consumption/suggestions,
empty current reports, invalid cross-home responses and clearing on home switch.
The normal Flutter formatting, analysis, test and coverage gates remain required.

## Linux prerequisites and launch acceptance

The Ubuntu setup script installs `xdg-user-dirs` and validates the presence of
`xdg-user-dir` before starting the toolchain. The Debian package declares the same
runtime dependency. AppImage users must install the host packages documented in
`packaging/linux/APPIMAGE-RUNTIME.md`.

The Debian verifier retains native linkage, camera plugin and Android-only-JNI
exclusion checks. With `PROVIDENTIA_LINUX_LAUNCH_SMOKE=true`, it also runs from a
fresh temporary HOME and XDG profile, checks the process remains alive, rejects
startup exceptions, and requires a visible `Providentia` window. The native
runner shows that window only after Flutter's first frame. This replaces the old
rule that treated reaching a process timeout as successful startup.

The headless verifier needs `xvfb` and `x11-utils` (`xwininfo`). These are test
utilities, not extra application runtime dependencies. It probes the application
for 60 quarter-second observations inside an outer timeout. The helper cleans up
only its own process and the package verifier deletes only its temporary profile.
Existing user databases, keyring credentials and storage paths are unchanged.

`tool/first_frame_smoke.test.mjs` covers visible success, an invisible live
process, a live process logging a startup exception, immediate process exit and
child cleanup. CI runs these with the existing Node source-only gates. Package
verification additionally executes the real built Linux application.

Useful commands from the repository root:

```sh
node --test tool/*.test.mjs
flutter analyze --fatal-infos --fatal-warnings
flutter test --coverage
PROVIDENTIA_LINUX_LAUNCH_SMOKE=true \
  bash tool/release/verify_linux_deb.sh \
  build/release/linux/pr/providentia_0.0.0_amd64.deb
```

The last path is the artifact produced by the existing PR Linux packaging job.
A visible first frame proves startup, not successful authentication or a complete
receipt/shopping workflow. Platform build proofs likewise do not replace physical
Android/iOS acceptance or real cross-installation household testing.

## Scope still outstanding from the architecture report

This change does not claim to repair the backend's 15 recorded response-contract
mismatches, receipt commit/readback reconciliation, offline cold-start access or
local database encryption. Strict Client decoding is not weakened to accommodate
invalid backend responses. No pending receipt should be manually recommitted or
assigned a new operation identity to work around an uncertain server outcome.
Those findings remain separate release acceptance items.
