# Project memory

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
- The project is proprietary. No distribution licence is selected yet and no
  public redistribution permission is implied.
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

## Current integration note — 2026-08-25

- The client pins the reviewed OpenAPI `1.18.0` boundary at SHA-256
  `fb7f18cc8d2e0f7aaf3ec9f1bd3039316c6f44af0023110936778a8d616a6759`.
  The canonical contract contains 177 operations; the default-deny homeowner
  facade generates 145 and excludes every admin/operator/moderation method.
- Product onboarding is email-only login-link authentication. The originating
  client owns a private poll token, state, and PKCE verifier. The emailed
  fragment-secret homeowner link opens this Flutter client, which proves,
  reviews, and approves or denies through JSON APIs. The originating client
  then polls and exchanges; session credentials never appear in URLs.
- The backend creates a verified account only after approval. A new person gets
  exactly one editable `My home` and becomes its `owner`; an existing person
  restores the same account and memberships without another default home.
- Web sessions use sliding 30-day inactivity and native sessions use sliding
  60-day inactivity, subject to backend enforcement. Signed-in devices and
  revocation are visible from the account screen.
- Recipient invitations and home selection/settings/governance are composed
  homeowner workflows. Platform administration exists only in the separate
  Admin Flutter client.
- Catalog sharing consent and explicit product-identity/store-price
  contributions are production-composed behind home permissions. Consent and
  selection do not submit; server opt-in, exact preview, and a fresh checkbox
  are required. A durable submission UUID is bound to the exact payload and
  consent revision before transport.
- Home roles (`owner`, `manager`, `member`, `viewer`) and platform roles are
  separate authorization domains. A platform role grants no private home
  access.
- Household mutations commit to Drift first and use the durable typed sync
  outbox. Local and simulated convergence tests are not a substitute for live
  backend, provider, or supported-platform acceptance evidence.
- Local Drift storage is not application-encrypted. Encryption and key
  lifecycle remain an explicit release decision and must not be claimed as a
  completed control.
