# Duo layout captures

These are simulator captures of the synthetic library, taken by
`CloveFlowTests.testCaptureDuoLayoutsWhenRequested` with
`CLOVE_CAPTURE_DUO=1` in the test runner's environment. No photo files or owner
folders are involved.

The installed iOS 27.0 runtime (24A434) still rejects the listed iPhone Duo device
type with SimError 403, incompatible device. Expanded captures use a disposable
iPhone 17 Pro simulator and the debug-only `CLOVE_TEST_DUO_VIEWPORT=expanded`
sample-library setting: a 900 × 690 pt logical viewport with regular size classes,
scaled into the supported phone's screen. Phone idiom and the production browsing,
preview, marking and dock code remain in use. The simulator also rejected a native
display-mode change to the expanded geometry.

The cover capture uses the same supported phone with the sample-library cover
setting. The ordinary iPhone and iPad captures use no Duo override. The iPad is an
11-inch iPad Pro (M4). Each capture simulator was named `Clove duo <PID>` and deleted
after capture; no simulator runs overlapped. The Simulator GUI application is absent on
this host, so captures come from its booted simulator's rendered app surface via
XCTest screenshots.

Expanded images are rotated to landscape and cropped to remove the surrounding
unused phone window margins. Cover, iPhone and iPad images retain their full
screen. The images use generated sample tiles; the handoff uses landscape
placeholders. Device bezels and the handoff's drawn system status area are not app
chrome. Actual Duo status-area alignment, safe areas and hinge callbacks require
the device checklist in the PR.

| Capture | Handoff frame |
| --- | --- |
| [Grid](grid.png) | [Expanded grid](../../../design/handoff/screens/08-duo-expanded-grid-default-full-width.png) |
| [Focus](focus.png) | [30/70](../../../design/handoff/screens/08-duo-expanded-photo-focus-30-70.png) |
| [Photo only](photo-only.png) | [Photo only](../../../design/handoff/screens/08-duo-expanded-photo-only.png) |
| [Star bar](stars.png) | [Dock star bar](../../../design/handoff/screens/08-duo-expanded-dock-star-bar-sliding.png) |
| [Label picker](labels.png) | [Dock label picker](../../../design/handoff/screens/08-duo-expanded-dock-label-picker.png) |
| [Cover](cover.png) | [Cover](../../../design/handoff/screens/08-duo-cover-folded-outer-screen.png) |
| [iPad spot check](ipad.png) | [iPad grid](../../../design/handoff/screens/06-ipad-grid.png) |
| [iPhone spot check](iphone.png) | [iPhone grid](../../../design/handoff/screens/02-grid-default.png) |
