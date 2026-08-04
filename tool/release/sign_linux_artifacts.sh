#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  echo 'Usage: sign_linux_artifacts.sh ARTIFACT_DIRECTORY' >&2
  exit 64
fi
for name in LINUX_SIGNING_KEY LINUX_SIGNING_KEY_ID LINUX_SIGNING_PASSPHRASE; do
  [[ -n "${!name:-}" ]] || { echo "${name} is required." >&2; exit 78; }
done

artifacts=$1
key_file=$(mktemp)
trap 'rm -f "$key_file"' EXIT
chmod 0600 "$key_file"
printf '%s' "$LINUX_SIGNING_KEY" | base64 --decode > "$key_file"
gpg --batch --import "$key_file"
fingerprint=$(gpg --batch --with-colons --fingerprint "$LINUX_SIGNING_KEY_ID" | awk -F: '$1 == "fpr" {print $10; exit}')
[[ -n "$fingerprint" ]] || { echo 'Imported Linux signing identity was not found.' >&2; exit 77; }

while IFS= read -r -d '' artifact; do
  gpg --batch --yes --pinentry-mode loopback \
    --passphrase "$LINUX_SIGNING_PASSPHRASE" \
    --local-user "$fingerprint" \
    --armor --detach-sign "$artifact"
  gpg --batch --verify "$artifact.asc" "$artifact"
done < <(find "$artifacts" -maxdepth 1 -type f \( -name '*.AppImage' -o -name '*.deb' \) -print0)
