# Clove MVP: screens and states

Every screen and state in the MVP, grouped by flow, with its Figma frame. Each frame holds the **Light** and **Dark** versions side by side. Any other theme is the same layout with a different variable mode (see `tokens/`).

Link base: `https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=<id with - instead of :>`. A machine-readable list is in `frames.json`.

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
| [Theme board](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=181-2391) | 181:2391 | All 8 palettes with every token. |
| [Live demo](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=215-1878) | 215:1878 | The same grid and detail in Darkroom, Mocha, Nord and Gruvbox. Use it to check a theme implementation. |
| [Group wrapper options](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=208-1154) | 208:1154 | An exploration. Option C (a muted accent tint) was chosen. Don't build the others. |

## 01 Entry (iPhone; iPad and Duo reuse it with wider margins)

| State | Node |
|---|---|
| [Resume first](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=187-1308) | 187:1308 |
| [First launch](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=189-1396) | 189:1396 |

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
| [Default](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=159-1596) | 159:1596 |
| [Filter menu](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=159-2251) | 159:2251 |
| [Select mode](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=176-2767) | 176:2767 |
| [Batch result](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=176-3424) | 176:3424 |
| [Opening 1: reading](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=211-1741) | 211:1741 |
| [Opening 2: grouping](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=211-2332) | 211:2332 |
| ["…" menu and no-preview tile](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=213-1422) | 213:1422 |

**Default**
- The top bar has Back, the folder title, the subtitle "1,284 photos · ● Saved", then the **Filter** and **"…"** icon buttons. There is no filter bar, status row or bottom toolbar.
- A **group** of similar shots is one stacked tile with a count badge in `group`. Tapping it opens group review. A single photo opens detail.
- A **rejected** photo is dimmed (`opacity/rejected`) with no ✕ badge. The rating badge and label dot stay. The RAW+JPEG badge is only in Info.
- **Move Rejects** is a 48 pt round glass icon button (a tray with a down arrow) at the bottom right. It has no count and shows only when rejects exist. It always opens the confirm sheet first.

**Filter menu**: All, Unmarked and Rejected with counts, then Rating ≥ and Label. While a filter is active the button is filled with `accent` and the subtitle names the filter ("Unmarked · 812").

**Select mode**: the title becomes "7 selected" and **Done** replaces Filter, "…" and Move Rejects. Selected tiles get the standard blue check, the only place a check is used. The same mark capsule as detail appears and applies to the whole selection.

**Batch result**: a toast above the capsule says "Saved 5 · 2 failed · Retry".

**Opening a folder.** There is no blocking screen. The grid shows straight away.
- Stage 1, reading: the subtitle is "412 of 1,284", a 2 pt line under the toolbar fills in `accent`, unread cells are plain placeholders, and there are no stacks yet. Existing XMP marks appear as they are read.
- Stage 2, grouping: the subtitle is "Finding similar shots…", the line switches to `group`, and stacks form one by one. The photo being viewed never jumps.
- Move Rejects is hidden while opening.

**"…" menu**: Sort by (Capture time ✓ or Filename), Select, Find similar shots again, Settings.
**No-preview tile**: a plain `surface/card` tile with the file type ("CR3") and "No preview".

## 03 Detail (iPhone)

| State | Node |
|---|---|
| [Default](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=154-1356) | 154:1356 |
| [Label popover](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=154-1653) | 154:1653 |
| [Swipe-up star bar](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=154-1968) | 154:1968 |
| [Info sheet](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=157-1584) | 157:1584 |
| [Rejected](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=176-2070) | 176:2070 |
| [Save failed](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=176-2301) | 176:2301 |
| [100% zoom](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=176-2532) | 176:2532 |

**Default**
- The photo sits on `bg/stage`.
- The top bar has Back, the filename as the title, and the subtitle "1 / 11 · + JPG · ● Saved". On the right are **Info (ⓘ)** and **Undo**.
- Marks appear **once**, in the floating glass **mark capsule** above the home indicator. Left to right: the reject circle, 5 stars, and the label circle.
- The **filmstrip** floats just above the capsule. Both fade out while zoomed, and tapping the photo toggles them.

**Label popover**: tapping the label circle pops 5 color dots (plus none) above the capsule. Picking one closes it.

**Swipe-up star bar**: swiping up on the photo shows a compact vertical bar of empty stars that fill from the bottom as you drag, up to the enabled levels. A ✕ chip below it is the swipe-down reject. The capsule stars preview the live value.

**Info sheet** (medium detent, read-only in the MVP)
- Capture: time with subseconds, camera and serial, lens, exposure.
- File: folder, size, RAW+JPEG pairing, marks and where they are stored (XMP), and save status.

**Rejected**: the capsule's reject circle is filled, the stars and label go neutral, and the photo dims. The subtitle is "1 / 11 · Rejected · ● Saved".

**Save failed**: the subtitle is "1 / 11 · ● Save failed · Retry", in `status/failed`, and Retry is tappable. The marks stay as set.

**100% zoom**: the capsule, filmstrip, Info and Undo hide. The subtitle shows "100%", and a small "100%" chip fades out.

In every filmstrip, rejected thumbnails are dimmed and have no badge.

## 04 Group review

| State | Node |
|---|---|
| [In progress (iPhone)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=173-1950) | 173:1950 |
| [Group done (iPhone)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=173-2193) | 173:2193 |
| [iPad](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=214-2931) | 214:2931 |
| [Duo expanded](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=214-3214) | 214:3214 |

