#!/usr/bin/env bash

# Builds the iOS store package of one commit on the home Mac over ssh (helpers/mac.sh) and, with
# --upload, sends it to App Store Connect. Called by release_all_platforms.sh, it checks no branch itself.
# With release_liveupdate=yes (release.conf) the Mac also gets res/ios/liveupdate of this checkout, the
# archives the release packed, so the package ships them as bundle resources.
#
# usage: build_on_mac.sh <commit> [--upload]

build_on_mac_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -euo pipefail
. "$build_on_mac_dir/../../helpers/build_helpers.sh"
. "$build_on_mac_dir/../../helpers/mac.sh"

commit=$(git -C "$directory_defold_project" rev-parse "${1:?usage: build_on_mac.sh <commit> [--upload]}")
upload="${2:-}"

mac_build_script() {
	mac_signing_script "$ios_distribution_certificate" "$ios_distribution_certificate_password" \
		"$ios_distribution_identity" "$ios_app_store_profile" IOS_APP_STORE
	echo 'ipa_path=$(build_shell/release/helpers/build_ios_release.sh | tee /dev/stderr | sed -n "s/^IPA=//p")'
	if [ "$upload" = "--upload" ]; then
		cat <<SCRIPT
export APPSTORE_API_KEY_ID='$(python3 -c "import json; print(json.load(open('$store_api_dir/appstore/other.json'))['key_id'])")'
export APPSTORE_API_ISSUER_ID='$(python3 -c "import json; print(json.load(open('$store_api_dir/appstore/other.json'))['issuer_id'])")'
export APPSTORE_API_PRIVATE_KEY='$(cat "$store_api_dir/appstore/appstore.p8")'
build_shell/release/helpers/appstore_upload.sh "\$ipa_path"
SCRIPT
	fi
}

mac_send_commit "$commit" release-build
if [ "$release_liveupdate" = yes ]; then
	mac_send_ios_liveupdate
fi
mac_build_script | ssh "$mac" 'bash -s'
