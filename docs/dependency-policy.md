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
- `excel_plus 2.15.0`, XLSX decoding for the desktop/web catalog spreadsheet
  import. Chosen over `excel` and `spreadsheet_decoder` because it is the
  maintained decoder compatible with the `archive 4.0.9`/`xml 7.0.1` tree the
  application already locks; it adds only `csv_plus` transitively, and CSV
  parsing stays in dependency-free domain code

Current direct development dependencies:

- `flutter_lints 6.0.0`
- `build_runner 2.15.1`, the exact Flutter 3.44.7-compatible generator runner
- `drift_dev 2.34.5`

The generated client is a local path package and is not published separately.
No proprietary backend SDK, hosted identity SDK, analytics SDK, or AI provider
SDK is present. `sqlite3_flutter_libs` is deliberately absent because sqlite3
3.x uses native asset build hooks and that former package is obsolete.

CI emits a machine-readable Dart dependency inventory. A release workflow must
add full OSI licence validation, a release SBOM, vulnerability scanning, and
signed provenance before Phase 9 artifacts are distributed.

Providentia is proprietary software under `LicenseRef-Proprietary`; it is not
open source. The root [LICENSE](../LICENSE) grants no right to use, copy,
modify, merge, publish, distribute, sublicense, or sell the project except as
expressly authorised in writing by Vast Development Method Trading Pty Ltd.
Flutter-generated runner files and third-party dependencies retain their own
upstream copyright and licence terms.
