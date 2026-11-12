# Duo simulator checks

## Headless cover flow

A Duo simulator boots in the **Closed** pose with no GUI involvement: the cover
display (466×678 pt, compact) is the active display from `simctl boot` alone,
on any freshly created device. The cover flow therefore needs no Device Hub
interaction, no Accessibility grant, and no unlocked graphical session — it runs
on a locked or headless build-server Mac.

After the existing build-for-testing products are available, one command creates
an owned device, runs the cover flow on the real cover display, and deletes the
device on exit:

```sh
scripts/smoke.sh flows \
  -only-testing:CloveUITests/CloveFlowTests/testDuoCoverToolbarMarkAndPickers \
  -resultBundlePath .build/duo-cover.xcresult
```

Use a fresh result-bundle path for each invocation; `xcodebuild` will not
overwrite an existing `.xcresult`. On a test-runner bootstrap retry the runner
keeps the first bundle and writes `.attempt-N.xcresult` bundles for later
attempts, so retries within one invocation never collide with an existing
bundle.

`CLOVE_SIM_RUNTIME` is honored. It must support iPhone Duo; the general 27.2
build 24B8117 excludes Duo. Install the Duo-capable runtime once with:

```sh
xcodebuild -downloadPlatform iOS -buildVersion 24B91016s
```

These guarantees are scoped to the exact spelling above. A class-level
`-only-testing:CloveUITests/CloveFlowTests` run or a plain `flows` run creates
no Duo device and checks no slot; the Duo tests then skip in those runs, which
is the pre-existing baseline for full-suite runs. For this targeted command,
the occupied-slot check (no other `Clove …` simulator may be booted) and the
skip-is-failure check (the flow must report `passed`, not `skipped`) are both
enforced; XCTest cloning remains disabled.

The cover flow retains cover, stars and labels screenshots from the active
cover display in the result bundle. Export them without committing the images:

```sh
xcrun xcresulttool export attachments \
  --path .build/duo-cover.xcresult --output-path .build/duo-cover-images
```

## Expanded flow: a hard GUI constraint

The **Open** pose has **no headless lever**. There is no `simctl` verb for
pose, no device or runtime preference that presets it, and `simctl io
screenConfig` only controls framebuffer power and geometry — powering the
cover display off does not switch the OS to the inner display. The pose
control exists only in Xcode's Device Hub window.

Because of that, `scripts/smoke.sh` refuses the targeted expanded spelling
(`-only-testing:…/testDuoGridFocusDockMarkAndPhotoOnly`) instead of silently
skipping. To run the expanded flow at all, a human must use Device Hub on a Mac
with an unlocked, logged-in graphical session:

1. Boot the owned Duo (the runner prints its name on creation), or any Duo.
2. In Device Hub, select the device and set **Open**.
3. Run the expanded test against that device, or use `scripts/duo-pose.sh
   --udid <udid> --name '<exact device name>' --pose open` to press the Open
   control through Accessibility.

This is the only supported path for the expanded flow. Automation that requires
an unlocked GUI session is not suitable for the build-server Mini, which is why
the headless runner does not attempt it.

## Device Hub helper (manual and diagnostic use)

`scripts/duo-pose.sh` operates Device Hub's semantic Accessibility controls for
a supplied owned Duo. It is a **manual and diagnostic aid** for the expanded
flow and for pose experiments — not part of any automated gate, because macOS
serves Accessibility only to apps in an unlocked graphical session.

It needs a one-time grant; run in the launch context that will use it:

```sh
scripts/duo-pose.sh --request-access
```

This opens **System Settings → Privacy & Security → Accessibility**. On the
Mini's T3 SSH service the TCC attribution was `com.apple.sshd-keygen-wrapper`;
its entry is **sshd-keygen-wrapper** (if absent, use **+**, **⌘⇧G**, and
`/usr/libexec/sshd-keygen-wrapper`). A different launch context can have a
different responsible application.

Verify the grant and current GUI session:

```sh
scripts/duo-pose.sh --check-access
```

A logged-out or locked session, or a missing grant, fails promptly. The helper
reads the current WindowServer session state and never unlocks the Mac, changes
locking or security settings, waits for a human, or enables automatic login.
`--inspect` prints Device Hub's AX controls for diagnosing an Xcode UI change.
Both the UUID and exact unique `Clove …` name must match a booted Duo; other
devices are never booted, shut down or deleted.

`mise run lint` checks this helper's Swift formatting and typechecks it on
macOS. The executable cache is rebuilt when its source, selected Xcode, Xcode
build, or macOS build changes.
