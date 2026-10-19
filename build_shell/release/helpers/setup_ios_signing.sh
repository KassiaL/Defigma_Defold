#!/usr/bin/env bash

# Runs on the Mac, from the script helpers/mac.sh (mac_signing_script) sends: puts the certificate into a
# throwaway keychain in $IOS_SIGNING_DIR and the provisioning profile next to it
# ($IOS_SIGNING_DIR/profile.mobileprovision), which is all bob needs for --identity and
# --mobileprovisioning. The caller deletes the keychain when the build ends.
#
# The keychain is the only thing that validates the certificate here: a p12 exported from a macOS
# keychain is encrypted with RC2-40-CBC, which OpenSSL 3 refuses to touch without its legacy
# provider, so openssl disagreeing with security says nothing about the certificate.

set -euo pipefail

keychain_path="$IOS_SIGNING_DIR/signing.keychain-db"
keychain_password=$(openssl rand -base64 24)
certificate_path="$IOS_SIGNING_DIR/certificate.p12"
mobileprovision_path="$IOS_SIGNING_DIR/profile.mobileprovision"

printf '%s' "$IOS_CERTIFICATE_BASE64" | base64 --decode >"$certificate_path"
printf '%s' "$IOS_MOBILEPROVISION_BASE64" | base64 --decode >"$mobileprovision_path"
security cms -D -i "$mobileprovision_path" >/dev/null

security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
if ! security import "$certificate_path" -k "$keychain_path" -P "$IOS_CERTIFICATE_PASSWORD" -f pkcs12 -A; then
	echo "error: the certificate is not a p12, or IOS_CERTIFICATE_PASSWORD is not its export password" >&2
	exit 1
fi
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path" >/dev/null
security list-keychains -d user -s "$keychain_path" $(security list-keychains -d user | tr -d '"')
rm -f "$certificate_path"

identities=$(security find-identity -v -p codesigning "$keychain_path")
printf '%s\n' "$identities"
if ! printf '%s' "$identities" | grep -qF "$IOS_SIGNING_IDENTITY"; then
	echo "error: the certificate is not '$IOS_SIGNING_IDENTITY'; bob signs with the name IOS_SIGNING_IDENTITY carries" >&2
	exit 1
fi
