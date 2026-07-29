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
| F-09 | Distribution occurs without a licence decision | No project licence or public distribution workflow | Owner selects licensing before Phase 9 |
| F-10 | Generated Drift, schema, worker, or golden outputs are silently stale | Exact-scope generated-artifact bootstrap and `git status` CI gates include untracked files | Review generated bot commit before merge |
| F-11 | Browser persistence falls back or is evicted | Pinned compatible WASM/worker, OPFS headers documented, IndexedDB fallback | Reload/private-mode/browser integration matrix |
