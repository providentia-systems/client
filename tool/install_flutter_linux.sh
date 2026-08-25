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
installer_state="${PROVIDENTIA_INSTALLER_STATE_ROOT:-$install_parent/.installer-state}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$installer_state/xdg/config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$installer_state/xdg/cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$installer_state/xdg/data}"
export ANALYZER_STATE_LOCATION_OVERRIDE="${ANALYZER_STATE_LOCATION_OVERRIDE:-$XDG_CACHE_HOME/dart-analysis}"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" \
  "$ANALYZER_STATE_LOCATION_OVERRIDE"
download_cache="${PROVIDENTIA_DOWNLOAD_CACHE:-$install_parent/.download-cache}"
mkdir -p "$download_cache"
archive_path="$download_cache/$ARCHIVE"
if ! printf '%s  %s\n' "$SHA256" "$archive_path" | sha256sum --check --status 2>/dev/null; then
  pending_archive=$(mktemp "$download_cache/.flutter-download.XXXXXX")
  trap 'rm -f -- "${pending_archive:-}"' EXIT
  curl --fail --location --retry 5 --retry-all-errors --retry-delay 2 \
    --output "$pending_archive" \
    "$BASE_URL/stable/linux/$ARCHIVE"
  printf '%s  %s\n' "$SHA256" "$pending_archive" | sha256sum --check --status
  mv -f -- "$pending_archive" "$archive_path"
  pending_archive=''
fi

staging_directory=$(mktemp -d "$install_parent/.flutter-install.XXXXXX")
trap 'rm -f -- "${pending_archive:-}"; rm -rf -- "${staging_directory:-}"' EXIT
tar --no-same-owner --extract --xz --file "$archive_path" --directory "$staging_directory"

export CI=true
export DART_SUPPRESS_ANALYTICS=true

version_json=$(
  PUB_CACHE="$staging_directory/pub-cache" \
    "$staging_directory/flutter/bin/flutter" --version --machine
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

mv -- "$staging_directory/flutter" "$install_parent/flutter"

echo "Installed verified Flutter $VERSION at $install_parent/flutter"
