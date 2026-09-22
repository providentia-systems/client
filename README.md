# Providentia Flutter application

> **Proprietary software.** Copyright (c) 2026 Vast Development Method Trading
> Pty Ltd. All rights reserved. No licence is granted; see [LICENSE](LICENSE).

This repository contains the authenticated, multi-platform Providentia client.
The application supplies real Android, iOS, Windows, macOS, Linux, and web
runners, explicit core/feature boundaries, pinned toolchains, a pinned backend
contract, deterministic generated Dart bindings, a responsive Fresh Market
workspace, Drift persistence, durable synchronization primitives,
architecture tests, and a full CI build matrix.

Phases 5–8 add household inventory, count sessions, purchase history, shopping
lists, AI review policies, private catalog data, explainable suggestions, price
intelligence, reporting, and evaluation. The client pins the backend's API
`2.2.0` contract. The exact operation set is pinned in the contract lock;
the default-deny homeowner generator exposes only authorized household operations. Admin,
operator, billing-operator, catalog-moderation, and platform-administrator
operations are excluded from the generated homeowner package and runtime. The
separate `providentia-systems/admin` Flutter repository owns those staff
surfaces.

Email sign-in uses an eight-digit code entered in the requesting client. The
backend delivers the code, binds its challenge to the requesting installation
and application, expires it after ten minutes, limits attempts and resends,
and consumes it once. Native sessions use protected device credentials; web
sessions use HttpOnly cookies and CSRF protection. No authentication callback
URL or browser approval step is required.

Account profiles, verified email aliases, cropped avatars, country-policy
acceptance, home profiles, invitations and individual member permissions are
composed in this client. Administrators assign one account group and one group
per home. Every screen follows the active home's backend-issued permissions;
access from a more permissive home never carries into another home. Lowered
quotas preserve existing records and prevent further additions over the limit.
See [platform access](docs/platform-access.md) for the runtime rules.

Private home categories and products remain usable without contribution
consent. Sharing is separately opt-in, field-scoped, active-home bound, and
reviewable before submission. Product identity, product image, and store-price
contributions each require current server consent, the exact household
permission, a private source item, and fresh review. Product images can be
captured by camera or selected from gallery/file input; format and dimensions
come from bounded decoded bytes, the preview remains local until two explicit
confirmations, and transient bytes are zeroized on replacement, completion, or
authorization loss. Changing consent never submits. Global publication and
contribution moderation remain concerns of the separate Admin Flutter client.
Current-contract home-report and data-governance adapters are composed from
Account & access with exact active-home permission gates, account-only privacy
actions, route-owned controller lifecycles, and a dual-navigator
session/permission revocation boundary.

Household AI is likewise production-composed from Account & access behind the
active home's exact `ai.read` permission. Receipt intake re-encodes one to eight
ordered photos or locally rasterized PDF pages. Stock counting accepts one to
eight images from the camera, gallery, or file picker on supported targets and
uses API 2.0 schema-v2 quantity ranges. Each route owns and clears transient
bytes, binds every operation to exact `ai.read`/`ai.use`/`ai.manage`
capabilities, and produces only a reviewed handoff. A server candidate is
accepted before its confirmed `photo-confirmed` count is recorded through the
ordinary inventory boundary; rejected, conflicting, or unreviewed proposals do
not mutate household stock.
Most household inventory workspaces still use an explicit local projection and
are not by themselves an end-to-end test of every backend resource. See
[docs/phases5-8-contract-release-plan.md](docs/phases5-8-contract-release-plan.md)
for the backend release sequence.

## Supported toolchain

- Local development: Flutter `>=3.44.7 <4.0.0` and Dart
  `>=3.12.2 <4.0.0`
- Reproducible CI baseline: Flutter `3.44.7`, Dart `3.12.2`, and Flutter
  revision `84fc5cbb223bc12f83d65b647ff8a56caf779ffd`

The compatibility ranges accept newer stable Flutter 3.x releases, including
`3.44.9`. A pubspec can validate an installed SDK but cannot install or update
Flutter. See [local development](docs/local-development.md) for the Ubuntu
installation, refresh, and native dependency commands. FVM/asdf and the
checksum-verifying scripts in `tool/` retain the exact baseline for
reproducible CI and release investigation.

For a guided Ubuntu desktop install, clone this repository and run the
checked-in setup command as your normal desktop user:

```bash
git clone https://github.com/providentia-systems/client.git
cd client
bash tools/setup-ubuntu-client.sh
```

