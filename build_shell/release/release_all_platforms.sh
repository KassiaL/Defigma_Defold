#!/usr/bin/env bash

# The whole store release from this computer: the Android bundle is built here, the iOS package on the
# home Mac over ssh (helpers/build_on_mac.sh). release.conf says which stores and whether the liveupdate
# content is published; --platforms overrides the stores for one run.
#
# usage: release_all_platforms.sh [--platforms "android ios"|android|ios] [--skip-store-upload]
#                                 [--play-track production|beta|alpha|internal] [--play-status draft|completed]

release_all_platforms_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -euo pipefail
. "$release_all_platforms_dir/../helpers/build_helpers.sh"

platforms="$release_platforms"
upload_to_stores=yes
play_track=production
play_status=draft
while [ $# -gt 0 ]; do
	case "$1" in
	--platforms) platforms=$2; shift 2 ;;
	--skip-store-upload) upload_to_stores=no; shift ;;
	--play-track) play_track=$2; shift 2 ;;
	--play-status) play_status=$2; shift 2 ;;
	*) echo "error: unknown argument $1" >&2; exit 1 ;;
	esac
done

export GOOGLE_PLAY_SERVICE_ACCOUNT_FILE="$store_api_dir/google_play.json"
APPSTORE_API_KEY_ID=$(python3 -c "import json; print(json.load(open('$store_api_dir/appstore/other.json'))['key_id'])")
APPSTORE_API_ISSUER_ID=$(python3 -c "import json; print(json.load(open('$store_api_dir/appstore/other.json'))['issuer_id'])")
APPSTORE_API_PRIVATE_KEY=$(cat "$store_api_dir/appstore/appstore.p8")
export APPSTORE_API_KEY_ID APPSTORE_API_ISSUER_ID APPSTORE_API_PRIVATE_KEY

builds() {
	[[ " $platforms " == *" $1 "* ]]
}

# Both stores refuse a version code they already hold only at the upload, a whole build too late.
check_store_versions() {
	local platform
	for platform in $platforms; do
		python3 "$release_all_platforms_dir/helpers/check_store_version.py" --platform "$platform"
	done
}

# The https remote only reads from here, so the RELEASE commit goes over ssh.
push_release_commit() {
	local remote
	remote="git@github.com:$(git remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##').git"
	GIT_SSH_COMMAND="ssh -i $HOME/.ssh/github -o IdentitiesOnly=yes" git push "$remote" "HEAD:refs/heads/$(git_current_branch)"
}

upload_android() {
	python3 "$release_all_platforms_dir/helpers/play_upload.py" --aab "$aab_path" --symbols "$symbols_zip_path" \
		--track "$play_track" --status "$play_status"
}

enter_project_root
require_git_branch "$release_branch"
require_clean_working_tree
project_release_checks
"$release_all_platforms_dir/bump_all_versions.sh"
if [ "$upload_to_stores" = yes ]; then
	check_store_versions
fi
project_before_release_commit
git add .
git commit -m 'RELEASE'
release_sha=$(git rev-parse HEAD)
push_release_commit
# With liveupdate the Android bundle is the build the archives are packed from, also for an iOS-only
# release: its first pass produces liveupdate.zip, the pack mirrors the archives into
# res/android/assets/liveupdate and res/ios/liveupdate, and the second pass ships them as bundle
# resources. The content is published before any store package exists, so a new build never asks the
# CDN for archives it does not hold. Exporting after the commit is what makes project_version the bumped one.
export_android_release
require_release_vendor
if [ "$release_liveupdate" = yes ]; then
	build_android_liveupdate_bundle --with-symbols
	package_android_symbols_zip
	"$release_all_platforms_dir/liveupdate.sh" --skip-build
elif builds android; then
	run_android_bundle --with-symbols
	package_android_symbols_zip
fi

ios_upload=""
if [ "$upload_to_stores" = yes ]; then
	ios_upload=--upload
fi
ios_pid=""
if builds ios; then
	"$release_all_platforms_dir/helpers/build_on_mac.sh" "$release_sha" $ios_upload &
	ios_pid=$!
fi
if builds android && [ "$upload_to_stores" = yes ]; then
	upload_android
fi
if [ -n "$ios_pid" ]; then
	wait "$ios_pid"
fi
send_telegram_message $'<b>Release builds ready</b>\n\nProject version: <code>'"${project_version}"$'</code>\nLiveupdate: <code>'"${release_liveupdate}"$'</code>\nPlatforms: <code>'"${platforms}"$'</code>\nUploaded to the stores: <code>'"${upload_to_stores}"$'</code>'
