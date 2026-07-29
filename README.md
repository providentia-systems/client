# Providentia Flutter application

This repository contains the authenticated, multi-platform Providentia client.
The application supplies real Android, iOS, Windows, macOS, Linux, and web
runners, explicit core/feature boundaries, pinned toolchains, a pinned backend
contract, deterministic generated Dart bindings, a responsive Fresh Market
prototype, Drift persistence, durable synchronization primitives,
architecture tests, and a full CI build matrix.

Phase 5 inventory, purchase, dashboard, and list workflow parity is
deliberately not implemented yet.

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
dart format --output=none --set-exit-if-changed \
  lib test contracts/generated/providentia_api_client/lib
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

Regenerate the client only after replacing the pinned backend-owned contract:

```bash
node tool/generate_api_client.mjs
node tool/generate_api_client.mjs --check
```

Generated files are never hand-edited.

On the first dependency-changing branch, GitHub produces `pubspec.lock` and
then the reviewable Drift implementation, exported schemas, web worker, and
phone golden through guarded, exact-scope workflows. Until those bot commits
land, those generated paths are intentionally absent and the ordinary quality
job is expected to wait/fail closed rather than accepting local placeholders.

## Development golden path

Start the backend development stack and its setup script first. Use the
authorized `homeId` and short-lived development access token printed by that
script:

```bash
flutter run -d chrome \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp \
  --dart-define=PROVIDENTIA_ENVIRONMENT=development \
  --dart-define=PROVIDENTIA_API_BASE_URL=http://localhost:8080 \
  --dart-define=PROVIDENTIA_DEV_HOME_ID=<home-uuid> \
  --dart-define=PROVIDENTIA_DEV_BEARER_TOKEN=<short-lived-dev-token>
```

The development home UUID selects the local database partition; it does not
grant access. The backend still derives membership and authorization from the
token. On web, the HTTP client also sends credentialed cookie requests so
same-origin and explicitly configured cross-origin development sessions work.

`PROVIDENTIA_DEV_BEARER_TOKEN` is accepted only when the environment is exactly
`development` and the API host is loopback. It is compiled into that
development build: never use a production token, never commit the launch
command, and revoke/discard the token after the session. Production clients
must obtain credentials through the authenticated session flow and secure
platform storage; tokens are never stored in Drift.

Launching without the development defines renders a clear configuration and
sign-in-required shell instead of crashing. Production authentication and
active-home selection remain the follow-on UI that replaces this development
bootstrap.

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
[docs/project-memory.md](docs/project-memory.md), and the exact support claims
are in [docs/platform-support.md](docs/platform-support.md).

This is a proprietary project. No distribution licence has been selected. Do
not publish or redistribute the application until the owner records that
decision.
