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

Domain, app-store, and trademark due diligence remains mandatory before public
launch. It does not reopen the owner-selected name.

## Current integration note — 2026-08-08

- The client pins OpenAPI `1.7.0` (86 generated operations); backend `main`
  publishes `1.10.0`. Updating the client pin remains an explicit reviewed
  change.
- The current composed sign-in is email/password compatibility against a local
  development backend. Production password login is disabled by default while
  the client adoption of the backend's published passwordless contract and its
  deep-link flow are pending.
- Account creation, verification, invitation-based user provisioning, and
  platform-role grants are backend-owned workflows for now.
- Home roles (`owner`, `manager`, `member`, `viewer`) and platform roles are
  separate authorization domains. A platform role grants no private home
  access.
- The visible household workspaces are mostly local-only and must not be used
  as evidence that the corresponding backend APIs have been tested end to end.
