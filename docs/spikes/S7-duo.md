# S7 — How does the system expose Duo fold state?

## Question

How does the system expose Duo fold state? On the Duo, confirm how the hinge
position, fold posture, and window size changes are reported, and whether the
scene survives switching between cover and inner screens. Output: Duo adaptation
approach and required minimum SDK.

This is **part 1 of #18**. The Duo device session is deferred. This report does
not establish physical hinge avoidance or cover ↔ inner continuity, and leaves
G1's choice open. Production layouts P3/P4 are outside this spike.

## SDK inventory correction and Duo simulator readiness (2026-11-12)

The original search below missed the iOS 27.1 layout APIs because it searched
for hinge/fold names. Its conclusion that no public hinge rectangle exists was
wrong. `GeometryProxy.reservedRegions(kind: .division)` and
`UIView.reservedRegions(kind:)` report the fold's frame and margins. Occlusion
regions report areas such as the camera. Only active regions are returned by
default; `.includeInactive` also exposes the inactive fold when fully open.
`ArrangementView` with `.split` adapts its panes to these regions.

The system also exposes `toolbarVerticalEdge` / `verticalBarEdge`, ordinary
vertical toolbar items with `axisBehavior`, vertical compression/behavior, and
container content margins. Use these system signals and containers for Duo
layout; do not infer Duo from phone idiom plus regular size classes or draw a
second bar beside the status column. Every new API remains guarded for iOS 27.1;
the app's deployment target stays iOS 18.

On the Mac mini with Xcode 27.2 (27B52), the default iOS 27.2 simulator build
**24B8117 explicitly excludes `iPhone19,4`** in its runtime profile. Apple also
ships a separate Duo runtime, **24B91016s**, in the same download catalog:

```sh
xcodebuild -downloadPlatform iOS -buildVersion 24B91016s
xcrun simctl create "Clove readiness <tag>" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-Duo \
  com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4
xcrun simctl bootstatus <owned-device-udid> -b
```

A fresh owned Duo **created and reached the `Booted` device state** on 24B91016s,
and a native SwiftUI probe rendered its toolbar in the cover's system status
column. `bootstatus -b` returned zero while its terminal progress said **Data
Migration Failed**. The detailed log explains this result: all 35 migration
plugins completed successfully, with zero crashes, watchdog failures, or plugins
returning failure. Apple's progress UI logged `Unsupported screen class -1`,
then reported a migration progress window incident. The OS booted and ran apps;
this progress-UI diagnostic is not a Clove data migration or evidence of an
unusable simulator. Owned devices were shut down and deleted, and the runtime
was retained. These are simulator findings, not physical-device results.

Apple documents Closed, Partially Open, Open, and an Option-drag angle slider in
Device Hub. This headless Mini session cannot launch its GUI (`OSLaunchdErrorDomain
125: Domain does not support specified action`), so no open/half-fold pose result
is claimed from that session. `simctl` screen power controls alone do not change
the physical pose.

