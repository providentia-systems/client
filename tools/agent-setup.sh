#!/usr/bin/env bash

# Canonical, vendor-neutral bootstrap for ephemeral Linux development agents.
# The script is intentionally idempotent and keeps downloaded SDK/cache state
# inside the checkout unless PROVIDENTIA_AGENT_ROOT selects another directory.

set -euo pipefail

readonly project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly agent_root="${PROVIDENTIA_AGENT_ROOT:-$project_root/.agent-tools}"
readonly sdk_parent="$agent_root/sdk"
readonly flutter_bin="$sdk_parent/flutter/bin/flutter"
readonly node_root="$agent_root/node"
readonly node_bin="$node_root/bin/node"
readonly pub_cache="$agent_root/pub-cache"
readonly xdg_config_home="$agent_root/xdg/config"
readonly xdg_cache_home="$agent_root/xdg/cache"
readonly xdg_data_home="$agent_root/xdg/data"
readonly analyzer_state="$xdg_cache_home/dart-analysis"
readonly environment_file="$project_root/.agent-env"
readonly flutter_version='3.44.7'
readonly flutter_revision='84fc5cbb223bc12f83d65b647ff8a56caf779ffd'
readonly node_version='22.14.0'

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
    ca-certificates clang cmake curl git gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libgtk-3-dev \
    liblzma-dev libsecret-1-0 libsecret-1-dev libstdc++-12-dev \
    ninja-build pkg-config unzip xz-utils zip
}

quarantine_tool() {
  local tool_path=$1
  local tool_name=$2
  local quarantine="$agent_root/quarantine"
  mkdir -p "$quarantine"
  local destination="$quarantine/${tool_name}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  mv -- "$tool_path" "$destination"
  echo "agent-setup: quarantined invalid $tool_name runtime at $destination." >&2
}

install_node() {
  if [[ -e "$node_root" ]]; then
    local actual=''
    if [[ -x "$node_bin" ]]; then
      actual="$($node_bin --version 2>/dev/null || true)"
    fi
    if [[ "$actual" == "v$node_version" ]]; then
      return 0
    fi
    quarantine_tool "$node_root" 'node'
  fi

  bash "$project_root/tools/install_node_linux.sh" "$node_root"
}

install_flutter() {
  if [[ -e "$sdk_parent/flutter" ]]; then
    local version_json=''
    local identity=''
    local actual_version=''
    local actual_revision=''
    if [[ -x "$flutter_bin" ]] &&
      version_json="$($flutter_bin --version --machine 2>/dev/null)" &&
      identity="$($node_bin -e '
        const value = JSON.parse(process.argv[1]);
        process.stdout.write([
          value.flutterVersion ?? value.frameworkVersion ?? "",
          value.frameworkRevision ?? "",
        ].join("\t"));
      ' "$version_json" 2>/dev/null)"; then
      IFS=$'\t' read -r actual_version actual_revision <<< "$identity"
      if [[ "$actual_version" == "$flutter_version" &&
        "$actual_revision" == "$flutter_revision" ]]; then
        return 0
      fi
    fi
    quarantine_tool "$sdk_parent/flutter" 'flutter'
    echo "agent-setup: repairing Flutter $flutter_version after executable, JSON, or revision validation failed." >&2
  fi

  mkdir -p "$sdk_parent"
  bash "$project_root/tool/install_flutter_linux.sh" "$sdk_parent"
}

write_environment() {
  mkdir -p \
    "$agent_root" "$pub_cache" "$xdg_config_home" "$xdg_cache_home" \
    "$xdg_data_home" "$analyzer_state"
  {
    printf 'export PROVIDENTIA_PROJECT_ROOT=%q\n' "$project_root"
    printf 'export PROVIDENTIA_AGENT_ROOT=%q\n' "$agent_root"
    printf 'export PUB_CACHE=%q\n' "$pub_cache"
    printf 'export XDG_CONFIG_HOME=%q\n' "$xdg_config_home"
    printf 'export XDG_CACHE_HOME=%q\n' "$xdg_cache_home"
    printf 'export XDG_DATA_HOME=%q\n' "$xdg_data_home"
    printf 'export ANALYZER_STATE_LOCATION_OVERRIDE=%q\n' "$analyzer_state"
    printf 'export DART_SUPPRESS_ANALYTICS=true\n'
    printf 'export CI=true\n'
    printf 'export PATH=%q:%q:$PATH\n' \
      "$node_root/bin" "$sdk_parent/flutter/bin"
  } > "$environment_file"
}

write_environment
export PUB_CACHE="$pub_cache"
export XDG_CONFIG_HOME="$xdg_config_home"
export XDG_CACHE_HOME="$xdg_cache_home"
export XDG_DATA_HOME="$xdg_data_home"
export ANALYZER_STATE_LOCATION_OVERRIDE="$analyzer_state"
export DART_SUPPRESS_ANALYTICS=true
export CI=true
export PATH="$node_root/bin:$sdk_parent/flutter/bin:$PATH"

install_linux_prerequisites
install_node
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
