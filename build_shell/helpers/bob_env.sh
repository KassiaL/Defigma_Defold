# The bob variables of every build, shared by every project that has build_shell/project.conf. Sourced by
# build_helpers.sh. The export_* functions set what one kind of build needs; the values come from
# project.conf and release/release.conf.

bob_env_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
directory_defold_project=$(cd "$bob_env_dir/../.." && pwd)
. "$bob_env_dir/../project.conf"
. "$bob_env_dir/../release/release.conf"

use_build_server() {
	local debug_build_server release_build_server
	. "$bob_env_dir/build_servers.conf"
	local name="${1}_build_server"
	export build_server="${!name}"
}

# $2: the value bob uses when game.project has none
game_project_value() {
	python3 "$bob_env_dir/game_project.py" get "$@"
}

export_bob_common() {
	export directory_defold_project
	export bob_settings=""
	export build_server="auto"
	export path_to_bundle="$directory_defold_project/bundles/"
	export project_title
	project_title=$(game_project_value project.title unnamed)
	# The Android bundler strips the spaces of project.title from the package name, the iOS one
	# keeps them in the ipa.
	export dir_build_after_bob_jar
	dir_build_after_bob_jar=$(printf '%s' "$project_title" | tr -d ' ')
	export android_package
	android_package=$(game_project_value android.package com.example.todo)
	export project_version
	project_version=$(game_project_value project.version 1.0)
	export apk_path="${path_to_bundle}${dir_build_after_bob_jar}/${dir_build_after_bob_jar}.apk"
	export aab_path="${path_to_bundle}${dir_build_after_bob_jar}/${dir_build_after_bob_jar}.aab"
	export symbols_zip_path="${path_to_bundle}${dir_build_after_bob_jar}/symbols.zip"
	export ipa_path="${path_to_bundle}${project_title}.ipa"
	export report_path="${path_to_bundle}reports/report.html"
	export liveupdate_zip_path="${path_to_bundle}liveupdate.zip"
}

export_android_common() {
	export_bob_common
	export keystore_path="$keystore"
	export keystore_alias
	export keystore_password_path="$keystore_password_file"
	export keystore_alias_password_path="$key_password_file"
	export platform="armv7-android"
	export texture_compression="yes"
}

# The store build: the AAB of release_all_platforms.sh, also the build release/liveupdate.sh packs from.
export_android_release() {
	export_android_common
	use_build_server release
	export vendor="$android_release_vendor"
	export bob_settings="${android_release_settings:+$directory_defold_project/$android_release_settings}"
	export liveupdate="$release_liveupdate"
	export variant="release"
	export architectures="$android_release_architectures"
	export bundle_format="aab"
}

# The dev build: the dev liveupdate publish (liveupdate.sh) and, through export_android_phone, the phone builds.
export_android_dev() {
	export_android_common
	use_build_server debug
	export vendor="$android_dev_vendor"
	export bob_settings="${android_dev_settings:+$directory_defold_project/$android_dev_settings}"
	export liveupdate="yes"
	export variant="debug"
	export architectures="$android_dev_architectures"
	export bundle_format="apk"
}

# The phone builds keep extension-automation-bridge, which every other script-driven build drops
# (project_build_start of helpers/project.sh), so automation-bridge-python can drive them on the device.
export_android_phone() {
	export_android_dev
	export liveupdate="no"
	export KEEP_AUTOMATION_BRIDGE=1
}

export_ios_common() {
	export_bob_common
	export vendor="ios"
	export bob_settings="${ios_settings:+$directory_defold_project/$ios_settings}"
	export platform="arm64-ios"
	export texture_compression="yes"
}

export_ios_release() {
	export_ios_common
	export liveupdate="$release_liveupdate"
	export variant="release"
}

export_ios_phone() {
	export_ios_common
	export liveupdate="no"
	export variant="debug"
	export KEEP_AUTOMATION_BRIDGE=1
}
