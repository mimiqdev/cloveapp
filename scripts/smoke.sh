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

duo_test=""
for argument in "$@"; do
    case "$argument" in
        # A Duo simulator boots in the Closed (cover) pose headlessly, so the
        # cover flow needs no Device Hub interaction and runs with no GUI session.
        -only-testing:CloveUITests/CloveFlowTests/testDuoCoverToolbarMarkAndPickers)
            duo_test="testDuoCoverToolbarMarkAndPickers" ;;
        # The Open pose exists only as a Device Hub control; there is no headless
        # way to select it, so this runner refuses the expanded flow.
        -only-testing:CloveUITests/CloveFlowTests/testDuoGridFocusDockMarkAndPhotoOnly)
            echo "error: the Open pose has no headless runner; select Open in Device Hub on an unlocked GUI session and see docs/duo-simulator.md" >&2
            exit 1 ;;
        -only-testing:CloveUITests/CloveFlowTests/testDuo*)
            echo "error: this Duo target needs an explicit mapping in scripts/smoke.sh" >&2
            exit 1 ;;
        *) continue ;;
    esac
done

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "nogit")
tag="${CLOVE_SIM_TAG:-$(printf '%s-%s' "$branch" "$$" | sed 's/[^A-Za-z0-9._-]/-/g')}"
device_type="${CLOVE_SIM_DEVICE_TYPE:-iPhone 17 Pro}"
# Targeted Duo flows use real Duo hardware emulation when its runtime is installed.
# The rest of the flow suite keeps its normal phone destination.
if [ -n "$duo_test" ] && [ -z "${CLOVE_SIM_DEVICE_TYPE:-}" ]; then
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

if [ -n "$duo_test" ] && [ "$device_type" != "iPhone Duo" ]; then
    echo "error: the selected runtime/device cannot run the real Duo flow; select a compatible Duo runtime (27.2 build 24B91016s)" >&2
    exit 1
fi

udid=""
log=$(mktemp 2>/dev/null || mktemp -t clove-smoke)

cleanup() {
    if [ -n "$udid" ]; then
        xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
        xcrun simctl delete "$udid" >/dev/null 2>&1 || true
    fi
    rm -f "$log"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

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
    if [ -n "$duo_test" ]; then
        xcrun simctl list devices --json | python3 -c '
import json, sys
active = [device for group in json.load(sys.stdin)["devices"].values() for device in group
          if device["state"] == "Booted" and device["name"].startswith("Clove ")]
if active:
    for device in active:
        print("error: simulator slot occupied by " + device["name"] + " (" + device["udid"] + ")", file=sys.stderr)
    sys.exit(1)
'
    fi
    device_name="Clove $suite $tag attempt-$attempt"
    echo "Creating simulator '$device_name' ($device_type, $runtime), attempt $attempt"
    udid=$(xcrun simctl create "$device_name" "$device_type" "$runtime")

    # Let the simulator and its accessibility service finish starting; launching
    # the UI test runner too early fails on some runtimes.
    xcrun simctl bootstatus "$udid" -b

    run_targets=("${test_targets[@]}")
    if [ -n "$duo_test" ] && [ "$attempt" -gt 1 ]; then
        for ((index=0;index<${#run_targets[@]}-1;index++)); do
            if [ "${run_targets[$index]}" = "-resultBundlePath" ]; then
                bundle="${run_targets[$((index + 1))]}"
                run_targets[$((index + 1))]="${bundle%.xcresult}.attempt-$attempt.xcresult"
            fi
        done
    fi
    : >"$log"
    set +e
    xcodebuild test-without-building \
        -project Clove.xcodeproj \
        -scheme Clove \
        -parallel-testing-enabled NO \
        "${run_targets[@]}" \
        -destination "id=$udid" \
        -derivedDataPath .build/DerivedData.noindex 2>&1 | tee "$log"
    code=$?
    set -e

    if [ "$code" -eq 0 ]; then
        if [ -n "$duo_test" ] && ! grep -Fq "$duo_test]' passed" "$log"; then
            echo "error: the real Duo flow did not execute and pass; a skipped Duo test is not success" >&2
            exit 1
        fi
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
