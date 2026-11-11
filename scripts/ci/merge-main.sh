#!/usr/bin/env bash
# Merge main into the checked-out head, the way CI tests a branch, and print
# the three commits it tested: the head, the main base, and the merge.
#
# Usage: scripts/ci/merge-main.sh [main-sha]
#
# With a main SHA (CI passes the one its first job resolved), every job merges
# the same main. Without one, the script fetches origin/main. The merge uses
# fixed author, committer and dates, so each job produces the same merge SHA.
# GitHub's refs/pull/N/merge is not used: it can lag behind main.
set -euo pipefail
cd "$(dirname "$0")/../.."

head=$(git rev-parse HEAD)
git fetch --quiet --no-tags origin +refs/heads/main:refs/remotes/origin/main
main="${1:-$(git rev-parse origin/main)}"
if ! git cat-file -e "$main^{commit}" 2>/dev/null; then
    git fetch --quiet --no-tags origin "$main"
fi
main=$(git rev-parse "$main^{commit}")

if git merge-base --is-ancestor "$main" "$head"; then
    echo "The head already contains main; nothing to merge."
else
    date=$(git show -s --format=%cI "$main")
    if ! GIT_AUTHOR_NAME="Clove CI" GIT_AUTHOR_EMAIL="ci@invalid" GIT_AUTHOR_DATE="$date" \
        GIT_COMMITTER_NAME="Clove CI" GIT_COMMITTER_EMAIL="ci@invalid" GIT_COMMITTER_DATE="$date" \
        git merge --quiet --no-ff --no-edit -m "Merge main $main into $head" "$main"; then
        git merge --abort || true
        message="The branch conflicts with main ($main). Merge main into the branch, resolve the conflicts, and push."
        echo "::error title=Merge conflict with main::$message"
        echo "error: $message" >&2
        exit 1
    fi
fi
merge=$(git rev-parse HEAD)

echo "Tested commits:"
echo "  head:  $head"
echo "  main:  $main"
echo "  merge: $merge"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "| Commit | SHA |"
        echo "| --- | --- |"
        echo "| head | \`$head\` |"
        echo "| main | \`$main\` |"
        echo "| merge | \`$merge\` |"
    } >>"$GITHUB_STEP_SUMMARY"
fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "head=$head"
        echo "main=$main"
        echo "merge=$merge"
    } >>"$GITHUB_OUTPUT"
fi
