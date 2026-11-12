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
if [ ! -x "$helper" ] || [ scripts/duo-devicehub.swift -nt "$helper" ] || [ "$cached" != "$toolchain" ]; then
    xcrun swiftc -swift-version 6 scripts/duo-devicehub.swift -o "$helper"
    printf '%s\n' "$toolchain" > "$stamp"
fi
exec "$helper" "$@"
