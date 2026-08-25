#!/usr/bin/env bash

# Canonical, vendor-neutral bootstrap for ephemeral Linux development agents.
# The script is intentionally idempotent and keeps downloaded SDK/cache state
# inside the checkout unless PROVIDENTIA_AGENT_ROOT selects another directory.

set -euo pipefail

readonly project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly agent_root="${PROVIDENTIA_AGENT_ROOT:-$project_root/.agent-tools}"
readonly sdk_parent="$agent_root/sdk"
readonly flutter_bin="$sdk_parent/flutter/bin/flutter"
readonly pub_cache="$agent_root/pub-cache"
readonly xdg_config_home="$agent_root/xdg/config"
readonly xdg_cache_home="$agent_root/xdg/cache"
readonly xdg_data_home="$agent_root/xdg/data"
readonly environment_file="$project_root/.agent-env"

install_linux_prerequisites() {
  command -v apt-get >/dev/null 2>&1 || {
    echo 'agent-setup: automatic OS provisioning currently supports Debian/Ubuntu.' >&2
    return 0
  }

  local -a elevate=()
  if [[ "$(id -u)" -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1 || ! sudo -n true 2>/dev/null; then
      echo 'agent-setup: root or passwordless sudo is required to install Linux prerequisites.' >&2
      return 77
    fi
    elevate=(sudo -n)
  fi

  "${elevate[@]}" apt-get update
  DEBIAN_FRONTEND=noninteractive "${elevate[@]}" apt-get install -y --no-install-recommends \
    ca-certificates clang cmake curl git gstreamer1.0-plugins-good \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libgtk-3-dev \
    liblzma-dev libsecret-1-0 libsecret-1-dev libstdc++-12-dev \
    ninja-build nodejs npm pkg-config unzip xz-utils
}

install_flutter() {
  if [[ -x "$flutter_bin" ]]; then
    local version
    version="$($flutter_bin --version --machine | node -e '
      let input = "";
      process.stdin.on("data", (chunk) => { input += chunk; });
      process.stdin.on("end", () => {
        const value = JSON.parse(input);
        process.stdout.write(value.flutterVersion ?? value.frameworkVersion ?? "");
      });
    ')"
    if [[ "$version" == '3.44.7' ]]; then
      return 0
    fi
    echo "agent-setup: expected Flutter 3.44.7, found $version in $sdk_parent." >&2
    return 65
  fi

  mkdir -p "$sdk_parent"
  "$project_root/tool/install_flutter_linux.sh" "$sdk_parent"
}

write_environment() {
  mkdir -p \
    "$agent_root" "$pub_cache" "$xdg_config_home" "$xdg_cache_home" \
    "$xdg_data_home"
  {
    printf 'export PROVIDENTIA_PROJECT_ROOT=%q\n' "$project_root"
    printf 'export PROVIDENTIA_AGENT_ROOT=%q\n' "$agent_root"
    printf 'export PUB_CACHE=%q\n' "$pub_cache"
    printf 'export XDG_CONFIG_HOME=%q\n' "$xdg_config_home"
    printf 'export XDG_CACHE_HOME=%q\n' "$xdg_cache_home"
    printf 'export XDG_DATA_HOME=%q\n' "$xdg_data_home"
    printf 'export DART_SUPPRESS_ANALYTICS=true\n'
    printf 'export CI=true\n'
    printf 'export PATH=%q:$PATH\n' "$sdk_parent/flutter/bin"
  } > "$environment_file"
}

write_environment
export PUB_CACHE="$pub_cache"
export XDG_CONFIG_HOME="$xdg_config_home"
export XDG_CACHE_HOME="$xdg_cache_home"
export XDG_DATA_HOME="$xdg_data_home"
export DART_SUPPRESS_ANALYTICS=true
export CI=true
export PATH="$sdk_parent/flutter/bin:$PATH"

install_linux_prerequisites
install_flutter

flutter config --enable-linux-desktop --no-analytics
flutter precache --linux
flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs

node tool/verify_toolchain.mjs
node tool/generate_api_client.mjs --check
node tool/verify_structure.mjs
node --test tool/*.test.mjs
dart format --output=none --set-exit-if-changed \
  lib test contracts/generated/providentia_api_client/lib
flutter analyze --fatal-infos --fatal-warnings
flutter test --coverage
node tool/check_coverage.mjs coverage/lcov.info 80
flutter build linux --release

echo "agent-setup: client toolchain, tests, coverage, and Linux release build are ready."
echo "agent-setup: source $environment_file in subsequent shells."
