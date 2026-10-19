#!/usr/bin/env bash

# ios_wireless.sh with liveupdate, all of it local: the liveupdate archives are built here (the first
# pass of the Android phone build, as a release does) and packed into the liveupdate folder of the local
# server, the iPhone package leaves them out, so the phone downloads and mounts them from this PC.
# Needs phone_server=local in phone.conf.

ios_wireless_local_liveupdate_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -euo pipefail
. "$ios_wireless_local_liveupdate_dir/../helpers/build_helpers.sh"
. "$ios_wireless_local_liveupdate_dir/../helpers/phone.sh"
. "$ios_wireless_local_liveupdate_dir/../helpers/mac.sh"

[ "$phone_server" = local ] || { echo "error: the local liveupdate test needs phone_server=local in phone.conf" >&2; exit 1; }
build_android_phone yes
ios_phone_on_mac yes
