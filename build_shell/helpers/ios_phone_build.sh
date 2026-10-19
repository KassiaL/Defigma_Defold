#!/usr/bin/env bash

# Runs on the Mac, started by ios_phone_on_mac (helpers/mac.sh) once the signing is set up: bundles the
# phone build of this checkout (export_ios_phone, phone.conf, helpers/phone.sh) and installs it on the iPhone over Wi-Fi.
# PHONE_LIVEUPDATE=yes leaves the liveupdate content out of the package.

ios_phone_build_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -euo pipefail
. "$ios_phone_build_dir/build_helpers.sh"
. "$ios_phone_build_dir/phone.sh"

export_ios_phone
export liveupdate="$PHONE_LIVEUPDATE"
phone_host=""
if [ "$phone_server" = local ]; then
	phone_host=$(ipconfig getifaddr en0)
	"$ios_phone_build_dir/ios_server_tunnel.sh" "$phone_host" "${phone_server_ports[@]}"
fi
mkdir -p "$directory_defold_project/.internal"
phone_settings_path=$(mktemp "$directory_defold_project/.internal/phone.XXXXXX")
phone_settings "$phone_host" >"$phone_settings_path"
enter_project_root
run_ios_bundle --settings "$phone_settings_path"
remove_liveupdate_zip
"$ios_phone_build_dir/ios_wifi_install.sh" "${path_to_bundle}${project_title}.app"
printf 'Installed %s. Open it on the iPhone.\n' "$project_title"
