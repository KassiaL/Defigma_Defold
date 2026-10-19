#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

fail() {
	printf 'Error: %s\n' "$*" >&2
	exit 1
}

sdk_adb="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}/platform-tools/adb"
if [[ -x "$sdk_adb" ]]; then
	export PATH="$(dirname "$sdk_adb"):$PATH"
fi
command -v adb >/dev/null || fail 'adb not found: install Android SDK platform-tools'

usage() {
	printf 'Usage: adb_wifi.sh pair <ip:port> <code> | connect [ip:port] | run [--address <ip:port>] <script> [args...]\n' >&2
	exit 2
}

wireless_debugging_address() {
	local candidates
	candidates="$(adb devices | awk 'NR > 1 && $2 == "device" && ($1 ~ /:[0-9]+$/ || $1 ~ /_adb-tls-connect/) { print $1 }')"
	if [[ -z "$candidates" ]]; then
		for _ in 1 2 3 4 5; do
			candidates="$(adb mdns services | awk '/_adb-tls-connect\._tcp/ { print $NF }' | sort -u)"
			[[ -n "$candidates" ]] && break
			sleep 1
		done
	fi
	[[ -n "$candidates" ]] || fail 'Phone not found: enable Wireless debugging, pair it, or pass --address <ip:port>'
	[[ "$candidates" != *$'\n'* ]] || fail 'Several Wi-Fi phones found: pass --address <ip:port>'
	printf '%s\n' "$candidates"
}

connect_phone() {
	local requested="${1:-${ANDROID_SERIAL:-}}"
	adb start-server >&2
	address="${requested:-$(wireless_debugging_address)}"
	[[ "$address" =~ ^[^[:space:]]+:[0-9]+$ || "$address" == *._adb-tls-connect._tcp* ]] || fail 'Expected a Wi-Fi address <ip:port>'
	if [[ "$address" =~ :[0-9]+$ ]]; then
		adb connect "$address" >&2
	fi
	for _ in 1 2 3 4 5; do
		if [[ "$(adb -s "$address" get-state 2>/dev/null || true)" == device ]]; then
			export ANDROID_SERIAL="$address"
			return 0
		fi
		sleep 1
	done
	fail "Phone $address is unavailable: check pairing and the Wireless debugging port"
}

case "${1:-connect}" in
pair)
	[ $# -eq 3 ] || usage
	adb pair "$2" "$3"
	;;
connect)
	[ $# -le 2 ] || usage
	connect_phone "${2:-}"
	adb devices -l
	;;
run)
	shift
	requested_address=""
	if [[ "${1:-}" == --address ]]; then
		[[ $# -ge 3 && -n "$2" ]] || usage
		requested_address="$2"
		shift 2
	fi
	[[ $# -ge 1 && -n "$1" ]] || usage
	connect_phone "$requested_address"
	cd "$project_root"
	exec "$@"
	;;
*)
	usage
	;;
esac
