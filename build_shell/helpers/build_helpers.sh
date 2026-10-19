#!/usr/bin/env bash

# The shell functions of every build script, shared by every project that has build_shell/project.conf.
# What differs per project goes through hooks; helpers/project.sh redefines the ones it needs, the rest
# keep the defaults below:
#   project_build_start / project_build_finish   around every bob run (vendor in $vendor); nothing
#   project_android_bob_args                     may append to the android_bob_args array; nothing
#   project_before_ios_bundle                    before an iOS bundle (on the Mac); nothing
#   project_release_checks                       before a release bumps anything; nothing
#   project_bump_versions                        after the game.project versions are bumped; nothing
#   project_before_release_commit                before the RELEASE commit; nothing
#   project_liveupdate_target                    prints the liveupdate folder of $vendor; liveupdate only
#   project_publish_liveupdate                   sends the packed content to the CDN; liveupdate only
#   project_validate_liveupdate                  refuses a release liveupdate the clients cannot take; nothing

build_helpers_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
build_shell_root_dir=$(cd "$build_helpers_dir/.." && pwd)
set -euo pipefail
: "${bob:?set bob to the bob.jar of the Defold version the project builds with}"
. "$build_helpers_dir/bob_env.sh"
. "$build_helpers_dir/build_server.sh"

project_build_start() { :; }
project_build_finish() { :; }
project_android_bob_args() { :; }
project_before_ios_bundle() { :; }
project_release_checks() { :; }
project_bump_versions() { :; }
project_before_release_commit() { :; }
project_validate_liveupdate() { :; }
no_liveupdate() {
	echo "error: this project has no liveupdate (helpers/project.sh defines no $1)" >&2
	exit 1
}
project_liveupdate_target() { no_liveupdate project_liveupdate_target; }
project_publish_liveupdate() { no_liveupdate project_publish_liveupdate; }

. "$build_helpers_dir/project.sh"
cd "$build_shell_root_dir"

enter_project_root() {
	cd "$directory_defold_project"
}

git_current_branch() {
	git -C "$directory_defold_project" rev-parse --abbrev-ref HEAD
}

require_clean_working_tree() {
	local status
	status=$(git -C "$directory_defold_project" status --porcelain -- . ':!build_shell/helpers/build_servers.conf')
	if [ -n "$status" ]; then
		echo "error: working tree is not clean; commit or stash changes before building" >&2
		printf '%s\n' "$status" >&2
		exit 1
	fi
}

require_git_branch() {
	local current
	current=$(git_current_branch)
	if [ "$current" != "$1" ]; then
		echo "error: this build must run on the '$1' branch (current: '$current')" >&2
		exit 1
	fi
}

require_release_vendor() {
	if [ "$vendor" = "$android_dev_vendor" ]; then
		echo "error: a release build must not use the $android_dev_vendor vendor" >&2
		exit 1
	fi
}

require_dev_vendor() {
	if [ "$vendor" != "$android_dev_vendor" ]; then
		echo "error: a dev build must use the $android_dev_vendor vendor (current: '$vendor')" >&2
		exit 1
	fi
}

# Everything under build_shell/release publishes to a store or to the production liveupdate folder,
# so it is pinned to a clean release branch and to a store vendor.
require_release_build() {
	require_git_branch "$release_branch"
	require_clean_working_tree
	require_release_vendor
}

# The dev liveupdate publish (liveupdate.sh) is pinned to the dev branch, but not to a clean tree: the
# point of a dev build is testing what is not committed yet. The phone builds and test_instance.sh
# publish nothing and run on any branch.
require_dev_build() {
	require_git_branch "$dev_branch"
	require_dev_vendor
}

clean_bundle_output() {
	rm -rf "${path_to_bundle}${dir_build_after_bob_jar}"
	rm -rf "$ipa_path"
	rm -rf "${path_to_bundle}reports"
	rm -rf "${path_to_bundle}build_input_data.json"
}

remove_liveupdate_zip() {
	rm -f "$liveupdate_zip_path"
}

# game.project comes back byte for byte after a finished, failed or interrupted (Ctrl-C) build: the
# EXIT trap belongs to the subshell bob runs in, so the EXIT traps of the calling scripts still run.
run_bob() (
	local build_server_args=()
	local build_server_url
	build_server_url=$(build_server_url "$build_server" "$platform")
	if [ -n "$build_server_url" ]; then
		build_server_args+=(--build-server "$build_server_url")
	fi
	local project_file_backup
	project_file_backup=$(mktemp)
	cp game.project "$project_file_backup"
	trap "set +e; project_build_finish; cp '$project_file_backup' game.project; rm -f '$project_file_backup'" EXIT
	project_build_start
	set +e
	java -jar "$bob" "$@" ${build_server_args[@]+"${build_server_args[@]}"}
	local bob_exit_code=$?
	set -e
	exit "$bob_exit_code"
)

