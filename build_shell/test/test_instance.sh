#!/usr/bin/env bash
# Builds and starts a test instance of this checkout: the debug bundle of the platform it runs on
# (x86_64-linux, arm64-macos, x86_64-win32) with the automation bridge, started so it never shows up
# for the person at that computer (on Linux inside its own invisible X display, build_shell/test/run-test-env).
# Prints ENGINE_PORT=<port>, ENGINE_LOG=<path>, ENGINE_DISPLAY=:<n> and ENGINE_AUDIO=<pulse source>; arguments go to the engine.
# The sound never reaches the speakers: on Linux it plays into a null sink of the instance that a recording
# takes it from (run-test-env); on macOS build_shell/test/mute_macos.m, injected with DYLD_INSERT_LIBRARIES
# into the bundle re-signed without the hardened runtime, sets the volume of every AVAudioPlayerNode to 0
# before it plays; on Windows run-test-window.py mutes the
# audio sessions of the engine. The game's own volume (the master group gain) is never touched.
# When this PC is short of RAM the build and the engine move to a test host of the LAN through
# ~/defold_test_host/test_host.py pick (md/shared/TEST_HOSTS.md), only to a Linux one with TEST_SOUND=1;
# the output is then ENGINE_PORT (a local port), ENGINE_LOG (a local mirror) and ENGINE_HOST=<host>;
# exit code 3 means no computer fits.
# On a test host the same script runs on Linux, macOS (bash 4+) and Windows (Git Bash).
# Shared by every Defold project and synced by sync_defold_docs.py. What differs per project lives
# in build_shell/test/test_instance_project.sh, sourced when present; see md/shared/PARALLEL_TEST_INSTANCES.md.
#
# build_shell/test/test_instance_project.sh may set:
#   save_root, save_name    per-instance save folder "$save_root/$save_name-<instance>" (TEST_RESET,
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
instance="${TEST_INSTANCE:-$(basename "$root")}"
run_dir="$root/.internal/test_instance"
bundle_dir="$root/bundles/test_instance"
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
	if [ "${TEST_CLEAN:-0}" = "1" ]; then
		commands=(clean resolve build bundle)
	fi
	rm -rf "$bundle_dir"
	java -jar "$bob" --root "$root" --archive --platform "$test_platform" --variant debug \
		--bundle-output "$bundle_dir" "${commands[@]}"
}

project_engine_args() {
	:
}

if [ -f "$root/build_shell/test/test_instance_project.sh" ]; then
	. "$root/build_shell/test/test_instance_project.sh"
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
rm -f "$run_dir/remote.json" "$run_dir/recording.json"
test_host_tool="$HOME/defold_test_host/test_host.py"
test_host=local
if [ "${TEST_LAUNCH_ONLY:-0}" != "1" ] && [ "${TEST_ON_DESKTOP:-0}" != "1" ]; then
	case "${TEST_HOST:-auto}" in
	auto) test_host=$(python3 "$test_host_tool" pick $([ "${TEST_SOUND:-0}" = "1" ] && echo --sound)) ;;
	*) test_host=$TEST_HOST ;;
	esac
fi
if [ "$test_host" != local ]; then
	main_port_args=()
	for port in ${main_host_ports[@]+"${main_host_ports[@]}"}; do
		main_port_args+=(--main-port "$port")
	done
	exec python3 "$test_host_tool" run --host "$test_host" --root "$root" \
		--instance "$instance" --bob "$bob" --run-dir "$run_dir" \
		${main_port_args[@]+"${main_port_args[@]}"} -- "$@"
fi
if [ "${TEST_RESET:-0}" = "1" ] && [ -n "$save_name" ]; then
	rm -rf "${save_root:?}/$save_name-$instance"
fi
if [ "${TEST_LAUNCH_ONLY:-0}" != "1" ]; then
	bundle_project
fi
if [ "${TEST_BUILD_ONLY:-0}" = "1" ]; then
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
if [ "$test_platform" = x86_64-linux ] && [ "${TEST_ON_DESKTOP:-0}" != "1" ]; then
	launcher=("$root/build_shell/test/run-test-env" --name "$instance")
fi
if [[ "$test_platform" == *-macos ]] && [ "${TEST_ON_DESKTOP:-0}" != "1" ]; then
	codesign --force --sign - "${executable%/Contents/MacOS/*}" >/dev/null 2>&1
	cc -dynamiclib -fobjc-arc -framework AVFoundation -o "$run_dir/mute_macos.dylib" "$root/build_shell/test/mute_macos.m"
	launcher=(env "DYLD_INSERT_LIBRARIES=$run_dir/mute_macos.dylib")
fi
engine_args=(--config=display.vsync=0 --config=display.update_frequency=60 ${extra_args[@]+"${extra_args[@]}"} "$@")
rm -f "$log_path" "$port_path"
if [ "$test_platform" = x86_64-win32 ]; then
	: >"$log_path"
	DM_SERVICE_PORT=dynamic python "$root/build_shell/test/run-test-window.py" --log "$(cygpath -w "$log_path")" \
		--pid-file "$(cygpath -w "$pid_path")" --cwd "$(cygpath -w "${engine_cwd:-$(dirname "$executable")}")" -- \
		"$(cygpath -w "$executable")" "${engine_args[@]}" </dev/null >/dev/null 2>&1 &
else
	(
		cd "${engine_cwd:-$(dirname "$executable")}"
		DM_SERVICE_PORT=dynamic ${launcher[@]+"${launcher[@]}"} "$executable" "${engine_args[@]}" </dev/null >"$log_path" 2>&1 &
		echo $! >"$pid_path"
	)
fi
for _ in $(seq 1 120); do
	port=$(sed -n 's/.*Engine service started on port \([0-9][0-9]*\).*/\1/p' "$log_path" | head -n1)
	if [ -n "$port" ]; then
		printf '%s\n' "$port" >"$port_path"
		echo "ENGINE_PORT=$port"
		echo "ENGINE_LOG=$log_path"
		if [ "$test_platform" = x86_64-linux ]; then
			echo "ENGINE_DISPLAY=$(tr '\0' '\n' <"/proc/$(cat "$pid_path")/environ" | sed -n 's/^DISPLAY=//p')"
			if [ ${#launcher[@]} -gt 0 ]; then
				echo "ENGINE_AUDIO=$("${launcher[0]}" --audio "$instance")"
			fi
		fi
		exit 0
	fi
	sleep 0.5
done
echo "error: engine service port not found in $log_path" >&2
stop_pid "$(cat "$pid_path")"
exit 1
