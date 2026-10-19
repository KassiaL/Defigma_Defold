#!/usr/bin/env bash

# Ships the IPA to App Store Connect with the same API key the project already uses for its
# App Store metadata. The build lands in processing; attaching it to a version and submitting for
# review stays manual, exactly as it is today.

set -euo pipefail

ipa_path="$1"
private_key_path="$HOME/private_keys/AuthKey_${APPSTORE_API_KEY_ID}.p8"

mkdir -p "$(dirname "$private_key_path")"
printf '%s\n' "$APPSTORE_API_PRIVATE_KEY" >"$private_key_path"
trap 'rm -f "$private_key_path"' EXIT

xcrun altool --upload-app --type ios --file "$ipa_path" \
	--apiKey "$APPSTORE_API_KEY_ID" --apiIssuer "$APPSTORE_API_ISSUER_ID"
