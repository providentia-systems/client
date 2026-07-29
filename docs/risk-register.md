# Flutter risk register

| ID | Risk | Current control | Next gate |
|---|---|---|---|
| F-01 | Generated client drifts from backend contract | Raw SHA-256 lock, deterministic generator, CI `--check` | Compare against tagged backend artifact |
| F-02 | Widgets bypass repositories and access HTTP/SQLite | Node and Dart architecture tests | Extend rules when presentation layers arrive |
| F-03 | Platform support is overclaimed | Evidence-separated platform matrix | Device/browser/release certification |
| F-04 | Transitive dependencies move unexpectedly | Exact direct versions and committed lock enforcement | Automated update review and vulnerability scan |
| F-05 | Native identifiers become difficult to change after store publication | One consistent Providentia identifier in all runners | Owner confirmation before signed store submission |
| F-06 | Design implementation starts before token review | Tokens are pinned but not imported into widgets | Phase 3 visual approval and golden tests |
| F-07 | Secrets enter Flutter configuration | HTTPS-only public runtime config; no secret fields or SDKs | Phase 2 secure-store and token threat tests |
| F-08 | CI compile is mistaken for runtime compatibility | Documentation labels every compile-only proof | Physical device, VM, and browser matrix |
| F-09 | Distribution occurs without a licence decision | No project licence or public distribution workflow | Owner selects licensing before Phase 9 |
