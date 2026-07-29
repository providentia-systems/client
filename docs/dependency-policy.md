# Dependency and distribution policy

Flutter, Dart, direct package versions, SDK archive hashes, and the Flutter
framework revision are pinned. Application CI resolves only the committed
`pubspec.lock` using `flutter pub get --enforce-lockfile`.

Current direct non-SDK runtime dependencies:

- `crypto 3.0.7`, deterministic synchronization batch identity
- `http 1.5.0`, used only by the generated/core networking boundary
- `drift 2.34.3`, the typed local database and migration API
- `drift_flutter 0.3.1`, the persistent native and web database opener
- `sqlite3 3.5.0`, pinned explicitly to the compatible native/WebAssembly ABI

Current direct development dependencies:

- `flutter_lints 6.0.0`
- `build_runner 2.15.2`
- `drift_dev 2.34.5`

The generated client is a local path package and is not published separately.
No proprietary backend SDK, hosted identity SDK, analytics SDK, or AI provider
SDK is present. `sqlite3_flutter_libs` is deliberately absent because sqlite3
3.x uses native asset build hooks and that former package is obsolete.

CI emits a machine-readable Dart dependency inventory. A release workflow must
add full OSI licence validation, a release SBOM, vulnerability scanning, and
signed provenance before Phase 9 artifacts are distributed.

The owner has not selected a distribution licence. This repository therefore
contains no project `LICENSE` file and makes no open-source licensing claim.
Flutter-generated runner files retain their upstream copyright headers.
