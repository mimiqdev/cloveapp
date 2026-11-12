# Clove MVP: screens and states

Every screen and state in the MVP, grouped by flow, with its Figma frame. Each frame holds the **Light** and **Dark** versions side by side. Any other theme is the same layout with a different variable mode (see `tokens/`).

Link base: `https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=<id with - instead of :>`. A machine-readable list is in `frames.json`. Every state also has a 1x PNG of its whole frame in `screens/` (the **png** link next to it), so the spec can be used without Figma access.

When this spec and the Figma frame disagree on layout or pixels, Figma wins. When they disagree on behavior, this spec wins (some frames show one moment of a flow).

Devices:
- **iPhone**: the base design. Everything not called out per device follows iPhone.
- **iPad**: sidebar plus grid; detail with a right rail.
- **Duo cover**: the folded phone's outer screen. Same as iPhone, with the side rail that Apple's Duo guidance puts next to the status bar.
- **Duo expanded**: the unfolded inner screen, in landscape. Every button lives in a right dock. Nothing sits on the fold.
- **Duo half fold**: a quick refresh only. The dedicated layout is planned for 1.1.

---

## Themes

| State | Node | Notes |
|---|---|---|
| [Theme board](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=181-2391) · [png](screens/00-themes-theme-board.png) | 181:2391 | All 8 palettes with every token. |
| [Live demo](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=215-1878) · [png](screens/00-themes-live-demo.png) | 215:1878 | The same grid and detail in Darkroom, Mocha, Nord and Gruvbox. Use it to check a theme implementation. |
| [Group wrapper options](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=208-1154) · [png](screens/00-themes-group-wrapper-color-options.png) | 208:1154 | An exploration. Option C (a muted accent tint) was chosen. Don't build the others. |

## 01 Entry (iPhone; iPad and Duo reuse it with wider margins)

| State | Node |
|---|---|
| [Resume first](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=187-1308) · [png](screens/01-entry-resume-first-has-recent-folders.png) | 187:1308 |
| [First launch](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=189-1396) · [png](screens/01-entry-first-launch-no-folders-yet.png) | 189:1396 |

**Resume first** (the app has opened folders before)
- A large title, with Settings as a gear icon at the top right.
- **Hero card**: the last folder. It shows the photo you stopped on, full bleed, with "Continue · Yesterday", the folder name, the source (card, drive or Files) and "412 left". A thin progress line at the bottom shows marked, rejected (in the reject color) and left. Tapping anywhere on the card reopens the folder at that photo.
- **Earlier** list: one row per folder, with a strip of 3 of that folder's own thumbnails, then the name and source, then the count and date. A finished folder shows "Done" in `status/saved`.
- A folder whose drive is missing shows as a faded row with a **Reconnect** chip. It is not shown as red error text.
- **Open folder** is a small glass capsule at the bottom center.

**First launch** (no folders yet)
- Fanned empty photo frames, the line "Cull where your photos live.", the line "Open a folder on a card, drive or Files. Nothing is imported or copied." and a filled **Open folder** button.

## 02 Grid (iPhone)

| State | Node |
|---|---|
| [Default](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=159-1596) · [png](screens/02-grid-default.png) | 159:1596 |
| [Filter menu](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=159-2251) · [png](screens/02-grid-filter-menu-unmarked-active.png) | 159:2251 |
| [Select mode](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=176-2767) · [png](screens/02-grid-select-mode-batch-capsule.png) | 176:2767 |
| [Read failure toast](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=243-3739) · [png](screens/02-grid-read-failure-toast.png) | 243:3739 |
| [Opening 1: reading](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=211-1741) · [png](screens/02-grid-opening-1-reading-photos.png) | 211:1741 |
| [Opening 2: grouping](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=211-2332) · [png](screens/02-grid-opening-2-finding-similar-shots.png) | 211:2332 |
| ["…" menu and no-preview tile](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=213-1422) · [png](screens/02-grid-more-menu-no-preview-tile.png) | 213:1422 |

