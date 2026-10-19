#!/usr/bin/env bash

# Publishes the production liveupdate content, built from the store vendor so the archives are the ones
# the store packages ship. With --skip-build it only publishes what the caller (release_all_platforms.sh)
# already packed, and then checks the branch but not the tree: the build it continues has
# already left the files of project_build_start rewritten.
#
# usage: liveupdate.sh [--skip-build]

release_liveupdate_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -euo pipefail
. "$release_liveupdate_dir/../helpers/build_helpers.sh"

if [ "$release_liveupdate" != yes ]; then
	echo "error: release_liveupdate is not yes in release/release.conf" >&2
	exit 1
fi
export_android_release
require_git_branch "$release_branch"
enter_project_root
if [ "${1:-}" != "--skip-build" ]; then
	require_clean_working_tree
	project_validate_liveupdate
	build_android_liveupdate_bundle
fi
publish_liveupdate "New build available"
