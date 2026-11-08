#!/usr/bin/env bash
# Run the Clove UI smoke test on a simulator created only for this run.
#
# Environment overrides:
#   CLOVE_SIM_TAG          device name suffix (default: branch name + PID)
#   CLOVE_SIM_DEVICE_TYPE  simulator device type (default: iPhone 17 Pro)
#   CLOVE_SIM_RUNTIME      simulator runtime (default: newest installed iOS)
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d Clove.xcodeproj ]; then
    echo "error: Clove.xcodeproj is missing; run 'mise run generate' first" >&2
    exit 1
fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "nogit")
tag="${CLOVE_SIM_TAG:-$(printf '%s-%s' "$branch" "$$" | sed 's/[^A-Za-z0-9._-]/-/g')}"
device_type="${CLOVE_SIM_DEVICE_TYPE:-iPhone 17 Pro}"

if [ -n "${CLOVE_SIM_RUNTIME:-}" ]; then
    runtime="$CLOVE_SIM_RUNTIME"
else
    runtime=$(
        xcrun simctl list runtimes --json | python3 -c '
import json
import sys

runtimes = json.load(sys.stdin)["runtimes"]
ios = [
    runtime
    for runtime in runtimes
    if runtime.get("isAvailable") and runtime.get("platform") == "iOS"
]
if not ios:
    raise SystemExit("no available iOS simulator runtime")
newest = max(ios, key=lambda runtime: tuple(int(part) for part in runtime["version"].split(".")))
print(newest["identifier"])
'
    )
fi

echo "Creating simulator 'Clove smoke $tag' ($device_type, $runtime)"
udid=$(xcrun simctl create "Clove smoke $tag" "$device_type" "$runtime")

cleanup() {
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

xcodebuild test \
    -project Clove.xcodeproj \
    -scheme Clove \
    -only-testing:CloveUITests \
    -destination "id=$udid" \
    -derivedDataPath .build/DerivedData
