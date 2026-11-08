# Clove launch PRD (pending review)

[简体中文](PRD.zh-CN.md) · [Notion source](https://app.notion.com/p/41237873fb548107bd96d0f6838b1200)

Status: pending review. This document defines product scope and acceptance criteria. It is neither implementation authorization nor an architecture proposal.

Visual source: [Culling UI — Native (canonical)](https://www.figma.com/design/qhGhxv3eRImQTXe3yzOD2G?node-id=33-2). Uxie has prepared light and dark designs for iPhone, iPad, and iPhone Duo. Tony is reviewing them separately. No approval record has been found, so this document does not treat the visuals as approved.

Sources: [2026-11-08 siftapp product positioning: pure culling, benchmarked against PhotoPicker App](https://app.notion.com/p/41237873fb5481bc9a28c2681f42a322), [2026-11-08 siftapp culling main-flow UI](https://app.notion.com/p/41237873fb5481c9bd5afcf26ae0a296), and [engineering research conclusions](https://app.notion.com/p/41237873fb548107bd96d0f6838b1200). Existing Notion pages still use siftapp. This document uses Clove as its replacement name.

---

## Product in one sentence

Clove is an in-place photo-culling app for photographers on iPhone, iPad, and iPhone Duo. Browse and mark photos in folders on SD cards, external drives, or Files. Ratings, Pick, Reject, and color labels go only into XMP sidecars. Originals stay unchanged. Continue in Lightroom, Capture One, or Photo Mechanic at home.

Clove is not a photo-library manager, cloud backup service, social app, or color editor. Its reference product is the third-party [AI Photo Culling — PhotoPicker](https://apps.apple.com/us/app/ai-photo-culling-photopicker/id661470243), not the system photo picker.

Priority: a good manual-culling experience and correct XMP writes come before AI accuracy. AI can be disabled.

## Users and jobs

Target users are photographers who want to finish a first pass while away or on the journey home. Their photos are on SD cards, external SSDs, or folders accessible through Files. They need to browse, inspect focus, and leave marks that desktop software can read.

Main jobs:

1. Open or reopen a folder without importing photos into the app or system photo library.
2. Browse the grid and open a large preview when focus needs inspection.
3. Apply ratings, Pick, Reject, or color labels. Write these marks only to XMP.
4. Review similar-photo groups and low-quality or blur suggestions, then decide whether to apply them. Suggestions must not change existing manual marks.
5. Read the same marks in Lightroom, Capture One, or Photo Mechanic and continue editing.

## Main flow

Open a folder or reopen it from Recents → browse and filter the grid → inspect focus and navigate photos in detail → rate, Pick, Reject, or label and write XMP → optionally review smart groups and apply suggestions → leave and reopen with marks intact and originals unchanged.

## Required for launch (P0)

| ID | Requirement |
| --- | --- |
| P0-01 | Use the system folder picker to open folders on SD readers, external drives, or Files. Scan JPEG, HEIC, and common RAW files the system can preview. Do not copy photos into an app-owned library. |
| P0-02 | Remember recent locations. Show a path summary, media type, photo count, and last-opened time. Reopen with one tap. If a location is unavailable, explicitly ask the user to select it again rather than failing silently. |
| P0-03 | Provide a scrollable grid. Prefer embedded previews in files for thumbnails. Smooth scrolling takes priority over immediately decoding full RAW images. |
| P0-04 | Detail provides a full-width preview, pinch zoom for focus inspection, previous and next navigation, and always-visible current marks. |
| P0-05 | Support ratings from 0 to 5, mutually exclusive Pick, Unmarked, and Reject states, and color labels. Write only XMP, never originals. Reject does not delete the original. |
| P0-06 | Read existing XMP when opening a folder and write changes back to sidecars. Preserve unknown information written by other apps as far as possible. Lightroom, Capture One, and Photo Mechanic must read Clove's ratings, flags, and labels. |
| P0-07 | Save status is always visible and matches disk state. Show Saved only after a confirmed successful write. Allow retries after failure. Never report a failed write as successful. |
| P0-08 | Long-press the grid to enter multi-select and write XMP in batches. |
| P0-09 | Analyze smart groups automatically when a folder opens and always offer Run again. Results are suggestions. Write XMP only when the user applies a suggestion. Never overwrite manual marks. AI can be disabled. Hide AI entry points below iOS 18 while keeping the main flow available. |
| P0-10 | Deliver the single-photo culling flow on both iPhone and iPad. Two-photo comparison on iPad is not in launch scope. |
| P0-11 | Include iPhone Duo at launch. Use a compact cover-screen layout. Default to a split grid and detail view on the inner screen. Design Overlay too, but not as the default. Controls must not cross the hinge when half-folded. Preserve the folder, current photo, filters, selection, and write status across folding, unfolding, and window resizing. |
| P0-12 | Use system components with light and dark appearances that follow the system. Pick and ratings use system orange. Reject uses system red. Color labels follow Lightroom color meanings. |

## Explicitly out of launch scope

- The system photo library as the main workspace, or temporary photo-picking sessions without XMP writes
- Writing favorites or marks back to the system photo library
- Album management, keyword management, cloud backup, CloudKit, or backup and sync wizards
- Social features or sharing feeds
- Opening or writing Lightroom Classic catalogs
- App-owned catalogs, or copying selected photos and XMP into a new folder. The latter may be a later priority, but is not in launch scope.
- Deleting originals, exporting finished photos, or a video-first workflow
- Two-photo comparison, which is deferred
- Color editing or autofocus-point overlays
- Natural-language culling, online cloud AI, or one-click AI overwrites of existing ratings or labels
- Custom RAW decoding or demosaicing

The Figma smart-groups screen contains a sample Manual group row. The product decision does not include user-created groups at launch. They are not P0 requirements here.

## Screens and states

The behavior below follows the product and UI conclusions. The current Figma page, `Culling UI — Native (canonical)`, contains 20 light and dark frames: iPhone entry, grid, detail, and smart groups; iPad grid with sidebar and detail with a right-hand marking rail; Duo compact cover, default inner Split, half-fold, and nondefault Overlay. The designs are not approved visuals.

### Entry: Open and Recents

- The primary action is Open folder…, through Files, SD cards, or external drives.
- Recents shows a path summary, media type, count, and last-opened time. Tap an item to reopen its remembered location.
- Do not make the system photo library the primary launch entry.
- The design contains a search field. Searching Recents has not been separately confirmed and is not P0.

### Grid

- iPhone uses three columns. iPad uses five columns with a left sidebar for navigation and filters.
- Cells overlay Pick or Reject flags, ratings, and color dots. Similar groups use a blue outline and count. Low-quality or blurred photos use less prominent badges.
- Top filters are All, Pick, Reject, and 3 stars or higher. Unmarked can follow later and does not block launch.
- Open detail or smart groups from the grid, through Similar groups N in the top bar or its equivalent entry.
- Long-press to enter multi-select, then write XMP in batches.

### Detail and marking

- Provide a full-width preview and pinch zoom for focus inspection. Tap the left or right edge for the previous or next photo, including while zoomed.
- Current marks must be immediately visible and not hidden by the user's hand. Detail uses a top marking HUD for ratings, Pick or Reject, and labels. iPad uses a right-hand marking rail. This avoids the competitor issue where the hand obscures bottom-bar state.
- A filmstrip identifies the current photo and supports horizontal navigation.
- The design also contains information such as filenames. The exact shooting metadata to display is undecided and not P0.

Marking rules:

| Control | Behavior |
| --- | --- |
| Rating from 0 to 5 | Tap a rating. Tap the same rating again to clear it. |
| Pick, Unmarked, Reject | Mutually exclusive. Reject does not delete the original. |
| Color label | Red, orange, yellow, green, blue, purple, and Clear. Use fixed English Lightroom names in XMP, regardless of system language. The specified names are Red, Yellow, Green, Blue, and Purple. The English name for orange must be checked against Lightroom's actual field. This document does not invent one. |
| Save status | Writing…, Saved, or Write failed. Offer Retry after failure. Show Saved only after confirmed success. |

### Batch writes with multi-select

Long-press the grid to select multiple photos, then apply ratings, Pick, Reject, or labels in one operation. Count successes and failures per photo. On partial success, keep successful writes saved and failed writes unsaved. Allow retrying only the failed items.

### Gestures and keyboard

Default gestures can be changed in Settings:

- Swipe up for Pick and down for Reject.
- Swipe left or right, or tap an edge, for the previous or next photo. Separate marking and navigation gesture areas to reduce accidental actions.
- Pinch to inspect focus. Edge-tap navigation remains available while zoomed.

Recommended launch settings, for which reasonable defaults are sufficient:

- Whether marking automatically advances to the next photo
- Gesture mapping for flags, ratings, or disabling gestures

External keyboard support prioritizes iPad and also works on an iPhone with a keyboard: `0` through `5` set ratings, Up sets Pick, Down sets Reject, and Left and Right navigate. Color-label shortcuts are not fixed for launch.

### Smart groups

- Analyze automatically after opening a folder. Show progress or Analyzed.
- Run again is always available.
- Present similar photos as group cards and identify a suggested best photo. Write XMP only after Apply suggestion.
- Present low-quality and blur findings as suggestions in a list. Users may ignore them or manually reject photos. The app must not automatically reject them.
- Never overwrite existing ratings, Pick, Reject, or color labels. Do not provide an enabled-by-default overwrite-existing-marks option.
- Users can disable AI. Hide its entry points while preserving opening, browsing, and manual marking.
- Hide AI entry points below iOS 18. Keep the main flow available.

Launch smart groups cover similar photos, using feature distance to find burst-like duplicates, and low-quality or blur suggestions. Closed-eye and expression analysis are out of scope. There is no promise of one-click AI culling equivalent to competitors, or any numeric AI accuracy commitment.

### iPhone, iPad, and iPhone Duo

| Device | Launch behavior |
| --- | --- |
| Single-screen iPhone | Three-column grid. Focus inspection and marking on a single detail screen. |
| iPad | Five-column grid with left sidebar. Detail uses a right-hand marking rail. No two-photo comparison at launch, but the single-photo flow must work end to end. |
| iPhone Duo cover | Compact entry or three-column grid, followed by detail. Do not create a separate information structure. |
| iPhone Duo inner | Expand for the available space. Default to simultaneous grid and detail, side by side when wide and stacked when tall. Overlay must work but is not the default after opening a folder. |
| iPhone Duo half-fold | Put grid and detail on separate sides. Filters, marking controls, and the bottom bar must stay on one side and not cross the hinge. Prefer an even number of grid columns so the grid can divide evenly. |

Moving from cover to inner screen, half-folding, or resizing must preserve the folder, current photo, filters, multi-selection, and visible write status.

## How marks reach disk

XMP sidecars on disk are the source of truth for persisted marks. Saved means the write has actually completed on disk.

1. Read existing XMP before displaying ratings, flags, and labels when a folder opens.
2. Write only XMP sidecars, not original image contents.
3. Write smart-group suggestions only after the user applies them. Analysis results alone are not saved marks.
4. Treat a specific change to a specific photo as saved only after confirmed success. Pending, failed, or unconfirmed writes must not show Saved.
5. Retain the user's requested marks after a write failure so they can retry. Do not treat them as saved before a successful retry.
6. Preserve existing information that Clove does not recognize as far as possible. Writing a rating must not discard other software's data.
7. Write fixed English Lightroom label names to XMP, independent of interface language.

### Failure and recovery

The following user-facing strings are proposals, not approved copy. Their meanings must stay accurate. Read-only storage and insufficient space need separate explanations. Counts are placeholders, not fixed examples.

| Situation | Proposed copy | Available action | Forbidden UI state |
| --- | --- | --- | --- |
| Single-photo write failure | This photo's marks weren't saved. Try again? | Retry; Cancel | Show Saved first, then silently revert to unsaved |
| Lost folder permission | Access to this folder is no longer available. Open it again. | Reopen the folder | Appear writable while writes fail |
| Remembered location unavailable | This location can't be found. Select it again through Open. | Select it through Open folder | Recents tap fails without explanation |
| Read-only location or storage that does not permit writes | You can view this location, but can't save marks here. | Cancel, or reopen a writable location | Combine this with insufficient space |
| Insufficient space | There isn't enough space here to save marks. | Free space and retry | Combine this with read-only storage |
| External drive disconnected during use | The drive disconnected. Reconnect it, then reopen this folder. | Reconnect and reopen | Keep showing Writing or Saved |
| Partial batch failure | Saved N photos. M photos couldn't be saved. | Retry failed items; Cancel | Show the entire batch as successful or failed |
| Leaving a page or folder with unconfirmed writes | Some marks haven't finished saving. | Wait for writes; Leave anyway | Treat unconfirmed changes as saved after leaving |

If users leave before writes finish, unconfirmed changes are not saved. The next open reads the actual XMP on disk.

## AI suggestions and manual marks

Manual marks take precedence. Smart groups only suggest.

- Analyze automatically on folder open, with manual reruns available.
- Write XMP only when the user applies a suggestion.
- Analysis and reruns must not change existing ratings, Pick, Reject, or color labels.
- The entire main flow works with AI disabled.
- Do not promise accuracy, recall, or parity with competitors at launch.

## Light, dark, and usability

- All main screens support light and dark appearances and follow the system. Duo shares the same structure as other devices, not a separate dark skin.
- Use system navigation bars, toolbars, lists, buttons, and colors to follow system contrast and standard accessibility behavior.
- This document does not promise specific contrast ratios or unspecified spoken accessibility copy. States and errors still need accurate, nontechnical wording, as listed above.

## Supported files

The confirmed product scope is to scan JPEG, HEIC, and common RAW files after opening a folder. No custom RAW decoder at launch.

The following are source-derived public facts, not a compatibility guarantee tested by Clove:

- Prefer system image capabilities for grid and detail previews. Engineering research recommends embedded previews for the grid and full RAW processing only when needed for detail. See the [engineering research source](https://app.notion.com/p/41237873fb548107bd96d0f6838b1200).
- Apple publishes iOS camera RAW support. Engineering research cites the [iOS 18 support page, dated July 2025](https://support.apple.com/en-us/120534). The list changes with OS updates. Apple provides basic DNG support for unlisted models. Some models support only uncompressed, lossless, or single-shot RAW.
- Clove's promise is to open JPEG, HEIC, and common RAW files for which the system can generate previews. Camera and compression-format support depends on the system on the user's device. This document does not create a guaranteed camera list.
- Unsupported files or compression formats require a visible explanation. A blank preview must not be presented as loaded.
- Typical folder size, preview speed, and detail-decoding speed have no approved numeric targets. Timing or photo-count targets remain pending measurement and are not launch promises.

If the system photo picker later becomes a secondary entry, it must not become a temporary viewing session without XMP writes. The confirmed product page defers the system photo library as a culling entry. It is not P0 here.

## Privacy and offline use

- The main flow works in the user's folders. Marks live in XMP sidecars in those folders.
- Smart-group analysis runs on-device. No online cloud AI, CloudKit, or backup sync at launch.
- Offline users must still be able to open folders they have permission to access, browse, mark, and write XMP.
- Earlier engineering research found no siftapp dependency on app cloud services. Clove launch does not introduce uploading originals to its own servers.
- This document does not replace a formal privacy policy.

## Proposed copy (pending revision)

These strings cover failure and recovery. They refine the earlier draft shown to Tony to distinguish the cases, but remain unapproved. Approved copy should return to the UI conclusions page.

- Single failure: This photo's marks weren't saved. Try again? Actions: Retry / Cancel
- Lost permission: Access to this folder is no longer available. Open it again.
- Missing location: This location can't be found. Select it again through Open.
- Read-only: You can view this location, but can't save marks here.
- Insufficient space: There isn't enough space here to save marks.
- Disconnected drive: The drive disconnected. Reconnect it, then reopen this folder.
- Partial batch failure: Saved N photos. M photos couldn't be saved. Actions: Retry failed items / Cancel
- Leaving before completion: Some marks haven't finished saving. Actions: Wait for writes / Leave anyway

## Acceptance by P0 ID

These manual tests determine whether launch meets product requirements. They are not performance benchmarks.

| ID | Passing condition |
| --- | --- |
| P0-01 | Through Files, open folders on local storage, an SD reader, and an external drive. Their JPEG, HEIC, and system-previewable RAW files appear in the grid. No imported copy of originals appears in the app's directory. |
| P0-02 | Fully quit the app, then reopen the same folder through Recents. After disconnecting the drive or revoking permission, the same action explains how to select the folder again rather than failing silently. |
| P0-03 | Scroll a RAW folder with embedded previews and use its thumbnails to browse. Unreadable files have explicit states, not blank images presented as loaded. |
| P0-04 | Pinch to inspect focus in detail. Edge taps navigate to previous and next photos, including while zoomed. Current ratings, flags, and labels are visible away from the hand. |
| P0-05 | Apply ratings, Pick, Reject, and labels separately. Original bytes remain unchanged and XMP appears or updates beside each original. Tapping the same rating clears it. Rejected originals remain in place. |
| P0-06 | Clove displays ratings, flags, and labels previously written by Lightroom, Capture One, or Photo Mechanic. Those apps read Clove's writes. Other preexisting XMP information survives the write. |
| P0-07 | Show Writing… during writes and Saved only after success. Force a write failure and verify a visible failure with Retry. The failed change never appears saved. |
| P0-08 | Long-press, select multiple photos, and apply Pick in a batch. Force some writes to fail. Report Saved N photos. M photos couldn't be saved. Successful items stay saved and failed items can be retried separately. |
| P0-09 | Smart-group analysis starts when a folder opens, and Run again is available afterward. Applying suggestions to manually marked photos preserves their manual marks. Disabling AI hides its entry points without affecting opening, browsing, or manual marking. Below iOS 18, AI entry points are hidden and the main flow still works. |
| P0-10 | Complete the flow on both iPhone and iPad: open folder → grid → mark in detail → quit and reopen with marks intact. |
| P0-11 | Open and mark on the Duo cover screen. Unfold and retain the same folder, photo, and marks, with grid and detail split by default. Overlay can be selected but is not the default for a newly opened folder. Half-folded filters, marking controls, and bottom bar never cross the hinge. |
| P0-12 | Switching system appearance updates entry, grid, detail, smart groups, and all Duo postures between light and dark. |

Additional interoperability acceptance: alternate between Clove and Photo Mechanic or Lightroom on the same folder. Each reads the other's ratings, flags, and labels.

## Engineering constraints (not product scope)

These constraints affect implementation without adding product features.

- Deliver a new native iOS and iPadOS app. The old Flutter [siftapp repository](https://github.com/mimiqdev/siftapp) is reference material, not something to migrate blindly. The new repository is [cloveapp](https://github.com/mimiqdev/cloveapp).
- The confirmed product decision excludes custom RAW demosaicing. Preferring system previews and decoding is an engineering recommendation recorded in the product page. Whether to remove all custom RAW image code on Apple targets awaits real-sample validation. That does not change product scope.
- Smart groups use on-device vision analysis. The product page identifies aesthetic scoring and feature distance. Closed-eye and expression analysis are out of launch scope.
- Remembering folders and reading and writing external drives involve platform file permissions. Users see Recents and the recovery states above, not internal permission terminology.
- Duo layouts respond to actual available space. Do not hard-code separate, disconnected interfaces by device type. Avoid the hinge when half-folded. Engineering research points to newer system SDKs for a fuller Duo experience. That is an implementation target, not an approved minimum OS version.
- Confirm save success per file and per change. Do not show unconfirmed writes as saved.

## Open decisions

Only unresolved items that affect launch commitments are listed here.

- Minimum OS version. AI entry points are hidden below iOS 18 while the main flow remains usable. The oldest supported OS for that main flow is undecided. Engineering considered 17 and later as validation candidates and newer SDKs for a fuller Duo experience. Neither is a minimum-version decision.
- Pricing. Sources contain no decision on free, one-time purchase, or subscription.
- Whether and when to stop maintaining Flutter siftapp, and how to transition old users and projects beyond XMP interoperability.
- Whether the system photo library becomes a secondary entry at launch. The confirmed product page defers it and excludes temporary sessions without XMP writes. It is not P0 in this document.
- The English XMP name for the orange label, to be checked against Lightroom's actual field.
- Visual approval has not been recorded.

The following are not launch commitments or numeric acceptance criteria: performance timings, AI accuracy, guaranteed camera or storage-brand lists, and folder-size limits. Any later targets require measurement and separate approval.
