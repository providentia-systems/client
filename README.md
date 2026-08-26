# Providentia Flutter application

This repository contains the authenticated, multi-platform Providentia client.
The application supplies real Android, iOS, Windows, macOS, Linux, and web
runners, explicit core/feature boundaries, pinned toolchains, a pinned backend
contract, deterministic generated Dart bindings, a responsive Fresh Market
workspace, Drift persistence, durable synchronization primitives,
architecture tests, and a full CI build matrix.

Phases 5–8 add household inventory, count sessions, purchase history, shopping
lists, AI review policies, private catalog data, explainable suggestions, price
intelligence, reporting, and evaluation. The client pins the backend's API
`1.19.0` contract: all 172 canonical operations remain reviewable, while the
default-deny homeowner generator exposes only 140 callable operations. Admin,
operator, billing-operator, catalog-moderation, and platform-administrator
operations are excluded from the generated homeowner package and runtime. The
separate `providentia-systems/admin` Flutter repository owns those staff
surfaces.

Email-only login-link onboarding — the only human authentication, with no
password surface anywhere — app-owned cross-device approval, durable
web/native trusted-device sessions that stay signed in until explicit
sign-out or revocation, current-user bootstrap, multiple homes, recipient
invitations, home governance, and signed-in-device management are composed in
this application. Approval links open the Flutter homeowner route, keep the
fragment capability in memory only, review the requesting device, and require
an explicit approve or deny decision. The backend provides JSON proof, review,
decision, polling, and exchange endpoints; it does not provide an interactive
login page.

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
uses API 1.19 schema-v2 quantity ranges. Each route owns and clears transient
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
notification worker needed to deliver login links. Then run Chrome on the
fixed, backend-allowlisted `http://localhost:8081` origin:

For the default loopback backend, put the Flutter web origins in
`CORS_ALLOWED_ORIGINS` and configure `HOMEOWNER_APP_LINK_BASE` to the Flutter
client route. The exact source and prebuilt commands are in
[local development](docs/local-development.md).

```bash
flutter run -d chrome \
  --web-hostname=localhost \
  --web-port=8081 \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp \
  --dart-define=PROVIDENTIA_ENVIRONMENT=development \
  --dart-define=PROVIDENTIA_API_BASE_URL=http://localhost:8080 \
  --dart-define=PROVIDENTIA_HOMEOWNER_APP_LINK_BASE=http://localhost:8081/homeowner
```

Enter an email in the client, open the delivered link in the Providentia
homeowner client, explicitly approve the reviewed device, and return to the
originating client. A genuinely different device requires a reachable trusted
HTTPS API and a configured client app-link base. The originating client polls
and exchanges its private PKCE proof; the reviewing client receives no session.
Use the newest **Approve your Providentia login** message after every retry;
resending deliberately retires older links, and a capability removed from the
browser address cannot be recovered by refreshing the cleaned URL.
Build-time bearer tokens and home IDs are not supported. Native refresh tokens
are kept in platform secure storage, access tokens remain in memory, and web
authentication uses credentialed HttpOnly cookies.

See [local development](docs/local-development.md) for the exact login-link
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

Production signing and store packaging are Phase 9 concerns. Current artifacts
are non-production engineering build proofs; Android local release
configuration uses the debug key.

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

This is a proprietary project. No distribution licence has been selected. Do
not publish or redistribute the application until the owner records that
decision.
