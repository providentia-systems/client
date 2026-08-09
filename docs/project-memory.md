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

## Current integration note — 2026-08-09

- The client pins the reviewed OpenAPI `1.11.0` onboarding/session boundary and
  generates 155 operations. Contract, lock, manifest, and generated Dart are
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
- Home roles (`owner`, `manager`, `member`, `viewer`) and platform roles are
  separate authorization domains. A platform role grants no private home
  access.
- The visible household workspaces are mostly local-only and must not be used
  as evidence that the corresponding backend APIs have been tested end to end.
