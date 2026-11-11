# Clove launch PRD (pending review)

[简体中文](PRD.zh-CN.md) · [Notion source](https://app.notion.com/p/41237873fb548107bd96d0f6838b1200)

Status: pending review. This document defines product scope and acceptance criteria. It is neither implementation authorization nor an architecture proposal.

Visual source: the MVP design handoff in [`design/handoff/`](../design/handoff/README.md), adopted by the product owner on 2026-11-10. For screens, interactions, and copy, the handoff takes precedence over this document: where they differ, follow the handoff. The 2026-11-10 revision below lists the scope changes it brought. The earlier Uxie designs remain not adopted.

Sources: [2026-11-08 siftapp product positioning: pure culling, benchmarked against PhotoPicker App](https://app.notion.com/p/41237873fb5481bc9a28c2681f42a322), [2026-11-08 siftapp culling main-flow UI](https://app.notion.com/p/41237873fb5481c9bd5afcf26ae0a296), [engineering research conclusions](https://app.notion.com/p/41237873fb548107bd96d0f6838b1200), and the 2026-11-08 launch-scope discussion with the product owner. Existing Notion pages still use siftapp. This document uses Clove as its replacement name.

### Revision history

2026-11-11 reject-as-rating revision, with the product owner:

- Reject is the rating value −1, the way Adobe Bridge stores it: a photo's rating and Reject are one value. Rejecting replaces the stars, clearing Reject leaves the photo unrated, and undoing a Reject restores the stars it replaced. The color label stays independent.
- A RAW set's rating, Reject included, goes to its XMP sidecar; a standalone JPEG/HIF keeps it in Clove. There is no separate Reject field or Clove-only Reject route, so one photo's marks go to one storage.
- No migration. Rejects that TestFlight builds stored in Clove are dropped, and old Clove records still decode.
- Interoperability with other apps for Reject is not a v1 goal. See [the decision record](decisions/reject-as-rating.md).

2026-11-10 design revision, with the product owner:

- The MVP design handoff in `design/handoff/` is adopted and takes precedence over this document for screens, interactions, and copy. Items it tags (proposed) still need the owner's confirmation.
- Move rejects can be undone in the app. Undo moves the files back and restores Reject on them, as one undo step. This replaces the earlier rule that the user restores moved files by hand.
- The Move rejects confirmation lets the user keep individual rejects before moving. A keep is only staged until Move.
- In-group culling has one finishing action, Reject N unmarked, in place of Keep this, reject the rest and Keep rated, reject the rest. To keep one photo and reject the rest, the user rates it and then uses Reject N unmarked.
- Synchronized zoom is always on in groups, with no toggle.
- The proposed copy in this document is superseded by `design/handoff/copy.md`.

2026-11-08 scope revision, aligned with the [approved G1 decision](decisions/G1-technical-approach.md) on 2026-11-09:

- Removed Pick. The only marks are ratings, color labels, and Reject.
- Reject is internal to Clove. The user runs Move rejects to move rejected photos into a `_Rejected` folder. (Revised 2026-11-11: Reject is the rating −1, so a RAW set stores it in its sidecar.)
- XMP interoperability covers ratings and color labels only. RAW files, including standalone DNG, get sidecars. Standalone JPEG/HIF get no sidecar: embedded marks are read, and new marks stay in Clove. In-file JPEG writing is a later feature; HIF/HEIC in-file writing stays out.
- RAW+JPEG, RAW+HIF, and RAW+JPEG+HIF sets are one item with RAW as primary and one shared XMP sidecar.
- Color labels default to Lightroom's five colors. Extended colors are optional. This closes the open orange-label question.
- Added: recursive subfolder scanning, undo, an Unmarked filter, sorting, swipe-distance rating, enabled rating levels, double-tap zoom, auto-advance, and in-group culling.
- Launch smart features are limited to similar groups, built from capture time plus visual similarity. AI best-shot suggestions and low-quality or blur suggestions move to 1.1.
- Minimum OS is iOS 18. The hide-AI-below-iOS-18 branch is removed.
- Duo stays in launch scope. Overlay and a dedicated half-fold layout move to 1.1.
- No migration or user transition from the old Flutter siftapp.
- No system photo library entry, neither primary nor secondary.
- The Figma designs are not adopted. New concept designs will be produced.
- Desktop-app checks remain open and must run before C3 is called done. Removable media is not on the MVP critical path. G2 uses any folder Files can open on the iPhone 17 Pro Max: local storage, or the CFexpress Type A USB reader when available. External-media checks are non-blocking. See Pending verification.

---

## Product in one sentence

Clove is an in-place photo-culling app for photographers on iPhone, iPad, and iPhone Duo. Browse photos in folders on SD cards, external drives, or Files, then rate, label, or reject them. Ratings and color labels for RAW photo sets go into XMP sidecars, Reject included as the rating −1; new standalone JPEG/HIF marks stay in Clove. After you confirm, rejected photos move into a `_Rejected` folder and are never deleted. Original image contents never change. Continue in Lightroom, Capture One, or Photo Mechanic at home, where you see only the photos you kept, with the RAW sets' XMP ratings and labels.

Clove is not a photo-library manager, cloud backup service, social app, or color editor. Its reference product is the third-party [AI Photo Culling — PhotoPicker](https://apps.apple.com/us/app/ai-photo-culling-photopicker/id661470243), not the system photo picker.

Priority: a good manual-culling experience and correct XMP writes come before AI. The only launch smart feature is similar groups, and it can be turned off.

## Users and jobs

Target users are photographers who want to finish a first pass while away or on the journey home, shooting mostly RAW, RAW+JPEG, or RAW+HIF, including RAW+JPEG+HIF sets. Their photos are on SD cards, external SSDs, or folders accessible through Files. They need to browse, inspect focus, and leave marks that desktop software can read.

Main jobs:

1. Open or reopen a folder, including subfolders such as `DCIM/100XXXXX`, without importing photos into the app or system photo library.
2. Browse the grid and open a large preview to inspect focus.
3. Rate, label, or reject photos with gestures, buttons, or a keyboard.
4. Cull bursts by group: compare within the group, keep the best one or two, and reject the rest.
5. Move rejected photos into a `_Rejected` folder in one action.
6. Read the same ratings and labels in Lightroom, Capture One, or Photo Mechanic and continue editing.

## Main flow

Open a folder or reopen it from Recents → browse, filter, and sort the grid → inspect focus and navigate photos in detail → rate, label, or reject (XMP for RAW sets, Clove storage for standalone JPEG/HIF) → cull bursts by similar group → run Move rejects → leave and reopen with marks intact and original image contents unchanged.

## Required for launch (P0)

| ID | Requirement |
| --- | --- |
| P0-01 | Open and scan: use the system folder picker to open any folder Files can access, for example local storage, SD readers, or external drives. Removable media is not on the MVP critical path. Scan all subfolders recursively, skipping the rejects folder. Scan common RAW files and JPEG. Combine same-name RAW+JPEG, RAW+HIF, and RAW+JPEG+HIF in the same folder into one item, with RAW as primary. HIF-only and iPhone HEIC appear when the system can preview them, with no extra format work; fuller support is deferred. JPEG+HIF without RAW is unsupported and follows generic rules. Do not copy photos into an app-owned library. |
| P0-02 | Recents: show a path summary, media type, photo count, and last-opened time. Reopen with one tap. If a location is unavailable, explicitly ask the user to select it again rather than failing silently. |
| P0-03 | Grid: prefer embedded previews in files for thumbnails. Smooth scrolling takes priority over immediately decoding full RAW images. Sort by capture time with subseconds by default, falling back to file creation time, then modification time; never show temporary filename order first. Photos using file times are not grouped. Filename order remains an option. Filters: All, Unmarked, Rejected, and N stars or higher. |
| P0-04 | Detail: full-width preview, pinch zoom and double-tap to 100% for focus inspection, previous and next navigation, a filmstrip, and always-visible current marks. |
| P0-05 | Marks: ratings from 0 to 5, color labels, and Reject as the rating −1. Rejecting a photo replaces its stars, clearing Reject leaves it unrated, and the color label stays independent. A RAW set's rating, Reject included, is written to its shared XMP sidecar; a standalone JPEG/HIF keeps its marks in Clove. Reject is not deletion. Undo is available, and undoing a Reject restores the stars it replaced. |
| P0-06 | Gestures and keyboard: swipe up to rate by distance, swipe down to reject, choose which rating levels are enabled, external-keyboard shortcuts, and auto-advance after marking. |
| P0-07 | XMP reads, writes, and interoperability cover ratings, which carry Reject as −1, and color labels only. Read existing XMP when opening a folder. An `xmp:Rating` of −1 shows the photo as rejected; another value outside 0–5, such as `6` or `-2`, reads as unrated and keeps its bytes. RAW files, including standalone DNG, use one sidecar per photo set; JPEG/HIF companions are never changed. Preserve unknown information written by other apps as far as possible. Lightroom, Capture One, and Photo Mechanic must read Clove's XMP ratings and color labels. Standalone JPEG/HIF get no sidecar: read embedded marks and keep new marks, Reject included, in Clove, visibly Saved in Clove only. In-file JPEG writing is a later feature; HIF/HEIC in-file writing stays out. |
| P0-08 | Marks show immediately in detail, the grid, filters, and counts, while writes run in user action order. The photos, XMP sidecars and Clove's standalone JPEG/HIF mark store are the truth. A connected write failure shows one toast, “Couldn't save the mark.”, re-reads that photo and displays its file's marks. Keep only pending marks; clear them when the write finishes either way. Keep no per-photo save status or retry. On disconnect, drop queued writes and pending marks, show the banner and disable marking until Reopen reads the files. Leaving has no prompt; admitted writes may finish in the background. Move Rejects reports how many did not move, keeps Undo and shows the files on disk. |
| P0-09 | Long-press the grid to enter multi-select, then write ratings, labels, or Reject in batches. |
| P0-10 | Move rejects: after user confirmation, move rejected photo sets as one unit, including RAW, JPEG and/or HIF companions, and the matching XMP, into `_Rejected` under the opened folder, preserving the subfolder structure. Never delete or overwrite any file. The user can keep individual rejects in the confirmation, and the move can be undone. The folder name can be changed, or the feature turned off, in Settings. |
| P0-11 | Similar groups: group photos automatically by capture time and visual similarity when a folder opens, and always offer Run again. Grouping itself never writes marks. It can be turned off. |
| P0-12 | In-group culling: synchronized zoom for comparison, progressive elimination, and one finishing action, Reject N unmarked. It never rejects a photo that already has a rating or color label. |
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

The behavior below follows the product and UI conclusions and the revisions above. Where it differs from the design handoff in `design/handoff/`, follow the handoff.

### Entry: Open and Recents

- The primary action is Open folder…, through Files, SD cards, or external drives.
- Recents shows a path summary, media type, count, and last-opened time. Tap an item to reopen its remembered location.
- There is no system photo library entry.
- The design contains a search field. Searching Recents has not been separately confirmed and is not P0.

### Scan scope

- Scan every subfolder of the opened folder recursively. Photos in SD-card folders such as `DCIM/100XXXXX` and `101XXXXX` appear together.
- Skip the rejects folder, `_Rejected` by default.
- Combine same-stem files case-insensitively within one folder: RAW+JPEG, RAW+HIF, and RAW+JPEG+HIF each take one grid cell, with RAW as primary. Companions are reference files and are never changed; ratings and labels use the RAW's shared sidecar.
- Support RAW alone and JPEG alone. Without RAW, JPEG is primary, then HIF. HIF-only and iPhone HEIC are shown when the system can preview them; fuller support is deferred. JPEG+HIF without RAW is unsupported, with generic handling accepted.
- Unreadable or unsupported files have a visible state. A blank preview must not be presented as loaded.

### Grid

- iPhone uses three columns. iPad uses five columns with a left sidebar for navigation and filters.
- Cells overlay a Reject flag, ratings, and color dots. RAW sets with JPEG and/or HIF companions have a badge.
- Sort by capture time by default, with subsecond precision, falling back to file creation time, then modification time. Never show temporary filename order first. Photos using fallback times are not grouped. Filename order remains an option.
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
| Rating from 0 to 5 | Tap a rating in the rating bar. Tap the same rating again to clear it. A star rating on a rejected photo replaces −1 with those stars. Only enabled ratings appear. |
| Color label | Red, yellow, green, blue, purple, and Clear by default. Settings can enable extended colors, orange and pink, matching Capture One. Use fixed English names in XMP, regardless of system language. |
| Reject | The rating −1. Swiping down, the HUD's Reject, or `↓` replaces the photo's stars with −1; turning Reject off leaves the photo unrated. The color label stays independent. Reject does not delete the original. |
| Undo | Uses the system undo mechanism: a toolbar Undo button, ⌘Z on an external keyboard, and the iOS three-finger undo gestures. Undoing after auto-advance returns to the photo whose mark was undone. Undo also covers Reject N unmarked and Move rejects, each as one step. |
| Save status | Writing…, Saved, or Write failed for XMP writes; Saved only after read-back confirmation. Confirm reject moves before showing success. Standalone JPEG/HIF marks show Saved in Clove only after confirmed app storage. Offer Retry after failure. |

### Batch writes with multi-select

Long-press the grid to select multiple photos, then apply ratings, labels, or Reject in one operation. Count successes and failures per photo. On partial success, keep successful writes saved and failed writes unsaved. Allow retrying only the failed items.

### Gestures and keyboard

Detail gestures:

| State | Action | Result |
| --- | --- | --- |
| Fit | Swipe up, by distance | Rate. On a rejected photo the stars replace Reject; the ladder never produces −1. |
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

1. Separate photos by camera model, plus body serial when present, then sort by capture time with subsecond precision. When serial is missing, fall back to model. Two bodies of the same model shooting the same scene at the same moment are unsupported; no extra work, UI, or setting is added for that case.
2. Split into runs by time gap: adjacent photos less than 2 seconds apart join the same run. This starting value is subject to real-sample checks, not a launch accuracy promise. This step reads only capture metadata, so it can appear shortly after the folder opens.
3. Split each run by visual similarity: compute on-device Vision features from 400 px embedded previews (feature revision 2), and split where adjacent distance exceeds 0.5. If Vision is unavailable, use dHash with a 12-bit cut-off; split when no usable feature exists. This runs in the background and refines the groups when done.

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

- Synchronized zoom: after zooming into an area in a group, navigating keeps the same zoom level and position. Always on in groups, with no toggle.
- Rejected photos are dimmed in the filmstrip. With Undecided only on, navigation skips rejected and rated photos.
- After marking, advance to the next undecided photo in the group.

Finishing action:

| Action | Result |
| --- | --- |
| Reject N unmarked | Reject every photo in the group that has no rating, no color label, and no Reject. Shown once any photo in the group is rated or labeled. To keep one photo and reject the rest, rate it, then use this action. |

- It never rejects a photo that already has a rating or color label.
- It follows batch-write rules for success and failure, and it can be undone as one step.

Group completion:

- Definition: every photo in the group is rated or rejected, or the user ran a finishing action.
- Setting, After a group is complete: stay in the group, or go to the next group (default). Going to the next group skips completed groups.

### Move rejects

Reject exists only for culling. After moving rejects, desktop software sees only the photos that were kept and does not need to know what was rejected.

- Trigger: the user taps Move rejects. It never runs automatically and can run at any time within a folder.
- Reject is the rating −1. A RAW set's sidecar holds it and moves with the set; a standalone JPEG/HIF keeps it in Clove. The move is the durable result.
- Confirmation: state how many photos will move, that JPEG and/or HIF companions and XMP move with them, and that originals are not deleted.
- Keeping before the move: the confirmation can show the rejects, and the user can tap a photo to keep it, or tap again to un-keep. A keep is only staged: nothing is written until Move, and dismissing the confirmation discards the keeps. On Move, kept photos have their Reject cleared by setting the rating to 0 (the label is untouched), and the rest move.
- Destination: `_Rejected/` under the opened folder. The name can be changed in Settings. Preserve the subfolder structure, so `DCIM/100XXXXX/IMG_0001.CR3` moves to `_Rejected/DCIM/100XXXXX/IMG_0001.CR3`.
- Move the photo set as one unit: the primary file, any JPEG and/or HIF companions, and the matching XMP.
- Move only within the same volume. Never copy and then delete.
- If a file with the same name exists at the destination, add a suffix. Never overwrite.
- Count successes and failures per photo. On partial failure, moved photos stay moved, failed photos stay in place, and the user can retry only the failures.
- Read-only locations cannot be organized. Reuse the view-only message.
- Moved photos disappear from the grid, and later scans skip `_Rejected`.
- Undo: after a move, Undo moves the files back to their original paths and re-rejects them and any photos kept in the confirmation by writing −1 again, as one undo step. It never overwrites a file that now occupies an original path; such a set stays in `_Rejected` and is reported. Restoring moves outside the undo history is not in launch scope: the user moves those files back. A RAW set then carries its rating −1 back with its sidecar; a standalone JPEG/HIF is not rejected again.
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

XMP on disk is the source of truth for RAW photo sets' persisted ratings, Reject included as −1, and labels. New standalone JPEG/HIF marks live in Clove's app storage. Saved refers to confirmed XMP writes and reject moves; standalone marks use Saved in Clove only.

1. Read existing XMP for RAW sets and embedded ratings and labels for standalone JPEG/HIF before displaying persisted marks. Read a standalone photo's Clove-stored marks from app storage.
2. Never modify original image contents at launch. RAW sets write only XMP sidecars; their JPEG/HIF companions are never changed.
3. Name sidecars by replacing the extension, so `IMG_0001.CR3` maps to `IMG_0001.xmp`. A RAW+JPEG, RAW+HIF, or RAW+JPEG+HIF set shares one sidecar. Reuse existing `.xmp`/`.XMP` spelling. Treat appended-extension names such as `IMG_0001.CR3.xmp` or competing packets as ambiguity; never create a second packet. Desktop-app checks remain required.
4. Write ratings to the standard rating field and color labels to the standard label field.
5. Write Reject as the standard rating −1: to the shared sidecar for a RAW set, and to Clove for a standalone JPEG/HIF. There is no separate Reject field, no Clove namespace, no Also write Rating −1 setting, and no saved prior rating. Rejecting replaces the stars, and clearing Reject writes rating 0.
6. Standalone JPEG/HIF, including previewable iPhone HEIC, get no sidecar. Read embedded ratings and labels; keep new marks in Clove with a visible Saved in Clove only status. In-file JPEG writing is a later feature; HIF/HEIC in-file writing stays out. Standalone DNG is RAW and uses a sidecar.
7. Show requested marks immediately, before any write finishes. Every screen, filter, count, and marking rule reads the desired marks until that revision or a newer one confirms. Queue marks, batches, group finishing, keeps, moves, move undo, and retries synchronously in user action order. A move waits for earlier writes, then re-plans from current desired rejects and the files now on disk. Confirmation counts are a preview; report any difference in the result. Closing a folder drains the action pipeline first, and the leave question counts photos with desired marks not yet confirmed. Confirm each change in the storage it uses. Show Saved for XMP ratings and labels, Reject included, only after read-back matches; show success for a reject move only after confirmation. Standalone marks show Saved in Clove only after confirmed app storage. Pending, failed, or unconfirmed changes must not show success.
8. Retain the user's requested marks on screen after a write failure, with the Failed glyph and tile corner dot, so they can retry. Show one small toast per failure burst, "Some marks weren't saved." with Retry, and announce that text with VoiceOver. Hide the toast after about six seconds; the marks and failure indicators remain. Drive loss and lost access use the error banner instead. The newer save-failure or Move rejects toast replaces the older one. A tap on Failed retries all failed photos together, including single marks and batch marks. Do not treat them as saved before a successful retry. A move undo or a retry that restores a keep or clear changes a photo only while its current desired marks still equal what that action left. Otherwise keep the newer marks and report the photo as changed since.
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

If users leave before writes finish, unconfirmed changes are not saved. The next open reads the actual XMP for RAW ratings and labels, embedded standalone marks, and confirmed Clove-stored state.

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

The primary input is camera files: RAW alone, RAW+JPEG, RAW+HIF, RAW+JPEG+HIF, and JPEG alone. RAW, including DNG, is primary when present; same-name JPEG/HIF files in the same folder are reference companions. Without RAW, JPEG is primary, then HIF. HIF-only and iPhone HEIC appear when the system can show a preview; fuller support is deferred, with no in-file writing or extra format work. JPEG+HIF without RAW is unsupported and follows generic rules. HEIF extensions include `.HEIC`, `.HEIF`, and `.HIF`. No custom RAW decoder at launch.

The following are source-derived public facts, not a compatibility guarantee tested by Clove:

- Prefer system image capabilities for grid and detail previews. Engineering research recommends embedded previews for the grid and full RAW processing only when needed for detail. Double-tap to 100% first enlarges the embedded preview, then decodes the full RAW when needed. See the [engineering research source](https://app.notion.com/p/41237873fb548107bd96d0f6838b1200).
- Apple publishes iOS camera RAW support. Engineering research cites the [iOS 18 support page, dated July 2025](https://support.apple.com/en-us/120534). The list changes with OS updates. Apple provides basic DNG support for unlisted models. Some models support only uncompressed, lossless, or single-shot RAW.
- Clove opens the supported camera sets above when the system can generate previews; standalone HIF and iPhone HEIC are shown when possible as deferred features. Camera and compression-format support depends on the system on the user's device. This document does not create a guaranteed camera list.
- DNG files, such as iPhone ProRAW, Leica, and Pentax, remain RAW for both display and sidecar writes. Broader iPhone-file work waits for photo library support. See item 6 under How marks reach disk.
- Unsupported files or compression formats require a visible explanation. A blank preview must not be presented as loaded.
- [G1's starting performance targets](decisions/G1-technical-approach.md#starting-performance-targets-iphone-for-m3-and-q3) guide engineering checks for M3 and Q3. They are based on one iPhone with local storage, are revisited after the card and iPad checks, and are not launch promises or folder-size limits.

Launch has no system photo library entry. If one is added later, it must not become a temporary viewing session without XMP writes, and it needs a separate decision.

## Privacy and offline use

- The main flow works in the user's folders. RAW ratings, Reject included, and labels live in sidecars there. New standalone JPEG/HIF marks live in Clove's app storage.
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
- Move confirmation: Move N rejected photos, with their JPEG/HIF companions and XMP, to the "_Rejected" folder? Originals won't be deleted. Actions: Move / Cancel
- Partial move failure: Moved N photos. M photos couldn't be moved. Actions: Retry unmoved items / Cancel
- Standalone marks: Saved in Clove only.

## Acceptance by P0 ID

These manual tests determine whether launch meets product requirements. They are not performance benchmarks.

| ID | Passing condition |
| --- | --- |
| P0-01 | Through Files, open any accessible folder on the iPhone 17 Pro Max: local storage, or the CFexpress Type A USB reader when available. SD readers and other external drives remain supported-media examples; removable-media checks do not block MVP acceptance. Photos from multiple subfolders under `DCIM` appear in the grid, and photos in `_Rejected` do not. Same-name RAW+JPEG, RAW+HIF, and RAW+JPEG+HIF sets each take one cell with RAW as primary. RAW alone and JPEG alone appear; HIF-only and iPhone HEIC appear when previewable. JPEG+HIF without RAW has no special handling. No imported copy of originals appears in the app's directory. |
| P0-02 | Fully quit the app, then reopen the same folder through Recents. After disconnecting the drive or revoking permission, the same action explains how to select the folder again rather than failing silently. |
| P0-03 | Scroll a RAW folder with embedded previews and use its thumbnails to browse. Unreadable files have explicit states. A folder shot with two bodies sorts correctly by capture time with subseconds, using creation time then modification time when capture time is missing; fallback photos are not grouped. No temporary filename order appears first, and the user can switch to filename order. Each of the four filters shows only matching photos. |
| P0-04 | In detail, pinch to zoom, or double-tap to 100% and double-tap back to fit. Edge taps navigate to previous and next photos, including while zoomed, without perceptible delay. Current ratings, Reject, and labels are visible away from the hand. |
| P0-05 | Apply ratings, labels, and Reject, where Reject is the rating −1 and replaces the stars. Clearing Reject leaves the photo unrated. Original bytes remain unchanged. RAW ratings, Reject included, create or update the shared sidecar; standalone JPEG/HIF marks stay in Clove without a sidecar. Tapping the same rating in the rating bar clears it. Rejected originals remain in place. Undo restores the previous mark, including the stars a Reject replaced, and undoing after auto-advance returns to that photo. |
| P0-06 | Swiping up different distances produces different ratings, with the current step visible and a haptic at each step. Returning to the start before release writes nothing. With only 1 through 3 enabled, the maximum applied rating is 3 and existing 5-star ratings still display. Keys work as listed. Auto-advance follows settings, and labels do not trigger it by default. |
| P0-07 | Clove displays ratings and labels previously written by Lightroom, Capture One, or Photo Mechanic, and reads `xmp:Rating="-1"` as Rejected. Those apps read Clove's XMP ratings and labels for RAW sets. Each RAW set, including a RAW+JPEG+HIF triple, has one XMP; standalone DNG uses a sidecar too. Other preexisting XMP information survives the write, including an out-of-range rating such as `6` or `-2`, which reads as unrated, and companions remain unchanged. Reject is written as the standard rating −1, with no Clove namespace. Standalone JPEG/HIF embedded marks are read; new marks, Reject included, create no sidecar or in-file change and show Saved in Clove only. |
| P0-08 | Hold a write and verify its mark appears immediately; make two quick marks and verify write order. Force a connected failure and verify one “Couldn't save the mark.” toast, a fresh file read and the file's marks on screen. Verify no save subtitle, failure marker, retry or leave prompt. Disconnect through a real folder session and verify queued marks are dropped, marking stays disabled until Reopen, and Reopen reads fresh sidecars. A partial Move Rejects result reports the unmoved count with Undo and shows what remains on disk. |
| P0-09 | Long-press, select multiple photos, and rate them in a batch. Force some writes to fail. Report Saved N photos. M photos couldn't be saved. Successful items stay saved and failed items can be retried separately. |
| P0-10 | Reject several photos, including RAW+JPEG, RAW+HIF, and RAW+JPEG+HIF sets across multiple subfolders, then run Move rejects. The confirmation shows the correct count. Afterward, every set's RAW, JPEG and/or HIF companions, and XMP are in the matching subfolders under `_Rejected`, no file was deleted or overwritten, and the photos no longer appear in the grid. A moved RAW set's sidecar holds the rating −1. Forced name collisions add a suffix, and forced partial failures report Moved N photos. M photos couldn't be moved. Running it on a read-only location shows the view-only message. A photo kept in the confirmation stays in place with its rating set to 0. Undo after the move returns every moved file to its original path and writes Reject (−1) again. |
| P0-11 | Opening a folder with bursts starts grouping automatically: groups appear by time first, then refine, and Run again is available. The photo being viewed does not jump during grouping. Grouping separates by model and serial when present, falling back to model when serial is missing; two same-model bodies shooting the same scene at the same moment are unsupported. Photos with only fallback file times are excluded. Starting values are a gap below 2 seconds and a split above Vision distance 0.5. All XMP is unchanged before and after grouping. Turning similar groups off hides entry points and blue outlines while the main flow still works. |
| P0-12 | In a group of 20 or more photos: zooming into an area keeps the same position while navigating. Undecided only skips marked photos. Reject N unmarked rejects only photos with no rating, label, or Reject; photos that already had ratings or labels are not rejected. A completed group advances to the next group according to settings. Reject N unmarked can be undone as one step. |
| P0-13 | Complete the flow on both iPhone and iPad: open folder → grid → mark in detail → cull a group → move rejects → quit and reopen with marks intact. |
| P0-14 | Open and mark on the Duo cover screen. Unfold and retain the same folder, photo, marks, and group-view position, with grid and detail split by default. Half-folded filters, marking controls, and bottom bar never cross the hinge. |
| P0-15 | Switching system appearance updates entry, grid, detail, similar groups, the group view, and all Duo postures between light and dark. |

Additional interoperability acceptance: alternate between Clove and Photo Mechanic or Lightroom on the same RAW folder. Each reads the other's XMP ratings and labels.

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

The [G1 decision](decisions/G1-technical-approach.md) settles the metadata-writing approach and starting grouping thresholds. The remaining desktop-app checks must run before C3 is called done. [#29](https://github.com/mimiqdev/cloveapp/issues/29) tracks the remaining external-media, iPad, and desktop-app checks. Removable media is not on the MVP critical path; external-media checks are non-blocking and use the CFexpress Type A USB reader first when convenient. iOS treats it as an external drive, like an SSD; SD cards are not the owner's workflow. G2 uses any folder Files can open on the iPhone 17 Pro Max, including local storage or that reader when available. [#18](https://github.com/mimiqdev/cloveapp/issues/18) keeps the Duo run open. Results can revise the implementation and starting targets; scope changes return to the product owner.

- Lightroom reads embedded JPEG metadata, Photo Mechanic embeds JPEG ratings, and Capture One's standalone JPEG sidecar behavior remains unclear. G1 therefore keeps new standalone JPEG/HIF marks in Clove; DNG remains RAW with a sidecar.
- Verify the three desktop apps' handling of replacement-extension sidecars and one sidecar shared by a RAW photo set, including JPEG/HIF companions.
- The XMP English names for Capture One's extended colors, orange and pink, and how Lightroom and Photo Mechanic treat those values.
- Whether non-English Lightroom localizes label names so fixed English names do not match. If so, help content must explain how to switch back to the default label set.
- Metadata-writing feasibility is settled: JPEG supports a lossless packet splice, deferred to later C7; ImageIO HIF/HEIC writing drops data, and DNG has no writer. DNG therefore uses a sidecar.
- Starting grouping values are settled: 2 seconds and Vision distance 0.5. The swipe distance per rating step still needs tuning.

## 1.1 candidates

- AI best-shot suggestion within a group, possibly using system aesthetic scoring
- Low-quality and blur suggestions
- Manually splitting similar groups, preserved across Run again
- Duo Overlay and a dedicated Duo half-fold layout
- Restoring moved rejects outside the undo history
- Double-tap to toggle a chosen color label, as an alternative double-tap behavior

## Open decisions

Only unresolved items that affect launch commitments are listed here.

- Pricing. Sources contain no decision on free, one-time purchase, or subscription.
- The design handoff's (proposed) items: keyboard shortcuts, long press, auto-advance timing, toast timings, and icons.

The following are not launch commitments or numeric acceptance criteria: performance timings, grouping accuracy, guaranteed camera or storage-brand lists, and folder-size limits. Any later targets require measurement and separate approval.
