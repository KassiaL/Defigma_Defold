#!/usr/bin/env bash

# iOS store build on the home Mac, run there by release/helpers/build_on_mac.sh once the signing is set
# up (helpers/mac.sh). Prints IPA=<path>.

build_ios_release_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -euo pipefail
. "$build_ios_release_dir/../../helpers/build_helpers.sh"

verify_ipa_bundle_version() {
	local plist
	plist=$(mktemp)
	unzip -p "$ipa_path" 'Payload/*.app/Info.plist' >"$plist"
	local actual
	actual=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
	rm -f "$plist"
	local expected
	expected=$(game_project_value ios.bundle_version)
	if [ "$actual" != "$expected" ]; then
		echo "error: the ipa carries CFBundleVersion $actual, game.project says $expected" >&2
		exit 1
	fi
	echo "$ipa_path: CFBundleVersion $actual"
}

export_ios_release
enter_project_root
run_ios_bundle
remove_liveupdate_zip
verify_ipa_bundle_version
project_verify_ipa
echo "IPA=$ipa_path"
