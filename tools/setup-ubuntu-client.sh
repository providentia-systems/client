#!/usr/bin/env bash

# Build and launch the Providentia homeowner client on Ubuntu/Debian Linux.
# Run this script as the signed-in desktop user, never with sudo.

set -Eeuo pipefail
umask 077

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly project_root
readonly tool_root="${PROVIDENTIA_CLIENT_TOOL_ROOT:-$project_root/.agent-tools}"
readonly node_root="$tool_root/node"
readonly flutter_parent="$tool_root/sdk"
readonly flutter_root="$flutter_parent/flutter"
readonly node_version='v22.14.0'
readonly flutter_version='3.44.7'
readonly flutter_revision='84fc5cbb223bc12f83d65b647ff8a56caf779ffd'

api_url="${PROVIDENTIA_API_BASE_URL:-}"
environment="${PROVIDENTIA_ENVIRONMENT:-}"
launch=true
install_packages=true

usage() {
  cat <<'EOF'
Usage: bash tools/setup-ubuntu-client.sh [OPTIONS]

Build the Providentia homeowner client for one backend origin and launch it.

Options:
  --api-url URL              Backend origin, for example https://inventory.example.com
  --environment NAME         production or development (normally inferred)
  --no-launch                Build without opening the application
  --skip-system-packages     Do not run apt-get (packages must already be installed)
  -h, --help                 Show this help

The API URL can instead be supplied as PROVIDENTIA_API_BASE_URL. The script
prompts for it on an interactive terminal when neither form is supplied.
Only HTTPS is accepted, except loopback HTTP in development mode.
EOF
}

fail() {
  printf 'setup-ubuntu-client: %s\n' "$*" >&2
  exit 64
}

