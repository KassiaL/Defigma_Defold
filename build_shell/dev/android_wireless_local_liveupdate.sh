#!/usr/bin/env bash

# android_wireless.sh with liveupdate, all of it local: the archives are packed into the liveupdate folder
# of the local server (pack_liveupdate) and left out of the APK, so the phone downloads and mounts them
# from this PC and the whole liveupdate flow shows in its log. Needs phone_server=local in phone.conf.
#
# usage: dev/android_wireless_local_liveupdate.sh [--address <ip:port>]

android_wireless_local_liveupdate_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -euo pipefail
. "$android_wireless_local_liveupdate_dir/../helpers/build_helpers.sh"
. "$android_wireless_local_liveupdate_dir/../helpers/phone.sh"

[ "$phone_server" = local ] || { echo "error: the local liveupdate test needs phone_server=local in phone.conf" >&2; exit 1; }
connect_android_phone "$android_wireless_local_liveupdate_dir/$(basename "${BASH_SOURCE[0]}")" "$@"
build_android_phone yes
install_android_phone
