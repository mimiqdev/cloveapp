#!/bin/bash
# From the repository root. A disposable project tests the actual S7 screen;
# neither the shared project definition nor the shared UI tests are changed.
set -euo pipefail
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
root="$PWD"
output="$root/.build/s7"
mkdir -p "$output"
python3 - "$root" "$output" <<'PY'
import json, pathlib, sys
root, output = map(pathlib.Path, sys.argv[1:])
project = {
    'name': 'S7Probe',
    'options': {'deploymentTarget': {'iOS': '18.0'}},
    'settings': {'base': {'SWIFT_VERSION': '6.0', 'SWIFT_STRICT_CONCURRENCY': 'complete',
                           'CODE_SIGNING_ALLOWED': 'NO', 'GENERATE_INFOPLIST_FILE': 'YES',
                           'MARKETING_VERSION': '0.1.0', 'CURRENT_PROJECT_VERSION': '1'}},
    'packages': {name: {'path': str(root / 'Packages' / name)}
                 for name in ['CloveCore', 'CloveImaging', 'CloveSpikes']},
    'targets': {
        'S7Lab': {'type': 'application', 'platform': 'iOS',
                  'sources': [{'path': str(root / 'CloveLab')}],
                  'dependencies': [{'package': name} for name in ['CloveCore', 'CloveImaging', 'CloveSpikes']],
                  'settings': {'base': {
                      'PRODUCT_BUNDLE_IDENTIFIER': 'com.mimiqdev.clove.s7probe',
                      'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES',
                      'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES',
                      'INFOPLIST_KEY_UISupportedInterfaceOrientations':
                      'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'}}},
        'S7UITests': {'type': 'bundle.ui-testing', 'platform': 'iOS',
                      'sources': [{'path': str(root / 'Packages/CloveSpikes/Tests/SpikeS7DuoTests/S7SimulatorUITests.swift')}],
                      'dependencies': [{'target': 'S7Lab'}],
                      'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'com.mimiqdev.clove.s7uitests',
                                             'TEST_TARGET_NAME': 'S7Lab',
                                             'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'S7_SIMULATOR_UI_TESTS'}}}
    },
    'schemes': {'S7Probe': {'build': {'targets': {'S7Lab': 'all'}},
                           'test': {'targets': ['S7UITests']}}}
}
(output / 'project.json').write_text(json.dumps(project))
PY
mise exec -- xcodegen generate --spec "$output/project.json" --project "$output"
udid="$(xcrun simctl create "Clove S7 geometry $$" 'iPhone 17 Pro' com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
cleanup() {
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid"
}
trap cleanup EXIT
xcodebuild test -project "$output/S7Probe.xcodeproj" -scheme S7Probe \
    -destination "platform=iOS Simulator,id=$udid" -parallel-testing-enabled NO \
    -derivedDataPath "$output/DerivedData.noindex" \
    -resultBundlePath "$output/geometry-$(date -u +%Y%m%dT%H%M%SZ).xcresult" \
    CODE_SIGNING_ALLOWED=NO
# Keep extraction tied to this device, not an XCTest-created clone. Some
# Xcode versions shut it down after testing; boot our own device if needed.
xcrun simctl boot "$udid" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$udid" -b
container="$(xcrun simctl get_app_container "$udid" com.mimiqdev.clove.s7probe data)"
cp "$container"/Documents/clove-lab-S7-*.json "$output/"
python3 - "$output" <<'PY'
import json, pathlib, sys
files = sorted(pathlib.Path(sys.argv[1]).glob('clove-lab-S7-*.json'))
assert files, 'No S7 report exported'
report = json.loads(files[-1].read_text())
events = [m['tags'] for m in report['measurements']]
attached = [e for e in events if e['sceneID'] != 'unattached']
assert len({e['window.xywh.pt'] for e in attached}) > 1, 'No rotation geometry logged'
assert len({e['stateID'] for e in attached}) > 1, 'View recreation not recorded'
assert any(e['stateCounter'] == '1' and e['sceneStorageCounter'] == '1' for e in attached)
assert all(e['hinge.availability'] == 'requiresIOS27_1' for e in attached)
exports = [e for e in attached if e['reason'] == 'export']
assert len(exports) == 4, 'Expected portrait, landscape, portrait, reopened exports'
assert all(e['stateCounter'] == '1' and e['sceneStorageCounter'] == '1' for e in exports[:3])
assert len({e['stateID'] for e in exports[:3]}) == 1, 'Rotation recreated State'
assert len({e['sceneID'] for e in exports}) == 1, 'Unexpected scene session replacement'
assert len({e['sceneStorageID'] for e in exports}) == 1, 'SceneStorage identity changed'
assert exports[-1]['sceneStorageCounter'] == '1' and exports[-1]['stateCounter'] == '0'
assert exports[-1]['stateID'] != exports[0]['stateID'], 'Reopening did not recreate the view'
assert report['app']['version'] == '0.1.0' and report['app']['build'] == '1'
print('S7 geometry/export/recreation assertions passed:', files[-1].name)
print('events:', len(events))
for key in ['window.xywh.pt', 'scene.xywh.pt', 'orientation', 'horizontalSizeClass',
            'verticalSizeClass', 'window.safeArea.tlbr.pt', 'stateCounter', 'sceneStorageCounter']:
    print(key, sorted({e[key] for e in attached}))
PY