while (($# > 0)); do
  case "$1" in
    --api-url)
      (($# >= 2)) || fail '--api-url requires a value.'
      api_url=$2
      shift 2
      ;;
    --environment)
      (($# >= 2)) || fail '--environment requires a value.'
      environment=$2
      shift 2
      ;;
    --no-launch)
      launch=false
      shift
      ;;
    --skip-system-packages)
      install_packages=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) fail "Unknown option: $1" ;;
  esac
done

if [[ -z "$api_url" ]]; then
  [[ -t 0 ]] || fail 'Supply --api-url or PROVIDENTIA_API_BASE_URL.'
  read -r -p 'Providentia backend origin (https://host[:port]): ' api_url
fi
api_url=${api_url%/}
[[ -n "$api_url" && "$api_url" != *[$'\r\n\t ']* ]] ||
  fail 'The backend origin cannot be empty or contain whitespace.'

validate_origin() {
  local candidate=$1
  local allow_loopback=$2
  local authority port=''
  if [[ "$candidate" =~ ^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$ ]]; then
    :
  elif [[ "$allow_loopback" == true && "$candidate" =~ ^http://(localhost|127\.0\.0\.1)(:[0-9]{1,5})?$ ]]; then
    :
  else
    return 1
  fi
  authority=${candidate#*://}
  if [[ "$authority" == *:* ]]; then
    port=${authority##*:}
    ((10#$port >= 1 && 10#$port <= 65535)) || return 1
  fi
}

loopback=false
if [[ "$api_url" =~ ^http://(localhost|127\.0\.0\.1)(:[0-9]{1,5})?$ ]]; then
  loopback=true
fi
validate_origin "$api_url" true ||
  fail 'Use an HTTPS origin without a path, query, credentials, or fragment; loopback HTTP is development-only.'

if [[ -z "$environment" ]]; then
  if [[ "$loopback" == true ]]; then
    environment=development
  else
    environment=production
  fi
fi
[[ "$environment" == development || "$environment" == production ]] ||
  fail 'The environment must be production or development.'
if [[ "$loopback" == true && "$environment" != development ]]; then
  fail 'Loopback HTTP is allowed only with the development environment.'
fi

((EUID != 0)) || fail 'Run this script as your desktop user, without sudo.'
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] ||
  fail 'This setup script supports x86-64 Linux.'
command -v apt-get >/dev/null 2>&1 ||
  fail 'Automatic setup requires Ubuntu or Debian with apt-get.'

if [[ "$install_packages" == true ]]; then
  command -v sudo >/dev/null 2>&1 ||
    fail 'Install sudo, or install the documented packages manually.'
  printf 'Installing Ubuntu desktop, secure-storage, camera, and build prerequisites...\n'
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends \
    ca-certificates clang cmake curl git \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    libegl1 libgles2 libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev libgtk-3-dev liblzma-dev \
    libsecret-1-0 libsecret-1-dev libstdc++-12-dev \
    ninja-build pkg-config unzip xz-utils zip
fi

quarantine_runtime() {
  local path=$1
  local name=$2
  local quarantine="$tool_root/quarantine"
  mkdir -p "$quarantine"
  mv -- "$path" "$quarantine/${name}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
}

if [[ ! -x "$node_root/bin/node" || "$("$node_root/bin/node" --version 2>/dev/null || true)" != "$node_version" ]]; then
  [[ ! -e "$node_root" ]] || quarantine_runtime "$node_root" node
  bash "$project_root/tools/install_node_linux.sh" "$node_root"
fi
export PATH="$node_root/bin:$PATH"

flutter_identity=''
if [[ -x "$flutter_root/bin/flutter" ]]; then
  flutter_identity="$("$flutter_root/bin/flutter" --version --machine 2>/dev/null \
    | "$node_root/bin/node" -e '
      let value = "";
      process.stdin.on("data", chunk => value += chunk);
      process.stdin.on("end", () => {
        const parsed = JSON.parse(value);
        process.stdout.write(`${parsed.flutterVersion ?? parsed.frameworkVersion ?? ""}\t${parsed.frameworkRevision ?? ""}`);
      });
    ' 2>/dev/null || true)"
fi
if [[ "$flutter_identity" != "$flutter_version"$'\t'"$flutter_revision" ]]; then
  [[ ! -e "$flutter_root" ]] || quarantine_runtime "$flutter_root" flutter
  mkdir -p "$flutter_parent"
  bash "$project_root/tool/install_flutter_linux.sh" "$flutter_parent"
  flutter_identity="$("$flutter_root/bin/flutter" --version --machine \
    | "$node_root/bin/node" -e '
      let value = "";
      process.stdin.on("data", chunk => value += chunk);
      process.stdin.on("end", () => {
        const parsed = JSON.parse(value);
        process.stdout.write(`${parsed.flutterVersion ?? parsed.frameworkVersion ?? ""}\t${parsed.frameworkRevision ?? ""}`);
      });
    ')"
  [[ "$flutter_identity" == "$flutter_version"$'\t'"$flutter_revision" ]] ||
    fail 'The installed Flutter SDK did not match the reviewed version and revision.'
fi

export PATH="$flutter_root/bin:$PATH"
export DART_SUPPRESS_ANALYTICS=true
export PUB_CACHE="${PROVIDENTIA_PUB_CACHE:-$tool_root/pub-cache}"
mkdir -p "$PUB_CACHE"

cd "$project_root"
flutter config --enable-linux-desktop --no-analytics
flutter precache --linux
flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
bash tool/materialize-openapi-contract.sh
node tool/generate_api_client.mjs --check
node tool/verify_structure.mjs

printf 'Building the %s client for %s...\n' "$environment" "$api_url"
flutter build linux --release --no-pub \
  --dart-define="PROVIDENTIA_ENVIRONMENT=$environment" \
  --dart-define="PROVIDENTIA_API_BASE_URL=$api_url"

readonly bundle="$project_root/build/linux/x64/release/bundle"
readonly executable="$bundle/Providentia"
[[ -x "$executable" ]] || fail "The expected executable was not built: $executable"

if command -v curl >/dev/null 2>&1; then
  if ! curl --fail --silent --show-error --connect-timeout 3 --max-time 8 \
    "$api_url/health/ready" >/dev/null; then
    printf 'WARNING: backend readiness failed; the offline-capable client was still built.\n' >&2
  fi
fi

printf 'Providentia client build ready: %s\n' "$executable"
if [[ "$launch" == true ]]; then
  [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] ||
    fail 'Build succeeded, but no graphical desktop session is available to launch it.'
  cd "$bundle"
  exec "$executable"
fi
