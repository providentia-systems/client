#!/usr/bin/env bash
set -euo pipefail

if (( $# != 3 )); then
  echo 'Usage: sign_android.sh SOURCE_AAB SOURCE_APK OUTPUT_DIRECTORY' >&2
  exit 64
fi

for name in ANDROID_KEYSTORE_PATH ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD ANDROID_EXPECTED_CERT_SHA256 RELEASE_VERSION; do
  if [[ -z "${!name:-}" ]]; then
    echo "Required Android signing value is missing: ${name}" >&2
    exit 78
  fi
done

source_aab=$1
source_apk=$2
output_directory=$3
[[ -f "$source_aab" && -f "$source_apk" && -f "$ANDROID_KEYSTORE_PATH" ]] || {
  echo 'Android source artifacts or keystore are missing.' >&2
  exit 66
}

expected=$(printf '%s' "$ANDROID_EXPECTED_CERT_SHA256" | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || {
  echo 'ANDROID_EXPECTED_CERT_SHA256 must be a complete SHA-256 fingerprint.' >&2
  exit 78
}

actual=$(keytool -list -v \
  -keystore "$ANDROID_KEYSTORE_PATH" \
  -storepass "$ANDROID_KEYSTORE_PASSWORD" \
  -alias "$ANDROID_KEY_ALIAS" \
  | sed -n 's/^[[:space:]]*SHA256: //p' \
  | head -n 1 \
  | tr -d ':[:space:]' \
  | tr '[:upper:]' '[:lower:]')
[[ "$actual" == "$expected" ]] || {
  echo 'Android signing certificate fingerprint does not match the protected release identity.' >&2
  exit 77
}

mkdir -p "$output_directory"
signed_aab="$output_directory/providentia-${RELEASE_VERSION}.aab"
aligned_apk="$output_directory/providentia-${RELEASE_VERSION}-aligned-unsigned.apk"
signed_apk="$output_directory/providentia-${RELEASE_VERSION}-test.apk"
cp "$source_aab" "$signed_aab"

# Flutter's checked-in build currently has development signing configured.
# Remove any existing JAR signature before applying the protected upload key.
zip -q -d "$signed_aab" 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' 'META-INF/*.SF' 2>/dev/null || true
jarsigner \
  -keystore "$ANDROID_KEYSTORE_PATH" \
  -storepass "$ANDROID_KEYSTORE_PASSWORD" \
  -keypass "$ANDROID_KEY_PASSWORD" \
  -digestalg SHA-256 \
  "$signed_aab" \
  "$ANDROID_KEY_ALIAS"
jarsigner -verify -strict "$signed_aab"

build_tools=$(find "${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)
[[ -n "$build_tools" && -x "$build_tools/zipalign" && -x "$build_tools/apksigner" ]] || {
  echo 'Android SDK zipalign/apksigner tools are unavailable.' >&2
  exit 69
}
"$build_tools/zipalign" -f 4 "$source_apk" "$aligned_apk"
"$build_tools/apksigner" sign \
  --ks "$ANDROID_KEYSTORE_PATH" \
  --ks-key-alias "$ANDROID_KEY_ALIAS" \
  --ks-pass "pass:$ANDROID_KEYSTORE_PASSWORD" \
  --key-pass "pass:$ANDROID_KEY_PASSWORD" \
  --out "$signed_apk" \
  "$aligned_apk"
rm -f "$aligned_apk"
"$build_tools/apksigner" verify --verbose --print-certs "$signed_apk"
apk_fingerprint=$("$build_tools/apksigner" verify --print-certs "$signed_apk" \
  | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' \
  | head -n 1 \
  | tr -d ':[:space:]' \
  | tr '[:upper:]' '[:lower:]')
[[ "$apk_fingerprint" == "$expected" ]] || {
  echo 'Signed APK certificate fingerprint does not match the protected release identity.' >&2
  exit 77
}
