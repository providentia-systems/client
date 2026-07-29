#!/usr/bin/env bash

set -euo pipefail

node tool/verify_toolchain.mjs
node tool/generate_api_client.mjs --check
node tool/verify_structure.mjs

if ! command -v flutter >/dev/null 2>&1; then
  echo 'Flutter is unavailable; Dart format, analysis, tests, and builds were not run.' >&2
  exit 69
fi

flutter_version=$(flutter --version --machine)
node -e '
  const actual = JSON.parse(process.argv[1]);
  const flutterVersion = actual.flutterVersion ?? actual.frameworkVersion;
  if (flutterVersion !== "3.44.7" || actual.dartSdkVersion !== "3.12.2") {
    throw new Error(
      `Expected Flutter 3.44.7 / Dart 3.12.2; found ` +
      `${flutterVersion} / ${actual.dartSdkVersion}.`,
    );
  }
' "$flutter_version"

flutter pub get
dart format --output=none --set-exit-if-changed lib test \
  contracts/generated/providentia_api_client/lib
flutter analyze --fatal-infos --fatal-warnings
flutter test
