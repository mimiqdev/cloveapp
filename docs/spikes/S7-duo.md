# S7 — How does the system expose Duo fold state?

## Question

How does the system expose Duo fold state? On the Duo, confirm how the hinge
position, fold posture, and window size changes are reported, and whether the
scene survives switching between cover and inner screens. Output: Duo adaptation
approach and required minimum SDK.

This is **part 1 of #18**. The Duo device session is deferred. This report does
not establish physical hinge avoidance or cover ↔ inner continuity, and leaves
G1's choice open. Production layouts P3/P4 are outside this spike.

## What was tested

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

The framework-wide search found hinge-observation APIs in UIKit and SwiftUICore;
no additional public fold/posture framework or hinge rectangle was found.
CoreMotion attitude is not a hinge angle. Neither documented API provides a
physical hinge rectangle, so there is **no reported rectangle to draw**. The
probe says so explicitly rather than drawing an assumed center seam. That
leaves physical hinge exclusion an open device question.

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

SDK 27.2 exposes public hinge **status and angle from iOS 27.1**, in both UIKit
and SwiftUI. It does not expose a hinge rectangle. The installed 27.0 runtime
cannot create the Duo simulator, so neither Duo scene continuity nor physical
hinge exclusion is settled in part 1. Geometry adaptation and explicit state
restoration remain necessary regardless of hinge API availability.

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
| Geometry plus public hinge observation (recommended, pending device data) | Verified build SDK **27.2**; hinge declarations introduced **27.1**, runtime **27.1+**. Guard APIs to retain the existing **iOS 18** deployment target. | Best available posture signal; no public rectangle. Need device evidence of safe-region behavior and a reliable exclusion strategy before promising half-fold controls avoid the hinge. |
| Geometry only | Existing iOS 18 baseline; `effectiveGeometry` is 16+, its coordinate space is 26+ with the older scene-coordinate-space fallback below 26. | Works on iOS 27.0 and older devices. Size classes and aspect ratio alone cannot establish posture or physical hinge location. Cannot certify the half-fold requirement from this spike. |
| Require a newer Duo runtime/SDK before completing P3 | Exact compatible simulator runtime remains unverified; hinge minimum runtime is 27.1. | Enables direct hinge testing, but a newer OS does not imply a rectangle API. Re-run part 2 first; any scope or support-policy change belongs to G1/product owner. |

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
- Does half-folding give safe regions that let P3 keep all controls clear of
  the physical hinge? There is no rectangle in the inspected API. If the
  device supplies neither safe regions nor another documented mechanism,
  bring that evidence to G1 before declaring P0-14 feasible or changing it.
- A compatible Duo simulator runtime is needed to repeat fold/screen-switch
  automation. Installing it is not part of this worker's brief.

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
   is no rectangle overlay because the public API reports no rectangle.
4. Rotate while half-folded; choose **Rotated**. Expect interface orientation
   and/or available geometry to follow the supported orientation. Check both
   counters and note any visible controls crossing the physical hinge.
5. Fold back to the cover; choose **Folded back**. Expect cover geometry and
   both counters still at **1**; note any reset or disappearance.
6. Tap **Write S7 report**. Scroll to the screen's **Device report** footer; check the
   `clove-lab-S7-<UTC timestamp>.json` name and tap **Export**. Attach that JSON
   to **issue #18**, with iOS version and any visual mismatch. The same JSON
   is in Files → On My iPhone → Clove Lab. Do not send the working journal.
