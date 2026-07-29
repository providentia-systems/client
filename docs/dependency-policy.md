# Dependency and distribution policy

Flutter, Dart, direct package versions, SDK archive hashes, and the Flutter
framework revision are pinned. Application CI resolves only the committed
`pubspec.lock` using `flutter pub get --enforce-lockfile`.

Current direct non-SDK runtime dependency:

- `http 1.5.0`, used only by the generated/core networking boundary

Current direct development dependency:

- `flutter_lints 6.0.0`

The generated client is a local path package and is not published separately.
No proprietary backend SDK, hosted identity SDK, database driver, SQLite
implementation, analytics SDK, or AI provider SDK is present in Phase 1.

CI emits a machine-readable Dart dependency inventory. A release workflow must
add full OSI licence validation, a release SBOM, vulnerability scanning, and
signed provenance before Phase 9 artifacts are distributed.

The owner has not selected a distribution licence. This repository therefore
contains no project `LICENSE` file and makes no open-source licensing claim.
Flutter-generated runner files retain their upstream copyright headers.
