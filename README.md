# Providentia Flutter application

This repository contains the authenticated, multi-platform Providentia client.
The application supplies real Android, iOS, Windows, macOS, Linux, and web
runners, explicit core/feature boundaries, pinned toolchains, a pinned backend
contract, deterministic generated Dart bindings, a responsive Fresh Market
workspace, Drift persistence, durable synchronization primitives,
architecture tests, and a full CI build matrix.

Phases 5–8 add household inventory, count sessions, purchase history, shopping
lists, AI review policies, catalog moderation models, explainable suggestions,
price intelligence, reporting, and evaluation. The client now pins the
backend's API `1.11.0` onboarding/session contract and generates 155 callable
operations from the reviewed bytes. Email-only login-link onboarding,
cross-device browser approval, persistent web/native sessions, current-user
bootstrap, multiple homes, recipient invitations, home governance, signed-in
devices, and platform-administrator controls are composed in the application.
Most household inventory workspaces still use an explicit local projection and
are not by themselves an end-to-end test of every backend resource. See
[docs/phases5-8-contract-release-plan.md](docs/phases5-8-contract-release-plan.md)
for the backend release sequence.

## Pinned environment

- Flutter `3.44.7`
- Dart `3.12.2`
- Flutter revision `84fc5cbb223bc12f83d65b647ff8a56caf779ffd`

Install the exact SDK with FVM/asdf or use the checksum-verifying scripts in
`tool/`. Then run:

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

```bash
flutter run -d chrome \
  --web-hostname=localhost \
  --web-port=8081 \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp \
  --dart-define=PROVIDENTIA_ENVIRONMENT=development \
  --dart-define=PROVIDENTIA_API_BASE_URL=http://localhost:8080
```

Enter an email in the client, open the delivered login link in Mailpit or the
recipient mailbox, explicitly approve the request in the browser, and return to
the originating client. With the loopback commands above, open Mailpit and the
approval link on the same workstation (or an ADB-reversed device). A genuinely
different device requires a reachable trusted HTTPS backend whose
`PUBLIC_BASE_URL` matches the emailed origin. The originating client polls and
exchanges its private PKCE proof, so a deep link is optional.
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
