# Clove privacy manifest audit

[`Clove/PrivacyInfo.xcprivacy`](../Clove/PrivacyInfo.xcprivacy) is copied into the
Clove app's resources by `project.yml`. Clove statically links CloveCore and
CloveImaging, so their required-reason API use is declared in the app manifest.
No tracking, tracking domains, or collected data are declared: the app has no
analytics or app-operated upload service, and grouping runs on-device. User-picked
Files providers can have their own network behavior.

Reason definitions come from Apple's
[required-reason API categories and approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

## Required-reason API use in Clove

Paths below are relative to the repository root. Tests and fixed sample dates are
not runtime API reads.

| Category / reason | API and source file | Purpose |
| --- | --- | --- |
| File timestamp / `3B52.1` | `contentModificationDateKey`, `contentModificationDate` in `Packages/CloveCore/Sources/CloveCore/PhotoFolderWalk.swift` | Read metadata in the folder the user selected while scanning photo sets. |
| File timestamp / `3B52.1` | `creationDateKey`, `contentModificationDateKey`, `creationDate`, `contentModificationDate` in `Packages/CloveImaging/Sources/CloveImaging/Metadata/MetadataReader.swift` | Fall back to file times for photo ordering when capture time is unavailable. |
| File timestamp / `3B52.1` | `contentModificationDateKey`, `contentModificationDate` in `Packages/CloveImaging/Sources/CloveImaging/Thumbnails/ThumbnailRequest.swift` | Detect changed source photos when requesting previews and image features. |
| File timestamp / `3B52.1` | `attributesOfItem(atPath:)`, `creationDateKey`, `creationDate` in `Packages/CloveCore/Sources/CloveCore/Moves/PhotoFileSystem.swift` | Check file size/existence for moves and renames; creation time supplies a rename date fallback. |
| File timestamp / `3B52.1`, `C617.1` | `attributesOfItem(atPath:)`, `FileAttributeKey.modificationDate` in `Packages/CloveCore/Sources/CloveCore/Writes/MarkWriteFileSystem.swift` | Read metadata for XMP writes in selected folders and standalone mark records in the app container. |
| File timestamp / `C617.1` | `contentModificationDateKey`, `contentModificationDate` in `Packages/CloveImaging/Sources/CloveImaging/Thumbnails/ThumbnailCache.swift` | Manage the app-owned thumbnail cache. |
| File timestamp / `C617.1` | `contentModificationDateKey`, `contentModificationDate` in `Packages/CloveImaging/Sources/CloveImaging/Features/ImageFeatureCache.swift` | Manage the app-owned image-feature cache. |
| User defaults / `CA92.1` | `UserDefaults` in `Packages/CloveCore/Sources/CloveCore/Settings/SettingsStorage.swift`, used by `Clove/Settings/SettingsStore.swift` | Read/write this app's settings, including remembered auto-advance choices. No shared app group or other apps' preferences. |
| System boot time / `35F9.1` | `ProcessInfo.processInfo.systemUptime` in `Clove/Detail/DetailZoomView.swift` | Measure elapsed time within a marking swipe to distinguish slow and quick gestures. No boot timestamp leaves the app. |

`3B52.1` permits metadata access for files/directories the user specifically granted
access to, including through a document picker. `C617.1` covers files in the app
container. `CA92.1` covers preferences accessible only to this app. `35F9.1` covers
elapsed time between events within the app.

`Clove/RootView.swift` also uses SwiftUI `@SceneStorage` for app-only browsing state;
`CA92.1` covers app-only preferences if the system backs this with user defaults.
No disk-space or active-keyboard APIs were found in Clove or its linked packages,
so those categories are absent. File sizes used to budget caches are not volume
capacity queries.

## Separate Clove Lab target

CloveLab links CloveLabKit, which Clove does not link. Its probe-only calls are
outside the Clove binary and this validation run; no Lab manifest is added here.
A Lab release needs its own audit, including these hits:

- File metadata: `PreviewProbe/PreviewMeasurement.swift`, `ScanProbe/ScanModels.swift`,
  `ScanProbe/ScanLister.swift` (`lstat`), and `XMPProbe/XMPSuite.swift`
  (`attributesOfItem`), under `Packages/CloveLabKit/Sources/`.
- Disk space: `FolderAccessProbe/AccessProbes.swift` (volume capacity keys),
  `ScanProbe/ScanTree.swift` (`statfs`), and `XMPProbe/XMPSuite.swift` (`fstatfs`),
  under `Packages/CloveLabKit/Sources/`. Disk capacity appears in exportable probe
  reports, so a Lab audit must check the optional-report conditions for `7D9E.1`.
- App-only scene state: `CloveLab/Probes/FoldState/FoldStateView.swift`.

## Validation

Follow [`release.md`](release.md) with `mise run release -- --app clove` (no upload).
Check that `Payload/Clove.app/PrivacyInfo.xcprivacy` in the exported IPA matches the
source manifest. Apple upload processing and Beta App Review are separate from
this validation-only command. External beta copy is in
[`testflight-external.md`](testflight-external.md).