set_android_bob_args() {
	android_bob_args=(
		--archive
		--platform "$platform"
		--bundle-output="$path_to_bundle"
		--liveupdate "$liveupdate"
		--variant "$variant"
		--texture-compression "$texture_compression"
		--build-report-html "$report_path"
		--bundle-format "$bundle_format"
		--architectures "$architectures"
	)
	if [ -n "$keystore_path" ]; then
		android_bob_args+=(--keystore "$keystore_path" --keystore-alias "$keystore_alias"
			--keystore-pass "$keystore_password_path" --key-pass "$keystore_alias_password_path")
	fi
	if [ -n "$bob_settings" ]; then
		android_bob_args+=(--settings "$bob_settings")
	fi
	project_android_bob_args
}

run_android_bundle() {
	set_android_bob_args
	clean_bundle_output
	remove_liveupdate_zip
	run_bob clean resolve build bundle "${android_bob_args[@]}" "$@"
}

# Second bundling pass: the liveupdate archives of the first pass are now in res/, so the package
# ships them as bundle resources. The build folder is reused, only the package is rebuilt.
run_android_rebundle() {
	set_android_bob_args
	clean_bundle_output
	run_bob build bundle "${android_bob_args[@]}" "$@"
}

liveupdate_bundle_resource_args() {
	local dir
	for dir in $liveupdate_bundle_resource_dirs; do
		printf -- '--bundle-resource-dir\n%s\n' "$dir"
	done
}

clear_liveupdate_bundle_resources() {
	local args
	mapfile -t args < <(liveupdate_bundle_resource_args)
	python3 "$build_helpers_dir/pack_liveupdate.py" --clear-bundle-resources "${args[@]}"
}

liveupdate_stat() {
	printf '%s\n' "$liveupdate_pack_output" | sed -n "s/^LIVEUPDATE_$1=//p" | tail -n1
}

# Packing is done once per build session: the second run would compare the pack against the
# manifest the first run already published and report zero changed archives.
pack_liveupdate() {
	if [ "${liveupdate_packed:-}" = "yes" ]; then
		return 0
	fi
	local args target
	mapfile -t args < <(liveupdate_bundle_resource_args)
	target=$(project_liveupdate_target)
	export liveupdate_pack_output
	liveupdate_pack_output=$(python3 "$build_helpers_dir/pack_liveupdate.py" --zip "$liveupdate_zip_path" \
		--target "$target" --game-version-file "$game_version_file" --game-version-pattern "$game_version_pattern" \
		"${args[@]}" | tee /dev/stderr)
	export liveupdate_packed="yes"
}

liveupdate_message() {
	printf '<b>%s</b>\n\nGame version: <code>%s</code>\nManifest: <code>%s</code>\nUpdated archives: <code>%s/%s</code>\nDownload size: <code>%s MB</code> (full: %s MB)' \
		"$1" "$(liveupdate_stat GAME_VERSION)" "$(liveupdate_stat MANIFEST_VERSION)" \
		"$(liveupdate_stat ARCHIVES_CHANGED)" "$(liveupdate_stat ARCHIVES_TOTAL)" \
		"$(liveupdate_stat CHANGED_MB)" "$(liveupdate_stat TOTAL_MB)"
}

# The standard two-pass liveupdate build: the first pass produces liveupdate.zip, the pack refills the
# bundle resource folders, the second pass ships them inside the package.
build_android_liveupdate_bundle() {
	clear_liveupdate_bundle_resources
	run_android_bundle "$@"
	pack_liveupdate
	run_android_rebundle "$@"
}

# $1: the title of the Telegram message
publish_liveupdate() {
	pack_liveupdate
	project_publish_liveupdate
	enter_project_root
	send_telegram_message "$(liveupdate_message "$1")"
}

package_android_symbols_zip() {
	local symbols_lib_dir="${path_to_bundle}${dir_build_after_bob_jar}/${dir_build_after_bob_jar}.apk.symbols/lib"
	rm -f "$symbols_zip_path"
	(cd "$symbols_lib_dir" && zip -r "$symbols_zip_path" arm64-v8a armeabi-v7a)
}

run_ios_bundle() {
	project_before_ios_bundle
	clean_bundle_output
	remove_liveupdate_zip
	run_bob clean resolve --archive --platform "$platform" build bundle \
		--bundle-output="$path_to_bundle" \
		--liveupdate "$liveupdate" \
		--variant "$variant" \
		--texture-compression "$texture_compression" \
		--build-report-html "$report_path" \
		--identity "$signing_identity" \
		--mobileprovisioning "$mobileprovision_path" \
		${bob_settings:+--settings "$bob_settings"} "$@"
}

install_android_build() {
	cd "${path_to_bundle}${dir_build_after_bob_jar}"
	adb install -r "${dir_build_after_bob_jar}.apk"
	adb shell monkey -p "${android_package}" -c android.intent.category.LAUNCHER 1
	adb logcat -s defold
}

send_telegram_message() {
	curl -sSf -m 30 -o /dev/null "https://api.telegram.org/bot$telegram_bot_token/sendMessage" \
		--data-urlencode "chat_id=$telegram_chat_id" --data-urlencode "text=$1" --data-urlencode "parse_mode=HTML"
}
