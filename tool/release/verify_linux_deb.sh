#!/usr/bin/env bash
set -euo pipefail

verify_linkage() {
  local native_file=$1
  local library_path=${2:-}
  local linkage
  if [[ -n "$library_path" ]]; then
    linkage=$(
      LD_LIBRARY_PATH="$library_path${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        ldd "$native_file"
    )
  else
    linkage=$(ldd "$native_file")
  fi
  if grep -q 'not found' <<< "$linkage"; then
    echo "Unresolved native dependency in $native_file:" >&2
    grep 'not found' <<< "$linkage" >&2
    exit 66
  fi
}

verify_loader_library() {
  local library=$1
  local loader_cache
  command -v ldconfig >/dev/null 2>&1 || {
    echo 'ldconfig is required for the Linux launch smoke.' >&2
    exit 69
  }
  loader_cache=$(ldconfig -p)
  if ! grep -Fq "$library (" <<< "$loader_cache"; then
    echo "Linux launch runtime is missing loader library: $library" >&2
    exit 66
  fi
}

verify_linux_deb() {
  if (( $# != 1 )); then
    echo 'Usage: verify_linux_deb.sh DEBIAN_PACKAGE' >&2
    exit 64
  fi

  local package
  package=$(realpath "$1")
[[ -f "$package" ]] || {
  echo "Debian package does not exist: $package" >&2
  exit 66
}

[[ "$(dpkg-deb --field "$package" Package)" == 'providentia' ]] || {
  echo 'Debian package name is not providentia.' >&2
  exit 65
}
[[ "$(dpkg-deb --field "$package" Architecture)" == 'amd64' ]] || {
  echo 'Debian package architecture is not amd64.' >&2
  exit 65
}

dependencies=$(dpkg-deb --field "$package" Depends)
dependencies=${dependencies// /}
for dependency in \
  libegl1 \
  libgles2 \
  libgtk-3-0 \
  libsecret-1-0 \
  libgstreamer1.0-0 \
  libgstreamer-plugins-base1.0-0 \
  gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good; do
  [[ ",$dependencies," == *",$dependency,"* ]] || {
    echo "Debian package is missing runtime dependency: $dependency" >&2
    exit 65
  }
done

extraction_root=$(mktemp -d)
trap 'rm -rf "$extraction_root"' EXIT
dpkg-deb --extract "$package" "$extraction_root"
binary="$extraction_root/opt/providentia/Providentia"
plugin_root="$extraction_root/opt/providentia/lib"
[[ -x "$binary" ]] || {
  echo 'Installed Providentia executable is missing.' >&2
  exit 66
}
[[ -f "$plugin_root/libcamera_desktop_plugin.so" ]] || {
  echo 'Installed desktop camera plugin is missing.' >&2
  exit 66
}
[[ -f "$plugin_root/libflutter_linux_gtk.so" ]] || {
  echo 'Installed Flutter Linux runtime is missing.' >&2
  exit 66
}
[[ ! -e "$plugin_root/libdartjni.so" ]] || {
  echo 'Installed Linux package contains an Android-only JNI runtime.' >&2
  exit 66
}

verify_linkage "$binary"
while IFS= read -r -d '' plugin; do
  verify_linkage "$plugin" "$plugin_root"
done < <(find "$plugin_root" -type f -name '*.so' -print0)

if [[ "${PROVIDENTIA_LINUX_LAUNCH_SMOKE:-false}" == true ]]; then
  command -v xvfb-run >/dev/null 2>&1 || {
    echo 'xvfb-run is required for the Linux launch smoke.' >&2
    exit 69
  }
  verify_loader_library 'libEGL.so.1'
  verify_loader_library 'libGLESv2.so.2'
  set +e
  timeout --signal=TERM --kill-after=5s 15s xvfb-run -a "$binary"
  launch_status=$?
  set -e
  [[ "$launch_status" -eq 124 ]] || {
    echo "Providentia exited before the 15-second launch smoke completed (status $launch_status)." >&2
    exit 70
  }
fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  verify_linux_deb "$@"
fi
