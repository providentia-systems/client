# Agent development environment

`tools/agent-setup.sh` is the canonical, vendor-neutral bootstrap for a fresh
Debian or Ubuntu cloud session. It installs the native Flutter/Linux build
packages, installs the repository's checksum-verified Flutter 3.44.7 SDK,
installs the checksum-verified Node.js 22.14.0 Linux x64 runtime,
uses a checkout-local Pub cache, regenerates guarded artifacts, runs every
source, analysis, test, and coverage gate, and produces a Linux release build.
It also persists project-local XDG configuration, cache, and data directories
and `CI=true` in `.agent-env`, preventing cloud metadata probes and writes to a
runner's shared user configuration. The Flutter archive is kept in an atomic,
checksum-verified download cache and extracted with ownership normalization.
Every session validates the Flutter executable's machine-readable version and
framework revision. A truncated or otherwise corrupt cached SDK is quarantined
and rebuilt from the verified archive instead of being trusted because its
launcher remains executable. Analyzer state is also kept inside the agent
cache through `ANALYZER_STATE_LOCATION_OVERRIDE`.

Run it from the repository root:

```bash
bash tools/agent-setup.sh
source .agent-env
```

The script requires root or passwordless `sudo` only for the documented
operating-system packages. Set `PROVIDENTIA_AGENT_ROOT` before invoking it to
place the SDK and Pub cache on a persistent volume. `.agent-env` and the
default `.agent-tools/` directory are generated state and are ignored by Git.
No credentials or application secrets belong in either location.

## Required outbound services

Development runners need HTTPS access to these dependency sources:

- `storage.googleapis.com` for the checksum-pinned Flutter SDK and Flutter
  engine artifacts;
- `nodejs.org` for the checksum-pinned Node.js Linux x64 archive;
- `pub.dev` and `storage.googleapis.com` for Dart and Flutter packages;
- `github.com`, `api.github.com`, and `objects.githubusercontent.com` for source
  checkout and pinned GitHub Actions;
- `services.gradle.org`, `plugins.gradle.org`, `repo.maven.apache.org`, and
  `dl.google.com` for Android dependency resolution when building the phone
  client.

Runtime development additionally needs the configured Providentia backend
origin. The supported loopback defaults are `http://127.0.0.1:8080` and
`http://localhost:8080`; browser development uses
`http://localhost:8081`. Live environments require trusted HTTPS.

## Platform scope

The canonical bootstrap supports Debian/Ubuntu x86-64 and validates the
complete Dart/Flutter codebase and the Linux
desktop release on Linux. GitHub Actions remains the executable cross-platform
matrix for Android, iOS, macOS, Windows, Linux, and web because Apple and
Windows compilers require their native operating systems. Android device
acceptance also requires an Android SDK/device or emulator; use the repository
ADB reverse command in [local development](local-development.md).

Agent work is not ready for review until the bootstrap's checks pass or a
platform-specific CI job supplies the unavailable native compiler evidence.
