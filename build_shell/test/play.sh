#!/usr/bin/env bash
# Builds the debug bundle of this checkout for the platform it runs on (x86_64-linux, arm64-macos,
# x86_64-win32 from Git Bash) and starts it on the desktop with sound, the way the editor's Build does:
# a build for a person to play, without the editor. Nothing of the agents' test setup applies here
# (test_instance.sh: invisible display, muted sound, test hosts). Arguments go to the engine; the engine
# log goes to the terminal.
# bob builds into build/play and bundles into bundles/play, apart from the editor and the test instances.
# build_shell/test/play_project.sh, sourced when present (not synced), may set engine_cwd (the folder the
# engine starts in, default: the bundle folder) and bundle_project() (default: plain bob bundle).
# PLAY_CLEAN=1 forces a clean build. Shared by every Defold project and synced by sync_defold_docs.py.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if [ -z "${bob:-}" ]; then
	bob="$HOME/defold_engines/$(ls -1 "$HOME/defold_engines" | grep -E '^[0-9]' | sort -V | tail -n1)/bob.jar"
	export bob
fi
bundle_dir="$root/bundles/play"
engine_cwd=""
case "$(uname -s)" in
Darwin) play_platform="$([ "$(uname -m)" = arm64 ] && echo arm64-macos || echo x86_64-macos)" ;;
MINGW* | MSYS*) play_platform=x86_64-win32 ;;
*) play_platform=x86_64-linux ;;
esac
export play_platform

bundle_project() {
	local commands=(resolve build bundle)
	if [ "${PLAY_CLEAN:-0}" = "1" ]; then
		commands=(clean resolve build bundle)
	fi
	rm -rf "$bundle_dir"
	java -jar "$bob" --root "$root" --output build/play --archive --platform "$play_platform" --variant debug \
		--bundle-output "$bundle_dir" "${commands[@]}"
}

if [ -f "$root/build_shell/test/play_project.sh" ]; then
	. "$root/build_shell/test/play_project.sh"
fi

bundled_executable() {
	case "$play_platform" in
	*-macos) find "$bundle_dir" -maxdepth 4 -type f -path '*.app/Contents/MacOS/*' | head -n1 ;;
	x86_64-win32) find "$bundle_dir" -maxdepth 3 -type f -name '*.exe' | head -n1 ;;
	*) find "$bundle_dir" -maxdepth 3 -type f -name '*.x86_64' -perm -u+x | head -n1 ;;
	esac
}

bundle_project
executable=$(bundled_executable)
if [ -z "$executable" ]; then
	echo "error: no bundled $play_platform executable under $bundle_dir" >&2
	exit 1
fi
cd "${engine_cwd:-$(dirname "$executable")}"
exec "$executable" "$@"
