#!/usr/bin/env bash
set -euo pipefail

if (( $# != 3 )); then
  echo 'Usage: package_linux.sh FLUTTER_BUNDLE VERSION OUTPUT_DIRECTORY' >&2
  exit 64
fi

bundle=$(realpath "$1")
version=$2
output=$(realpath -m "$3")
formats="${PROVIDENTIA_LINUX_PACKAGE_FORMATS:-appimage,deb}"
package_appimage=false
package_deb=false
IFS=',' read -r -a requested_formats <<< "$formats"
for format in "${requested_formats[@]}"; do
  case "$format" in
    appimage) package_appimage=true ;;
    deb) package_deb=true ;;
    *)
      echo "Unsupported Linux package format: $format" >&2
      exit 64
      ;;
  esac
done
[[ "$package_appimage" == true || "$package_deb" == true ]] || {
  echo 'At least one Linux package format is required.' >&2
  exit 64
}
[[ -x "$bundle/Providentia" ]] || {
  echo 'Flutter Linux release bundle is missing its executable.' >&2
  exit 66
}
command -v desktop-file-validate >/dev/null 2>&1 || {
  echo 'desktop-file-utils is required to validate Linux launcher integration.' >&2
  exit 69
}
desktop-file-validate packaging/linux/com.vastdevelopmentmethod.providentia.desktop
if find "$bundle" -type f -name 'libdartjni.so' -print -quit | grep -q .; then
  echo 'Linux release bundle contains an Android-only JNI runtime.' >&2
  exit 66
fi
camera_plugin="$bundle/lib/libcamera_desktop_plugin.so"
[[ -f "$camera_plugin" ]] || {
  echo 'Flutter Linux release bundle is missing the desktop camera plugin.' >&2
  exit 66
}
missing_native=$(ldd "$camera_plugin" | awk '/not found/ {print $1}')
[[ -z "$missing_native" ]] || {
  echo "Desktop camera plugin has unresolved native libraries: $missing_native" >&2
  exit 66
}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || {
  echo 'Linux package version is not a semantic version.' >&2
  exit 64
}
if [[ "$package_appimage" == true ]]; then
  for name in APPIMAGETOOL_URL APPIMAGETOOL_SHA256; do
    [[ -n "${!name:-}" ]] || { echo "${name} is required." >&2; exit 78; }
  done
  [[ "$APPIMAGETOOL_URL" == https://* && "$APPIMAGETOOL_SHA256" =~ ^[0-9a-fA-F]{64}$ ]] || {
    echo 'AppImage tool must use a pinned HTTPS URL and SHA-256 digest.' >&2
    exit 78
  }
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$output"

if [[ "$package_appimage" == true ]]; then
  appdir="$work/Providentia.AppDir"
  mkdir -p "$appdir/usr/lib/providentia" "$appdir/usr/share/applications" \
    "$appdir/usr/share/icons/hicolor/512x512/apps" "$appdir/usr/share/metainfo" \
    "$appdir/usr/share/doc/providentia"
  cp -a "$bundle/." "$appdir/usr/lib/providentia/"
  cp packaging/linux/com.vastdevelopmentmethod.providentia.desktop "$appdir/usr/share/applications/"
  cp packaging/linux/com.vastdevelopmentmethod.providentia.metainfo.xml "$appdir/usr/share/metainfo/"
  cp packaging/linux/APPIMAGE-RUNTIME.md "$appdir/usr/share/doc/providentia/"
  cp web/icons/Icon-512.png "$appdir/usr/share/icons/hicolor/512x512/apps/com.vastdevelopmentmethod.providentia.png"
  ln -s usr/share/applications/com.vastdevelopmentmethod.providentia.desktop "$appdir/com.vastdevelopmentmethod.providentia.desktop"
  ln -s usr/share/icons/hicolor/512x512/apps/com.vastdevelopmentmethod.providentia.png "$appdir/com.vastdevelopmentmethod.providentia.png"
  cp packaging/linux/AppRun "$appdir/AppRun"
  chmod 0755 "$appdir/AppRun"

  appimagetool="$work/appimagetool"
  curl --fail --silent --show-error --location "$APPIMAGETOOL_URL" --output "$appimagetool"
  printf '%s  %s\n' "$(printf '%s' "$APPIMAGETOOL_SHA256" | tr '[:upper:]' '[:lower:]')" "$appimagetool" \
    | sha256sum --check --strict
  chmod 0755 "$appimagetool"
  ARCH=x86_64 "$appimagetool" --no-appstream "$appdir" "$output/Providentia-${version}-x86_64.AppImage"
fi

if [[ "$package_deb" == true ]]; then
  debian="$work/debian"
  mkdir -p "$debian/DEBIAN" "$debian/opt/providentia" "$debian/usr/bin" "$debian/usr/share/applications" "$debian/usr/share/icons/hicolor/512x512/apps" "$debian/usr/share/metainfo"
  cp -a "$bundle/." "$debian/opt/providentia/"
  cp packaging/linux/com.vastdevelopmentmethod.providentia.desktop "$debian/usr/share/applications/"
  cp packaging/linux/com.vastdevelopmentmethod.providentia.metainfo.xml "$debian/usr/share/metainfo/"
  cp web/icons/Icon-512.png "$debian/usr/share/icons/hicolor/512x512/apps/com.vastdevelopmentmethod.providentia.png"
  ln -s /opt/providentia/Providentia "$debian/usr/bin/providentia"
  installed_size=$(du -sk "$debian" | cut -f1)
  cat > "$debian/DEBIAN/control" <<EOF
Package: providentia
Version: ${version%%+*}
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: ${installed_size}
Maintainer: Vast Development Method
Depends: libegl1, libgles2, libgtk-3-0, libblkid1, liblzma5, libsecret-1-0, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0, gstreamer1.0-plugins-base, gstreamer1.0-plugins-good
Description: Providentia household stock control client
 Proprietary multi-platform client for authorized Providentia users.
EOF
  dpkg-deb --root-owner-group --build "$debian" "$output/providentia_${version%%+*}_amd64.deb"
  dpkg-deb --info "$output/providentia_${version%%+*}_amd64.deb" >/dev/null
fi
