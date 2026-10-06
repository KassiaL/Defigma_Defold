#!/usr/bin/env bash
# Debug x86_64-linux bundle for the automation bridge, started from this checkout inside its own
# invisible X display (build_shell/test/run-test-env), so it never shows up on the desktop.
# Prints ENGINE_PORT=<port>, ENGINE_LOG=<path> and ENGINE_DISPLAY=:<n>; arguments go to the engine.
# When this PC is short of RAM the build and the engine move to a test host of the LAN through
# build_shell/test/test_host.py: the output is then ENGINE_PORT (a local port), ENGINE_LOG (a local mirror)
# and ENGINE_HOST=<host>; exit code 3 means neither this PC nor a test host has enough free RAM.
# On a test host the same script runs on Linux, macOS (bash 4+) and Windows (Git Bash).
# Shared by every Defold project and synced by sync_defold_docs.py. What differs per project lives
# in build_shell/test/linux_test_project.sh, sourced when present; see md/shared/PARALLEL_TEST_INSTANCES.md.
#
# build_shell/test/linux_test_project.sh may set:
#   save_root, save_name    per-instance save folder "$save_root/$save_name-<instance>" (LINUX_RESET,
#                           agent_worktree_clean.sh); leave save_name empty when there is none
#   bundle_dir, engine_cwd  bundle folder; folder the engine starts in (default: the bundle folder)
#   bundle_project()        builds the bundle for $test_platform into $bundle_dir (default: plain bob bundle)
#   project_engine_args()   prints extra engine arguments, one per line; gets the instance id
#   worktree_output_dirs()  prints test output folders of a worktree path (agent_worktree_clean.sh)
#   main_host_ports         ports of this PC the game needs (local server, CDN); on a test host the engine
#                           reaches them at $TEST_MAIN_HOST:$TEST_MAIN_PORT_<port>
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
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
main_host_ports=()
case "$(uname -s)" in
Darwin) test_platform="$([ "$(uname -m)" = arm64 ] && echo arm64-macos || echo x86_64-macos)" ;;
MINGW* | MSYS*) test_platform=x86_64-win32 ;;
*) test_platform=x86_64-linux ;;
esac
export test_platform

bundle_project() {
	local commands=(resolve build bundle)
	if [ "${LINUX_CLEAN:-0}" = "1" ]; then
		commands=(clean resolve build bundle)
	fi
	rm -rf "$bundle_dir"
	java -jar "$bob" --root "$root" --archive --platform "$test_platform" --variant debug \
		--bundle-output "$bundle_dir" "${commands[@]}"
}

project_engine_args() {
	:
}

if [ -f "$root/build_shell/test/linux_test_project.sh" ]; then
	. "$root/build_shell/test/linux_test_project.sh"
fi

stop_pid() {
	if [ "$test_platform" = x86_64-win32 ]; then
		taskkill //PID "$1" //T //F >/dev/null 2>&1 || true
	else
		kill "$1" 2>/dev/null || true
	fi
}

bundled_executable() {
	case "$test_platform" in
	*-macos) find "$bundle_dir" -maxdepth 4 -type f -path '*.app/Contents/MacOS/*' | head -n1 ;;
	x86_64-win32) find "$bundle_dir" -maxdepth 3 -type f -name '*.exe' | head -n1 ;;
	*) find "$bundle_dir" -maxdepth 3 -type f -name '*.x86_64' -perm -u+x | head -n1 ;;
	esac
}

mkdir -p "$run_dir"
if [ -f "$pid_path" ]; then
	stop_pid "$(cat "$pid_path")"
	rm -f "$pid_path"
fi
test_host=local
if [ "${LINUX_LAUNCH_ONLY:-0}" != "1" ] && [ "${LINUX_ON_DESKTOP:-0}" != "1" ]; then
	case "${LINUX_TEST_HOST:-auto}" in
	auto) test_host=$(python3 "$root/build_shell/test/test_host.py" pick) ;;
	*) test_host=$LINUX_TEST_HOST ;;
	esac
fi
if [ "$test_host" != local ]; then
	main_port_args=()
	for port in ${main_host_ports[@]+"${main_host_ports[@]}"}; do
		main_port_args+=(--main-port "$port")
	done
	exec python3 "$root/build_shell/test/test_host.py" run --host "$test_host" --root "$root" \
		--instance "$instance" --bob "$bob" --run-dir "$run_dir" \
		${main_port_args[@]+"${main_port_args[@]}"} -- "$@"
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

executable=$(bundled_executable)
if [ -z "$executable" ]; then
	echo "error: no bundled $test_platform executable under $bundle_dir" >&2
	exit 1
fi
extra_args=()
while IFS= read -r line; do
	extra_args+=("$line")
done < <(project_engine_args "$instance")
launcher=()
if [ "$test_platform" = x86_64-linux ] && [ "${LINUX_ON_DESKTOP:-0}" != "1" ]; then
	launcher=("$root/build_shell/test/run-test-env" --name "$instance")
fi
rm -f "$log_path" "$port_path"
(
	cd "${engine_cwd:-$(dirname "$executable")}"
	DM_SERVICE_PORT=dynamic ${launcher[@]+"${launcher[@]}"} "$executable" \
		--config=display.vsync=0 \
		--config=display.update_frequency=60 \
		${extra_args[@]+"${extra_args[@]}"} "$@" </dev/null >"$log_path" 2>&1 &
	if [ "$test_platform" = x86_64-win32 ]; then
		cat "/proc/$!/winpid" >"$pid_path"
	else
		echo $! >"$pid_path"
	fi
)
for _ in $(seq 1 120); do
	port=$(sed -n 's/.*Engine service started on port \([0-9][0-9]*\).*/\1/p' "$log_path" | head -n1)
	if [ -n "$port" ]; then
		printf '%s\n' "$port" >"$port_path"
		echo "ENGINE_PORT=$port"
		echo "ENGINE_LOG=$log_path"
		if [ "$test_platform" = x86_64-linux ]; then
			echo "ENGINE_DISPLAY=$(tr '\0' '\n' <"/proc/$(cat "$pid_path")/environ" | sed -n 's/^DISPLAY=//p')"
		fi
		exit 0
	fi
	sleep 0.5
done
echo "error: engine service port not found in $log_path" >&2
stop_pid "$(cat "$pid_path")"
exit 1
