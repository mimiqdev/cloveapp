#!/usr/bin/env bash
# Run the Clove UI smoke test on a simulator created only for this run.
#
# Environment overrides:
#   CLOVE_SIM_TAG          device name suffix (default: branch name + PID)
#   CLOVE_SIM_DEVICE_TYPE  simulator device type (default: iPhone 17 Pro)
#   CLOVE_SIM_RUNTIME      simulator runtime (default: newest installed iOS)
#   CLOVE_SMOKE_ATTEMPTS   attempts on UI-test-runner bootstrap failure (default: 4)
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

udid=""
log=$(mktemp -t clove-smoke)

cleanup() {
    if [ -n "$udid" ]; then
        xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
        xcrun simctl delete "$udid" >/dev/null 2>&1 || true
    fi
    rm -f "$log"
}
trap cleanup EXIT

# The UI test runner intermittently fails to attach before the assertion runs.
# Those failures are infrastructure, not test results, so retry them on a fresh
# simulator; assertion failures are reported immediately.
is_runner_failure() {
    grep -q \
        -e "failed to initialize for UI testing" \
        -e "Timed out waiting for AX loaded notification" \
        -e "operation never finished bootstrapping" \
        -e "test runner crashed while preparing to run tests" \
        "$log"
}

max_attempts="${CLOVE_SMOKE_ATTEMPTS:-4}"
attempt=1
while [ "$attempt" -le "$max_attempts" ]; do
    echo "Creating simulator 'Clove smoke $tag' ($device_type, $runtime), attempt $attempt"
    udid=$(xcrun simctl create "Clove smoke $tag" "$device_type" "$runtime")

    # Let the simulator and its accessibility service finish starting; launching
    # the UI test runner too early fails on some runtimes.
    xcrun simctl bootstatus "$udid" -b

    : >"$log"
    set +e
    xcodebuild test \
        -project Clove.xcodeproj \
        -scheme Clove \
        -only-testing:CloveTests \
        -only-testing:CloveUITests \
        -destination "id=$udid" \
        -derivedDataPath .build/DerivedData.noindex 2>&1 | tee "$log"
    code=$?
    set -e

    if [ "$code" -eq 0 ]; then
        break
    fi
    if [ "$attempt" -ge "$max_attempts" ] || ! is_runner_failure; then
        exit "$code"
    fi

    echo "UI test runner failed to initialize; retrying on a fresh simulator" >&2
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
    udid=""
    attempt=$((attempt + 1))
done
