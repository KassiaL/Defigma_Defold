# The home Mac the iOS packages are built on over ssh (`ssh macbookair`, md/shared/TEST_HOSTS.md), shared
# by every project that builds for iOS. Sourced after build_helpers.sh; the project values (mac_checkout,
# ios_* certificates, identities and profiles, store_api_dir) come from project.conf. The commit goes to ~/<mac_checkout>
# on the Mac by git push, bob.jar by scp; the signing material only lives for the build, in a throwaway
# keychain (release/helpers/setup_ios_signing.sh). The Mac login keychain is locked in an ssh session.

mac=macbookair
mac_defold_version=$(basename "$(dirname "$bob")")

# $1 profile name, $2 profile type; through the App Store Connect API of store_api_dir (project.conf)
ios_profile_base64() {
	(cd "$store_api_dir" && python3 - "$1" "$2" <<'PY'
import sys
import asc
profiles = asc.get("/v1/profiles", **{"filter[name]": sys.argv[1], "filter[profileType]": sys.argv[2], "filter[profileState]": "ACTIVE"})["data"]
print(profiles[0]["attributes"]["profileContent"])
PY
	)
}

# The working tree as it is, uncommitted and untracked files included, as a commit on top of HEAD that
# no branch points at.
working_tree_commit() {
	local index tree
	index=$(mktemp)
	cp "$(git -C "$directory_defold_project" rev-parse --path-format=absolute --git-path index)" "$index"
	GIT_INDEX_FILE="$index" git -C "$directory_defold_project" add -A
	tree=$(GIT_INDEX_FILE="$index" git -C "$directory_defold_project" write-tree)
	rm -f "$index"
	git -C "$directory_defold_project" commit-tree "$tree" -p HEAD -m "build snapshot"
}

# $1 commit, $2 the branch it gets on the Mac
mac_send_commit() {
	: "${mac_checkout:?set mac_checkout in project.conf}"
	ssh "$mac" "mkdir -p $mac_checkout && git -C $mac_checkout init -q"
	git -C "$directory_defold_project" push -q --force "$mac:$mac_checkout" "$1:refs/heads/$2"
	ssh "$mac" "git -C $mac_checkout checkout -q -f --detach $1 && git -C $mac_checkout clean -fdq && rm -rf $mac_checkout/res/ios/liveupdate"
	ssh "$mac" "test -f defold_release/bob/$mac_defold_version/bob.jar" || {
		ssh "$mac" "mkdir -p defold_release/bob/$mac_defold_version"
		scp -q "$bob" "$mac:defold_release/bob/$mac_defold_version/bob.jar"
	}
}

mac_send_ios_liveupdate() {
	rsync -a --delete "$directory_defold_project/res/ios/liveupdate/" "$mac:$mac_checkout/res/ios/liveupdate/"
}

# The start of the script the Mac runs: tools on PATH, bob, the signing material in a throwaway keychain,
# then signing_identity and mobileprovision_path exported in the checkout.
# $1 certificate p12, $2 its password file, $3 identity, $4 profile name, $5 profile type
mac_signing_script() {
	cat <<SCRIPT
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
cd "\$HOME/defold_release"
if [ ! -x venv/bin/python3 ]; then
	python3 -m venv venv
	venv/bin/pip install --quiet pillow requests "pyjwt[crypto]"
fi
export PATH="\$HOME/defold_release/venv/bin:/opt/homebrew/opt/openjdk/bin:\$PATH"
export bob="\$HOME/defold_release/bob/$mac_defold_version/bob.jar"
export IOS_SIGNING_DIR=\$(mktemp -d)
trap 'security delete-keychain "\$IOS_SIGNING_DIR/signing.keychain-db" 2>/dev/null; rm -rf "\$IOS_SIGNING_DIR"' EXIT
export IOS_CERTIFICATE_BASE64='$(base64 -w0 "$1")'
export IOS_CERTIFICATE_PASSWORD='$(cat "$2")'
export IOS_SIGNING_IDENTITY='$3'
export IOS_MOBILEPROVISION_BASE64='$(ios_profile_base64 "$4" "$5")'
cd "\$HOME/$mac_checkout"
build_shell/release/helpers/setup_ios_signing.sh
export signing_identity="\$IOS_SIGNING_IDENTITY"
export mobileprovision_path="\$IOS_SIGNING_DIR/profile.mobileprovision"
SCRIPT
}

# The phone build of the working tree on the iPhone (helpers/ios_phone_build.sh on the Mac).
# $1 yes|no: the build leaves the liveupdate content out (it is on the local server) or carries everything
ios_phone_on_mac() {
	: "${ios_development_profile:?set the iOS development values of project.conf}"
	mac_send_commit "$(working_tree_commit)" phone-build
	{
		mac_signing_script "$ios_development_certificate" "$ios_development_certificate_password" \
			"$ios_development_identity" "$ios_development_profile" IOS_APP_DEVELOPMENT
		printf 'export PHONE_LIVEUPDATE=%q IOS_DEVICE_UDID=%q\n' "$1" "${IOS_DEVICE_UDID:-}"
		echo build_shell/helpers/ios_phone_build.sh
	} | ssh "$mac" 'bash -s'
}
