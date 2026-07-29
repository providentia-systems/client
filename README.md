# Providentia Flutter application

This repository contains the authenticated, multi-platform Providentia client.
The Phase 1 foundation supplies real Android, iOS, Windows, macOS, Linux, and
web runners, explicit core/feature boundaries, pinned toolchains, a pinned
backend contract, deterministic generated Dart bindings, architecture tests,
and a full CI build matrix.

Product workflows, Drift storage, synchronization, and the approved responsive
Fresh Market design system are deliberately not implemented in Phase 1.

## Pinned environment

- Flutter `3.44.7`
- Dart `3.12.2`
- Flutter revision `84fc5cbb223bc12f83d65b647ff8a56caf779ffd`

Install the exact SDK with FVM/asdf or use the checksum-verifying scripts in
`tool/`. Then run:

```bash
flutter pub get --enforce-lockfile
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

No distribution licence has been selected. Do not publish or redistribute the
application until the owner records that decision.
