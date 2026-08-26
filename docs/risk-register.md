# Flutter risk register

| ID | Risk | Current control | Next gate |
|---|---|---|---|
| F-01 | Generated client drifts from backend contract | Raw SHA-256 lock, deterministic generator, CI `--check` | Compare against tagged backend artifact |
| F-02 | Widgets bypass repositories and access HTTP/SQLite | Node and Dart architecture tests | Extend rules when presentation layers arrive |
| F-03 | Platform support is overclaimed | Evidence-separated platform matrix | Device/browser/release certification |
| F-04 | Transitive dependencies move unexpectedly | Exact direct versions and committed lock enforcement | Automated update review and vulnerability scan |
| F-05 | Native identifiers become difficult to change after store publication | One consistent Providentia identifier in all runners | Owner confirmation before signed store submission |
| F-06 | Visual implementation drifts from the approved Fresh Market direction | Pinned tokens, adaptive widget tests, guarded phone golden generation | Human visual review and device screenshots |
| F-07 | Credentials leak into Flutter persistence or release configuration | Tokens never enter Drift; dev bearer is rejected outside loopback development; browser cookies are credentialed | Production secure-store/session flow and token threat tests |
| F-08 | CI compile is mistaken for runtime compatibility | Documentation labels every compile-only proof | Physical device, VM, and browser matrix |
| F-09 | A public repository is mistaken as permission to use or redistribute Providentia | Root proprietary `LICENSE`, prominent README notice, and release metadata declaring `LicenseRef-Proprietary` | Include the proprietary notice in every distributed artifact and complete legal review before Phase 9 distribution |
| F-10 | Generated Drift, schema, worker, or golden outputs are silently stale | Exact-scope generated-artifact bootstrap and `git status` CI gates include untracked files | Review generated bot commit before merge |
| F-11 | Browser persistence falls back or is evicted | Pinned compatible WASM/worker, OPFS headers documented, IndexedDB fallback | Reload/private-mode/browser integration matrix |
| F-12 | Household records in the local Drift database are readable if an unlocked device profile or application storage is compromised | OS sandbox/device storage protection, session-loss boundary, and revoked-home purge; no claim of application-level database encryption | Before release, select and test an encrypted database/key lifecycle and migration strategy, or record explicit owner risk acceptance |
| F-13 | A composed catalog route is mistaken for accepted end-to-end evidence | Permission-gated, separately confirmed identity/image/price submissions use privacy allowlists; image bytes are bounded, locally previewed, and zeroized; staff moderation is excluded from this homeowner runtime; permission/session loss clears protected state | Live backend/Admin/client catalog acceptance and evidence for every enabled contribution category |