Sources: [Apple runtime catalog](https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex),
[component installation](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components),
[Device Hub pose controls](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub),
[preparing for Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo),
[ArrangementView](https://developer.apple.com/documentation/swiftui/arrangementview).

## What was tested in the original part 1 run

- Xcode **27.2**, build **27B52**, iPhoneOS and iPhoneSimulator SDK **27.2**.
- Installed simulator runtime: **iOS 27.0 (24A434)**.
- macOS **27.0 (26A428)**, arm64; tests ran on a **shared, loaded Mac** with other
  workers. No macOS performance target is inferred from these runs.
- Public SDK headers and Swift interfaces, plus Apple's documentation, inspected
  on 2026-11-09. No private API or third-party dependency.
- No photo fixtures or external volume are needed: the inputs are window/scene
  geometry, lifecycle events, operator checkpoints, and the two counters. The
  shared fixture cache's `files/` directory was not modified.
- Actual iPhone Duo hardware, OS version, hinge callbacks, and physical overlay
  alignment: **pending part 2**.

### Reproducible SDK inventory

Let `SDK=$(xcrun --sdk iphoneos --show-sdk-path)`. Paths below are relative to
`$SDK/System/Library/Frameworks/`. Availability is from those declarations, not
inferred from a device name. Search headers **and** Swift interfaces across all
frameworks, including `SwiftUICore` (a search limited to `SwiftUI` misses its
hinge declarations):

```sh
rg -n -i 'hinge|foldable|foldposture|foldstate' \
  "$SDK/System/Library/Frameworks" --glob '*.h' --glob '*.swiftinterface'
```

| Public API | SDK source and iOS availability | Meaning and limits |
| --- | --- | --- |
| `UIHinge`, `UIHinge.Status` | `UIKit.framework/Headers/UIHinge.h:15–68`; `API_AVAILABLE(ios(27.1), tvos(27.1), visionos(27.1))`, unavailable watchOS | `unknown`, `closed`, `partiallyOpen`, `fullyOpen`; `angle` is **radians**. Update rate/precision are system policy; prefer status for categorical decisions. No position, axis, occlusion rectangle, or screen identifier. |
| `UIHingeInteraction`, `UIHingeInteraction.Update.hinge` | `UIKit.framework/Headers/UIHingeInteraction.h:15–70`; same availability as `UIHinge` | Attach interaction to a view. Handler delivers initial state and subsequent hinge/hierarchy updates. `hinge == nil` means no hinge in that hierarchy; it does **not** mean closed. `isEnabled` controls delivery; disabled updates are not queued. |
| `DeviceHinge`, `DeviceHinge.Status`, `DeviceHingeContext.hinge` | `SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface:16798–16831`; `@available(anyAppleOS 27.1, *)` | SwiftUI equivalent: `status`, `angle: Angle`, optional hinge context. Status has `closed`, `partiallyOpen`, `fullyOpen`; treat future status values as unknown. No hinge rectangle. |
| `View.onHingeChange(isEnabled:_:)` | Same interface, lines 24303–24305; `@available(anyAppleOS 27.1, *)` | Old/new `DeviceHingeContext` callback. UIKit interaction is used in this probe to get its documented initial update and sample the attached window in the same place. |
| `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)`, `UIView.reservedRegions(kind:options:)` | `SwiftUICore` Swift interface and `UIKit.framework/Headers/UIViewReservedRegion.h`, `UIView.h`; iOS **27.1** | Division frames and margins describe the fold; occlusion frames describe cameras and similar obstructions. Query `.includeInactive` when the inactive region is needed. |
| `EnvironmentValues.toolbarVerticalEdge`, `UITraitCollection.verticalBarEdge` | `SwiftUICore` Swift interface; `UIKit.framework/Headers/UIVerticalBarEdge.h`; iOS **27.1** | The system's preferred vertical bar edge, even while the bar is hidden; nil/unspecified where no vertical bar is used. |
| `ToolbarContent.axisBehavior`, `toolbarVerticalCompressionBehavior`, `toolbarVerticalBehavior` | `SwiftUI` Swift interface; `UIBarButtonItem.h`, `UINavigationItem.h`; iOS **27.1** | Ordinary toolbar items adapt between horizontal and vertical bars. The system owns spacing, chrome, overflow and safe areas. |
| `ArrangementView`, `.split`, `splitArrangementLayoutRatio`, `splitArrangementLayoutSize`, `splitArrangementAxis` | `SwiftUICore` Swift interface; `UISplitArrangement.h`, `UIArrangementViewController.h`; iOS **27.1** | System pane sizing and adaptation to reserved regions. This is a layout container, not a navigation or drag-to-collapse API. |
| `contentMargins(for: .container)`, `GeometryProxy.contentMargins(for:)` | `SwiftUICore` Swift interface; related UIKit layout regions in `UIViewLayoutRegion.h`; iOS **27.1** | System container margins, including asymmetric margins near vertical bars. |
| `UIWindowScene.effectiveGeometry` | `UIKit.framework/Headers/UIWindowScene.h:34`; iOS **16.0** | Current effective scene geometry. Geometry does not identify a fold posture. |
| `UIWindowSceneGeometry.coordinateSpace` | `UIKit.framework/Headers/UIWindowSceneGeometry.h:36`; iOS **26.0** | Actual scene coordinate-space bounds. On older OS versions the probe uses `UIWindowScene.coordinateSpace` (iOS 13, deprecated from 26). |
| `UIWindowSceneGeometry.interfaceOrientation` | Same header, class available iOS **16.0** | Scene interface orientation, rather than physical device orientation. `isInteractivelyResizing` is iOS **26.0**. Neither is a hinge signal. |
| `UIWindowSceneDelegate.windowScene(_:didUpdateEffectiveGeometry:)` | `UIKit.framework/Headers/UIWindowScene.h:95`; iOS **26.0** | Production option for geometry changes; older coordinate-space delegate callback is deprecated from 26. The spike observes its own view layout instead of replacing the shared scene delegate. |
| `UIWindow.bounds`, `UIView.safeAreaInsets`, trait size classes | `UIView.h`, `UITraitCollection.h`; bounds predate scene APIs, safe areas iOS **11.0**, size classes iOS **8.0** | Probe records window bounds, view bounds, window/view safe areas, H/V size classes; `registerForTraitChanges` is iOS **17.0**. Insets describe safe areas, not the physical hinge location. |
| `GeometryReader` / `GeometryProxy.size`, `frame(in:)`, `safeAreaInsets`; `onGeometryChange` | SwiftUI / SwiftUICore public interfaces; geometry iOS **13.0**, single-value `onGeometryChange` back-deployed to iOS **16.0** | `onGeometryChange` samples the full SwiftUI viewport's geometry proxy, outside list rows. Reports points, not pixels. No device-model inference. |
| `@State`, `@SceneStorage` | SwiftUI public interfaces; iOS **13.0**, **14.0**, respectively | Probe counters/identity tokens expose view recreation versus restoration. SceneStorage is system-managed and cannot guarantee durable production write state. |

Apple documentation, cross-checked with SDK declarations:

- [UIHinge](https://developer.apple.com/documentation/uikit/uihinge),
  [angle](https://developer.apple.com/documentation/uikit/uihinge/angle),
  [UIHingeInteraction](https://developer.apple.com/documentation/uikit/uihingeinteraction).
- [DeviceHinge](https://developer.apple.com/documentation/swiftui/devicehinge),
  [DeviceHingeContext](https://developer.apple.com/documentation/swiftui/devicehingecontext),
  [onHingeChange](https://developer.apple.com/documentation/swiftui/view/onhingechange(isenabled:_:)).
- [effectiveGeometry](https://developer.apple.com/documentation/uikit/uiwindowscene/effectivegeometry),
  [GeometryReader](https://developer.apple.com/documentation/swiftui/geometryreader),
  [SceneStorage](https://developer.apple.com/documentation/swiftui/scenestorage).

The original hinge-name search found the observation APIs but missed reserved
regions. `UIHinge` and `DeviceHinge` themselves expose status and angle, while
reserved-region APIs separately expose division and occlusion frames. CoreMotion
attitude is not a hinge angle. The existing Lab probe records status and angle;
it does not yet record reserved regions. Physical-device alignment still needs
a device run, but there is a public reported rectangle to use.

## Data

### Simulator availability (Xcode 27.2, installed iOS 27.0 runtime)

```text
$ xcrun simctl list devicetypes
...
iPhone Duo (com.apple.CoreSimulator.SimDeviceType.iPhone-Duo)
...
$ xcrun simctl list runtimes
iOS 27.0 (27.0 - 24A434) - com.apple.CoreSimulator.SimRuntime.iOS-27-0
$ xcrun simctl create "Clove S7 research <PID>" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-Duo \
  com.apple.CoreSimulator.SimRuntime.iOS-27-0
An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=403):
Incompatible device
Unable to create a device for device type: iPhone Duo ... runtime: iOS 27.0 ...
```

| Question | Observation | What it establishes |
| --- | --- | --- |
| Duo simulator type exists? | Yes, exact identifier above | Xcode has a device definition. |
| Duo boots with installed runtime? | Creation refused: **SimError 403, incompatible device** | No Duo folding or screen-switch test is possible on this installed runtime. No new runtime installed. |
| Hinge APIs callable on iOS 27.0? | Availability is 27.1; probe guards them | Geometry fallback only. Device type existence does not make 27.1 APIs available. |
| Screen switching / half-fold / scene continuity on Duo simulator | **Not run**, incompatible runtime | No claims about what a compatible simulator or hardware would report. |

### Supported simulator geometry and continuity (not Duo findings)

The actual Lab screen was run in a disposable test host on **iPhone 17 Pro /
iOS 27.0**, reported model `iPhone18,1`. The complete 20-event report is
[`clove-lab-S7-20261109T040732Z.json` on issue #18](https://github.com/mimiqdev/cloveapp/issues/18#issuecomment-6732003889).
The test host uses bundle `com.mimiqdev.clove.foldstateprobe`, version `0.1.0`, build `1`;
the validation-only release separately checks the normal Clove Lab app.

| Observation | Portrait | Landscape | After leaving and reopening S7 |
| --- | --- | --- | --- |
| Window and scene size (pt) | 402 × 874 | 874 × 402 | 402 × 874 |
| Interface orientation | `portrait` | `landscapeRight` (physical device set landscape-left) | `portrait` |
| H / V size classes | compact / regular | compact / compact | compact / regular |
| Window safe area T,L,B,R (pt) | 62,0,34,0 | 0,62,20,62 | 62,0,34,0 |
| SceneStorage / State counters after increment | 1 / 1 | 1 / 1 | 1 / 0 |
| Scene session and SceneStorage identity | initial | unchanged | unchanged |
| State identity | initial | unchanged | changed |
| Hinge observation | `requiresIOS27_1` | `requiresIOS27_1` | `requiresIOS27_1` |

Rotation back to portrait also kept both counters at 1. Reopening S7 proved that
the journal retained the earlier events while the new State counter reset. This
validates the probe's ability to expose recreation; it **does not** establish
what a fold or a system scene recreation does on Duo.

Reproduce from the repository root (about 2–4 minutes on this shared host):

```sh
bash Packages/CloveLabKit/Tests/FoldStateProbeTests/measure-simulator.sh
```

The helper generates a disposable Xcode project under `.build/fold-state/`, tests the
actual Lab sources without editing shared files, validates the exported JSON,
and deletes its own simulator on exit. XCTest uses the explicitly created
device with parallel cloning disabled. Outputs stay under `.build/fold-state/`; JSON is
not committed. The standard `mise run verify` gate remains unchanged.

### Event and export semantics

`FoldStateProbe` owns the Codable event model, deduplication, deterministic text
formatting, and conversion to the shared schema-v1 `LabReport`. Unit tests cover
geometry/safe-area/size-class changes, unsupported vs waiting vs absent vs closed
hinges, angle units, forced checkpoints, journal restoration with lost State,
and exported event order/timestamp precision/JSON round-trip. These are
synthetic correctness tests, not physical device findings.

Each `duo-event` measurement has a sequential `count` value and a complete
snapshot in string tags. `timestamp` uses UTC with milliseconds; `reason` names
the callback or operator checkpoint. Rectangle tags end in `.xywh.pt`; inset
tags end in `.tlbr.pt`. Unsupported/missing hinge readings are `unavailable`,
never zero. `sceneID` is a UIKit session's persistent identifier, not proof that
the scene object instance survived. The State token detects view recreation.

The Lab screen persists `fold-state-working-journal.json` atomically in Documents after
each changed snapshot or explicit checkpoint, preserving earlier observations
if its view is recreated. **Start new run** clears that history and resets
both counters to zero, without changing the identity tokens. For the device
checklist, start a new run and increment once. **Write S7 report** snapshots the full journal through
`LabSession.export`; the shared footer then shares the resulting
`clove-lab-S7-<UTC timestamp>.json`. No folder selection is needed.

### Device findings — all pending part 2

| Device / OS | Check | Findings |
| --- | --- | --- |
| iPhone Duo / pending | Cover geometry, safe areas, size classes, hinge callback | **pending** |
| iPhone Duo / pending | Unfold: inner geometry and scene/State/SceneStorage continuity | **pending** |
| iPhone Duo / pending | Half-fold ≈90°: status/angle, safe-area behavior, hinge location | **pending** |
| iPhone Duo / pending | Rotate while half-folded: orientation and geometry | **pending** |
| iPhone Duo / pending | Fold back: cover and both counters/IDs | **pending** |
| iPhone Duo / pending | Export and returned JSON | **pending** |

## Conclusion

SDK 27.2 exposes public hinge **status and angle from iOS 27.1**, together with
reserved division/occlusion frames, system vertical toolbars, split arrangements,
and container margins. The original 27.0 runtime could not create Duo; the
separate 27.2 Duo build 24B91016s creates it, boots the OS, and runs a native
cover probe. Its startup progress-UI diagnostic is explained above.
Physical-device scene continuity and fold alignment remain device questions.
Navigation and selection must remain outside layout branches.

## Recommendation and options for G1

Recommended for consideration at G1: use measured available geometry for compact
vs expanded presentation; observe hinge status with the public API on iOS 27.1+
without relying on angle frequency or exact precision. Prefer actual safe
regions when supplied by the system. Keep folder/photo/filter/selection/group
position outside layout branches, with restorable identifiers; keep the write
queue and its durable status independent of views and SceneStorage. This is a
proposal for U1/P3/P4, not their implementation.

| Option | Minimum SDK / runtime | Cost and unresolved evidence |
| --- | --- | --- |
| System vertical bars, split arrangements, reserved regions and public hinge observation | Build SDK **27.2**; new layout and hinge declarations introduced **27.1**, runtime **27.1+**. Guard APIs to retain the existing **iOS 18** deployment target. | The system reports fold frames and owns bar placement and arrangement sizing. Physical-device evidence is still needed for fold alignment and scene continuity. |
| Geometry only | Existing iOS 18 baseline; `effectiveGeometry` is 16+, its coordinate space is 26+ with the older scene-coordinate-space fallback below 26. | Works on iOS 27.0 and older devices. Size classes and aspect ratio alone cannot establish posture or physical hinge location. Cannot certify the half-fold requirement from this spike. |
| Use the separate Duo simulator runtime | iOS **27.2 build 24B91016s**, runtime identifier `com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4`; creation, OS boot and native cover rendering verified on the Mini; the progress-UI diagnostic is explained above. | The general 24B8117 runtime excludes Duo. Device Hub supplies supported pose controls; a GUI session is needed to use them. |

Availability supports a theoretical minimum SDK of 27.1 for hinge symbols; only
**Xcode 27.2 / SDK 27.2 was compiled here**. No increase to the project's minimum
OS is needed for this guarded probe. An unguarded hinge implementation would
require iOS 27.1. Do not special-case a hardware identifier or hard-code a hinge
midpoint. No decision record or PRD change is made here.

## Open questions

- What iOS version is on the real Duo, and does its view hierarchy provide
  hinge callbacks? The 27.0 fallback cannot answer that.
- Does cover ↔ inner retain the scene session and State, recreate a view while
  restoring SceneStorage, or create a new scene? Compare IDs and counters in
  the returned JSON; a counter alone cannot distinguish these cases.
- On real hardware, do the reported division frames and margins align with the
  physical fold across poses? Use reserved regions and system arrangements;
  the original Lab probe's status/angle-only report cannot answer this.
- Repeat open/half-fold/screen-switch checks using Device Hub's pose controls.
  The compatible Duo runtime is installed; creation, OS boot and native cover
  rendering are verified on the Mini.

### Deferred device checklist (about 2–3 minutes)

Prepare: supervisor-provided Clove Lab TestFlight build on **iPhone Duo**; record
the iOS version. No cable, photo fixtures, external drive, or folder selection.
Start from a fresh Lab launch on the cover screen. All device results above
remain pending until this run is returned.

1. Open **Clove Lab → S7 · Fold state → Start new run**, then tap **Increment both counters**
   once. Expect both counters to read **1**. In **Record checkpoint**, choose
   **Cover**.
2. Unfold fully; choose **Unfolded**. Expect the live geometry/timestamp to
   update when geometry changes; check that both counters remain **1**.
3. Half-fold to about 90°; choose **Half-fold 90°**. On iOS 27.1+, inspect the
   reported status/angle if provided. Note if no hinge callback arrives. There
   is no rectangle overlay in this original status/angle-only Lab probe; the
   production layout APIs separately provide reserved-region frames.
4. Rotate while half-folded; choose **Rotated**. Expect interface orientation
   and/or available geometry to follow the supported orientation. Check both
   counters and note any visible controls crossing the physical hinge.
5. Fold back to the cover; choose **Folded back**. Expect cover geometry and
   both counters still at **1**; note any reset or disappearance.
6. Tap **Write S7 report**. Scroll to the screen's **Device report** footer; check the
   `clove-lab-S7-<UTC timestamp>.json` name and tap **Export**. Attach that JSON
   to **issue #18**, with iOS version and any visual mismatch. The same JSON
   is in Files → On My iPhone → Clove Lab. Do not send the working journal.
