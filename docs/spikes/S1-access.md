# S1 — Can folder access be remembered and restored reliably?

## Question

Can folder access be remembered and restored reliably? Part 1 of #12 supplies
reusable probes, local macOS/simulator observations, and the Clove Lab device
checklist. G1 remains open; physical-media results belong to part 2.

## What was tested

- Mac mini `Mac14,12`, macOS 27.0 (26A428), Xcode 27.2 (27B52), Swift 6.
  Local temporary folders on APFS, with a sentinel text file. **macOS numbers
  were taken on a shared, loaded host with other spike workers running.**
- A newly created iPhone 17 Pro simulator (`iPhone18,1`), iOS 27.0 (24A434),
  deleted after the run. The same local Foundation probes ran in a simulator
  command-line process. This process does **not** establish document-picker
  sandbox grants. Simulator storage is backed by the Mac's filesystem.
- Unit tests cover bookmark encode/resolve, refresh after a real rename,
  Recents persistence/corruption/schema checks, underlying-error classification,
  read-back and cleanup, bounded fill allocation, and missing-folder watch
  detection. The mapping test has 11 domain/code cases.
- Clove and CloveLab simulator builds and the repository smoke test are the
  app integration checks. A simulator CLI run is not a picker UI test.
- No photo fixtures were needed; the existing shared sets were present. Nothing
  was written into the fixture cache's `files/` directory.

