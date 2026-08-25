#!/usr/bin/env bash

# Installs the repository-pinned Node.js runtime without relying on a mutable
# distribution package. The final directory is moved into place only after the
# official archive checksum and executable version both pass.

set -euo pipefail

readonly version='22.14.0'
readonly architecture='x64'
readonly archive="node-v${version}-linux-${architecture}.tar.xz"
readonly sha256='69b09dba5c8dcb05c4e4273a4340db1005abeafe3927efda2bc5b249e80437ec'
readonly base_url="https://nodejs.org/dist/v${version}"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 INSTALL_DIRECTORY" >&2
  exit 64
fi

if [[ "$(uname -m)" != 'x86_64' ]]; then
  echo 'The canonical Linux agent runtime currently supports x86_64 only.' >&2
  exit 65
fi

install_directory=$1
if [[ -e "$install_directory" ]]; then
  echo "Refusing to overwrite existing path: $install_directory" >&2
  exit 73
fi

install_parent=$(dirname -- "$install_directory")
mkdir -p "$install_parent"
download_cache="${PROVIDENTIA_DOWNLOAD_CACHE:-$install_parent/.download-cache}"
mkdir -p "$download_cache"
archive_path="$download_cache/$archive"
if ! printf '%s  %s\n' "$sha256" "$archive_path" \
  | sha256sum --check --status 2>/dev/null; then
  pending_archive=$(mktemp "$download_cache/.node-download.XXXXXX")
  trap 'rm -f -- "${pending_archive:-}"' EXIT
  curl --fail --location --retry 5 --retry-all-errors --retry-delay 2 \
    --output "$pending_archive" "$base_url/$archive"
  printf '%s  %s\n' "$sha256" "$pending_archive" \
    | sha256sum --check --status
  mv -f -- "$pending_archive" "$archive_path"
  pending_archive=''
fi

staging_directory=$(mktemp -d "$install_parent/.node-install.XXXXXX")
trap 'rm -f -- "${pending_archive:-}"; rm -rf -- "${staging_directory:-}"' EXIT
tar --no-same-owner --extract --xz --strip-components=1 \
  --file "$archive_path" --directory "$staging_directory"

actual_version="$($staging_directory/bin/node --version)"
if [[ "$actual_version" != "v$version" ]]; then
  echo "Expected Node.js v$version, found $actual_version." >&2
  exit 65
fi

mv -- "$staging_directory" "$install_directory"
staging_directory=''
echo "Installed verified Node.js $version at $install_directory"
