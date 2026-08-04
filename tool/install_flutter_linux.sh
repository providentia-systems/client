#!/usr/bin/env bash

set -euo pipefail

readonly VERSION='3.44.7'
readonly ARCHIVE='flutter_linux_3.44.7-stable.tar.xz'
readonly SHA256='a0edd646c159c0e816788c0e46a4f071199c1320495898f5a679599b583a05a4'
readonly BASE_URL='https://storage.googleapis.com/flutter_infra_release/releases'

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 INSTALL_PARENT" >&2
  exit 64
fi

install_parent=$1
if [[ -e "$install_parent/flutter" ]]; then
  echo "Refusing to overwrite existing path: $install_parent/flutter" >&2
  exit 73
fi

mkdir -p "$install_parent"
download_directory=$(mktemp -d)
trap 'rm -rf -- "$download_directory"' EXIT
archive_path="$download_directory/$ARCHIVE"

curl --fail --location --retry 3 --output "$archive_path" \
  "$BASE_URL/stable/linux/$ARCHIVE"
printf '%s  %s\n' "$SHA256" "$archive_path" | sha256sum --check --status
tar --no-same-owner --extract --xz --file "$archive_path" --directory "$install_parent"

version_json=$(
  PUB_CACHE="$download_directory/pub-cache" \
    "$install_parent/flutter/bin/flutter" --version --machine
)
actual_version=$(
  node -e '
    const version = JSON.parse(process.argv[1]);
    process.stdout.write(version.flutterVersion ?? version.frameworkVersion ?? "");
  ' "$version_json"
)
if [[ "$actual_version" != "$VERSION" ]]; then
  echo "Expected Flutter $VERSION, found $actual_version." >&2
  exit 65
fi

echo "Installed verified Flutter $VERSION at $install_parent/flutter"
