#!/usr/bin/env bash
# Throw away the agent worktrees of this project and the save folders their instances left behind.
# Shared by every Defold project and synced by sync_defold_docs.py: the checkout comes from the
# directory the script lives in; save_root/save_name and worktree_output_dirs() of
# build_shell/test/test_instance_project.sh name the save folders and the test output a worktree leaves
# behind (none without that file). The engine a worktree still runs is stopped first, also on a test
# host, and the checkout ~/defold_test_host/test_host.py made of it on every other computer is removed;
# so is the Defigma web server agent_worktree.sh started for it (build_shell/test/defigma_twin.py).
#
# usage: agent_worktree_clean.sh [-n] [-y] [-f] [--include-main-save] [<name> ...]
#   <name>               clean only these agents (the <name> of agent_worktree.sh); all when omitted
#   -n, --dry-run        print what would be removed and stop
#   -y, --yes            do not ask
#   -f, --force          remove a worktree that still has uncommitted changes, delete unmerged branches
#       --include-main-save  also delete the save folder of the plain build, not only the per-instance ones
set -euo pipefail

dry_run=no
assume_yes=no
force=no
include_main_save=no
names=()
while [ $# -gt 0 ]; do
	case "$1" in
	-n | --dry-run) dry_run=yes ;;
	-y | --yes) assume_yes=yes ;;
	-f | --force) force=yes ;;
	--include-main-save) include_main_save=yes ;;
	-h | --help)
		sed -n '7,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	-*)
		echo "unknown option: $1" >&2
		exit 2
		;;
	*) names+=("$1") ;;
	esac
	shift
done

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
save_root=""
save_name=""
worktree_output_dirs() {
	:
}
if [ -f "$root/build_shell/test/test_instance_project.sh" ]; then
	. "$root/build_shell/test/test_instance_project.sh"
fi
project_label=$(basename "$root")
# Every worktree of this repository is listed by the main checkout, and that is also the only
# place git lets us remove one from - a worktree cannot delete itself.
main_checkout=$(dirname "$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)")

matches_names() {
	local candidate="$1"
	[ ${#names[@]} -eq 0 ] && return 0
	local name
	for name in "${names[@]}"; do
		case "$candidate" in
		*"$name"*) return 0 ;;
		esac
	done
	return 1
}

worktree_paths=()
output_dirs=()
while IFS= read -r line; do
	path="${line#worktree }"
	[ "$path" = "$main_checkout" ] && continue
	matches_names "$(basename "$path")" || continue
	worktree_paths+=("$path")
	while IFS= read -r candidate; do
		[ -d "$candidate" ] && output_dirs+=("$candidate")
	done < <(worktree_output_dirs "$path")
done < <(git -C "$main_checkout" worktree list --porcelain | grep '^worktree ')

save_dirs=()
if [ -n "$save_name" ]; then
	for candidate in "$save_root/$save_name"-*; do
		[ -d "$candidate" ] || continue
		matches_names "$(basename "$candidate")" || continue
		save_dirs+=("$candidate")
	done
	if [ "$include_main_save" = yes ] && [ -d "$save_root/$save_name" ] && [ ${#names[@]} -eq 0 ]; then
		save_dirs+=("$save_root/$save_name")
	fi
fi

if [ ${#worktree_paths[@]} -eq 0 ] && [ ${#save_dirs[@]} -eq 0 ]; then
	echo "nothing to clean for $project_label"
	exit 0
fi

echo "project: $project_label ($main_checkout)"
for path in "${worktree_paths[@]+"${worktree_paths[@]}"}"; do
	branch=$(git -C "$path" rev-parse --abbrev-ref HEAD)
	dirty=$(git -C "$path" status --porcelain --untracked-files=no)
	echo "  worktree  $path [$branch]${dirty:+  UNCOMMITTED CHANGES}"
done
for path in "${save_dirs[@]+"${save_dirs[@]}"}"; do
	echo "  save      $path"
done
for path in "${output_dirs[@]+"${output_dirs[@]}"}"; do
	echo "  output    $path"
done

if [ "$dry_run" = yes ]; then
	exit 0
fi
if [ "$assume_yes" != yes ]; then
	if [ ! -t 0 ]; then
		echo "error: not a terminal, pass -y to clean without asking" >&2
		exit 1
	fi
	read -r -p "remove all of this? [y/N] " answer
	case "$answer" in
	y | Y | yes | YES) ;;
	*)
		echo "cancelled"
		exit 1
		;;
	esac
fi

for path in "${worktree_paths[@]+"${worktree_paths[@]}"}"; do
	if [ "$path" = "$root" ]; then
		echo "skip $path: run this from the main checkout to remove the worktree it is called from"
		continue
	fi
	branch=$(git -C "$path" rev-parse --abbrev-ref HEAD)
	if [ "$force" != yes ] && [ -n "$(git -C "$path" status --porcelain --untracked-files=no)" ]; then
		echo "skip $path: uncommitted changes, pass -f to remove it anyway"
		continue
	fi
	pid_path="$path/.internal/test_instance/engine.pid"
	if [ -f "$pid_path" ]; then
		kill "$(cat "$pid_path")" 2>/dev/null || true
	fi
	python3 "$main_checkout/build_shell/test/defigma_twin.py" stop "$path"
	# --force only drops the build artifacts and the copied dependency cache; the uncommitted
	# work that --force is meant to protect is checked above.
	git -C "$main_checkout" worktree remove --force "$path"
	echo "removed worktree $path"
	python3 "$HOME/defold_test_host/test_host.py" remove --root "$main_checkout" --instance "$(basename "$path")"
	if [ "$force" = yes ]; then
		git -C "$main_checkout" branch -D "$branch"
	elif ! git -C "$main_checkout" branch -d "$branch" 2>/dev/null; then
		echo "kept branch $branch: not merged, delete it with 'git branch -D $branch'"
	fi
done

for path in "${save_dirs[@]+"${save_dirs[@]}"}"; do
	rm -rf "$path"
	echo "removed save $path"
done

for path in "${output_dirs[@]+"${output_dirs[@]}"}"; do
	rm -rf "$path"
	echo "removed output $path"
done

worktree_parent="$(dirname "$main_checkout")/worktrees"
[ -d "$worktree_parent" ] && rmdir "$worktree_parent" 2>/dev/null && echo "removed empty $worktree_parent"
exit 0
