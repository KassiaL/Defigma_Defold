#!/usr/bin/env bash
# One isolated checkout per agent: bob and the build scripts write build/, .internal/, bundles/
# (and project build stages more), so two agents must never share a directory.
# Shared by every Defold project and synced by sync_defold_docs.py; see md/shared/PARALLEL_TEST_INSTANCES.md.
# usage: agent_worktree.sh <name> [base-ref]
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
worktree_name="${1:?usage: agent_worktree.sh <name> [base-ref]}"
base_ref="${2:-HEAD}"
# Everything is anchored to the main checkout, so calling this from inside a worktree still
# creates a sibling worktree instead of nesting one inside it.
main_checkout=$(dirname "$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)")

# Worktrees live next to the project in their own folder, so a finished one can be thrown away
# without picking it out from between the real projects.
worktree_parent="$(dirname "$main_checkout")/worktrees"
worktree_root="$worktree_parent/$(basename "$main_checkout")-$worktree_name"

mkdir -p "$worktree_parent"
git -C "$main_checkout" worktree add -B "agent/$worktree_name" "$worktree_root" "$base_ref"

# The resolved dependency cache is the slow part of a fresh checkout; copy it instead of refetching.
mkdir -p "$worktree_root/.internal"
if [ -d "$main_checkout/.internal/lib" ]; then
	cp -r "$main_checkout/.internal/lib" "$worktree_root/.internal/lib"
fi

echo "WORKTREE=$worktree_root"
