# The phone builds, shared by every project that has build_shell/phone.conf. Sourced after
# build_helpers.sh; the project side is phone.conf.

phone_settings() { :; }
android_phone_setup() { :; }
android_phone_restore() { :; }
. "$build_shell_root_dir/phone.conf"

# A phone reaches port <port> of the local server at <port> + 10000: neither Android (adb reverse) nor
# the Mac (ssh tunnel) may listen below 1024.
phone_port() {
	printf '%s' "$(($1 + 10000))"
}

# Without ANDROID_SERIAL the script runs again through adb_wifi.sh, which finds the phone of Wireless
# debugging (or the one --address names) and sets it. usage: connect_android_phone <script> [--address <ip:port>]
connect_android_phone() {
	[ -z "${ANDROID_SERIAL:-}" ] || return 0
	if [[ $# -ne 1 && ! ($# -eq 3 && "$2" == --address) ]]; then
		printf 'usage: %s [--address <ip:port>]\n' "$(basename "$1")" >&2
		exit 2
	fi
	exec "$build_shell_root_dir/helpers/adb_wifi.sh" run "${@:2}" "$1"
}

reverse_local_server_ports() {
	[ "$phone_server" = local ] || return 0
	local port
	for port in "${phone_server_ports[@]}"; do
		adb reverse "tcp:$(phone_port "$port")" "tcp:$port"
	done
}

clear_android_liveupdate_mounts() {
	if adb shell pm path "$android_package" >/dev/null; then
		adb shell am force-stop "$android_package"
		adb shell run-as "$android_package" rm -f files/liveupdate.mounts files/liveupdate_archives
	fi
}

# $1 yes: the liveupdate archives go to the local server (pack_liveupdate) and stay out of the APK, so
# the phone downloads them; no: every resource is inside the APK.
build_android_phone() {
	export_android_phone
	export liveupdate="$1"
	mkdir -p "$directory_defold_project/.internal"
	phone_settings_path=$(mktemp "$directory_defold_project/.internal/phone.XXXXXX")
	phone_settings 127.0.0.1 >"$phone_settings_path"
	enter_project_root
	trap 'cd "$directory_defold_project"; android_phone_restore; rm -f "$phone_settings_path"' EXIT
	android_phone_setup
	clear_liveupdate_bundle_resources
	run_android_bundle --settings "$phone_settings_path"
	if [ "$1" = yes ]; then
		pack_liveupdate
		clear_liveupdate_bundle_resources
	fi
	android_phone_restore
	rm -f "$phone_settings_path"
	trap - EXIT
}

install_android_phone() {
	reverse_local_server_ports
	clear_android_liveupdate_mounts
	install_android_build
}
