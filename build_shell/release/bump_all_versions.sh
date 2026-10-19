#!/usr/bin/env bash

# Bumps android.version_code, ios.bundle_version and the last number of project.version in game.project,
# the game version of game_version_file (project.conf) when the project has one, then whatever else the
# project versions (project_bump_versions of helpers/project.sh).

bump_all_versions_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -euo pipefail
. "$bump_all_versions_dir/../helpers/build_helpers.sh"

export_android_release
require_release_build
enter_project_root
python3 "$build_shell_root_dir/helpers/game_project.py" bump
if [ -n "$game_version_file" ]; then
	python3 "$build_shell_root_dir/helpers/game_project.py" bump-game-version "$game_version_file" "$game_version_pattern"
fi
project_bump_versions
