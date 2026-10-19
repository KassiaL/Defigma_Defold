#!/usr/bin/env bash

# The phone build of this checkout (uncommitted changes included, the automation bridge kept, no
# liveupdate) on the iPhone over Wi-Fi, from this PC: the home Mac builds it over ssh (helpers/mac.sh) and
# installs it with xcrun devicectl (helpers/ios_wifi_install.sh). phone.conf picks the server.
# IOS_DEVICE_UDID picks the iPhone when several are available.

ios_wireless_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -euo pipefail
. "$ios_wireless_dir/helpers/build_helpers.sh"
. "$ios_wireless_dir/helpers/mac.sh"

ios_phone_on_mac no