Reports (untracked under `.build/s1/`; JSON is supplied on issue #12):

| Run | Report |
| --- | --- |
| macOS local | `mac/clove-lab-S1-20261108T165438Z.json` |
| simulator local, warm process | `sim/clove-lab-S1-20261108T165624Z.json` |
| simulator local, first process after boot | `sim/clove-lab-S1-20261108T165610Z.json` |

`S1LocalRunner.swift` in the S1 test folder is an opt-in executable, enabled with
`-D CLOVE_S1_LOCAL_RUNNER`. Compile `SpikeSupport`, then `SpikeS1Access`, as static
Swift modules, then link that runner against both. The targets used were
`arm64-apple-macos15.0` with the macOS SDK and
`arm64-apple-ios18.0-simulator` with the iPhoneSimulator SDK, using Swift 6 and
`-parse-as-library`. Its one argument is an existing report output directory.
The simulator executable runs with `xcrun simctl spawn <new-device> <executable>
<output-directory>`. Create a fresh simulator and delete it afterwards. It only
mutates its own UUID-named temporary directory, restoring permission bits before
cleanup. The first simulator run finished after the boot wrapper timed out;
a second invocation on that same owned simulator supplied the warm-process run.
Neither run is a physical-device timing benchmark.

A disposable 64 MiB exFAT image was created, but `hdiutil attach` returned
`Permission denied`. The replacement `diskutil image attach` did not complete
within 60 seconds. No exFAT volume was successfully mounted. A run that reached
the ordinary mount-point directory after the failed attach was discarded;
its data is not exFAT evidence. No full-volume measurement is claimed.

**Pending:** SD lock switch, external SSD unplug/reinsert, exFAT resource values,
full-volume failures, true iOS permission revocation, picker grants after force
quit/reboot, and replacement media with an identical volume label.

## Data

### Bookmark and identity behavior

Local CLI observations; both environments are outside the Lab app's picker grant.

| Operation | macOS | iOS simulator |
| --- | --- | --- |
| Default bookmark size | 1,152 bytes | 1,044 bytes |
| `.minimalBookmark` comparison size | 1,176 bytes | 1,068 bytes |
| Initial default/minimal resolution | Success, stale=false | Success, stale=false |
| Rename within the same local volume | Resolves new URL, stale=true | Resolves new URL, stale=true |
| Re-create stale bookmark after successful coordinated read | Success; unit test checks next resolve is not stale | Success |
| Independent Recents store reload in a new actor | 1 record | 1 record |
| Delete target, then resolve before recreation | Cocoa 4, no underlying error | Cocoa 4, no underlying error |
| Recreate a different folder at the bookmark's last resolved path | Resolves replacement, stale=true | Resolves replacement, stale=true |
| `startAccessingSecurityScopedResource` in these runs | true | true |
| Force quit / reboot / reinsert same card / another same-label card | Pending | Requires device; pending |

A stale bookmark is not an inaccessible bookmark. Conversely, successful
resolution is not proof that the target is the same folder or that a write can
succeed. The replacement-folder result is a reason to verify identity before a
production scan or write, particularly after media changes.

### Read/write and watch timings

One observation per condition, milliseconds, rounded to three decimals. No
percentiles or production performance claim can be derived from these samples.

| Measurement | macOS local | Simulator warm process | Simulator first process |
| --- | ---: | ---: | ---: |
| Baseline coordinated directory read | 2.955 | 316.078 | 10,443.439 |
| Write 31 bytes + read-back + remove | 1.655 | 172.361 | 147.435 |
| Read after rename | 2.088 | 95.633 | 48.070 |
| Unreachable since operator marker | 502.508 | 535.058 | 510.280 |
| Unreachable since last successful poll | 503.096 | 558.578 | 511.711 |
| Failing reachability call itself | 0.914 | 0.392 | 0.383 |
| Presenter callbacks for uncoordinated local directory deletion | 0 | 0 | 0 |

The runner marks, removes the folder, waits 500 ms, then polls once. These are
**local directory-deletion observation intervals**, not measured drive-unplug
latency. The large cold simulator read is retained because shared-host load and
Foundation/file-coordination startup are material limitations of this setup.

The Lab watch polls a fresh uncached URL every 500 ms **plus the call duration**.
It holds a balanced security scope and records last successful reachability,
first failure, the operator marker, and monotonic callback times. Presenter
change/move/deletion/eviction callbacks are independent observations, not proof
of disconnect. The presenter is removed and scope released on stop, leaving the
screen, or backgrounding. Calls may block in a provider; 500 ms is not a deadline.
There is no background-disconnect detection claim.

`NSWorkspace.didUnmountNotification` belongs to macOS AppKit, not public UIKit.
It cannot be the iOS mechanism. `NSFilePresenter` participates in coordinated
access and is useful for folder changes, but did not signal our uncoordinated
local deletion. The comparison on a real unplug remains pending. Missing-path
errors are classified as disconnect only with prior success on media marked
external **and** an unavailable volume-root check. Unknown volume roots or
provider errors remain inconclusive; a missing folder alone is not a disconnect.

### Resource hints

First baseline query in each report; byte counts are snapshots of a changing
shared host. Each key is queried separately, so an unsupported key does not
suppress the others. `unavailable (nil)` is distinct from false or zero.

| Key | macOS APFS | Simulator local | exFAT on device |
| --- | --- | --- | --- |
| `volumeName` | Macintosh HD | Data | Pending |
| `volumeUUIDString` | Present | Present (host volume UUID) | Pending |
| `volumeLocalizedFormatDescription` | APFS | nil | Pending |
| `volumeIsReadOnly` | false | false | Pending |
| `isWritable` | true | true | Pending |
| `volumeAvailableCapacity` | 44,988,370,944 | 44,137,209,856 | Pending |
| `volumeAvailableCapacityForImportantUsage` | 105,066,577,283 | 44,137,021,440 | Pending |
| `volumeAvailableCapacityForOpportunisticUsage` | 33,407,209,472 | 44,137,021,440 | Pending |
| `volumeTotalCapacity` | 494,384,795,648 | 494,384,795,648 | Pending |

Important-usage capacity can exceed immediate free bytes on APFS. None of these
keys reserves space. A permission hint cannot confirm a write. The Lab's explicit
small write creates a unique file in `clove-lab-s1/`, verifies its bytes, and
removes only that file. Failures during write or cleanup stay visible.

### Failure table and proposed PRD mapping

`Cocoa` means `NSCocoaErrorDomain`; `POSIX` means `NSPOSIXErrorDomain`.
Observed rows below occurred on **both** local CLI environments unless stated.
Numbers for pending hardware cases are test inputs/candidates, not observations.
The mapping implements the meanings in P0-02/P0-08 and “Failure and recovery”;
it does not approve copy or implement production save state.

| Situation / how caused | Exact observed error and underlying chain | When it appears | Proposed PRD row / status |
| --- | --- | --- | --- |
| Folder deleted | Cocoa 4; no underlying error | Bookmark resolve | Remembered location unavailable; observed |
| Folder removed after a successful read | Cocoa 260 → POSIX 2 (`ENOENT`) | Reachability poll; directory read unit test gives same chain | Remembered location unavailable; observed. For a confirmed unavailable external volume, use External drive disconnected during use |
| Unplugged physical drive | Pending; candidates Cocoa 260/4, POSIX 2/6/19; POSIX 5 alone remains unknown | Resolve/start-access/read/write must each be recorded | External drive disconnected during use only with session/volume evidence; pending |
| SD lock switch | Pending; candidates Cocoa 642 or POSIX 30 (`EROFS`) | Resource hints, first write | Read-only location or storage that does not permit writes; pending |
| Full dedicated volume | Pending; candidates Cocoa 640 or POSIX 28 (`ENOSPC`) | Create/write/synchronize/close or report export | Insufficient space; synthetic classifier tests only |
| Permissions removed with `chmod 000` | Cocoa 257 → POSIX 13 (`EACCES`) on read; Cocoa 513 → POSIX 13 on write | Directory read; create Lab subfolder | Lost folder permission; observed simulation, not proof of picker-grant revocation |
| True picker/provider permission revoked on iOS | Pending; candidates permission chain above or provider-specific error | Resolve/start-access/read/write | Lost folder permission when established; otherwise keep exact provider error and ask to reopen |
| Rename/move within local volume | No error, stale=true; refreshed successfully | Resolve followed by read | No failure copy; update bookmark/path. exFAT/provider behavior pending |
| Deleted then recreated at same resolved path | No error, stale=true; resolved replacement | Resolve/read | Identity ambiguity; do not interpret as “permission revoked” |
| Intentionally corrupt bookmark bytes | Cocoa 259; no underlying error | Resolve | Remembered location unavailable / select again; do not silently drop the Recent |
| Scope acquisition returns false | Not observed here; API has no NSError result | Start access | Record false and try the actual operation; an app-owned URL may work. Do not invent a permission NSError |
| Unknown provider error | No such observed device result; unit test preserves custom domain/code | Any phase | Retain exact diagnostic, offer reopen/retry; do not claim storage is full or read-only |

An NSError snapshot preserves domain, numeric code, localized description, and
`NSUnderlyingErrorKey` / `NSMultipleUnderlyingErrorsKey` recursively (bounded at
eight levels). Events carry UTC timestamps and the phase. The classifier checks
underlying errors before falling back to unknown; it does not infer a full or
read-only volume from a generic failed write. EACCES/EPERM express access denial,
which can have several causes. A generic marks-write failure, partial batch
failure, partial move failure, and leaving with unfinished writes still require
C4/C6/U7's per-item state; S1 alone cannot choose their counts or claim Saved.

### Bookmark and Lab Recents approach

- Folder selection uses the shared `UIDocumentPickerViewController` in folder
  mode with `asCopy: false`. Begin access before bookmark creation and always
  stop a successfully acquired scope. A watch holds its own scope until stopped.
- Use default bookmark creation options for the part-1 candidate and compare
  `.minimalBookmark` on each pick. The size results do not justify a space-saving
  claim for minimal bookmarks. `.withSecurityScope` and the corresponding resolve
  option are unavailable on iOS in the installed SDK; do not use macOS-only flags
  as an iOS fix. Implicit-scope/reboot behavior must be checked on device.
- Resolve with `.withoutUI`, `.withoutMounting`, and
  `.withoutImplicitStartAccessing`. Explicitly acquire/release access to the
  returned URL. Capture `bookmarkDataIsStale`; re-create stale data while scope is
  held, only after a real read succeeds. Preserve the Recent's ID and photo count.
- Store a versioned Codable envelope atomically at app-private Application
  Support `CloveLab/S1/recents-v1.json`: UUID, bookmark bytes, path summary, volume
  name and UUID when available, operator-selected media type, optional photo
  count, and last successful open time. The bookmark is Data (base64 in JSON).
  S1 does not scan photos, so photo count stays nil. C2 would supply it to C11.
  This does not use or implement production Recents.
- Volume names are display text. Lab deduplicates by path only when a nonnil
  volume UUID also matches; it retains ambiguity when UUID is unavailable.
  Production should compare volume UUID plus a suitable file identity when
  available, and request explicit re-selection on mismatch. A same-label card
  must not inherit a different card's write session. The local replacement-folder
  result shows why stale=false/true or path equality alone cannot settle identity.
- Failed reads do not update last-opened time or discard a Recent. Corrupt storage
  is reported and not overwritten. There is no cloud/Keychain dependency or photo
  import. Production persistence/protection/backup choices remain a C11 decision.
- Lab export first secures a Documents copy through the shared exporter/footer,
  then attempts the tested-folder copy through the same exporter. A full,
  unplugged, or protected target records the exact export error and retains a
  Documents report. Export before force quit/reboot: event logs are in memory,
  while Recents persist. Reports contain paths; review them before sharing.

API availability and behavior were checked against Xcode 27.2's installed
Foundation `NSURL.h` and `NSFilePresenter.h`, including the scope-balancing and
background-presenter-removal requirements. Reference API pages:
[bookmark creation](https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions),
[bookmark resolution](https://developer.apple.com/documentation/foundation/nsurl/bookmarkresolutionoptions),
[file presenters](https://developer.apple.com/documentation/foundation/nsfilepresenter),
[macOS unmount notification](https://developer.apple.com/documentation/appkit/nsworkspace/didunmountnotification).

## Conclusion

Local macOS and simulator data support persisting bookmarks, resolving renamed
folders, and refreshing stale data after a successful read. They also demonstrate
that a replacement directory can resolve from an old bookmark. Picker-grant
persistence, actual exFAT behavior, and physical disconnect timing are inconclusive
until part 2. Read-only and capacity keys are advisory; confirmed write/read-back
and exact per-operation errors remain necessary for P0-08.

## Recommendation and options for G1

**Recommendation, pending device evidence:** use the versioned bookmark record
approach for C11, explicit scope lifetimes and coordinated I/O for C2/C4, and
foreground 500 ms reachability polling as the baseline for disconnect observation.
Add presenter callbacks for changes/early hints and validate the volume/identity
before calling a missing path a disconnected drive. Refresh hints on reopen;
stop trusting a previously successful write as soon as a later write fails.
A provisional engineering target is an unavailable-location indication within
one second of a disconnect while active, subject to measured provider call
latency on hardware; this is not a PRD promise or a G1 decision.

Options for the product owner:

1. Default bookmark data + identity checks + polling/presenters. Best supported by
   local observations, but wakeup cost, provider blocking, and reboot persistence
   need device data before acceptance.
2. Minimal bookmark data with the same recovery flow. Simple iOS-compatible API,
   but no demonstrated size advantage here; requires the same full device matrix
   before preferring it over default data.
3. Presenters only. Avoids periodic polling, but our uncoordinated local deletion
   produced no callback. Reject as the sole detector unless device results supply
   a reliable guarantee; polling can be adapted after measuring energy/latency.
4. Re-select every time. Removes persistent-grant ambiguity but fails P0-02's
   one-tap Recents requirement. This would require a product-owner PRD decision;
   it is not adopted by this spike.

No decision record or production code is changed. G1 stays open.

## Open questions

- Do default and minimal picker bookmarks retain the grant after force quit,
  reboot, unplug/reinsert, and same-label replacement on the supported iPhone and
  iPad? The device checklist supplies the missing evidence.
- Which values are nil or misleading on exFAT, SD lock-switch readers, and Files
  providers? Does the reader honor the lock switch at all?
- How can a true iOS picker grant be revoked reproducibly? Delete/recreate is an
  identity test, not proven grant revocation. There is no claim that Location &
  Privacy resets revoke document-picker access. Provider account/location removal
  may offer another test, but is not automated or required for part 1.
- Are presenter callbacks useful for a physical unplug, and does volume-root
  reachability reliably distinguish folder loss from media loss? A provider may
  keep a stub reachable; exact errors and recovery behavior take precedence.
- Should C11 refuse all folder/volume identity ambiguities, and what fallback is
  acceptable when the provider has no UUID/file ID? Product owner decides at G1.

### Device checklist (part 2)

Repeat on the product owner's iPhone 17 Pro Max and iPad Pro, recording the actual
model and iOS version. Use the supervisor's merged Clove Lab TestFlight build.
Needed: an SD card with a lock switch and a reader that honors it, an external
SSD, and a **disposable small card/partition** (ideally 64–256 MiB) for the full
case. Use dedicated empty `S1-test` folders. Do not fill a normal photo card or
the device's internal storage. A second same-label card is needed only for that
replacement test; if unavailable, mark the step pending.

1. Open **Clove Lab → S1**. With no external media, choose media **local** and
   **Choose folder**. In Files, create/select an empty `S1-test` folder under
   **On My iPhone/iPad**. Set the scenario text to `local baseline`.
   Tap **Read + capacity + read-only hints**, then **Write small file + read back
   + remove**. Expect read success, an explicit write/read-back confirmation, and
   cleanup success. A false/nil hint must be visible as such, not a write success.
2. Tap **Export S1 report**. Note the on-screen `clove-lab-S1-<timestamp>.json`
   name. Return to the Lab home and use the footer's share/export control to save
   or send that JSON. Reports also appear in Files under **On My iPhone/iPad →
   Clove Lab**. Export after each following case so app restarts cannot lose logs.
3. Force quit Clove Lab from the app switcher; reopen **S1** and tap the saved
   local Recent. Expect a resolve event, a scope result, and a successful read.
   Run the write probe and export. Reboot the device, repeat, and export again.
   Record any mismatch; a preserved row alone does not prove usable access.
4. Connect the external SSD. Choose media **externalSSD**, select its dedicated
   `S1-test` folder, label the scenario with the drive label/filesystem, run both
   probes, and export. Repeat force quit and reboot with this drive connected,
   reopening its Recent and exporting after each.
5. On the SSD, tap **Start disconnect watch**, then **Mark: unplug now**, and
   immediately unplug **only the test SSD**. Expect a timestamped poll failure or
   clearly recorded lack of detection. Wait up to ten seconds, tap **Stop watch**,
   and export. The Documents JSON must remain available even if copying it to
   the SSD fails. Tell us roughly how long after the marker you physically pulled
   the cable, and whether any file-presenter callbacks appeared. Repeat three
   short trials after reconnecting/reopening; export each trial.
6. With the SSD absent, tap its Recent. Expect an explicit resolve/read failure
   with domain/code, or record if the provider leaves a reachable stub. Export.
   Reconnect the same SSD; reopen the Recent, run both probes, and export.
   If it fails, select the same folder again through **Choose folder**, test, and
   export the recovery. Do not silently substitute another folder.
7. Connect the **unlocked SD card**. Choose **sdCard**, select its `S1-test`
   folder, set the scenario to `SD unlocked` plus its label/filesystem, run both
   probes, and export. Force quit and reopen its Recent; export. Reboot with it
   connected, reopen its Recent again, and export.
8. Repeat the watch/unplug trial for the SD card three times using step 5.
   Reinsert the same card, reopen its Recent, run both probes, and export.
9. Eject/remove the SD card, slide its **physical lock switch** to locked, and
   reconnect. Reopen/select `S1-test`; label the scenario `SD locked`.
   Run both probes and export. Reads should work if the reader honors the lock;
   write failures must show an exact error, never write/read-back confirmation.
   Record both read-only/writable hints even if they disagree. If writing succeeds,
   report that the reader did not enforce the lock rather than calling this a pass.
   Remove/unlock/reinsert, rerun the write probe, and export recovery.
10. If a spare card is available, give it the **same volume name** on a computer,
    but put a visibly different sentinel file in its `S1-test` folder. After saving
    a Recent for the first card, remove it and insert the second card. Tap the first
    card's Recent and use **Read + capacity + read-only hints** only. Export and
    report whether it fails, resolves the replacement, or needs selection. Compare
    reported volume UUIDs. Do not run a write probe until explicitly selecting the
    second card. If no spare card is available, mark this case pending.
11. On a disposable local test folder, save a Recent and export. Leave S1, then use
    Files to rename that folder and move it within the same storage location.
    Return to S1 and reopen the existing Recent. Expect the resolved path and
    `stale` result in the log. If a read succeeds with stale=true, expect
    **Re-created stale bookmark**. Run both probes and export. Repeat on exFAT SD.
12. For the lost-folder/permission attempt, save/export a Recent for a **dedicated
    empty test folder**. Leave S1, delete only that test folder in Files, then
    return and tap its Recent. Export the failure. Recreate a folder with the same
    name/path in Files, tap the original Recent again, run the read probe, and
    export. Record whether it resolves the replacement. This tests identity loss;
    it does not by itself prove that a sandbox grant was revoked. Recovery is to
    choose the folder again. If you already use a removable Files provider and can
    safely disable/re-enable its location in Files, optionally repeat while it is
    disabled, describing exactly what you changed. Do not reset privacy settings
    or change an account for this test. True grant revocation stays pending if it
    cannot be induced on the available device.
13. Connect the **disposable small test card/partition**. Choose its empty test
    folder with the correct media type. Run both probes and export a baseline.
    Tap **Add up to 256 MiB fill file… → Add fill file**. Each tap writes real
    bytes only into `clove-lab-s1/fill-s1-<UUID>.bin`; it stops at 256 MiB or an
    error. Repeat only on the small test volume until an insufficient-space error
    appears. Stop adding at the first error.
14. With the volume full, run both probes. Capture capacity hints, exact
    create/write/synchronize errors, and whether the small write still fits.
    A fill failure alone need not make a 31-byte write fail. Export; a tested-folder
    export failure is expected if there is no room, but the Documents report and
    footer must work. Retain the error report before cleanup.
15. Tap **Delete S1 fill files… → Delete S1 fill files**. Expect per-file cleanup
    events; other files stay. Run both probes again and export the recovered
    capacity/write result. If a cleanup fails, remove only the named S1 fill files
    using Files or a computer, then rerun/export recovery.
16. Export the final S1 report, note its on-screen filename, and **attach the JSON
    file to issue #12**. Attach the earlier per-case JSON files too, with a short
    list of media labels/filesystems, device/iOS versions, reader model, any steps
    skipped, and any behavior that differed from the expectations. Use the Lab
    home footer's share/export control or the Documents copies in Files.
