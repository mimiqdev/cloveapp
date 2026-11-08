#!/bin/bash
# Run from the repository root. Produces .build/s5/simulator.json and deletes
# only the simulator created here. Does not write to the fixture cache.
set -euo pipefail
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
root="$PWD"
output="$root/.build/s5/simulator-runner"
mkdir -p "$output/S5Probe.app"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
flags=(-sdk "$sdk" -target arm64-apple-ios18.0-simulator -swift-version 6 -O
    -module-cache-path "$output/ModuleCache.noindex")
xcrun --sdk iphonesimulator swiftc "${flags[@]}" -emit-library -static -emit-module -module-name SpikeSupport \
    Packages/CloveSpikes/Sources/SpikeSupport/*.swift -o "$output/libSpikeSupport.a" \
    -emit-module-path "$output/SpikeSupport.swiftmodule"
xcrun --sdk iphonesimulator swiftc "${flags[@]}" -I "$output" -emit-library -static -emit-module -module-name SpikeS5Grouping \
    Packages/CloveSpikes/Sources/SpikeS5Grouping/*.swift -o "$output/libSpikeS5Grouping.a" \
    -emit-module-path "$output/SpikeS5Grouping.swiftmodule"
xcrun --sdk iphonesimulator swiftc "${flags[@]}" -I "$output" -L "$output" -lSpikeS5Grouping -lSpikeSupport \
    -D S5_SIMULATOR_RUNNER -parse-as-library \
    Packages/CloveSpikes/Tests/SpikeS5GroupingTests/S5SimulatorRunner.swift \
    -o "$output/S5Probe.app/S5Probe"
python3 - "$output/S5Probe.app/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as stream:
    plistlib.dump(dict(CFBundleExecutable='S5Probe', CFBundleIdentifier='com.mimiqdev.clove.s5probe',
                      CFBundleName='S5Probe', CFBundlePackageType='APPL', CFBundleVersion='1',
                      CFBundleShortVersionString='0.1', MinimumOSVersion='18.0',
                      LSRequiresIPhoneOS=True, UILaunchScreen={},
                      UIApplicationSceneManifest=dict(UIApplicationSupportsMultipleScenes=False)), stream)
PY
udid="$(xcrun simctl create "Clove S5 measurement $$" 'iPhone 17 Pro' com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
launch_pid=""
cleanup() {
    if [ -n "$launch_pid" ]; then kill "$launch_pid" 2>/dev/null || true; fi
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid"
}
trap cleanup EXIT
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$output/S5Probe.app"
container="$(xcrun simctl get_app_container "$udid" com.mimiqdev.clove.s5probe data)"
# Simulator apps are sandboxed: give the probe its own fixture copies.
ditto "${CLOVE_FIXTURES_DIR:-/Volumes/T7/Projects/.clove-fixtures}/sets/formats" "$container/Documents/formats"
xcrun simctl launch --console "$udid" com.mimiqdev.clove.s5probe \
    "$container/Documents/formats" > "$output/console.log" 2>&1 &
launch_pid="$!"
echo "S5 simulator container: $container"
for attempt in {1..180}; do
    if [ -f "$container/Documents/simulator.json" ]; then
        cp "$container/Documents/simulator.json" "$root/.build/s5/simulator.json"
        echo 'S5 simulator: .build/s5/simulator.json saved'
        exit 0
    fi
    if [ -f "$container/Documents/failure.txt" ]; then
        cp "$container/Documents/failure.txt" "$output/failure.txt"
        exit 1
    fi
    sleep 1
done
if [ -f "$container/Documents/progress.txt" ]; then
    cp "$container/Documents/progress.txt" "$output/progress.txt"
fi
xcrun simctl spawn "$udid" log show --last 3m --style compact \
    --predicate 'process == "S5Probe"' > "$output/process.log" 2>&1 || true
echo "S5 simulator: timed out; see $output/console.log and process.log" >&2
exit 1
