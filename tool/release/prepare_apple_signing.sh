#!/usr/bin/env bash
set -euo pipefail

for name in APPLE_SIGNING_CERTIFICATE_P12_BASE64 APPLE_SIGNING_CERTIFICATE_PASSWORD APPLE_TEAM_ID; do
  [[ -n "${!name:-}" ]] || { echo "${name} is required." >&2; exit 78; }
done

keychain_path=${RUNNER_TEMP:?}/providentia-release.keychain-db
certificate_path=${RUNNER_TEMP}/providentia-release.p12
keychain_password=$(openssl rand -hex 24)
printf '%s' "$APPLE_SIGNING_CERTIFICATE_P12_BASE64" | base64 --decode > "$certificate_path"
chmod 0600 "$certificate_path"

security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$certificate_path" -k "$keychain_path" \
  -P "$APPLE_SIGNING_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/productbuild
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain_path"
security list-keychains -d user -s "$keychain_path"

if [[ -n "${IOS_PROVISIONING_PROFILE_BASE64:-}" ]]; then
  profile=${RUNNER_TEMP}/providentia.mobileprovision
  printf '%s' "$IOS_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$profile"
  security cms -D -i "$profile" > "${RUNNER_TEMP}/providentia-profile.plist"
  profile_uuid=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "${RUNNER_TEMP}/providentia-profile.plist")
  profile_team=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "${RUNNER_TEMP}/providentia-profile.plist")
  [[ "$profile_team" == "$APPLE_TEAM_ID" ]] || {
    echo 'iOS provisioning profile team does not match APPLE_TEAM_ID.' >&2
    exit 77
  }
  mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
  cp "$profile" "$HOME/Library/MobileDevice/Provisioning Profiles/${profile_uuid}.mobileprovision"
  printf 'IOS_PROFILE_UUID=%s\n' "$profile_uuid" >> "${GITHUB_ENV:?}"
fi

printf 'APPLE_RELEASE_KEYCHAIN=%s\n' "$keychain_path" >> "${GITHUB_ENV:?}"
