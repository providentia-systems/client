#!/usr/bin/env bash

set -euo pipefail

readonly VERSION='3.44.7'
readonly REVISION='84fc5cbb223bc12f83d65b647ff8a56caf779ffd'

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 INSTALL_PARENT" >&2
  exit 64
fi

install_parent=$1
flutter_path="$install_parent/flutter"
if [[ -e "$flutter_path" ]]; then
  echo "Refusing to overwrite existing path: $flutter_path" >&2
  exit 73
fi

mkdir -p "$install_parent"
git clone --depth 1 --branch "$VERSION" \
  https://github.com/flutter/flutter.git "$flutter_path"
actual_revision=$(git -C "$flutter_path" rev-parse HEAD)
if [[ "$actual_revision" != "$REVISION" ]]; then
  echo "Expected Flutter revision $REVISION, found $actual_revision." >&2
  exit 65
fi

"$flutter_path/bin/flutter" --version
echo "Installed Flutter $VERSION from verified Git revision $REVISION."
