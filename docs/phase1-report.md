# Phase 1 Flutter foundation report

## 1. Outcome

The Providentia Flutter repository now has a production foundation for all six
first-class targets. It contains real platform source trees, enforced
architecture boundaries, exact SDK pins, authoritative cross-repository
contract pins, a deterministic generated API package, tests, documentation,
and a six-target CI build matrix.

## 2. Evidence inspected

- The controlling Providentia master implementation prompt.
- Every handover `documentation/` file.
- Historical client source and its verified Fresh Market CSS tokens.
- Backend-owned OpenAPI contract SHA-256
  `960dc1d69dad9fecbb8c3e176444d9a1faae20ec8e88ba42b23569b90a5d676e`.
- Backend-owned design-token SHA-256
  `6b8b81238eaa36d735f4aa579c8a04655878e2a1c930c806495aadfeabd98c74`.
- Flutter 3.44.7 platform templates and official SDK metadata.

The corrected Phase 0 package is preserved under `docs/phase0/`.

## 3. Decisions made

- Providentia is used throughout package names, application IDs, contracts,
  runners, documentation, and generated code.
- `com.vastdevelopmentmethod.providentia` is the permanent owner-confirmed
  native identifier.
- Flutter 3.44.7, Dart 3.12.2, and framework revision
  `84fc5cbb223bc12f83d65b647ff8a56caf779ffd` are pinned.
- No distribution licence was selected.

## 4. Changes implemented

- Core/application/feature namespace shells without Phase 2–5 workflows.
- Android, iOS, Linux, macOS, web, and Windows runners and required assets.
- HTTPS-enforcing public runtime configuration.
- Generated client package and RFC 9457 failure model.
- Architecture, widget, contract, configuration, and shell tests.
- Checksum-verifying SDK installers, generation checks, and CI workflows.
- A one-time, exact-branch workflow that commits only the initial
  `pubspec.lock`; all normal CI runs require the lock afterward.

## 5. Database and API changes

No client database or Drift schema was added; that remains Phase 3.

The Flutter client pins backend API `1.0.0-foundation.1` and generates typed
support for liveness, readiness with structured dependency checks, system
information, metrics text, and required RFC 9457 problem fields including
`requestId`.

## 6. Privacy and security impact

- Widgets and features are prevented from directly importing HTTP, generated
  transport, SQLite, `dart:io`, or `dart:html`.
- Non-loopback API configuration must use HTTPS.
- No database credentials, provider keys, analytics SDK, private media,
  production data, or historical user images are present.
- Metrics access remains a backend operational-network responsibility.

## 7. Tests and exact results

Locally passed:

```text
node tool/verify_toolchain.mjs
  Flutter 3.44.7 / Dart 3.12.2 pins verified.

node tool/generate_api_client.mjs --check
  Contract and generated client verified
  (960dc1d69dad9fecbb8c3e176444d9a1faae20ec8e88ba42b23569b90a5d676e).

node tool/verify_structure.mjs
  Repository structure and architecture boundaries verified.

bash -n tool/*.sh
node --check tool/*.mjs
  Passed.
```

Flutter and Dart are not installed in the local execution environment, and
pub.dev is unavailable there. Consequently, formatting, dependency resolution,
analysis, Flutter tests, and compiled builds were not run locally and are not
represented as passed. The dedicated bootstrap workflow successfully resolved
and committed the initial dependency lock on
`agent/phase-1-production-foundations` at
`fb9bf90dc6e5e66202a9bd3e4cbf7ecc629a68c5`; ordinary CI runs those gates from
the committed lock.

## 8. Platform results

All six runner trees and required tracked assets pass structural validation.
CI is configured to build Android, unsigned iOS, Windows, macOS, Linux, and
web independently. No runtime, signing, device, browser, Arm64, or store
certification claim is made before those jobs and later release tests pass.

## 9. Migration reconciliation

No operational data was imported in Phase 1. The baseline totals, unresolved
descriptions, aliases, and identity rules remain protected by the Phase 0
migration specification.

## 10. Known limitations

- Platform compile evidence is pending the remote CI matrix.
- Phase 1 runner icons are Flutter engineering assets, not approved public
  Providentia branding.
- Store signing, installer production, and browser/device certification remain
  future phase work.

## 11. Decisions required from the user

No new product decision blocks this foundation. Before public distribution the
owner must select a distribution licence. Existing AI, authentication, media,
proposal, locale, deployment, and commercial decisions remain required by
their owning later phases.

## 12. Recommended next phase

Proceed to Phase 2 only after the dependency-lock bootstrap and all ordinary CI
quality/platform jobs pass. Phase 2 should implement identity, homes,
memberships, catalog foundations, and cross-home authorization without starting
the Phase 3 Drift or visual implementation early.
