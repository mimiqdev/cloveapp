#!/usr/bin/env bash
# Operate only the supplied owned Duo through Device Hub's public Accessibility controls.
set -euo pipefail
cd "$(dirname "$0")/.."
helper=.build/DerivedData.noindex/Tools/duo-devicehub
stamp="$helper.toolchain"
mkdir -p "$(dirname "$helper")"
toolchain="$(xcode-select -p)
$(xcodebuild -version)
$(sw_vers -buildVersion)"
cached=""
if [ -f "$stamp" ]; then cached=$(<"$stamp"); fi
rebuild=""
if [ ! -x "$helper" ] || [ scripts/duo-devicehub.swift -nt "$helper" ] || [ "$cached" != "$toolchain" ]; then
    rebuild=1
fi
stderr_file="$(mktemp "${TMPDIR:-/tmp}/duo-pose.XXXXXX")"
trap 'rm -f "$stderr_file"' EXIT

build_helper() {
    rm -f "$helper"
    xcrun swiftc -swift-version 6 scripts/duo-devicehub.swift -o "$helper"
    printf '%s\n' "$toolchain" > "$stamp"
}

run_helper() {
    status=0
    "$helper" "$@" 2>"$stderr_file" || status=$?
    cat "$stderr_file" >&2
    return 0
}

if [ -n "$rebuild" ]; then
    build_helper
fi
run_helper "$@"

# A point update can leave the cached binary unable to load while the stamp
# above still matches. Rebuild it once; a genuine helper failure then surfaces.
load_error='dyld|symbol not found|bad cpu type|invalid'
if [ -z "$rebuild" ] && [ "$status" -ne 0 ] && grep -Eqi "$load_error" "$stderr_file"; then
    build_helper
    run_helper "$@"
fi

exit "$status"
