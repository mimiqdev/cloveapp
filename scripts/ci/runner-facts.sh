#!/usr/bin/env bash
# Print the macOS runner's Xcode, simulator runtimes and device types, and fail
# clearly when the Xcode or iOS runtime this project needs is missing.
#
# Environment:
#   CLOVE_CI_XCODE_VERSION  required Xcode version (default: 27.2)
#   CLOVE_CI_IOS_MAJOR      required iOS simulator runtime major version (default: 27)
#   CLOVE_SIM_DEVICE_TYPE   the device type scripts/smoke.sh uses (default: iPhone 17 Pro)
set -euo pipefail

xcode_version="${CLOVE_CI_XCODE_VERSION:-27.2}"
ios_major="${CLOVE_CI_IOS_MAJOR:-27}"
device_type="${CLOVE_SIM_DEVICE_TYPE:-iPhone 17 Pro}"

fail() {
    echo "::error title=Runner is missing a requirement::$1"
    echo "error: $1" >&2
    exit 1
}

if [ -n "${DEVELOPER_DIR:-}" ] && [ ! -d "$DEVELOPER_DIR" ]; then
    fail "DEVELOPER_DIR $DEVELOPER_DIR does not exist; this runner has no Xcode $xcode_version."
fi

echo "::group::xcodebuild -version"
version_output=$(xcodebuild -version)
echo "$version_output"
echo "::endgroup::"
echo "::group::xcrun simctl list runtimes"
xcrun simctl list runtimes
echo "::endgroup::"
echo "::group::xcrun simctl list devicetypes"
xcrun simctl list devicetypes
echo "::endgroup::"

first_line=$(printf '%s\n' "$version_output" | head -n 1)
case "$first_line" in
    "Xcode $xcode_version" | "Xcode $xcode_version."*) ;;
    *) fail "Expected Xcode $xcode_version, found '$first_line'." ;;
esac

runtimes_json=$(xcrun simctl list runtimes --json)
devicetypes_json=$(xcrun simctl list devicetypes --json)

summary=$(
    RUNTIMES="$runtimes_json" DEVICETYPES="$devicetypes_json" IOS_MAJOR="$ios_major" \
        DEVICE_TYPE="$device_type" XCODE="$first_line" /usr/bin/python3 - <<'PY'
import json
import os

runtimes = json.loads(os.environ["RUNTIMES"])["runtimes"]
types = [entry["name"] for entry in json.loads(os.environ["DEVICETYPES"])["devicetypes"]]
ios = sorted(
    (
        runtime["version"]
        for runtime in runtimes
        if runtime.get("isAvailable") and runtime.get("platform") == "iOS"
    ),
    key=lambda version: tuple(int(part) for part in version.split(".")),
)
major = os.environ["IOS_MAJOR"]
wanted = os.environ["DEVICE_TYPE"]
duo = [name for name in types if name.startswith("iPhone Duo")]
ipad = [name for name in types if name.startswith("iPad Pro") and "(M5)" in name]


def found(names):
    return ", ".join(names) if names else "missing"


rows = [
    ("Xcode", os.environ["XCODE"]),
    ("iOS simulator runtimes", ", ".join(ios) or "none"),
    ("Smoke device type (" + wanted + ")", "present" if wanted in types else "missing"),
    ("iPhone Duo device types", found(duo)),
    ("iPad Pro (M5) device types", found(ipad)),
]
print("| Fact | Value |")
print("| --- | --- |")
for fact, value in rows:
    print("| " + fact + " | " + value + " |")
missing = []
if not any(version.split(".")[0] == major for version in ios):
    missing.append("an available iOS " + major + " simulator runtime")
if wanted not in types:
    missing.append("the " + wanted + " device type")
if missing:
    print("MISSING: " + " and ".join(missing))
PY
)
printf '%s\n' "$summary" | grep -v '^MISSING: '
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '%s\n' "$summary" | grep -v '^MISSING: ' >>"$GITHUB_STEP_SUMMARY"
fi
missing=$(printf '%s\n' "$summary" | sed -n 's/^MISSING: //p')
if [ -n "$missing" ]; then
    fail "This runner is missing $missing."
fi
