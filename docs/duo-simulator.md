# Unattended Duo checks on the Mini

The dedicated Mac must keep a graphical user session logged in and unlocked. Device Hub supplies
Closed, Partially Open and Open controls; the test helper operates those semantic
Accessibility controls for the simulator created by the test run. It does not use
screen coordinates, simulator metadata changes or app viewport overrides.

## One-time access

Run in the same launch context that will run tests:

```sh
scripts/duo-pose.sh --request-access
```

This opens **System Settings → Privacy & Security → Accessibility**. Enable the
responsible application's entry shown by macOS. On the Mini's T3 SSH service, the
TCC attribution was `com.apple.sshd-keygen-wrapper`, executable
`/usr/libexec/sshd-keygen-wrapper`. Its entry is **sshd-keygen-wrapper**; if absent,
use **+**, **⌘⇧G**, and that exact path. A different launch context can have a
different responsible application. The helper uses AX APIs directly and needs no
Automation/System Events grant.

Verify the grant and current GUI session:

```sh
scripts/duo-pose.sh --check-access
```

A logged-out or locked session, or a missing grant, fails promptly. The helper
reads the current WindowServer session state. It never unlocks the Mac, changes
locking or security settings, waits for a human, or enables automatic login.
The targeted test keeps a temporary `caffeinate` assertion during its run to
prevent idle display and system sleep. The assertion ends with that owned run.

## Expanded flow and captures

Install the Duo-specific iOS 27.2 runtime if needed:

```sh
xcodebuild -downloadPlatform iOS -buildVersion 24B91016s
```

After the existing build-for-testing products are available, one command creates
an owned device, selects it in Device Hub, sets Open, confirms its real inner
display, executes the flow and deletes that device on exit:

```sh
scripts/smoke.sh flows \
  -only-testing:CloveUITests/CloveFlowTests/testDuoGridFocusDockMarkAndPhotoOnly \
  -resultBundlePath .build/duo-expanded.xcresult
```

Use a fresh result-bundle path for each run; `xcodebuild` will not overwrite an
existing `.xcresult`. Choose another path or remove only your own previous bundle.

`CLOVE_SIM_RUNTIME` is honored. It must support iPhone Duo; the general 27.2 build
24B8117 excludes Duo. The targeted cover flow similarly selects Closed. Run the
Open and Closed flows separately. A skipped Duo test is a failure of this targeted command. The targeted Duo
commands reject an occupied Clove simulator slot. Other suites keep their existing
selection behavior. XCTest cloning remains disabled.

On a test-runner bootstrap retry, the runner keeps the first result bundle and
writes a new `.attempt-N.xcresult` bundle. Each attempt has a distinct owned name.

The expanded flow retains grid, 30/70 focus, photo-only, star-picker and label-picker
screenshots from the active inner display in the result bundle. Export them without committing the images:

```sh
xcrun xcresulttool export attachments \
  --path .build/duo-expanded.xcresult --output-path .build/duo-expanded-images
```

For focused pose checks during the same owned-device run, the helper also accepts:

```sh
scripts/duo-pose.sh --udid "$owned_udid" --name "$owned_name" --pose partially-open
scripts/duo-pose.sh --udid "$owned_udid" --name "$owned_name" --pose open
```

Both the UUID and exact unique `Clove ...` name must match a booted Duo. The helper
selects that UUID's sidebar row and requires its exact device window before
pressing a pose control. `--inspect` prints Device Hub's AX controls for diagnosing
an Xcode UI change. Other devices are not booted, shut down or deleted. `mise run lint` checks this
helper's Swift formatting and typechecks it on macOS. The executable cache is
rebuilt when its source, selected Xcode, Xcode build, or macOS build changes.
