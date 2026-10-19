#!/usr/bin/env bash

# The dev counterpart of release/liveupdate.sh: builds the dev vendor of project.conf on the dev branch
# (uncommitted changes included) and publishes its liveupdate content, which only the clients of dev
# builds read (helpers/project.sh decides where).

liveupdate_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -euo pipefail
. "$liveupdate_dir/helpers/build_helpers.sh"

export_android_dev
require_dev_build
enter_project_root
build_android_liveupdate_bundle
publish_liveupdate "New dev build available"
