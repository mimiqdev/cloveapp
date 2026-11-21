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
| [Group wrapper options](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=208-1154) · [png](screens/00-themes-group-wrapper-color-options.png) | 208:1154 | An exploration. Option C (a tinted wrapper) was chosen; its colour is now `text/primary` at 12% (owner decision, 2026-11-13, #226). Don't build the others. |

## 01 Entry (iPhone; iPad and Duo reuse it with wider margins)

| State | Node |
|---|---|
| [Resume first](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=187-1308) · [png](screens/01-entry-resume-first-has-recent-folders.png) | 187:1308 |
| [First launch](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=189-1396) · [png](screens/01-entry-first-launch-no-folders-yet.png) | 189:1396 |

**Resume first** (the app has opened folders before)
- A large title, with Settings as a gear icon at the top right.
- **Hero card**: the last folder. It shows the photo you stopped on, full bleed, with "Continue · Yesterday", the folder name, the source (card, drive or Files) and "412 left". A thin progress line at the bottom shows marked, rejected (in the reject color) and left. Tapping anywhere on the card reopens the folder at that photo.
- **Earlier** list: one row per folder, with a strip of 3 of that folder's own thumbnails, then the name and source, then the count and date. A finished folder shows "Done" in `status/saved`.
- A folder whose drive is missing shows as a faded row with a **Reconnect** chip on a `surface/card` capsule. It is not shown as red error text, and it never renders as an unreadable accent pill (owner decision, 2026-11-13, #227).
- **Open folder** is a text-only native capsule at the bottom center, 168 × 48, with no icon (owner decision, 2026-11-13, #227).

**First launch** (no folders yet)
- Fanned empty photo frames, the line "Cull where your photos live.", the line "Open a folder on a card, drive or Files. Nothing is imported or copied." and a filled, text-only **Open folder** button at 168 × 48 (owner decision, 2026-11-13, #227).

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
- When Similar groups is on (default), a **group** with at least 2 visible members appears as one collapsed stacked tile using its **Representative Photo** (`Highest rated > Non-rejected labeled > First unmarked > First visible`) with peeking visible-member cards and a neutral count badge (`visibleMembers.count`). Tapping a stack opens Detail directly in **Group Focus** (`expandedGroup = group.id`) at the Representative Photo; tapping a standalone tile opens Detail in **Timeline**. Groups with only 1 visible member behave as standalone tiles.
- A **rejected** photo is dimmed (`opacity/rejected`) with no ✕ badge (collapsed stacks dim only when all visible members are rejected). The rating badge and label dot stay. The RAW+JPEG badge is only in Info.
- **Move Rejects** is a 48 pt round glass icon button (a tray with a down arrow) at the bottom right. It has no count and shows only when rejects exist. It always opens the confirm sheet first.
- **Landscape**: uses the full safe width with an adaptive column count (`3` columns below `500 pt` width, scaling up from `4+` columns in landscape), preserving the scroll anchor across rotation behind the compact 54 pt inline top bar.

**Filter menu**: All, Unmarked and Rejected with counts, then Rating ≥ and Label. While a filter is active the button is filled with `accent` and the subtitle names the filter ("Unmarked · 812").

**Select mode**: the header hides Back on compact widths, shows the visible selection count ("7 selected") alongside a separate hidden-by-filter count ("2 hidden by filter") when a filter hides selected photos, keeps **Filter** reachable beside Selection options ("…") and **Done**, and hides Move Rejects. Interaction is strictly **1 cell = 1 visible photo**: long-pressing a collapsed stack selects only the visible cover photo ("1 selected") without pulling in other or hidden group members. After a ~120 ms opening beat (or immediately on tap, 1-finger drag-range pan, `Select all`, or under Reduce Motion), active groups (`>= 2` visible members) unfold inline in grid order (~280 ms damped spring) into **inline group trays** with connected same-row bands and a decorative first-member count pill while preserving the pressed tile or top visible anchor; tapping **Done** refolds groups cleanly back into stacks. Selected tiles get the standard blue check, the only place a check is used. One unified 48 pt glass selection toolbar combines the three marking actions (Reject, Rating, Label) with a labeled **Actions** menu exposing **Save to Photos**, **Add Keywords…**, and **Rename…**; all controls disable when zero visible targets are selected or the folder's location is lost, while **Save to Photos** stays available even when marking/keywords/rename are gated off so long as visible targets exist and the folder is reachable. **Save to Photos** saves one existing JPEG or HEIF per visible target (RAW+JPEG prefers JPEG; RAW-only sets are skipped without re-encoding), keeps selection, filter, and scroll intact, asks confirmation when mixing eligible and RAW-only photos, alerts if all visible targets are RAW-only, and reports results or permission/write errors in a bottom glass toast positioned clear of the batch bar.

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
- The top bar has Back and the **Focus regions** (`viewfinder`) toggle on the leading side, the filename as the title, and the subtitle `"{i} / {n} · + JPG"` in Timeline or `"Group · {i} / {n} · + JPG"` in Group Focus (no loading or save label). On the right are **Info (ⓘ)** and **Undo**.
- Focus overlays draw camera AF rectangles, four-corner face fallbacks, or one small square eye marker per person without fill; compact passive face and missing-AF result glyphs (`16 pt`) appear in the photo viewport's upper-leading corner (with a subtle dark scrim only over photo pixels) when chrome and Focus regions are visible.
- Marks appear **once**, in the shared **marking toolbar** (168 × 48) above the home indicator: the `flag.slash` Reject action, the star+value rating action, and the label circle (owner decision, 2026-11-13, #227). Disabled on unexpanded group stacks in Timeline.
- The **filmstrip** floats just above the marking toolbar. Both stay in place at fit and while zoomed, and a single tap on the photo toggles them with the rest of the chrome (#302).
- **Landscape (iPhone)**:
  - Ordinary iPhone (including Max/Plus models reporting a regular horizontal size class in landscape) always stays in single-photo Focus View — never offering iPad's `30/70` Photo Preview (`sidebar.left`) or `DetailMarkRail`.
  - A compact 54 pt inline top bar places Back and Focus regions (`viewfinder`) leading, filename and subtitle centered (truncating cleanly without overlapping controls), any active group pill (`"Expand {n} photos"` / `"Reject {n} unmarked"`), Info, and Undo trailing.
  - One compact bottom review row below the stage (`landscapeBottomReviewRow`) pairs the 48 × 48 two-level filmstrip (`4 pt` Timeline gaps; compact Group Focus tray with trailing `chevron.up` collapse cap) beside the shared `168 × 48` marking toolbar within horizontal safe-area insets for both `landscapeLeft` and `landscapeRight`; tapping Rating or Label opens the horizontal `RatingPicker` / `LabelPicker` above the toolbar.
  - Hiding chrome on a single tap removes the bottom review row and top-bar tools so the photo stage expands into the reclaimed vertical space (enlarging fitted photos and preserving zoom scale and normalized anchor when zoomed).

**Label popover**: tapping the label action pops 5 color dots (plus none) above the toolbar. Picking one closes it.

**Swipe-up star ladder**: swiping up on the photo shows the quick-rating ladder (48 × 204) of empty stars that fill from the bottom as you drag, up to the enabled levels. A 44 pt chip below it is the swipe-down reject stage: `flag.slash`, filled `flag.slash.fill` in `reject` when the swipe reaches it; the clear stage shows `star.slash` in `text/secondary` with the stars empty (owner decision, 2026-11-13, #227). The ladder appears beside where the swipe started: vertically centred on the touch start, 24 pt to the left of the finger (to its right when the touch starts in the left third), kept inside the stage clear of the top bar and filmstrip. It stays put for the rest of the swipe, so the finger moves along it. The grey circles in the frame mark the touch and are not drawn in the app. The toolbar's rating action previews the live value.

**Info sheet** (medium detent, read-only in the MVP)
- Capture: time with subseconds, camera and serial, lens, exposure.
- File: folder, size, RAW+JPEG pairing, live marks and where they are stored (`XMP sidecar` / `Clove only`, showing keyword count when a photo has only keywords), and an optional `Keywords` row omitted when empty. There is no save status line.

**Rejected**: the toolbar's Reject action fills (`flag.slash.fill` in `reject`) and the rating and label actions go neutral. The photo stays at full brightness. A 22 pt `flag.slash.fill` in a filled `reject` circle sits in the stage's top-trailing corner, inset 8 pt inside the safe area (owner decision, 2026-11-13, #227). It stays fixed during zoom and pan and remains visible with the chrome hidden. It ignores taps; VoiceOver includes "Rejected" in the photo label and skips the decorative glyph. Rejected has no subtitle word.

**Save failure toast**: when a mark can't be written, one glass toast says "Couldn't save the mark." with no action, and the photo goes back to the marks in its file. There is no subtitle status and no Retry. One toast per failure burst; it hides after about 6 seconds. In the frame it sits above the filmstrip so it doesn't cover the marking toolbar; the build currently draws it at the bottom edge over the toolbar (see the note in `decisions-log.md`).

**Swipe star bar: cleared step (proposal, #125, not reviewed)**: a quick swipe down from a rated photo now stops at 0 before Reject. The proposal shows three stops on a 3★ photo: A start (no chip), B cleared (all stars empty, the chip slot shows `star.slash` in `text/secondary`), C reject (the chip fills in `reject` with a white ✕ and the stars dim). The bar sits beside the touch start, as in the swipe-up frame. Waiting on the designer.

**100% zoom**: the marking toolbar, filmstrip, Info and Undo stay put across fit and zoom (#302). The subtitle appends `100%`, and a small "100%" chip fades out. Tapping an actionable focus region centres native 100% zoom on that region and highlights only that marker in `accent` until returning to fit.

In every filmstrip, rejected thumbnails are dimmed and have no badge.

## 04 Groups in detail

There is no separate group review screen or sidebar. Detail uses a two-level filmstrip workflow (`#304`):

| State | Node |
|---|---|
| [iPhone](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=173-1950) · [png](screens/04-groups-in-detail-iphone.png) | 173:1950 |
| [iPad (provisional)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=214-2931) · [png](screens/04-groups-in-detail-ipad.png) | 214:2931 |
| [Duo expanded (Focus View)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=214-3214) · [png](screens/04-groups-in-detail-duo-expanded.png) | 214:3214 |

- **Timeline** (`expandedGroup == nil`): the filmstrip shows standalone photos and collapsed group stacks in grid order with no inline expansion. Stepping left/right moves 1-by-1 across Timeline slots (skipping bursts in one swipe). On an unexpanded group stack, marking inputs are disabled and `"Expand {n} photos"` (`clove.detail.expandGroup`) floats centred above the filmstrip without taking its layout height (or in the compact top bar in iPhone landscape, or at the bottom of the stage in Photo Preview); vertical stage drags gently pulse this pill. Tapping the pill, tapping the current stack in the strip, swiping upward on any strip stack, or pressing `Return` enters Group Focus.
- **Group Focus** (`expandedGroup == group.id`): tapping a group stack in Grid opens Detail directly here at the group's **Representative Photo**. The filmstrip isolates **only** that group's visible members (`1 … N`) on `text/primary` at 12% (`ExpandedGroupSurface`), led by a `chevron.down` collapse button (`clove.detail.filmstrip.group.fold`, `"Collapse group"`). The subtitle reads `"Group · {i} / {n}"`, horizontal swipes/arrows stop at both ends of the group, zoom/pan stay synced across members, and folding (via the strip button, downward vertical strip swipe, `Return`/`Escape`, or Photo Preview's `chevron.up` header chevron) returns to Timeline on the Representative Photo without leaving Detail.
- **Photo Preview vs Focus View**: in **Photo Preview** (30/70 split on wide iPad and expanded Duo) the split folder grid draws the same two levels as the filmstrip: Timeline shows the filtered folder with collapsed stacks, and Group Focus replaces the pane's content with only the active group's visible members (`{n} photos` header + `chevron.up` fold). **Focus View** shows the same levels in the two-level filmstrip. Top-bar Back always exits to Grid View in one tap.
- **Reject N unmarked** floats centred above the filmstrip, outside its layout height (or sits in the compact top bar in iPhone landscape), in Group Focus once the visible group has both a rated or labeled member and an unmarked member. It rejects only visible unmarked photos; Undo restores the action together and returns to the photo shown at submission.
- **First-pass vs second-pass auto-advance**: marking visits remaining unmarked members (wrapping once) and, after the final unmarked member or `"Reject N unmarked"`, collapses to Timeline and advances across Timeline slots; editing an already-decided group (0 unmarked visible members) never auto-collapses or leaves the group.
- On iPad and Duo the active pill sits centred at the bottom of the photo stage, above the filmstrip, never under the rail or dock. It never resizes the stage as it appears or disappears (#305).

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
- **Details sheet**: the title is "2 photos couldn't be moved" and the subtitle is "They stay rejected in place. Nothing was deleted." There is one row per photo set, with a thumbnail, file name and the reason in `reject`, then one **Done** button. There is no Try again.

## 06–07 iPad

| State | Node |
|---|---|
| [Grid (provisional)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=166-1836) · [png](screens/06-ipad-grid.png) | 166:1836 |
| [Grid: Locations, subfolder selected (provisional)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=243-1957) · [png](screens/06-ipad-grid-locations-subfolder.png) | 243:1957 |
| [Detail (provisional)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=166-2591) · [png](screens/06-ipad-detail.png) | 166:2591 |
| [Detail: rejected (provisional)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=243-2691) · [png](screens/06-ipad-detail-rejected.png) | 243:2691 |

The iPad frames were drawn before the sidebar (#170), the detail rail (#174), and the Photo Preview / Focus View toggle (#256) were built. Where a frame disagrees with the build, the build wins.

- **Sidebar**, top to bottom, a plain list with one selected row:
  - **Header**: the folder name and the source line ("External SSD · T7 Shield"), with no save word.
  - **Locations**: "All" with the photo count, then one row per subfolder that holds photos (`DCIM/100CANON`). The section appears only when photos occupy more than one folder. `_Rejected` isn't listed and there is no "Skipped" row.
  - **Filters**: Unmarked, Rejected, then one "★n+" row for each rating that has photos.
  - **Color labels**: one row per label in use, with its dot, name and count. Hidden when no photo has a label.
  - **Similar groups**: one row, "86 groups", with a small regroup glyph button (Find similar shots again). A spinner replaces the button while grouping runs. There is no "Analyzed" word. Hidden when similar groups are off.
- **Grid View**: the title is the selected sidebar row's name ("All", "Unmarked", "Red", "DCIM/100CANON") and the subtitle is the count ("1,284 photos"). There is no Filter button. The top right has Move Rejects (only when rejects exist) and "…", as 40 × 40 glass icon buttons. Move Rejects is never at the bottom right on iPad. Stacks and dimmed rejects work as on iPhone.
- **Detail** and Settings open full screen with a back button named after the selected row, such as "‹ All" or "‹ Unmarked", alongside the **Photo Preview / Focus View** (`sidebar.left`) toggle on wide widths (`>= 680` pt) and the **Focus regions** (`viewfinder`) toggle. Detail offers two presentations via the `sidebar.left` button (or draggable 8 pt divider): **Photo Preview** (default on wide iPad: 30% filtered folder grid synchronized with `expandedGroup` + 70% photo stage, no filmstrip) and **Focus View** (full photo stage + two-level bottom filmstrip, no folder grid). Tapping `sidebar.left` switches presentation for the same photo and `expandedGroup`, preserving marks, filter, sort, zoom, and overlays; chosen presentation stays active across photo navigation and resets to Photo Preview when returning to Grid View. Compact/narrow widths (`< 680` pt) fall back to Focus View and hide the toggle until returning to wide width. A 96 pt right rail replaces the toolbar. It sits beside the stage, never over it, and never hides (marking actions disable on unexpanded group stacks in Timeline): a single tap or zoom hides the filmstrip (in Focus View), the active group pill and the top bar buttons, while the stage keeps its size. Top to bottom: the quick-rating ladder (43 × 174) that fills from the bottom (tap, or drag and release), a hairline, and the marking family's shared Reject (`flag.slash`) and Label actions stacked below (owner decision, 2026-11-13, #227); the label action opens the shared picker in its popover. Tapping the current rating clears it. Each rail control has a hover tooltip with its VoiceOver label (the frame shows "Reject"). Info and Undo are 40 × 40 in the top bar. Swipe marking on the photo still works; the rail ladder shows the live value. There are no keyboard hints.
- **Rejected**: the rail's Reject action fills (`flag.slash.fill` in `reject`), the ladder and label action go neutral, and the corner glyph sits in the stage's top-trailing corner, left of the rail.
- **Filmstrip** (in **Focus View** at the bottom; omitted in **Photo Preview**): **Timeline** shows standalone photos and collapsed stacks in grid order; **Group Focus** isolates only the expanded group's visible members on `text/primary` at 12% (`ExpandedGroupSurface`), led by a `chevron.down` collapse control. The current item carries the quiet `accent` current-photo indicator (`1.5 pt` inset outline + centered `14 × 2 pt` bottom locator adapted to the thumbnail or cover-card corner radius).

## 08–09 Duo

| State | Node |
|---|---|
| [Cover](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=167-1856) · [png](screens/08-duo-cover-folded-outer-screen.png) | 167:1856 |
| [Expanded: Grid View (default)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=167-2521) · [png](screens/08-duo-expanded-grid-default-full-width.png) | 167:2521 |
| [Expanded: Photo Preview 30/70](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=196-1119) · [png](screens/08-duo-expanded-photo-focus-30-70.png) | 196:1119 |
| [Expanded: Photo Preview, rejected](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=243-2960) · [png](screens/08-duo-expanded-photo-focus-rejected.png) | 243:2960 |
| [Expanded: Focus View](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=197-1161) · [png](screens/08-duo-expanded-photo-only.png) | 197:1161 |
| [Expanded: dock star bar](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=217-2575) · [png](screens/08-duo-expanded-dock-star-bar-sliding.png) | 217:2575 |
| [Expanded: dock label picker](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=217-3348) · [png](screens/08-duo-expanded-dock-label-picker.png) | 217:3348 |

**Cover**: the same grid as iPhone, with no save status. Detail on the cover is iPhone detail (including the `viewfinder` toggle in the right action rail and the reject corner glyph). The side rail holds Filter instead of Groups, and Move Rejects sits just under the status bar and Back. Select is in "…".

**Expanded** (landscape, unfolded). The rules follow Apple's Duo guidance:
- **The right dock** is a vertical column shared with the status bar, made of glass capsules from top to bottom:
  1. **Back**, on its own, at the top under the status bar.
  2. **View tools**: Filter, "…", **Photo Preview / Focus View** (`sidebar.left`, in detail), Info.
  3. **Bottom**: Undo, Move Rejects.
  The capsules are centered under the signal icon. The grid and photo have no buttons over them.
- **Marking toolbar** (owner changes, #200 and #227): while a photo is open, the shared 168 × 48 marking toolbar sits beneath the right-hand photo, inside the photo pane's 70 pt bottom control band — not in the side toolbar, so system island/status activity cannot push marking into overflow or cover the image (disabled on unexpanded group stacks in Timeline). Both **Photo Preview** and **Focus View** share one bottom-trailing anchor (`16 pt` trailing inset, vertically centered in the 70 pt band / on the thumbnail track), so switching between them keeps the capsule stationary. In **Focus View**, the toolbar sibling (with a small leading optical gap) is the one width reservation: it narrows the filmstrip's viewport so its thumbnails never scroll under the toolbar, and the strip's content fills that viewport up to the toolbar with no second, content-side gap (#237); the two regions share the photo stage's background, with no contrasting sidebar slab behind the toolbar region. The cover keeps its compact dock controls.
- **Group Focus parity**: in **Photo Preview**, the left pane keeps the filtered folder grid without a redundant header, while the photo corner overlay shows the filename and Timeline (`"{i} / {n}"`) or Group Focus (`square.stack` + `"{i} / {n}"`, VoiceOver `"Group · {i} / {n}"`) position. The pane follows `browsing.expandedGroup` and draws the same level the Focus View filmstrip draws: collapsed stacks for the whole filtered folder when nil (indicating the stack holding `currentPhoto` with the quiet `accent` `1.5 pt` inset outline + `14 × 2 pt` bottom locator on its front cover card), or only the active group's visible members when set, on `ExpandedGroupSurface` (`text/primary` at 12%) inside a `{n} photos` header with a `chevron.up` fold button and no count badge (with the active member indicated at radius `6`, and standalone tiles at radius `0`). Choosing a member changes the photo without leaving Group Focus, folding returns to Timeline on the Representative Photo, and Back returns to **Grid View** with its filter and position.
- **Fit containment** (#199): the fitted photo never drags over the divider or left grid; it stays stationary during a fit drag, and the pane clips its pixels.
- **Grid View (default)**: a full-width 6-column grid. The dock shows Back, view tools and the bottom capsule.
- **Photo Preview (30/70)**: tapping a photo or stack enters Photo Preview by default, splitting the screen into the filtered folder grid (30%) and the photo stage (70%) with no filmstrip. The photo stage reclaims the former 48 pt top header row so the fitted photograph takes the full usable viewport height above the 70 pt bottom control band and clear of the system side dock (#390). A passive translucent two-line identity overlay (`12 pt` semibold middle-truncated filename preserving extension; `11 pt` position/magnification, with `square.stack` in Group Focus and no `+ JPG` / `+ HIF` suffix, on `black` at 62% with `8 pt` continuous corners, scaling with Dynamic Type) is pinned to the upper-leading corner of the **photo viewport** (`16 pt` leading, `12 pt` top, respecting system safe areas), staying rock-solid across landscape/portrait switches, zoom, pan, and loading/error states, hiding with photo chrome, and passing gestures and focus-region taps cleanly through. Floating glass controls — the **Focus regions** (`viewfinder`) toggle, clickable **Folder preparation** ring (when active), and view-only/disconnected **Save status** glyph (absent during normal access) — sit beside the identity overlay inside the viewport with adaptive glass contrast on both bright/dark photographs and the stage, clear of the top-trailing reject glyph and without contributing to stage layout or resizing the fitted image. Any passive focus-result glyphs or preview-only note stack below the top row. An 8 pt gutter with a hairline and a drag handle separates the grid and photo stage. The split is never at 50/50 and never on the fold. Tapping `sidebar.left` in the dock (or dragging the divider left) switches to Focus View.
- **Focus View**: toggling `sidebar.left` or sliding the divider all the way left hides the grid for the same current photo and `expandedGroup`: a full-width photo stage reclaiming the full top height with the same upper-leading viewport-pinned identity overlay (`16 pt` leading, `12 pt` top) and floating glass controls (Focus regions toggle, active preparation ring, and view-only/disconnected glyph), plus the two-level filmstrip at the bottom (**Timeline** collapsed stacks when `expandedGroup == nil`, or isolated **Group Focus** with a leading `chevron.down` collapse button when `expandedGroup != nil`). Tapping `sidebar.left` again returns to Photo Preview.
- **Rejected**: the toolbar's Reject action fills (`flag.slash.fill` in `reject`), the rating and label actions go neutral, and the corner glyph sits in the photo pane's top-trailing corner. Nothing on the Duo shows a save dot or "Saved".
- **Cover dock pickers** (cover only after #200): sliding on the dock's star button opens a vertical star bar to the left of the dock, filling from the bottom with the live value on the button. Tapping the dock's label circle opens a horizontal row of colors (none, red, yellow, green, blue, purple) beside it, with the current color ringed.

## 10 Duo half fold (quick refresh; the dedicated layout is 1.1)

| State | Node |
|---|---|
| [Refreshed](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=193-1172) · [png](screens/10-halffold-quick-refresh.png) | 193:1172 |

- The top half shows only the photo.
- The bottom half has the Filter and "…" icon buttons with Move Rejects beside "…", the grid, and the floating marking toolbar.
- Nothing crosses the hinge.

## 11 Settings

| State | Node |
|---|---|
| [Theme picker](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=212-1394) · [png](screens/11-settings-theme-picker.png) | 212:1394 |

Settings uses an adaptive layout across five categories (`Appearance`, `Culling & marking`, `Browsing & groups`, `Photo display`, `Move rejects`) plus a `Reset to defaults` action with a native destructive confirmation alert.

- **Compact** (iPhone, Duo cover, narrow windows below 680 pt or compact size class): categorized home list with native push navigation into each category detail view; `Rating scale` and `After marking` push as nested detail pages under `Culling & marking`.
- **Wide** (iPad, expanded Duo, regular width `>= 680` pt): category list on the left (selected category highlighted with a quiet neutral surface and `accent` text) beside the active category detail on the right; preserves the selected category across compact/wide resizes.
- **Appearance**: three-way segmented mode picker (`Light` / `Dark` / `System`) and a 3 × 2 picker of 6 paired theme family tiles (`Default`, `Catppuccin`, `Darkroom`, `Night`, `Nord`, `Gruvbox`), each showing Light (left) and Dark (right) halves around an untinted photo. Summary row shows `{Mode} · {Family}` (`System · Default` by default). Footer: "Photos are never tinted. Only the app around them changes."
- **Culling & marking**: Marking gestures (toggle), While zoomed (Rate & switch / Pan; the footer explains both), Rating scale (nested subpage showing enabled levels with cumulative SF Symbols stars and accessible spoken labels, keeping at least one level enabled), Extended color labels (toggle adding Orange and Pink), and Auto-advance (`After marking` nested subpage offering Stay / Next photo / Next unmarked photo; `Ratings advance`, `Reject advances`, `Color labels advance` triggers preserved while Stay disables advancing).
- **Browsing & groups**: Similar groups (toggle; On collapses multi-photo visible groups into stacks in Grid and Detail Timeline, Off shows a flat 1D stream everywhere) and Double-tap (Zoom to focus / Zoom to tap point / Off; the Detail zoom footer states that similar groups stay zoom-synced while leaving a group or switching standalone photos returns to fit).
- **Photo display**: Show photos as (RAW / Camera preview, preserving device-measured default and explicit choices) with explanation footer.
- **Move rejects**: Move Rejects (toggle) and validated Folder name (`_Rejected` by default) with inline error feedback; footer confirms rejected photos are moved, never deleted.
- Interactive emphasis (toggles, selection accents) follows the active theme `accent` token rather than system blue or `status/saved`.

## 12 Errors

| State | Node |
|---|---|
| [Drive disconnected](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=214-1484) · [png](screens/12-errors-drive-disconnected.png) | 214:1484 |
| [Lost access](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=214-2083) · [png](screens/12-errors-lost-access.png) | 214:2083 |

- **Drive disconnected**: the grid dims, the subtitle keeps the count and adds the `externaldrive.badge.xmark` glyph (VoiceOver: "Not connected"), and a glass banner says "The drive disconnected. Reconnect it, then reopen this folder." with **Reopen**.
- **Lost access**: the same pattern. The subtitle adds the `lock.fill` glyph (VoiceOver: "View only"), and the banner says "Access to this folder is no longer available." with **Open**.
- There is no "Leaving with unsaved marks" alert. Leaving never waits on saves.

## 13 Batch rename (draft for #176, not reviewed)

A first draft of the flow in #176 for the designer. The engine is #175.

| State | Node |
|---|---|
| [Select mode with Rename…](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=259-2552) · [png](screens/13-rename-select.png) | 259:2552 |
| [Order (drag to reorder)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=259-3217) · [png](screens/13-rename-order.png) | 259:3217 |
| [Check focus viewer](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=259-3926) · [png](screens/13-rename-check-viewer.png) | 259:3926 |
| [Name sheet: a name in use warns, Rename replaces](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=260-2330) · [png](screens/13-rename-name-sheet-replace-warning.png) | 260:2330 |
| [Renaming (progress)](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=260-2553) · [png](screens/13-rename-running.png) | 260:2553 |
| [Done toast](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=260-2770) · [png](screens/13-rename-done-toast.png) | 260:2770 |
| [Partial failure toast](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=260-3371) · [png](screens/13-rename-partial-failure-toast.png) | 260:3371 |
| [iPad: order grid with the name form sheet](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=260-3974) · [png](screens/13-rename-ipad-name-form-sheet.png) | 260:3974 |

- **Select**: in select mode, the shared 48 pt bottom selection toolbar integrates **Actions** beside Reject, Rating, and Label. Tapping **Actions** opens a menu containing **Save to Photos**, **Add Keywords…**, and **Rename…**; all controls disable when zero visible targets are selected or the folder's location is lost, and **Add Keywords…** / **Rename…** also disable when the folder cannot be written to.
- **Order**: a full-screen grid of only the visible selected photos, in the grid's current sort. Each tile has its position in an `accent` circle at the top leading corner. Dragging lifts the tile (larger, with a shadow), leaves an empty slot where it will land, and renumbers the other tiles as it moves. The header has Cancel, "Order N photos" (singular "Order 1 photo" for one photo), a Sort menu, and Next; compact widths (`< 500` pt) place "Drag to reorder · tap to check" on a full-width second line beneath the header controls so labels never clip. The order is never saved; Cancel drops it and returns to select mode with selection, filter, and scroll position preserved.
- **Check focus**: tapping a tile opens the photo full screen with the detail zoom (double-tap or pinch to 100%). The subtitle reads "2 of 6", and swiping moves through this order. There is no capsule, filmstrip, Info or Undo. Back returns to the order grid.
- **Name sheet**: a large-detent sheet over the order grid. The fields are Prefix, Add capture date, Start number and Digits (steppers). A **Where** card follows: "Keep in place" (checked, the default) or "Move to a new folder", which opens a folder-name field; when moving, the preview shows the destination folder (not drawn yet). Below that is a live preview, scrolling inside its card: the new name, then the current name with its companions ("IMG_4795.CR3 + JPG").
  - **A name already in this folder** (outside the batch) doesn't block. The row gets a `label/yellow` "!" and "Replaces a file with this name". The line above the button counts the names in use, and the button turns `reject` and reads "Rename 6 · Replace 1". The replaced file set moves to `_Rejected`, so nothing is deleted.
  - Invalid characters, names over 255 bytes and two equal names in the batch still block: those rows use `reject` text and the button is disabled. That state isn't drawn yet.
  - The footer reads "Renaming can't be undone. Replaced files move to _Rejected."
- **Renaming**: the grabber goes away and the sheet can't be swiped down. The fields dim to 40%, the title reads "Renaming 6 photos…", and a progress line with "Renaming 3 of 6…" replaces the button.
- **Done**: the folder is read again, select mode ends and the toast says "Renamed 6 photos". There is no Undo.
- **Partial failure**: the toast reads "Renamed 4 of 6" with the reason ("IMG_4806.CR3 was in use") and Details. Details lists the failure and any photo left under a temporary name, like the Couldn't move sheet.
- **iPad**: the order grid uses 6 columns, and the name sheet is a 540 pt form sheet.

## Not designed (build with system defaults, or ask)

- An empty folder (no supported photos). Suggested: the first-launch layout with "No photos in this folder."
- Keyboard shortcuts on iPad. The rail exists, but no shortcut sheet was designed.
- Metadata editing in Info, which is planned for later.
- Accessibility sizes and VoiceOver labels. Follow the system defaults; the labels are in `copy.md`.

## 14 Compare

- **Eligible wide surfaces**: iPad, unfolded iPhone Duo, and landscape iPhone (omitted on portrait iPhone and Duo Cover; rotating to portrait or folding to Cover exits Compare back to Detail on the active pane's photo without losing marks).
- **Top bar**: leading `Done` glass pill, centered `Compare` title, and trailing `Sync On` (`lock.fill`, warm `accent` fill) / `Sync Off` (`lock.open`, neutral glass) toggle, clear of the Duo right side-toolbar safe area.
- **Side-by-side panes**: 50/50 split (split strictly along the vertical center hinge on unfolded Duo while respecting the trailing system side-toolbar safe area on B). Each pane is clipped inside a subtle dark-neutral rounded frame (`2 pt` `accent` stroke on active pane, `1 pt` hairline `separator` on inactive pane) with a slim header carrying the `A`/`B` pill, middle-truncated filename preserving extension, live zoom readout (`Fit`, `100%`, `%`), and read-only current marks (star + count and/or label dot when set, red `flag.slash.fill` when rejected). Tapping either pane switches `activeSide`.
- **Bottom review bar**: `[Undo] [A/B] [Marking Capsule]` trailing, acting strictly on `activeSide`. Stepping mode adds `<`, `>`, and `Set as A` leading, plus a compact scrollable **filmstrip** (`A`/`B` badges, tapping replaces B) on iPad and unfolded Duo; landscape iPhone omits the filmstrip, and Fixed Pair mode omits `<`, `>`, `Set as A`, and the filmstrip.
