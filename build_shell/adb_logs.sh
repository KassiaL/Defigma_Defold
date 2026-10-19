#!/usr/bin/env bash

adb_logs_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -euo pipefail
cd "$adb_logs_dir"
adb logcat -s defold
