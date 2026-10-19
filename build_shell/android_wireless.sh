#!/usr/bin/env bash

# The phone build of this checkout (uncommitted changes included, the automation bridge kept, no
# liveupdate) on the Android phone over Wi-Fi: replaces the installed app without clearing its data,
# starts it and shows its log (Ctrl+C stops the log). phone.conf picks the server. The phone is the one
# of Wireless debugging (pair it once: helpers/adb_wifi.sh pair <ip:port> <code>), --address picks one,
# ANDROID_SERIAL skips the Wi-Fi lookup (a USB phone).
#
# usage: android_wireless.sh [--address <ip:port>]

android_wireless_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -euo pipefail
. "$android_wireless_dir/helpers/build_helpers.sh"
. "$android_wireless_dir/helpers/phone.sh"

connect_android_phone "$android_wireless_dir/$(basename "${BASH_SOURCE[0]}")" "$@"
build_android_phone no
install_android_phone
