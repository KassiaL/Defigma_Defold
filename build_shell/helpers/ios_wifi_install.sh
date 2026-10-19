#!/usr/bin/env bash

# Installs an .app or .ipa on an iPhone over Wi-Fi (or USB) with xcrun devicectl; ios-deploy cannot
# reach an iOS 17+ device over Wi-Fi. The device is IOS_DEVICE_UDID or the first available one.
#
# Without an argument it installs the newest .app or .ipa in the bundles folder of the project.
#
# usage: ios_wifi_install.sh [app|ipa]

set -euo pipefail

[ "$(uname -s)" = Darwin ] || { echo "error: this installs through xcrun devicectl, run it on the Mac (from Linux use build_shell/ios_wireless.sh)" >&2; exit 1; }
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
package="${1:-$(ls -td "$project_root"/bundles/*.app "$project_root"/bundles/*.ipa 2>/dev/null | head -n1)}"
[ -n "$package" ] || { echo "error: no .app or .ipa in $project_root/bundles, build one first" >&2; exit 1; }
device="${IOS_DEVICE_UDID:-$(xcrun devicectl list devices | grep -E 'available|connected' | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -n1 || true)}"
if [ "${package##*.}" = "ipa" ]; then
	unpacked=$(mktemp -d)
	trap 'rm -rf "$unpacked"' EXIT
	unzip -q "$package" -d "$unpacked"
	package=$(echo "$unpacked"/Payload/*.app)
fi
xcrun devicectl device install app --device "${device:?No available iPhone: unlock it, keep it on the Mac network}" "$package"
