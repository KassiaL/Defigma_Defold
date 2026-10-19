# The server bob builds the native engine on. Sourced by every build script after $bob is set; shared by
# every Defold project and synced by sync_defold_docs.py.
# build_server_url <choice> <platform> prints the url for --build-server, nothing for bob's own
# build.defold.com. <choice>:
#   auto   the local Extender (http://localhost:9000) when it answers /actuator/health within 2 s and builds
#          <platform> (not iOS or macOS), else build.defold.com
#   local  the local Extender, started with ~/extender/local.sh up when it is down; an error when it does
#          not come up
#   cloud  build.defold.com
#   <url>  that server
# A beta_* bob builds on build-stage.defold.com instead of build.defold.com and never on the local Extender.
local_extender_url="http://localhost:9000"
local_extender_script="$HOME/extender/local.sh"

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

start_local_extender() {
	if local_extender_up; then
		return
	fi
	if [ -x "$local_extender_script" ]; then
		"$local_extender_script" up >&2
		for _ in $(seq 60); do
			if local_extender_up; then
				return
			fi
			sleep 2
		done
	fi
	echo "error: the local Extender does not answer at $local_extender_url" >&2
	return 1
}

auto_build_server_url() {
	if ! local_extender_builds "$1"; then
		cloud_build_server_url
	elif local_extender_up; then
		printf '%s' "$local_extender_url"
	else
		echo "build server: the local Extender does not answer at $local_extender_url, building on build.defold.com" >&2
	fi
}

build_server_url() {
	case "$1" in
	auto) auto_build_server_url "$2" ;;
	local) start_local_extender && printf '%s' "$local_extender_url" ;;
	cloud) cloud_build_server_url ;;
	*) printf '%s' "$1" ;;
	esac
}
