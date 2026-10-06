#!/usr/bin/env bash
# linux_test.sh with the bob protobuf warnings filtered out; prints errors and the engine port.
# Shared by every Defold project and synced by sync_defold_docs.py.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/build_shell/test/linux_test.sh" "$@" 2>&1 | grep -v -E "makeExtensionsImmutable|Vulnerable protobuf|warnPre22Gencode|GeneratedMessage|INFO|^ *[0-9]+%|sun.misc.Unsafe|Please consider reporting|will be removed in a future|terminally deprecated|^WARNING: *$"
exit "${PIPESTATUS[0]}"
