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
- Local login-link acceptance must explicitly verify the backend-hosted browser
  approval origin as well as the Flutter web origins. The default loopback
  handoff supplies `127.0.0.1:8080` and `localhost:8080` in the backend CORS
  allowlist and requires a `303` capture smoke test before client onboarding.

Domain, app-store, and trademark due diligence remains mandatory before public
launch. It does not reopen the owner-selected name.

## Current integration note — 2026-08-11

- The client pins the reviewed OpenAPI `1.12.0` boundary and generates 156
  operations. Contract, lock, manifest, and generated Dart are
  updated as one deliberate change.
- Product onboarding is email-only login-link authentication. The originating
  client owns a private poll token, state, and PKCE verifier; the emailed link
  can be approved in any browser; the originating client polls and exchanges.
  A platform return link is only a convenience, never the authoritative
  handoff, and session credentials do not appear in URLs.
- The backend creates a verified account only after approval. A new person gets
  exactly one editable `My home` and becomes its `owner`; an existing person
  restores the same account and memberships without another default home.
- Web sessions use sliding 30-day inactivity and native sessions use sliding
  60-day inactivity, subject to backend enforcement. Signed-in devices and
  revocation are visible from the account screen.
- Recipient invitations, home selection/settings/governance, and
  platform-administrator management are composed client workflows.
- Catalog sharing consent, explicit per-item product-identity contribution,
  validated icon metadata, and attribution-free platform-role moderation are
  production-composed behind independent home-permission and platform-role
  gates. Consent and item selection do not submit; the server consent plus a
  fresh per-item checkbox are required. Live backend acceptance remains open.
- Home roles (`owner`, `manager`, `member`, `viewer`) and platform roles are
  separate authorization domains. A platform role grants no private home
  access.
- The visible household workspaces are mostly local-only and must not be used
  as evidence that the corresponding backend APIs have been tested end to end.
- Local Drift storage is not application-encrypted. Encryption and key
  lifecycle remain an explicit release decision and must not be claimed as a
  completed control.
