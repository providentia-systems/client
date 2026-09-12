# Project memory

Current access authority: [Platform access](platform-access.md).
The current implementation uses numeric email codes, separate account/home/admin
groups and delegated audited operator inspection. Earlier entries below retain
historical decisions and do not define the current sign-in or access model.


## Owner decision — 2026-07-29

- `Providentia` is the official project name, product name, and base for
  packages, namespaces, contracts, deployment resources, and documentation.
- `StockHome` identifies only the historical React/TypeScript prototype and
  evidence derived from it. It must not reappear as a current product or
  package name.
- The canonical repositories are
  `providentia-systems/backend` and `providentia-systems/client`.
- The Flutter stable baseline is Flutter `3.44.7` with Dart `3.12.2`.
- The verified Ubuntu range is Ubuntu `20.04 LTS` through `24.04 LTS`.
  Ubuntu 26.04 is not part of the official Flutter support table used for this
  decision.
- Android and iOS are first-class targets alongside Windows, macOS, Linux, and
  authenticated web.
- The permanent application/distribution identifier is
  `com.vastdevelopmentmethod.providentia`.
- The project is proprietary. At this date no distribution licence had been
  selected; the 2026-08-26 licensing decision below supersedes that deferral.
- The preferred production backend database is MySQL.
- Redis is the preferred production queue/cache profile. The shared
  Redis-compatible port and Valkey verification remain architecture safeguards.

## Owner decision — 2026-08-10

- Local client development accepts Flutter `>=3.44.7 <4.0.0` and Dart
  `>=3.12.2 <4.0.0`, so stable Flutter 3.x patch and minor releases do not
  require a repository edit.
- Flutter `3.44.7` and Dart `3.12.2` remain the exact reproducible CI and
  release-investigation baseline. FVM/asdf and the verified archive installers
  continue to select that baseline.
- The project cannot install a Flutter SDK through `pubspec.yaml`. Local setup
  documentation must install or refresh Flutter separately and validate it
  before package resolution.
- Linux desktop setup must include Flutter's native build prerequisites plus
  Libsecret development and runtime packages for secure session storage.
- Local login-link acceptance must explicitly verify the configured Flutter
  homeowner app-link origin and JSON proof/review/decision APIs. The backend
  serves no interactive approval page. The default loopback handoff keeps the
  Flutter web origin in CORS and scrubs the approval fragment before review.

Domain, app-store, and trademark due diligence remains mandatory before public
launch. It does not reopen the owner-selected name.

## Current integration note — 2026-09-12

The coordinated API 2.1.0 work is described in
[Product lifecycle integration](product-lifecycle-integration.md). Numeric email
codes authenticate accounts; homes are explicitly created or joined. Homeowner
permissions and administrator group permissions are separate. Authorized system
operators can inspect private home records through dedicated audited routes,
independently of public catalog contribution consent. The client keeps household
mutations in its typed durable outbox. Runtime acceptance remains open; do not
interpret historical notes as claims that these PRs have passed production tests.

## Owner licensing decision — 2026-08-26

- The earlier licensing deferral is superseded. Providentia is proprietary
  software under `LicenseRef-Proprietary`, as stated in the root
  [LICENSE](../LICENSE) file.
- Copyright (c) 2026 Vast Development Method Trading Pty Ltd. All rights
  reserved. No licence is granted except as expressly authorised in writing.
  Viewing or forking the GitHub repository does not grant a licence.