The command asks for the public backend origin, validates it, installs the
reviewed native prerequisites, downloads checksum-pinned Node and Flutter
runtimes, verifies the generated API client, builds the Linux release, and
launches it. It never asks for a database, administrator, or AI-provider
credential. See the [guided Ubuntu setup](docs/local-development.md#guided-ubuntu-client-setup)
for non-interactive use, safe URL rules, firewall/CORS boundaries, upgrades,
and troubleshooting.

Fresh Linux development agents can provision and validate themselves with the
vendor-neutral bootstrap documented in
[agent development](docs/agent-development.md):

```bash
bash tools/agent-setup.sh
source .agent-env
```

Then run:

```bash
flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
node tool/generate_api_client.mjs --check
node tool/verify_structure.mjs
node --test tool/*.test.mjs
dart format --output=none --set-exit-if-changed \
  lib test contracts/generated/providentia_api_client/lib
flutter analyze --fatal-infos --fatal-warnings
flutter test --coverage
node tool/check_coverage.mjs coverage/lcov.info 80
```

Regenerate the client only after replacing the pinned backend-owned contract:

```bash
node tool/generate_api_client.mjs
node tool/generate_api_client.mjs --check
```

Generated files are never hand-edited.

`pubspec.lock`, the reviewable Drift implementation, exported schemas, web
worker, and phone golden are committed repository artifacts. Dependency or
schema changes must regenerate them through the guarded, exact-scope workflows;
the ordinary quality job fails closed when a required artifact is missing or
stale rather than accepting a local placeholder.

## Development golden path

Start the backend development stack first. It includes Mailpit and the
notification worker needed to deliver sign-in codes. Then run Chrome on the
fixed, backend-allowlisted `http://localhost:8081` origin:

For the default loopback backend, put the Flutter web origins in
`CORS_ALLOWED_ORIGINS`. The exact source and prebuilt commands are in
[local development](docs/local-development.md).

```bash
flutter run -d chrome \
  --web-hostname=localhost \
  --web-port=8081 \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp \
  --dart-define=PROVIDENTIA_ENVIRONMENT=development \
  --dart-define=PROVIDENTIA_API_BASE_URL=http://localhost:8080
```

Enter your email, request a code, read the newest **Your Providentia verification
code** email and enter its eight digits in the same client. Complete your name,
country and privacy agreement on first use, then create a home if the account
group permits it or accept a pending invitation. Reading the email on another
device does not require exposing a backend browser route.
Build-time bearer tokens and home IDs are not supported. Native refresh tokens
are kept in platform secure storage, access tokens remain in memory, and web
authentication uses credentialed HttpOnly cookies.

See [local development](docs/local-development.md) for the exact email-code
acceptance flow, Linux and Android commands, session restoration, invitation
and role checks, and current end-to-end limitations. The backend's canonical
[client/user testing runbook](https://github.com/providentia-systems/backend/blob/main/docs/deployment/client-user-testing.md)
covers the same contract from the server side. Invalid API settings render a
safe configuration screen. The defaults are already valid for a backend on
`http://localhost:8080`.

## Build commands

```bash
flutter build apk --debug
flutter build ios --release --no-codesign
flutter build windows --release
flutter build macos --release
flutter build linux --release
flutter build web --release
```

The commands above create local engineering builds and do not supply production
signing identities. Protected Phase 9–10 release workflows now implement the
signed/store-ready package formats, but a release is accepted only when its
environment-owned credentials and external device/store evidence pass. Android
local release configuration continues to use the debug key.

## Documentation

Start with [docs/index.md](docs/index.md). The permanent owner decisions are in
[docs/project-memory.md](docs/project-memory.md), the current SOLID and Phase 4
readiness decision is in
[docs/phase4-solid-readiness-audit.md](docs/phase4-solid-readiness-audit.md),
the runnable backend/client handoff is in
[docs/local-development.md](docs/local-development.md),
the Phase 5–8 backend boundary is in
[docs/phases5-8-contract-release-plan.md](docs/phases5-8-contract-release-plan.md),
and the exact support claims are in
[docs/platform-support.md](docs/platform-support.md).

## License

Copyright (c) 2026 Vast Development Method Trading Pty Ltd. All rights reserved.

This repository is proprietary software. No licence is granted to use, copy,
modify, merge, publish, distribute, sublicense, or sell the software except as
expressly authorised in writing by Vast Development Method Trading Pty Ltd.
Viewing or forking this repository on GitHub does not grant a licence. See the
[LICENSE](LICENSE) file for the complete terms.

See [Product lifecycle integration](docs/product-lifecycle-integration.md) for the coordinated API 2.1 implementation and outstanding acceptance gates.

Household product editing, global/local category selection, adjustment reasons and upgrade requirements: [Household workflows](docs/household-workflows.md).