- Marking works the same way as in detail: the capsule, the swipe-up star bar, and Undo in the top bar. The "…" menu holds "Undecided only" and the group options.
- The header is "Group · 12 photos" with the subtitle "6 undecided · ● Saved".
- The filmstrip is the progress indicator: rejected thumbnails are dimmed and rated ones show stars. There is no progress bar.
- Zoom is always synced across the group, with no toggle.
- **One finishing action**: the pill "Reject 6 unmarked" appears above the capsule once any photo is rated or labeled. It never touches rated or labeled photos.
- When every photo is decided, the pill becomes **"Continue →"**, which goes to the next item in grid order (a group opens group review, a single photo opens detail). After the last item it returns to the grid where you left off.
- On iPad and Duo the screen is built from that device's photo-only layout. The filmstrip shows only this group, and the pill sits above the strip.

## 05 Move Rejects

| State | Node |
|---|---|
| [Confirm sheet](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=161-1716) | 161:1716 |
| [Quick grid (tap to keep)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=162-1776) | 162:1776 |
| [Toast with Undo](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=211-2923) | 211:2923 |
| [Partial failure](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=211-3532) | 211:3532 |
| [Details sheet](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=217-1928) | 217:1928 |

- **Confirm sheet**: a small sheet over the grid showing a fanned stack of the rejected thumbnails, "Move 42 rejected photos", "To _Rejected in this folder. Nothing is deleted." and one **Move** button. Swiping down cancels.
- **Quick grid**: tapping the stack expands the sheet into a 4-column grid of the rejects, all dimmed. Tapping a photo keeps it: it returns to full brightness with no badge, and the button updates to "41 of 42 will move" / "Move 41". Keeping clears that photo's reject flag, but only when Move is tapped; cancelling the sheet discards the keeps. Undo restores both the move and the flags.
- **Done**: the moved photos leave the grid, and a glass toast says "Moved 42 to _Rejected" with **Undo**.
- **Partial failure**: the toast says "Moved 40 to _Rejected", then "2 couldn't be moved" in `reject`, with **Details**.
- **Details sheet**: the title is "2 photos couldn't be moved" and the subtitle is "They stay rejected in Clove. Nothing was deleted." There is one row per photo set, with a thumbnail, the file name and the reason in `reject`, then **Done** and **Try again**.

## 06–07 iPad

| State | Node |
|---|---|
| [Grid](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=166-1836) | 166:1836 |
| [Detail](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=166-2591) | 166:2591 |

- **Grid**: the sidebar is the filter (All, Unmarked, Rejected, ratings, labels), so there is no Filter button. The top right has only "…" and Move Rejects, a small icon button beside it. Move Rejects is never at the bottom right on iPad. Stacks, dimmed rejects and the save status in the subtitle work as on iPhone.
- **Detail**: the right rail has a vertical 5-star bar that fills from the bottom, the reject circle, and the label dots. Info and Undo are in the top bar. There is no sync-zoom control, no "Saved" label and no keyboard hints.
- **Filmstrip** (at the bottom, following grid order): every group except the current one is collapsed into one stacked tile with a count badge in `group`. The current group is expanded in place on a tint of `group` at 25% layer opacity, with no outline. The current frame has a thin ring in `text/primary`.

## 08–09 Duo

| State | Node |
|---|---|
| [Cover](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=167-1856) | 167:1856 |
| [Expanded: grid (default)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=167-2521) | 167:2521 |
| [Expanded: photo focus 30/70](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=196-1119) | 196:1119 |
| [Expanded: photo only](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=197-1161) | 197:1161 |
| [Expanded: dock star bar](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=217-2575) | 217:2575 |
| [Expanded: dock label picker](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=217-3348) | 217:3348 |

**Cover**: the same grid as iPhone. The side rail holds Filter instead of Groups, and Move Rejects sits just under the status bar and Back. Select is in "…".

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
- **Dock label picker**: tapping the label circle opens a horizontal row of colors (none, red, yellow, green, blue, purple) beside it, with the current color ringed.

## 10 Duo half fold (quick refresh; the dedicated layout is 1.1)

| State | Node |
|---|---|
| [Refreshed](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=193-1172) | 193:1172 |

- The top half shows only the photo.
- The bottom half has the Filter and "…" icon buttons with Move Rejects beside "…", the grid, and the floating mark capsule.
- Nothing crosses the hinge.

## 11 Settings

| State | Node |
|---|---|
| [Theme picker](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=212-1394) | 212:1394 |

- **Appearance**: a "Match system light/dark" toggle and a picker of 8 mini previews, each drawn in its own theme. The footer reads "Photos are never tinted. Only the app around them changes."
- **Culling**: Similar groups (toggle), Auto-advance after marking (toggle), Rating scale (5 stars).
- **Move rejects**: Move Rejects (toggle) and Folder name (_Rejected). The footer says nothing is deleted.

## 12 Errors

| State | Node |
|---|---|
| [Drive disconnected](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=214-1484) | 214:1484 |
| [Lost access](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=214-2083) | 214:2083 |
| [Leaving with unsaved marks](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=214-2682) | 214:2682 |

- **Drive disconnected**: the grid dims, the subtitle reads "Not connected" (never "Saved"), and a glass banner says "The drive disconnected. Reconnect it, then reopen this folder." with **Reopen**.
- **Lost access**: the same pattern. The subtitle reads "View only", and the banner says "Access to this folder is no longer available." with **Open**.
- **Leaving with unsaved marks**: an alert says "Some marks haven't finished saving." with **Leave anyway** (destructive, in red) and **Wait** (the primary action).

## Not designed (build with system defaults, or ask)

- An empty folder (no supported photos). Suggested: the first-launch layout with "No photos in this folder."
- Keyboard shortcuts on iPad. The rail exists, but no shortcut sheet was designed.
- Metadata editing in Info, which is planned for later.
- Accessibility sizes and VoiceOver labels. Follow the system defaults; the labels are in `copy.md`.
