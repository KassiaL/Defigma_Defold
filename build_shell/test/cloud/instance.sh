#!/usr/bin/env bash
# build_shell/test/test_instance.sh for a Claude Code cloud session (md/shared/CLOUD.md): the same build and
# instance, with what the cloud container lacks worked around. Arguments and TEST_* switches go through.
#   - dependencies: deps.py packs them into .internal/lib from git clones, bob runs without `resolve`
#     (TEST_RESOLVE=0): the GitHub proxy of the session refuses archive downloads of other repositories;
#   - native engine: built on build.defold.com through extender_proxy.py on 127.0.0.1:9100
#     (TEST_BUILD_SERVER), which bob's Extender client cannot reach without a proxy of its own;
#   - display: no GPU, so run-test-env renders with Mesa llvmpipe (TEST_SOFTWARE_GL=1): slow, but bridge
#     input, screenshots and record.py work as on the desktop;
#   - always this container (TEST_HOST=local): there are no test hosts.
# Prints what test_instance.sh prints (ENGINE_PORT, ENGINE_LOG, ENGINE_DISPLAY), bob noise filtered out.
# Shared by every Defold project and synced by sync_defold_docs.py.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cloud_dir="$root/build_shell/test/cloud"
extender_port=9100

if ! curl -s -o /dev/null -m 2 "http://127.0.0.1:$extender_port/"; then
	setsid python3 "$cloud_dir/extender_proxy.py" --port "$extender_port" </dev/null >/tmp/extender_proxy.log 2>&1 &
	for _ in $(seq 1 20); do
		curl -s -o /dev/null -m 2 "http://127.0.0.1:$extender_port/" && break
		sleep 0.5
	done
fi
if [ "${TEST_LAUNCH_ONLY:-0}" != "1" ]; then
	python3 "$cloud_dir/deps.py" "$root" >/dev/null
fi

export TEST_HOST=local TEST_RESOLVE=0 TEST_SOFTWARE_GL=1
export TEST_BUILD_SERVER="${TEST_BUILD_SERVER:-http://127.0.0.1:$extender_port}"
exec "$root/build_shell/test/build_quiet.sh" "$@"
