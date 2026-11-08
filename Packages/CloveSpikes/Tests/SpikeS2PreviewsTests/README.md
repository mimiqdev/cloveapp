# S2 measurement reproduction

Ordinary verification runs the functional tests, with no timing thresholds. The
fixture-dependent tests skip if `formats` or `card-basic` is absent. To collect a
macOS report (one observation per variant, including full RAW):

```sh
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
mkdir -p .build/s2
CLOVE_S2_REPORT="$PWD/.build/s2/macOS.json" \
  mise exec -- swift test --package-path Packages/CloveSpikes \
  --filter PreviewTests.collectReport
```

For simulator data, the following builds a standalone executable against the
same module sources. It uses a newly created simulator, reads the host fixture
folder directly, and deletes only its own simulator on exit. It does not test
the system folder picker or external media access. Expect SDK/runtime startup
to take longer than the measurements. The simulator result must not be labeled
physical-device performance. Xcode 27.2 with the installed iOS 27.0 runtime was
used for part 1. Run from the checkout root; all build products stay there.

```sh
set -eu
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
s2_out="$PWD/.build/s2-simulator"
mkdir -p "$s2_out"
s2_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"

xcrun --sdk iphonesimulator swiftc -sdk "$s2_sdk" \
  -target arm64-apple-ios18.0-simulator -swift-version 6 \
  -parse-as-library -whole-module-optimization -emit-object -emit-module \
  -module-name SpikeSupport \
  Packages/CloveSpikes/Sources/SpikeSupport/*.swift \
  -emit-module-path "$s2_out/SpikeSupport.swiftmodule" \
  -o "$s2_out/SpikeSupport.o"
xcrun --sdk iphonesimulator swiftc -sdk "$s2_sdk" \
  -target arm64-apple-ios18.0-simulator -swift-version 6 \
  -parse-as-library -whole-module-optimization -emit-object -emit-module \
  -module-name SpikeS2Previews -I "$s2_out" \
  Packages/CloveSpikes/Sources/SpikeS2Previews/*.swift \
  -emit-module-path "$s2_out/SpikeS2Previews.swiftmodule" \
  -o "$s2_out/SpikeS2Previews.o"

cat > "$s2_out/Runner.swift" <<'SWIFT'
import Foundation
import SpikeS2Previews

@main struct Runner {
    static func main() async throws {
        let arguments = CommandLine.arguments
        var report = try await PreviewSuite.run(folder: URL(fileURLWithPath: arguments[1]))
        report.context["execution"] = "standalone arm64 iOS Simulator runner; debug compiler settings"
        report.notes.append("iOS simulator on shared, loaded Mac host. Not physical-device measurements.")
        try report.write(to: URL(fileURLWithPath: arguments[2]))
    }
}
SWIFT

xcrun --sdk iphonesimulator swiftc -sdk "$s2_sdk" \
  -target arm64-apple-ios18.0-simulator -swift-version 6 \
  -parse-as-library -I "$s2_out" "$s2_out/Runner.swift" \
  "$s2_out/SpikeSupport.o" "$s2_out/SpikeS2Previews.o" -o "$s2_out/runner"
s2_device="$(xcrun simctl create "Clove S2 measurement $$" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max \
  com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
trap 'xcrun simctl delete "$s2_device" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$s2_device"
xcrun simctl bootstatus "$s2_device" -b
xcrun simctl spawn "$s2_device" "$s2_out/runner" \
  "${CLOVE_FIXTURES_DIR:-/Volumes/T7/Projects/.clove-fixtures}/sets/formats" \
  "$s2_out/simulator.json"
```

Reports from Clove Lab use the shared exporter and appear in the selected
folder and Documents. The CLI/test collectors above take an output path instead;
keep their JSON out of git and preserve it on issue #13. The full device
checklist and interpretation limits are in `docs/spikes/S2-previews.md`.
