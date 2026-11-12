#!/usr/bin/env bash
# Merge the latest main into the checked-out head, the way CI tests a branch,
# and print the three commits it tested: the head, the main base, and the merge.
# GitHub's refs/pull/N/merge is not used: it can lag behind main.
set -euo pipefail
cd "$(dirname "$0")/../.."

head=$(git rev-parse HEAD)
git fetch --quiet --no-tags origin +refs/heads/main:refs/remotes/origin/main
main=$(git rev-parse origin/main)

if ! git -c user.name="Clove CI" -c user.email="ci@invalid" \
    merge --quiet --no-ff --no-edit "$main"; then
    git merge --abort || true
    message="The branch conflicts with main ($main). Merge main into the branch, resolve the conflicts, and push."
    echo "::error title=Merge conflict with main::$message"
    echo "error: $message" >&2
    exit 1
fi

echo "Tested commits:"
echo "  head:  $head"
echo "  main:  $main"
echo "  merge: $(git rev-parse HEAD)"