**Default**
- The top bar has Back, the folder title, the subtitle "1,284 photos", then the **Filter** and **"…"** icon buttons. There is no filter bar, status row or bottom toolbar.
- A **group** of similar shots is one stacked tile with a count badge in `group`. Tapping it opens detail on the first unmarked member, or the first member if all are marked, with the filmstrip group expanded. A single photo opens detail.
- A **rejected** photo is dimmed (`opacity/rejected`) with no ✕ badge. The rating badge and label dot stay. The RAW+JPEG badge is only in Info.
- **Move Rejects** is a 48 pt round glass icon button (a tray with a down arrow) at the bottom right. It has no count and shows only when rejects exist. It always opens the confirm sheet first.

**Filter menu**: All, Unmarked and Rejected with counts, then Rating ≥ and Label. While a filter is active the button is filled with `accent` and the subtitle names the filter ("Unmarked · 812").

**Select mode**: the title becomes "7 selected" and **Done** replaces Filter, "…" and Move Rejects. Selected tiles get the standard blue check, the only place a check is used. The same mark capsule as detail appears and applies to the whole selection.

**Read failure toast**: when a sidecar can't be read while a folder opens, one glass toast at the bottom (the Move Rejects toast position) says "Couldn't read some marks." It has no action and hides after about 6 seconds. There is no save status anywhere: no Saved dot, no Saving pulse, no batch result toast. A failed batch mark shows the save failure toast below.

**Opening a folder.** There is no blocking screen. The grid shows straight away.
- Stage 1, reading: the subtitle is "412 of 1,284", a 2 pt line under the toolbar fills in `accent`, unread cells are plain placeholders, and there are no stacks yet. Existing XMP marks appear as they are read.
- Stage 2, grouping: the subtitle is "Finding similar shots…", the line switches to `group`, and stacks form one by one. The photo being viewed never jumps.
- Move Rejects is hidden while opening.

**"…" menu**: Sort by (Capture time ✓ or Filename), Select, Find similar shots again, Settings.
**No-preview tile**: a plain `surface/card` tile with the file type ("CR3") and "No preview".

## 03 Detail (iPhone)

