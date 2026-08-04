#!/usr/bin/env bash
set -euo pipefail

if (( $# != 3 )); then
  echo 'Usage: package_linux.sh FLUTTER_BUNDLE VERSION OUTPUT_DIRECTORY' >&2
  exit 64
fi

bundle=$(realpath "$1")
version=$2
output=$(realpath -m "$3")
[[ -x "$bundle/Providentia" ]] || {
  echo 'Flutter Linux release bundle is missing its executable.' >&2
  exit 66
}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || {
  echo 'Linux package version is not a semantic version.' >&2
  exit 64
}
for name in APPIMAGETOOL_URL APPIMAGETOOL_SHA256; do
  [[ -n "${!name:-}" ]] || { echo "${name} is required." >&2; exit 78; }
done
[[ "$APPIMAGETOOL_URL" == https://* && "$APPIMAGETOOL_SHA256" =~ ^[0-9a-fA-F]{64}$ ]] || {
  echo 'AppImage tool must use a pinned HTTPS URL and SHA-256 digest.' >&2
  exit 78
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$output"

appdir="$work/Providentia.AppDir"
mkdir -p "$appdir/usr/lib/providentia" "$appdir/usr/share/applications" \
  "$appdir/usr/share/icons/hicolor/512x512/apps" "$appdir/usr/share/metainfo"
cp -a "$bundle/." "$appdir/usr/lib/providentia/"
cp packaging/linux/com.vastdevelopmentmethod.providentia.desktop "$appdir/usr/share/applications/"
cp packaging/linux/com.vastdevelopmentmethod.providentia.metainfo.xml "$appdir/usr/share/metainfo/"
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
Depends: libgtk-3-0, libblkid1, liblzma5
Description: Providentia household stock control client
 Proprietary multi-platform client for authorized Providentia users.
EOF
dpkg-deb --root-owner-group --build "$debian" "$output/providentia_${version%%+*}_amd64.deb"
dpkg-deb --info "$output/providentia_${version%%+*}_amd64.deb" >/dev/null
