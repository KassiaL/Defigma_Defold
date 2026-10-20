# The server bob builds the native engine on. Sourced by every build script after $bob is set; shared by
# every Defold project and synced by sync_defold_docs.py.
# build_server_url <choice> <platform> prints the url for --build-server, nothing for bob's own
# build.defold.com. <choice>:
#   auto   the first available server in build_servers_auto.conf, in order
#   local  the local Extender, an error when it does not answer
#   cloud  build.defold.com
#   <url>  that server
# A beta_* bob builds on build-stage.defold.com instead of build.defold.com and never on the local Extender.
local_extender_url="http://localhost:9000"
build_servers_auto_config="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build_servers_auto.conf"

local_extender_up() {
	curl -sf -m 2 "$local_extender_url/actuator/health" | grep -q UP
}

local_extender_builds() {
	case "$1" in
	*-ios | *-macos) return 1 ;;
	esac
	case "$(basename "$(dirname "$bob")")" in
	beta_*) return 1 ;;
	esac
}

cloud_build_server_url() {
	case "$(basename "$(dirname "$bob")")" in
	beta_*) printf '%s' "https://build-stage.defold.com" ;;
	esac
}

require_local_extender() {
	if ! local_extender_up; then
		echo "error: the local Extender does not answer at $local_extender_url" >&2
		return 1
	fi
}

auto_build_server_url() {
	local auto_build_servers=(local cloud)
	local auto_local_platforms=('*')
	local config="$build_servers_auto_config"
	local server pattern supported auto_lan_build_server
	if [ -f "$config" ]; then
		. "$config"
	fi
	if ! local_extender_builds "$1"; then
		cloud_build_server_url
		return
	fi
	for server in "${auto_build_servers[@]}"; do
		case "$server" in
		local)
			supported=0
			for pattern in "${auto_local_platforms[@]}"; do
				case "$1" in $pattern) supported=1 ;; esac
			done
			[ "$supported" = 1 ] || continue
			server="$local_extender_url"
			;;
		cloud) cloud_build_server_url; return ;;
		esac
		if curl -sf -m 2 "${server%/}/actuator/health" | grep -q UP; then
			printf '%s' "$server"
			return
		fi
		echo "build server: $server is unavailable, trying the next server" >&2
	done
	echo "error: no configured build server is available for $1" >&2
	return 1
}

build_server_url() {
	case "$1" in
	auto) auto_build_server_url "$2" ;;
	local) require_local_extender && printf '%s' "$local_extender_url" ;;
	cloud) cloud_build_server_url ;;
	*) printf '%s' "$1" ;;
	esac
}
