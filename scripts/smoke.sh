#!/usr/bin/env bash
# Run a Clove simulator test suite on a simulator created only for this run.
#
# Usage: scripts/smoke.sh [smoke|flows|all] [xcodebuild arguments]
#   smoke (default)  the app unit tests (CloveTests) and the one smoke UI test (CloveSmokeTests)
#   flows            the long UI flow tests (CloveFlowTests)
#   all              all of the above on one simulator, for verify and CI: a new
#                    simulator's first boot costs minutes, so it is paid once
#
# It runs `xcodebuild test-without-building` against the build that
# `mise run build-tests` left in .build/DerivedData.noindex, so the app is
# compiled once however many suites run. `mise run smoke` and `mise run ui-flows`
# build first.
#
# Environment overrides:
#   CLOVE_SIM_TAG          device name suffix (default: branch name + PID)
#   CLOVE_SIM_DEVICE_TYPE  simulator device type (default: iPhone 17 Pro)
#   CLOVE_SIM_RUNTIME      simulator runtime (default: newest installed iOS)
#   CLOVE_SMOKE_ATTEMPTS   attempts on UI-test-runner bootstrap failure (default: 4)
# Additional arguments pass to xcodebuild; any -only-testing: argument replaces
# the suite's own selection, e.g. -only-testing:CloveUITests/CloveFlowTests/testDesignGalleryShowsSharedControls.
set -euo pipefail
cd "$(dirname "$0")/.."

suite="smoke"
case "${1:-}" in
    smoke | flows | all)
        suite="$1"
        shift
        ;;
esac

if [ ! -d Clove.xcodeproj ]; then
    echo "error: Clove.xcodeproj is missing; run 'mise run generate' first" >&2
    exit 1
fi
if ! compgen -G ".build/DerivedData.noindex/Build/Products/Clove_*.xctestrun" >/dev/null; then
    echo "error: no Clove test build in .build/DerivedData.noindex; run 'mise run build-tests' first" >&2
    exit 1
fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "nogit")
tag="${CLOVE_SIM_TAG:-$(printf '%s-%s' "$branch" "$$" | sed 's/[^A-Za-z0-9._-]/-/g')}"
device_type="${CLOVE_SIM_DEVICE_TYPE:-iPhone 17 Pro}"
# Targeted Duo flows use real Duo hardware emulation when its runtime is installed.
# The rest of the flow suite keeps its normal phone destination.
if [ -z "${CLOVE_SIM_DEVICE_TYPE:-}" ]; then
    for argument in "$@"; do
        case "$argument" in
            -only-testing:CloveUITests/CloveFlowTests/testDuo*)
                if xcrun simctl list runtimes --json | python3 -c '
import json, sys
selected_runtime = sys.argv[1]
available = any(
    runtime.get("isAvailable")
    and (not selected_runtime or runtime["identifier"] == selected_runtime)
    and any(device["name"] == "iPhone Duo" for device in runtime.get("supportedDeviceTypes", []))
    for runtime in json.load(sys.stdin)["runtimes"]
)
sys.exit(0 if available else 1)
' "${CLOVE_SIM_RUNTIME:-}"; then
                    device_type="iPhone Duo"
                fi
                break
                ;;
        esac
    done
fi

if [ -n "${CLOVE_SIM_RUNTIME:-}" ]; then
    runtime="$CLOVE_SIM_RUNTIME"
else
    runtime=$(
        xcrun simctl list runtimes --json | python3 -c '
import json
import sys

# Only runtimes that can run the device type: some images also ship a runtime
# for one device model only, with the same version.
device_type = sys.argv[1]
runtimes = json.load(sys.stdin)["runtimes"]
ios = [
    runtime
    for runtime in runtimes
    if runtime.get("isAvailable")
    and runtime.get("platform") == "iOS"
    and any(device["name"] == device_type for device in runtime.get("supportedDeviceTypes", []))
]
if not ios:
    raise SystemExit("no available iOS simulator runtime runs " + device_type)
newest = max(ios, key=lambda runtime: tuple(int(part) for part in runtime["version"].split(".")))
print(newest["identifier"])
' "$device_type"
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
# simulator. Only a run in which no test case started counts: once one has run,
# any failure is reported, so a retry can never hide an assertion failure.
is_runner_failure() {
    ! grep -qF "Test Case '-[" "$log" && grep -q \
        -e "failed to initialize for UI testing" \
        -e "Timed out waiting for AX loaded notification" \
        -e "operation never finished bootstrapping" \
        -e "test runner crashed while preparing to run tests" \
        "$log"
}

case "$suite" in
    smoke) test_targets=(-only-testing:CloveTests -only-testing:CloveUITests/CloveSmokeTests) ;;
    flows) test_targets=(-only-testing:CloveUITests/CloveFlowTests) ;;
    all) test_targets=(-only-testing:CloveTests -only-testing:CloveUITests) ;;
esac
test_targets+=("$@")
for argument in "$@"; do
    case "$argument" in
        -only-testing:*) test_targets=("$@"); break ;;
    esac
done

max_attempts="${CLOVE_SMOKE_ATTEMPTS:-4}"
attempt=1
while [ "$attempt" -le "$max_attempts" ]; do
    xcrun simctl list devices | grep 'Clove ' || true
    echo "Creating simulator 'Clove $suite $tag' ($device_type, $runtime), attempt $attempt"
    udid=$(xcrun simctl create "Clove $suite $tag" "$device_type" "$runtime")

    # Let the simulator and its accessibility service finish starting; launching
    # the UI test runner too early fails on some runtimes.
    xcrun simctl bootstatus "$udid" -b

    : >"$log"
    set +e
    xcodebuild test-without-building \
        -project Clove.xcodeproj \
        -scheme Clove \
        -parallel-testing-enabled NO \
        "${test_targets[@]}" \
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
