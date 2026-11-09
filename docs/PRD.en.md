# Clove launch PRD (pending review)

[简体中文](PRD.zh-CN.md) · [Notion source](https://app.notion.com/p/41237873fb548107bd96d0f6838b1200)

Status: pending review. This document defines product scope and acceptance criteria. It is neither implementation authorization nor an architecture proposal.

Visual source: [Culling UI — Native (canonical)](https://www.figma.com/design/qhGhxv3eRImQTXe3yzOD2G?node-id=33-2). After review by the product owner, these designs (Uxie's light and dark designs for iPhone, iPad, and iPhone Duo) are not adopted. New concept designs will be produced from this document and then refined. This document, not those designs, defines interface behavior.

Sources: [2026-11-08 siftapp product positioning: pure culling, benchmarked against PhotoPicker App](https://app.notion.com/p/41237873fb5481bc9a28c2681f42a322), [2026-11-08 siftapp culling main-flow UI](https://app.notion.com/p/41237873fb5481c9bd5afcf26ae0a296), [engineering research conclusions](https://app.notion.com/p/41237873fb548107bd96d0f6838b1200), and the 2026-11-08 launch-scope discussion with the product owner. Existing Notion pages still use siftapp. This document uses Clove as its replacement name.

### Revision history

2026-11-08 scope revision:

- Removed Pick. The only marks are ratings, color labels, and Reject.
- Reject is internal to Clove. The user runs Move rejects to move rejected photos into a `_Rejected` folder.
- XMP interoperability is narrowed to ratings and color labels. RAW files get sidecars. Standalone JPEG, HEIC, and DNG files can optionally receive embedded metadata.
- RAW+JPG pairs are one item and share one XMP sidecar.
- Color labels default to Lightroom's five colors. Extended colors are optional. This closes the open orange-label question.
- Added: recursive subfolder scanning, undo, an Unmarked filter, sorting, swipe-distance rating, enabled rating levels, double-tap zoom, auto-advance, and in-group culling.
- Launch smart features are limited to similar groups, built from capture time plus visual similarity. AI best-shot suggestions and low-quality or blur suggestions move to 1.1.
- Minimum OS is iOS 18. The hide-AI-below-iOS-18 branch is removed.
- Duo stays in launch scope. Overlay and a dedicated half-fold layout move to 1.1.
- No migration or user transition from the old Flutter siftapp.
- No system photo library entry, neither primary nor secondary.
- The Figma designs are not adopted. New concept designs will be produced.
- Interoperability testing with Lightroom and other desktop apps is deferred. Items under Pending verification are working assumptions for now.

---

## Product in one sentence

Clove is an in-place photo-culling app for photographers on iPhone, iPad, and iPhone Duo. Browse photos in folders on SD cards, external drives, or Files, then rate, label, or reject them. Ratings and color labels go into XMP sidecars. After you confirm, rejected photos move into a `_Rejected` folder and are never deleted. Original image contents never change. Continue in Lightroom, Capture One, or Photo Mechanic at home, where you see only the photos you kept, with your ratings and labels.

Clove is not a photo-library manager, cloud backup service, social app, or color editor. Its reference product is the third-party [AI Photo Culling — PhotoPicker](https://apps.apple.com/us/app/ai-photo-culling-photopicker/id661470243), not the system photo picker.

Priority: a good manual-culling experience and correct XMP writes come before AI. The only launch smart feature is similar groups, and it can be turned off.

## Users and jobs

Target users are photographers who want to finish a first pass while away or on the journey home, shooting mostly RAW or RAW+JPG. Their photos are on SD cards, external SSDs, or folders accessible through Files. They need to browse, inspect focus, and leave marks that desktop software can read.

Main jobs:

1. Open or reopen a folder, including subfolders such as `DCIM/100XXXXX`, without importing photos into the app or system photo library.
2. Browse the grid and open a large preview to inspect focus.
3. Rate, label, or reject photos with gestures, buttons, or a keyboard.
4. Cull bursts by group: compare within the group, keep the best one or two, and reject the rest.
5. Move rejected photos into a `_Rejected` folder in one action.
6. Read the same ratings and labels in Lightroom, Capture One, or Photo Mechanic and continue editing.

## Main flow

Open a folder or reopen it from Recents → browse, filter, and sort the grid → inspect focus and navigate photos in detail → rate, label, or reject and write XMP → cull bursts by similar group → run Move rejects → leave and reopen with marks intact and original image contents unchanged.

## Required for launch (P0)

| ID | Requirement |
| --- | --- |
| P0-01 | Open and scan: use the system folder picker to open folders on SD readers, external drives, or Files. Scan all subfolders recursively, skipping the rejects folder. Scan JPEG, HEIC, and common RAW files the system can preview. Combine RAW and JPG files with the same name into one item. Do not copy photos into an app-owned library. |
| P0-02 | Recents: show a path summary, media type, photo count, and last-opened time. Reopen with one tap. If a location is unavailable, explicitly ask the user to select it again rather than failing silently. |
| P0-03 | Grid: prefer embedded previews in files for thumbnails. Smooth scrolling takes priority over immediately decoding full RAW images. Sort by capture time by default, or by filename. Filters: All, Unmarked, Rejected, and N stars or higher. |
| P0-04 | Detail: full-width preview, pinch zoom and double-tap to 100% for focus inspection, previous and next navigation, a filmstrip, and always-visible current marks. |
| P0-05 | Marks: ratings from 0 to 5, color labels, and Reject. Reject is not deletion. Undo is available. |
| P0-06 | Gestures and keyboard: swipe up to rate by distance, swipe down to reject, choose which rating levels are enabled, external-keyboard shortcuts, and auto-advance after marking. |
| P0-07 | XMP reads, writes, and interoperability: read existing XMP when opening a folder. Write only sidecars for RAW files, with one sidecar shared by a RAW+JPG pair. Preserve unknown information written by other apps as far as possible. Lightroom, Capture One, and Photo Mechanic must read Clove's ratings and color labels. Reject is stored in a Clove-specific field and is not an interoperability promise. Standalone JPEG, HEIC, and DNG files can optionally receive embedded metadata, off by default. |
| P0-08 | Save status is always visible and matches disk state. Show Saved only after a confirmed successful write. Allow retries after failure. Never report a failed write as successful. |
| P0-09 | Long-press the grid to enter multi-select, then write ratings, labels, or Reject in batches. |
| P0-10 | Move rejects: after user confirmation, move rejected photos with their paired files and XMP into `_Rejected` under the opened folder, preserving the subfolder structure. Never delete or overwrite any file. The folder name can be changed, or the feature turned off, in Settings. |
| P0-11 | Similar groups: group photos automatically by capture time and visual similarity when a folder opens, and always offer Run again. Grouping itself never writes marks. It can be turned off. |
| P0-12 | In-group culling: synchronized zoom for comparison, progressive elimination, Keep this, reject the rest, and Keep rated, reject the rest. Neither action ever rejects a photo that already has a rating or color label. |
| P0-13 | Deliver the single-photo culling flow on both iPhone and iPad. Two-photo comparison on iPad is not in launch scope. |
| P0-14 | iPhone Duo: use a compact cover-screen layout. Default to a split grid and detail view on the inner screen. Controls must not cross the hinge when half-folded. Preserve the folder, current photo, filters, selection, and write status across folding, unfolding, and window resizing. Overlay and a dedicated half-fold layout move to 1.1. |
| P0-15 | Use system components with light and dark appearances that follow the system. Ratings use system orange. Reject uses system red. Color labels follow Lightroom color meanings. |

## Explicitly out of launch scope

- The Pick flag, replaced by ratings
- A system photo library entry, primary or secondary, or temporary photo-picking sessions without XMP writes
- Writing favorites or marks back to the system photo library
- Album management, keyword management, cloud backup, CloudKit, or backup and sync wizards
- Social features or sharing feeds
- Opening or writing Lightroom Classic catalogs
- App-owned catalogs, or copying selected photos and XMP into a new folder. The latter may be a later priority, but is not in launch scope.
- Deleting originals, exporting finished photos, or a video-first workflow. Moving rejects into `_Rejected` is not deletion.
- Two-photo comparison, which is deferred
- Color editing or autofocus-point overlays
- AI best-shot suggestions and low-quality or blur suggestions, which move to 1.1
- Manually splitting or merging similar groups, or user-created groups. Splitting moves to 1.1.
- A grouping-sensitivity setting
- Duo Overlay and a dedicated Duo half-fold layout, which move to 1.1
- Closed-eye and expression analysis, natural-language culling, online cloud AI, or any feature where AI writes or overwrites marks automatically
- Custom RAW decoding or demosaicing

## Screens and states

The behavior below follows the product and UI conclusions and this revision. The old Figma designs are not adopted. New concept designs follow the behavior in this section.

### Entry: Open and Recents

- The primary action is Open folder…, through Files, SD cards, or external drives.
- Recents shows a path summary, media type, count, and last-opened time. Tap an item to reopen its remembered location.
- There is no system photo library entry.
- The design contains a search field. Searching Recents has not been separately confirmed and is not P0.

### Scan scope

- Scan every subfolder of the opened folder recursively. Photos in SD-card folders such as `DCIM/100XXXXX` and `101XXXXX` appear together.
- Skip the rejects folder, `_Rejected` by default.
- Combine a RAW and a JPG in the same folder whose names match without the extension into one item. It takes one grid cell, with RAW as the primary file, and marks apply to both.
- Unreadable or unsupported files have a visible state. A blank preview must not be presented as loaded.

### Grid

- iPhone uses three columns. iPad uses five columns with a left sidebar for navigation and filters.
- Cells overlay a Reject flag, ratings, and color dots. RAW+JPG pairs have a badge.
- Sort by capture time by default, with subsecond precision, or by filename.
- Top filters are All, Unmarked, Rejected, and N stars or higher.
- Similar-group display:
  - Expanded, the default: show every photo, with each group outlined in blue and labeled with its count.
  - Collapsed: show one cover cell per group with its count. Tapping it opens the group view.
  - Expanded is the default because grouping refines in the background, which adds and removes cells in the collapsed view. In either mode, refinement must not move the photo the user is looking at.
- Open detail or similar groups from the grid.
- Long-press to enter multi-select, then write in batches.
- The grid has no double-tap action, so a single tap opens detail without delay.

### Detail and marking

- Provide a full-width preview and pinch zoom for focus inspection. Double-tap the center area to zoom to 100% around the tapped point. Double-tap again to return to fit.
- Tap the left or right edge for the previous or next photo, including while zoomed. Edge areas recognize single taps only and do not wait for a double tap, so navigation has no delay.
- Current marks must be immediately visible and not hidden by the user's hand. Detail uses a top marking HUD for ratings, Reject, and labels. iPad uses a right-hand marking rail. This avoids the competitor issue where the hand obscures bottom-bar state.
- A filmstrip identifies the current photo and supports horizontal navigation.
- The design also contains information such as filenames. The exact shooting metadata to display is undecided and not P0.

Marking rules:

| Control | Behavior |
| --- | --- |
| Rating from 0 to 5 | Tap a rating in the rating bar. Tap the same rating again to clear it. Only enabled ratings appear. |
| Color label | Red, yellow, green, blue, purple, and Clear by default. Settings can enable extended colors, orange and pink, matching Capture One. Use fixed English names in XMP, regardless of system language. |
| Reject | A separate toggle, independent of the rating. Rejecting keeps the existing rating. Reject does not delete the original. |
| Undo | Uses the system undo mechanism: a toolbar Undo button, ⌘Z on an external keyboard, and the iOS three-finger undo gestures. Undoing after auto-advance returns to the photo whose mark was undone. |
| Save status | Writing…, Saved, or Write failed. Offer Retry after failure. Show Saved only after confirmed success. |

### Batch writes with multi-select

Long-press the grid to select multiple photos, then apply ratings, labels, or Reject in one operation. Count successes and failures per photo. On partial success, keep successful writes saved and failed writes unsaved. Allow retrying only the failed items.

### Gestures and keyboard

Detail gestures:

| State | Action | Result |
| --- | --- | --- |
| Fit | Swipe up, by distance | Rate. If the photo is rejected, also clear Reject. |
| Fit | Swipe down | Reject |
| Fit | Swipe left or right, or tap an edge | Navigate |
| Fit | Double-tap the center area | Zoom to 100% around the tapped point |
| Zoomed | One-finger drag | Pan. Vertical marking swipes are disabled while zoomed. |
| Zoomed | Tap an edge | Navigate |
| Zoomed | Double-tap | Return to fit |
| Any | Pinch | Zoom |
| Any | Three-finger system gesture or ⌘Z | Undo |

Rating by swipe distance:

- Each rating step corresponds to a fixed swipe distance, initially about 60 pt and subject to tuning. Steps do not scale with screen height, so iPhone and iPad feel the same.
- While swiping, show the current rating near the finger and play a light haptic at each step boundary. Swiping back lowers the rating.
- The release position decides the rating, not the velocity. A short flick gives the lowest step.
- Returning to the starting point before release writes nothing.
- Gestures never clear a rating. Clear it with the rating bar or the `0` key.

Enabled rating levels (Settings):

- The user chooses which ratings may be applied. All of 1 through 5 are enabled by default.
- Swipe steps map, in order, to the enabled ratings. With only 1 through 3 enabled, there are three steps. With 1, 3, and 5 enabled, one step gives 1 star and two steps give 3 stars.
- The rating bar and keyboard accept only enabled ratings.
- This setting affects input only, not display or filtering. 4- and 5-star ratings written by other apps still display and are never rewritten.

External keyboard support prioritizes iPad and also works on an iPhone with a keyboard:

| Key | Result |
| --- | --- |
| `0` through `5` | Set rating; `0` clears |
| `6` `7` `8` `9` | Red, yellow, green, blue label, matching Lightroom |
| `↑` | Raise to the next enabled rating |
| `↓` | Reject |
| `←` `→` | Navigate |
| `⌘Z` | Undo |

Auto-advance (Settings):

- After marking: stay, next photo (default), or next unmarked photo.
- Marks that trigger advance: ratings and Reject by default. Color labels do not trigger it by default.
- Pause about 0.3 seconds after marking so the user sees the mark take effect, then advance.
- In a group view, advance to the next undecided photo in the group. Group-completion behavior is described under In-group culling.

Gesture-related settings: gestures on or off, enabled ratings, auto-advance, marks that trigger advance, double-tap behavior (zoom, the default, or off), and keep zoom while navigating (on by default in groups, off in regular detail).

### Similar groups

The only launch smart feature is similar groups, which put bursts and repeated compositions together. It only groups photos and never writes marks for the user.

Grouping:

1. Separate photos by camera body, using model and serial number, then sort by capture time with subsecond precision. Photos from two bodies shooting at the same time are not mixed into one group.
2. Split into runs by time gap: adjacent photos less than a threshold apart join the same run. The initial threshold is about 2 seconds, to be calibrated with real samples, and is not a launch promise. This step reads only EXIF, so it can appear shortly after the folder opens.
3. Split each run by visual similarity: compute on-device image features from embedded previews, and break the run where adjacent photos differ substantially, such as when the subject changes. This runs in the background and refines the groups when done.

Rules:

- A group has at least 2 photos. Files without a capture time are not grouped.
- Groups are cached only in Clove and never written to XMP.
- Show analysis progress or Analyzed. Run again is always available.
- Users can turn similar groups off. That hides group entry points and blue outlines while preserving opening, browsing, and manual marking.
- There is no grouping-sensitivity setting. Use calibrated defaults.
- No numeric grouping-accuracy commitment.

### In-group culling

A burst may contain dozens of photos that differ only in focus, expression, or moment. The group view is built around comparing details, narrowing candidates, and finishing in one action.

Layout:

- iPhone: large preview on top, the group's filmstrip below.
- iPad and Duo inner screen: large preview with a sidebar grid of the group.
- Every photo shows its rating or Reject state. The top shows Undecided N / M total. Undecided means no rating and no Reject.

Comparison and elimination:

- Synchronized zoom: after zooming into an area in a group, navigating keeps the same zoom level and position. On by default in groups.
- Rejected photos are dimmed in the filmstrip. With Undecided only on, navigation skips rejected and rated photos.
- After marking, advance to the next undecided photo in the group.

Finishing actions:

| Action | Result |
| --- | --- |
| Keep this, reject the rest | If the current photo has no rating, give it the lowest enabled rating. Reject the other unmarked photos in the group. |
| Keep rated, reject the rest | Leave rated photos unchanged and reject the other unmarked photos in the group. Unavailable when no photo in the group is rated. |

- Neither action ever rejects a photo that already has a rating or color label.
- Both actions follow batch-write rules for success and failure, and both can be undone.

Group completion:

- Definition: every photo in the group is rated or rejected, or the user ran a finishing action.
- Setting, After a group is complete: stay in the group, or go to the next group (default). Going to the next group skips completed groups.

### Move rejects

Reject exists only for culling. After moving rejects, desktop software sees only the photos that were kept and does not need to know what was rejected.

- Trigger: the user taps Move rejects. It never runs automatically and can run at any time within a folder.
- Confirmation: state how many photos will move, that paired JPGs and XMP move with them, and that originals are not deleted.
- Destination: `_Rejected/` under the opened folder. The name can be changed in Settings. Preserve the subfolder structure, so `DCIM/100XXXXX/IMG_0001.CR3` moves to `_Rejected/DCIM/100XXXXX/IMG_0001.CR3`.
- Move together: the RAW, its paired JPG, and the matching XMP.
- Move only within the same volume. Never copy and then delete.
- If a file with the same name exists at the destination, add a suffix. Never overwrite.
- Count successes and failures per photo. On partial failure, moved photos stay moved, failed photos stay in place, and the user can retry only the failures.
- Read-only locations cannot be organized. Reuse the view-only message.
- Moved photos disappear from the grid, and later scans skip `_Rejected`.
- Restore: the user moves files back. Their XMP still records Reject, so Clove shows them as rejected again. An in-app Restore action is not in launch scope.
- Settings can turn Move rejects off. Reject still works for filtering, without the move.

### iPhone, iPad, and iPhone Duo

| Device | Launch behavior |
| --- | --- |
| Single-screen iPhone | Three-column grid. Focus inspection and marking on a single detail screen. |
| iPad | Five-column grid with left sidebar. Detail uses a right-hand marking rail. The group view uses a large preview with a sidebar grid. No two-photo comparison at launch, but the single-photo flow must work end to end. |
| iPhone Duo cover | Compact entry or three-column grid, followed by detail. Do not create a separate information structure. |
| iPhone Duo inner | Expand for the available space. Default to simultaneous grid and detail, side by side when wide and stacked when tall. |
| iPhone Duo half-fold | Filters, marking controls, and the bottom bar must not cross the hinge. Launch guarantees only that the layout avoids the hinge and works. A dedicated half-fold layout, such as an even number of grid columns split across the hinge, moves to 1.1. |

Moving from cover to inner screen, half-folding, or resizing must preserve the folder, current photo, filters, multi-selection, group-view position, and visible write status.

Duo is one of Clove's selling points. Launch gets these behaviors right first. Further optimization and deeper adaptation follow in later versions.

## How marks reach disk

XMP on disk is the source of truth for persisted marks. Saved means the write has actually completed on disk.

1. Read existing XMP before displaying ratings, labels, and Reject when a folder opens.
2. Never modify original image contents. By default, write only XMP sidecars.
3. Name sidecars by replacing the extension, so `IMG_0001.CR3` maps to `IMG_0001.xmp`. A RAW+JPG pair shares that sidecar. The exact naming must be confirmed with all three desktop apps.
4. Write ratings to the standard rating field and color labels to the standard label field.
5. Store Reject in a Clove-specific XMP field that other apps ignore. Settings offers Also write Rating −1 when rejecting, for apps such as Bridge. It is off by default.
6. Standalone JPEG, HEIC, and DNG files without a paired RAW: Lightroom reads embedded metadata for these formats and ignores sidecars. Settings offers Write metadata into files, off by default. When on, Clove changes only metadata and never re-encodes the image. If iOS cannot write a format's metadata without re-encoding, that format's option is disabled with an explanation.
7. Treat a specific change to a specific photo as saved only after confirmed success. Pending, failed, or unconfirmed writes must not show Saved.
8. Retain the user's requested marks after a write failure so they can retry. Do not treat them as saved before a successful retry.
9. Preserve existing information that Clove does not recognize as far as possible. Writing a rating must not discard other software's data.
10. Write fixed English label names to XMP, independent of interface language. The five default names are Red, Yellow, Green, Blue, and Purple.

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
| Partial Move rejects failure | Moved N photos. M photos couldn't be moved. | Retry unmoved items; Cancel | Hide unmoved photos from the grid |
| Leaving a page or folder with unconfirmed writes | Some marks haven't finished saving. | Wait for writes; Leave anyway | Treat unconfirmed changes as saved after leaving |

If users leave before writes finish, unconfirmed changes are not saved. The next open reads the actual XMP on disk.

## Smart grouping and manual marks

Manual marks take precedence. Similar groups only group.

- Grouping and Run again never write or change marks.
- In-group finishing actions are explicit user actions, and they never reject photos that already have a rating or color label.
- The entire main flow works with similar groups turned off.
- Do not promise accuracy, recall, or parity with competitors at launch.

## Light, dark, and usability

- All main screens support light and dark appearances and follow the system. Duo shares the same structure as other devices, not a separate dark skin.
- Use system navigation bars, toolbars, lists, buttons, and colors to follow system contrast and standard accessibility behavior.
- Swipe-distance rating is not comfortable for every user. The rating bar and keyboard must support every marking action and work with VoiceOver.
- This document does not promise specific contrast ratios or unspecified spoken accessibility copy. States and errors still need accurate, nontechnical wording, as listed above.

## Supported files

The confirmed product scope is to scan JPEG, HEIC, and common RAW files, including DNG, after opening a folder. HEIC includes camera HEIF files with `.HEIC`, `.HEIF`, or `.HIF` extensions. RAW is the primary use case. No custom RAW decoder at launch.

The following are source-derived public facts, not a compatibility guarantee tested by Clove:

- Prefer system image capabilities for grid and detail previews. Engineering research recommends embedded previews for the grid and full RAW processing only when needed for detail. Double-tap to 100% first enlarges the embedded preview, then decodes the full RAW when needed. See the [engineering research source](https://app.notion.com/p/41237873fb548107bd96d0f6838b1200).
- Apple publishes iOS camera RAW support. Engineering research cites the [iOS 18 support page, dated July 2025](https://support.apple.com/en-us/120534). The list changes with OS updates. Apple provides basic DNG support for unlisted models. Some models support only uncompressed, lossless, or single-shot RAW.
- Clove's promise is to open JPEG, HEIC, and common RAW files for which the system can generate previews. A RAW and a same-name HEIF in the same folder form a pair, treated like RAW+JPEG. Camera and compression-format support depends on the system on the user's device. This document does not create a guaranteed camera list.
- DNG files, such as iPhone ProRAW, Leica, and Pentax, display as RAW. For writing marks, they fall under standalone JPEG, HEIC, and DNG files. See item 6 under How marks reach disk.
- Unsupported files or compression formats require a visible explanation. A blank preview must not be presented as loaded.
- Typical folder size, preview speed, and detail-decoding speed have no approved numeric targets. Timing or photo-count targets remain pending measurement and are not launch promises.

Launch has no system photo library entry. If one is added later, it must not become a temporary viewing session without XMP writes, and it needs a separate decision.

## Privacy and offline use

- The main flow works in the user's folders. Marks live in XMP in those folders.
- Similar-group analysis runs on-device. No online cloud AI, CloudKit, or backup sync at launch.
- Offline users must still be able to open folders they have permission to access, browse, mark, write XMP, and move rejects.
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
- Move confirmation: Move N rejected photos, with their paired JPGs and XMP, to the "_Rejected" folder? Originals won't be deleted. Actions: Move / Cancel
- Partial move failure: Moved N photos. M photos couldn't be moved. Actions: Retry unmoved items / Cancel
- Embedded write unavailable: Marks can't be written into this file format yet. They'll be saved in an XMP file next to it.

## Acceptance by P0 ID

These manual tests determine whether launch meets product requirements. They are not performance benchmarks.

| ID | Passing condition |
| --- | --- |
| P0-01 | Through Files, open folders on local storage, an SD reader, and an external drive. Photos from multiple subfolders under `DCIM` appear in the grid, and photos in `_Rejected` do not. A same-name RAW+JPG pair takes one cell. No imported copy of originals appears in the app's directory. |
| P0-02 | Fully quit the app, then reopen the same folder through Recents. After disconnecting the drive or revoking permission, the same action explains how to select the folder again rather than failing silently. |
| P0-03 | Scroll a RAW folder with embedded previews and use its thumbnails to browse. Unreadable files have explicit states. A folder shot with two bodies sorts correctly by capture time and can switch to filename order. Each of the four filters shows only matching photos. |
| P0-04 | In detail, pinch to zoom, or double-tap to 100% and double-tap back to fit. Edge taps navigate to previous and next photos, including while zoomed, without perceptible delay. Current ratings, Reject, and labels are visible away from the hand. |
| P0-05 | Apply ratings, labels, and Reject separately. Original bytes remain unchanged and XMP appears or updates beside each original. Tapping the same rating in the rating bar clears it. Rejected originals remain in place with their existing rating. Undo restores the previous mark, and undoing after auto-advance returns to that photo. |
| P0-06 | Swiping up different distances produces different ratings, with the current step visible and a haptic at each step. Returning to the start before release writes nothing. With only 1 through 3 enabled, the maximum applied rating is 3 and existing 5-star ratings still display. Keys work as listed. Auto-advance follows settings, and labels do not trigger it by default. |
| P0-07 | Clove displays ratings and labels previously written by Lightroom, Capture One, or Photo Mechanic. Those apps read Clove's ratings and labels. A RAW+JPG pair has one XMP. Other preexisting XMP information survives the write. With default settings, other apps do not see Reject. With Write metadata into files on, Lightroom reads ratings and labels on a standalone JPEG, and the image is not re-encoded. |
| P0-08 | Show Writing… during writes and Saved only after success. Force a write failure and verify a visible failure with Retry. The failed change never appears saved. |
| P0-09 | Long-press, select multiple photos, and rate them in a batch. Force some writes to fail. Report Saved N photos. M photos couldn't be saved. Successful items stay saved and failed items can be retried separately. |
| P0-10 | Reject several photos, including RAW+JPG pairs across multiple subfolders, then run Move rejects. The confirmation shows the correct count. Afterward, the RAW, JPG, and XMP files are in the matching subfolders under `_Rejected`, no file was deleted or overwritten, and the photos no longer appear in the grid. Forced name collisions add a suffix, and forced partial failures report Moved N photos. M photos couldn't be moved. Running it on a read-only location shows the view-only message. |
| P0-11 | Opening a folder with bursts starts grouping automatically: groups appear by time first, then refine, and Run again is available. The photo being viewed does not jump during grouping. Bursts from two bodies shooting at once are not mixed. All XMP is unchanged before and after grouping. Turning similar groups off hides entry points and blue outlines while the main flow still works. |
| P0-12 | In a group of 20 or more photos: zooming into an area keeps the same position while navigating. Undecided only skips marked photos. After Keep this, reject the rest, photos that already had ratings or labels are not rejected. Keep rated, reject the rest rejects only unmarked photos. A completed group advances to the next group according to settings. Finishing actions can be undone. |
| P0-13 | Complete the flow on both iPhone and iPad: open folder → grid → mark in detail → cull a group → move rejects → quit and reopen with marks intact. |
| P0-14 | Open and mark on the Duo cover screen. Unfold and retain the same folder, photo, marks, and group-view position, with grid and detail split by default. Half-folded filters, marking controls, and bottom bar never cross the hinge. |
| P0-15 | Switching system appearance updates entry, grid, detail, similar groups, the group view, and all Duo postures between light and dark. |

Additional interoperability acceptance: alternate between Clove and Photo Mechanic or Lightroom on the same folder. Each reads the other's ratings and labels.

## Engineering constraints (not product scope)

These constraints affect implementation without adding product features.

- Deliver a new native iOS and iPadOS app with a minimum of iOS 18. The old Flutter [siftapp repository](https://github.com/mimiqdev/siftapp) is reference material only. There is no code migration and no transition for old users or projects. The new repository is [cloveapp](https://github.com/mimiqdev/cloveapp).
- The confirmed product decision excludes custom RAW demosaicing. Preferring system previews and decoding is an engineering recommendation recorded in the product page. Whether to remove all custom RAW image code on Apple targets awaits real-sample validation. That does not change product scope.
- Similar groups use on-device visual features computed from embedded previews. The 1.1 best-shot suggestion can consider the system's aesthetic scoring.
- Remembering folders and reading, writing, and moving files on external drives involve platform file permissions. Users see Recents and the recovery states above, not internal permission terminology.
- Move rejects must be a same-volume move with success or failure confirmed per file.
- Duo layouts respond to actual available space. Do not hard-code separate, disconnected interfaces by device type. Avoid the hinge when half-folded.
- Confirm save success per file and per change. Do not show unconfirmed writes as saved.

### Pending verification

This document depends on the following facts, which have not yet been verified with real samples. Testing with Lightroom and other desktop apps is not scheduled during launch design and development, so these are working assumptions for now, and testing will be scheduled separately. The results may change the implementation but in principle not the product scope. If one does not hold, return it for a product decision.

- Lightroom reads only embedded metadata for JPEG, HEIC, and DNG and ignores sidecars.
- How the three desktop apps handle sidecar naming (`IMG_0001.xmp` versus `IMG_0001.CR3.xmp`) and a sidecar shared by a RAW+JPG pair.
- The XMP English names for Capture One's extended colors, orange and pink, and how Lightroom and Photo Mechanic treat those values.
- Whether non-English Lightroom localizes label names so fixed English names do not match. If so, help content must explain how to switch back to the default label set.
- How Bridge and Lightroom treat `Rating = -1`.
- Whether iOS can write metadata to JPEG, HEIC, and DNG without re-encoding the image.
- Initial values for the time-gap threshold, similarity threshold, and swipe distance per rating step.

## 1.1 candidates

- AI best-shot suggestion within a group, possibly using system aesthetic scoring
- Low-quality and blur suggestions
- Manually splitting similar groups, preserved across Run again
- Duo Overlay and a dedicated Duo half-fold layout
- An in-app Restore action for moved rejects
- Double-tap to toggle a chosen color label, as an alternative double-tap behavior

## Open decisions

Only unresolved items that affect launch commitments are listed here.

- Pricing. Sources contain no decision on free, one-time purchase, or subscription.
- Final visuals. The old Figma designs are not adopted, and new concept designs are in progress.

The following are not launch commitments or numeric acceptance criteria: performance timings, grouping accuracy, guaranteed camera or storage-brand lists, and folder-size limits. Any later targets require measurement and separate approval.
