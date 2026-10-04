#!/usr/bin/env bash
# Debug x86_64-linux bundle for the automation bridge, started from this checkout inside its own
# invisible X display (build_shell/run-test-env), so it never shows up on the desktop.
# Prints ENGINE_PORT=<port>, ENGINE_LOG=<path> and ENGINE_DISPLAY=:<n>; arguments go to the engine.
# Shared by every Defold project and synced by sync_defold_docs.py. What differs per project lives
# in build_shell/linux_test_project.sh, sourced when present; see md/shared/PARALLEL_TEST_INSTANCES.md.
#
# build_shell/linux_test_project.sh may set:
#   save_root, save_name    per-instance save folder "$save_root/$save_name-<instance>" (LINUX_RESET,
#                           agent_worktree_clean.sh); leave save_name empty when there is none
#   bundle_dir, engine_cwd  bundle folder; folder the engine starts in (default: the bundle folder)
#   bundle_project()        builds the bundle into $bundle_dir (default: plain bob bundle)
#   project_engine_args()   prints extra engine arguments, one per line; gets the instance id
#   worktree_output_dirs()  prints test output folders of a worktree path (agent_worktree_clean.sh)
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [ -z "${bob:-}" ]; then
	bob="$HOME/defold_engines/$(ls -1 "$HOME/defold_engines" | grep -E '^[0-9]' | sort -V | tail -n1)/bob.jar"
	export bob
fi
instance="${LINUX_INSTANCE:-$(basename "$root")}"
run_dir="$root/.internal/linux_test"
bundle_dir="$root/bundles/linux"
log_path="$run_dir/engine.log"
port_path="$run_dir/engine.port"
pid_path="$run_dir/engine.pid"
save_root=""
save_name=""
engine_cwd=""

bundle_project() {
	local commands=(resolve build bundle)
	if [ "${LINUX_CLEAN:-0}" = "1" ]; then
		commands=(clean resolve build bundle)
	fi
	rm -rf "$bundle_dir"
	java -jar "$bob" --root "$root" --archive --platform x86_64-linux --variant debug \
		--bundle-output "$bundle_dir" "${commands[@]}"
}

project_engine_args() {
	:
}

if [ -f "$root/build_shell/linux_test_project.sh" ]; then
	. "$root/build_shell/linux_test_project.sh"
fi

mkdir -p "$run_dir"
if [ -f "$pid_path" ]; then
	kill "$(cat "$pid_path")" 2>/dev/null || true
	rm -f "$pid_path"
fi
if [ "${LINUX_RESET:-0}" = "1" ] && [ -n "$save_name" ]; then
	rm -rf "${save_root:?}/$save_name-$instance"
fi
if [ "${LINUX_LAUNCH_ONLY:-0}" != "1" ]; then
	bundle_project
fi
if [ "${LINUX_BUILD_ONLY:-0}" = "1" ]; then
	exit 0
fi

executable=$(find "$bundle_dir" -maxdepth 3 -type f -name '*.x86_64' -perm -u+x | head -n1)
if [ -z "$executable" ]; then
	echo "error: no bundled linux executable under $bundle_dir" >&2
	exit 1
fi
mapfile -t extra_args < <(project_engine_args "$instance")
launcher=("$root/build_shell/run-test-env" --name "$instance")
if [ "${LINUX_ON_DESKTOP:-0}" = "1" ]; then
	launcher=()
fi
rm -f "$log_path" "$port_path"
(
	cd "${engine_cwd:-$(dirname "$executable")}"
	DM_SERVICE_PORT=dynamic "${launcher[@]}" "$executable" \
		--config=display.vsync=0 \
		--config=display.update_frequency=60 \
		"${extra_args[@]}" "$@" >"$log_path" 2>&1 &
	echo $! >"$pid_path"
)
for _ in $(seq 1 120); do
	port=$(sed -n 's/.*Engine service started on port \([0-9]\+\).*/\1/p' "$log_path" | head -n1)
	if [ -n "$port" ]; then
		printf '%s\n' "$port" >"$port_path"
		echo "ENGINE_PORT=$port"
		echo "ENGINE_LOG=$log_path"
		echo "ENGINE_DISPLAY=$(tr '\0' '\n' <"/proc/$(cat "$pid_path")/environ" | sed -n 's/^DISPLAY=//p')"
		exit 0
	fi
	sleep 0.5
done
echo "error: engine service port not found in $log_path" >&2
kill "$(cat "$pid_path")" 2>/dev/null || true
exit 1
