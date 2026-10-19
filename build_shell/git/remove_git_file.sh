#!/usr/bin/env bash

set -e

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: not inside a Git repository"
    exit 1
}

cd "$GIT_ROOT"

while :; do
    read -p "File path (relative to git root): " FILE_PATH

    git rm --cached -- "$FILE_PATH"

    echo
    echo "Removed from Git tracking:"
    echo "  $FILE_PATH"
    echo "File remains on disk."
    echo

    git status --short -- "$FILE_PATH"
done