| State | Node |
|---|---|
| [Default](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=154-1356) · [png](screens/03-detail-default-floating-capsule.png) | 154:1356 |
| [Label popover](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=154-1653) · [png](screens/03-detail-label-popover-open.png) | 154:1653 |
| [Swipe-up star bar](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=154-1968) · [png](screens/03-detail-swipe-up-star-bar.png) | 154:1968 |
| [Info sheet](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=157-1584) · [png](screens/03-detail-info-sheet.png) | 157:1584 |
| [Rejected (corner glyph)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=176-2070) · [png](screens/03-detail-rejected.png) | 176:2070 |
| [Save failure toast](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=176-2301) · [png](screens/03-detail-save-failure-toast.png) | 176:2301 |
| [100% zoom](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=176-2532) · [png](screens/03-detail-100pct-zoom-chrome-hidden.png) | 176:2532 |
| [Swipe star bar: cleared step (proposal, #125)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=244-1984) · [png](screens/03-detail-swipe-star-bar-cleared-step-proposal.png) | 244:1984 |

**Default**
- The photo sits on `bg/stage`.
- The top bar has Back, the filename as the title, and the subtitle "1 / 11 · + JPG" (no loading or save label). On the right are **Info (ⓘ)** and **Undo**.
- Marks appear **once**, in the floating glass **mark capsule** above the home indicator. Left to right: the reject circle, 5 stars, and the label circle.
- The **filmstrip** floats just above the capsule. Both fade out while zoomed, and tapping the photo toggles them.

**Label popover**: tapping the label circle pops 5 color dots (plus none) above the capsule. Picking one closes it.

**Swipe-up star bar**: swiping up on the photo shows a compact vertical bar of empty stars that fill from the bottom as you drag, up to the enabled levels. A ✕ chip below it is the swipe-down reject. The bar appears beside where the swipe started: vertically centred on the touch start, 24 pt to the left of the finger (to its right when the touch starts in the left third), kept inside the stage clear of the top bar and filmstrip. It stays put for the rest of the swipe, so the finger moves along it. The grey circles in the frame mark the touch and are not drawn in the app. The capsule stars preview the live value.

**Info sheet** (medium detent, read-only in the MVP)
- Capture: time with subseconds, camera and serial, lens, exposure.
- File: folder, size, RAW+JPEG pairing, and marks and where they are stored (XMP). There is no save status line.

**Rejected**: the capsule's reject circle is filled and the stars and label go neutral. The photo stays at full brightness. A 22 pt `xmark` in a filled `reject` circle sits in the stage's top-trailing corner, inset 8 pt inside the safe area. It stays fixed during zoom and pan and remains visible with the chrome hidden. It ignores taps; VoiceOver includes "Rejected" in the photo's label and skips the decorative glyph. Rejected has no subtitle word.

**Save failure toast**: when a mark can't be written, one glass toast says "Couldn't save the mark." with no action, and the photo goes back to the marks in its file. There is no subtitle status and no Retry. One toast per failure burst; it hides after about 6 seconds. In the frame it sits above the filmstrip so it doesn't cover the capsule; the build currently draws it at the bottom edge over the capsule (see the note in `decisions-log.md`).

**Swipe star bar: cleared step (proposal, #125, not reviewed)**: a quick swipe down from a rated photo now stops at 0 before Reject. The proposal shows three stops on a 3★ photo: A start (no chip), B cleared (all stars empty, the chip slot shows `star.slash` in `text/secondary`), C reject (the chip fills in `reject` with a white ✕ and the stars dim). The bar sits beside the touch start, as in the swipe-up frame. Waiting on the designer.

**100% zoom**: the capsule, filmstrip, Info and Undo hide. The subtitle shows "100%", and a small "100%" chip fades out.

In every filmstrip, rejected thumbnails are dimmed and have no badge.

## 04 Groups in detail

There is no group review screen. A stack opens the normal detail screen with its group expanded in the filmstrip. There is no group header, no undecided count, no Continue → and no "Undecided only" menu.

| State | Node |
|---|---|
| [iPhone](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=173-1950) · [png](screens/04-groups-in-detail-iphone.png) | 173:1950 |
| [iPad (provisional)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=214-2931) · [png](screens/04-groups-in-detail-ipad.png) | 214:2931 |
| [Duo expanded (photo only)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=214-3214) · [png](screens/04-groups-in-detail-duo-expanded.png) | 214:3214 |

- A grid stack opens detail at its first unmarked member, or its first member when all are marked. The ordinary detail header and controls remain.
- The current group expands in the grid-order filmstrip; rejected thumbnails are dimmed and rated ones show stars.
- Zoom and pan stay synced within the group. Leaving it follows the detail setting.
- **Reject N unmarked** is a pill centred in its own row above the strip. It requires a rated or labeled visible member and at least one unmarked visible member, and never touches existing marks or hidden photos. Undo restores the action together and returns to the photo shown at submission.
- The pill hides with chrome or when marking is off, and disappears when nothing remains to reject. It stays clear of the capsule and swipe star bar.
- Auto-advance visits unmarked members, then the first photo after the group in grid order. No group sidebar remains.
- On iPad and Duo the pill sits centred at the bottom of the photo stage, above the filmstrip, never under the rail or dock.

## 05 Move Rejects

| State | Node |
|---|---|
| [Confirm sheet](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=161-1716) · [png](screens/05-move-confirm-sheet.png) | 161:1716 |
| [Quick grid (tap to keep)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=162-1776) · [png](screens/05-move-expanded-quick-grid-tap-to-keep.png) | 162:1776 |
| [Toast with Undo](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=211-2923) · [png](screens/05-move-done-toast-with-undo.png) | 211:2923 |
| [Partial failure](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=211-3532) · [png](screens/05-move-done-partial-failure-toast.png) | 211:3532 |
| [Details sheet](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=217-1928) · [png](screens/05-move-couldnt-move-details-sheet.png) | 217:1928 |

- **Confirm sheet**: a small sheet over the grid showing a fanned stack of the rejected thumbnails, "Move 42 rejected photos", "To _Rejected in this folder. Nothing is deleted." and one **Move** button. Swiping down cancels.
- **Quick grid**: tapping the stack expands the sheet into a 4-column grid of the rejects, all dimmed. Tapping a photo keeps it: it returns to full brightness with no badge, and the button updates to "41 of 42 will move" / "Move 41". Keeping clears that photo's reject flag, but only when Move is tapped; cancelling the sheet discards the keeps. Undo restores both the move and the flags.
- **Done**: the moved photos leave the grid, and a glass toast says "Moved 42 to _Rejected" with **Undo**.
- **Partial failure**: the toast says "Moved 40 to _Rejected", then "2 couldn't be moved" in `reject`, with **Details**.
- **Details sheet**: the title is "2 photos couldn't be moved" and the subtitle is "They stay rejected in place. Nothing was deleted." There is one row per photo set, with a thumbnail, the file name and the reason in `reject`, then one **Done** button. There is no Try again.

## 06–07 iPad

| State | Node |
|---|---|
| [Grid (provisional)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=166-1836) · [png](screens/06-ipad-grid.png) | 166:1836 |
| [Grid: Locations, subfolder selected (provisional)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=243-1957) · [png](screens/06-ipad-grid-locations-subfolder.png) | 243:1957 |
| [Detail (provisional)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=166-2591) · [png](screens/06-ipad-detail.png) | 166:2591 |
| [Detail: rejected (provisional)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=243-2691) · [png](screens/06-ipad-detail-rejected.png) | 243:2691 |

The iPad frames were drawn before the sidebar (#170) and the detail rail (#174) were built. Where a frame disagrees with the build, the build wins.

- **Sidebar**, top to bottom, a plain list with one selected row:
  - **Header**: the folder name and the source line ("External SSD · T7 Shield"), with no save word.
  - **Locations**: "All" with the photo count, then one row per subfolder that holds photos (`DCIM/100CANON`). The section appears only when photos occupy more than one folder. `_Rejected` isn't listed and there is no "Skipped" row.
  - **Filters**: Unmarked, Rejected, then one "★n+" row for each rating that has photos.
  - **Color labels**: one row per label in use, with its dot, name and count. Hidden when no photo has a label.
  - **Similar groups**: one row, "86 groups", with a small regroup glyph button (Find similar shots again). A spinner replaces the button while grouping runs. There is no "Analyzed" word. Hidden when similar groups are off.
- **Grid**: the title is the selected sidebar row's name ("All", "Unmarked", "Red", "DCIM/100CANON") and the subtitle is the count ("1,284 photos"). There is no Filter button. The top right has Move Rejects (only when rejects exist) and "…", as 40 × 40 glass icon buttons. Move Rejects is never at the bottom right on iPad. Stacks and dimmed rejects work as on iPhone.
- **Detail** and Settings open full screen with a back button named after the selected row, such as "‹ All" or "‹ Unmarked". The old grid-beside-detail layout is removed. A 96 pt right rail replaces the capsule. It sits beside the stage, never over it, and never hides: a single tap or zoom hides the filmstrip, the Reject N unmarked pill and the top bar buttons, while the stage keeps its size. Top to bottom: a vertical 5-star bar that fills from the bottom (tap, or drag and release), a hairline, the reject circle, a hairline, and the five label dots, tapped directly with no popover. The current label has a ring. Tapping the current rating or label clears it. Each rail control has a hover tooltip with its VoiceOver label (the frame shows "Reject"). Info and Undo are 40 × 40 in the top bar. Swipe marking on the photo still works; the rail stars show the live value. There are no keyboard hints.
- **Rejected**: the rail's reject circle is filled, the stars and dots go neutral, and the corner glyph sits in the stage's top-trailing corner, left of the rail.
- **Filmstrip** (at the bottom, following grid order): every group except the current one is collapsed into one stacked tile with a count badge in `group`. The current group is expanded in place on a tint of `group` at 25% layer opacity, with no outline. The current frame has a thin ring in `text/primary`.

## 08–09 Duo

| State | Node |
|---|---|
| [Cover](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=167-1856) · [png](screens/08-duo-cover-folded-outer-screen.png) | 167:1856 |
| [Expanded: grid (default)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=167-2521) · [png](screens/08-duo-expanded-grid-default-full-width.png) | 167:2521 |
| [Expanded: photo focus 30/70](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=196-1119) · [png](screens/08-duo-expanded-photo-focus-30-70.png) | 196:1119 |
| [Expanded: photo focus, rejected](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=243-2960) · [png](screens/08-duo-expanded-photo-focus-rejected.png) | 243:2960 |
| [Expanded: photo only](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=197-1161) · [png](screens/08-duo-expanded-photo-only.png) | 197:1161 |
| [Expanded: dock star bar](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=217-2575) · [png](screens/08-duo-expanded-dock-star-bar-sliding.png) | 217:2575 |
| [Expanded: dock label picker](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=217-3348) · [png](screens/08-duo-expanded-dock-label-picker.png) | 217:3348 |

**Cover**: the same grid as iPhone, with no save status. Detail on the cover is iPhone detail, including the reject corner glyph. The side rail holds Filter instead of Groups, and Move Rejects sits just under the status bar and Back. Select is in "…".

**Expanded** (landscape, unfolded). The rules follow Apple's Duo guidance:
- **The right dock** is a vertical column shared with the status bar, made of glass capsules from top to bottom:
  1. **Back**, on its own, at the top under the status bar.
  2. **View tools**: Filter, "…", Info.
  3. **Marks**, only while a photo is open: one star button showing the rating ("★ 2"), the reject circle, and one label circle showing the current color.
  4. **Bottom**: Undo, Move Rejects.
  The capsules are centered under the signal icon. The grid and photo have no buttons over them.
- **Grid (default)**: a full-width 6-column grid. The dock shows Back, view tools and the bottom capsule.
- **Photo focus 30/70**: tapping a photo splits the screen into the grid (30%) and the photo (70%). An 8 pt gutter with a hairline and a drag handle separates them. The split is never at 50/50 and never on the fold.
- **Photo only**: sliding the divider all the way left gives an iPad-style detail: a full-width photo, the filename and counter centered at the top, and the filmstrip (with collapsed group stacks) at the bottom.
- **Dock star bar**: sliding on the star button opens a vertical star bar to the left of the dock. It fills from the bottom, and the button shows the live value.
- **Rejected**: the dock's reject circle is filled, the star button and label circle go neutral, and the corner glyph sits in the photo pane's top-trailing corner. Nothing on the Duo shows a save dot or "Saved".
- **Dock label picker**: tapping the label circle opens a horizontal row of colors (none, red, yellow, green, blue, purple) beside it, with the current color ringed.

## 10 Duo half fold (quick refresh; the dedicated layout is 1.1)

| State | Node |
|---|---|
| [Refreshed](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=193-1172) · [png](screens/10-halffold-quick-refresh.png) | 193:1172 |

- The top half shows only the photo.
- The bottom half has the Filter and "…" icon buttons with Move Rejects beside "…", the grid, and the floating mark capsule.
- Nothing crosses the hinge.

## 11 Settings

| State | Node |
|---|---|
| [Theme picker](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=212-1394) · [png](screens/11-settings-theme-picker.png) | 212:1394 |

- **Appearance**: a "Match system light/dark" toggle and a picker of 8 mini previews, each drawn in its own theme. The footer reads "Photos are never tinted. Only the app around them changes."
- **Culling**: Similar groups (toggle), Auto-advance after marking (toggle), Rating scale (5 stars).
- **Move rejects**: Move Rejects (toggle) and Folder name (_Rejected). The footer says nothing is deleted.

## 12 Errors

| State | Node |
|---|---|
| [Drive disconnected](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=214-1484) · [png](screens/12-errors-drive-disconnected.png) | 214:1484 |
| [Lost access](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=214-2083) · [png](screens/12-errors-lost-access.png) | 214:2083 |

- **Drive disconnected**: the grid dims, the subtitle keeps the count and adds the `externaldrive.badge.xmark` glyph (VoiceOver: "Not connected"), and a glass banner says "The drive disconnected. Reconnect it, then reopen this folder." with **Reopen**.
- **Lost access**: the same pattern. The subtitle adds the `lock.fill` glyph (VoiceOver: "View only"), and the banner says "Access to this folder is no longer available." with **Open**.
- There is no "Leaving with unsaved marks" alert. Leaving never waits on saves.

## Not designed (build with system defaults, or ask)

- An empty folder (no supported photos). Suggested: the first-launch layout with "No photos in this folder."
- Keyboard shortcuts on iPad. The rail exists, but no shortcut sheet was designed.
- Metadata editing in Info, which is planned for later.
- Accessibility sizes and VoiceOver labels. Follow the system defaults; the labels are in `copy.md`.
