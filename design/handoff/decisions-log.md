# Clove concept design: review decisions

Figma: https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept

Working rule: the PRD is a guide, not the source of truth. Design decisions here can override it.

## Group decisions and subtitle (supervisor decision, 2026-11-11)

A rating, colour label or Reject decides a photo. Undecided means unmarked: no rating, no label and no Reject. This definition governs the group count, first photo, Undecided only navigation and Continue. A labelled-only keep therefore lets Reject unmarked finish the group. The subtitle is "{n} undecided" followed by the save glyph, with no visible status words. Ignore Continue taps for about 0.5 seconds after Reject unmarked replaces the pill, so a double tap cannot leave the group.

## Move Rejects failure copy (supervisor decision, 2026-11-11)

The Details subtitle is "They stay rejected in place. Nothing was deleted." Reject is stored as rating −1 in a RAW set's XMP sidecar, so the earlier "in Clove" wording no longer describes its storage.

## Save glyphs (owner decision, 2026-11-11)

Issue #118 replaces visible save-status words in grid and detail with glyphs:

- Saved is a small solid dot in `status/saved` in the subtitle.
- Saving uses the same dot in `text/secondary`, gently pulsing only after the write has remained pending for about 0.5 seconds. Respect Reduce Motion.
- Failed is `exclamationmark.circle.fill` in `status/failed`. Tapping retries. A failed photo also has a small `status/failed` dot in its grid tile.
- Not connected and View only use `externaldrive.badge.xmark` and `lock.fill` in `text/secondary`. The recovery banners keep their words.
- Rejected has no subtitle word. The filled reject circle, neutral stars and label, and dimmed photo express it.
- Batch success has no toast. On partial failure, failed tiles have corner dots and the header shows the Failed glyph. Tapping retries the failed items only.
- Every glyph has a VoiceOver label. The former status strings in `copy.md` are accessibility labels only. Counts and companion text remain visible.

Undo stays in the detail top bar with its existing wiring and hides at 100% zoom. This decision adds no undo behavior. Reject presentation reads `isRejected` and does not depend on its storage representation.

## Design principles

0. Each device gets the layout that suits it best; cross-device consistency is secondary.

1. Less is more: show a control only when it is needed; no always-on bars.
2. Let the graphics and layout tell: encode state in the image and layout (stacks, dimming, position) before adding labels or badges.

## Detail screen (decided 2026-11-10)

- Marks appear once, in the capsule only. No top status bar; save status lives in the nav subtitle ("1 / 11 · + JPG · ● Saved"), which also carries Save failed · Retry.
- Bottom input is option A: one floating glass capsule above the home indicator.
  - Left: Reject, system red. Middle: 5 stars. Right: label button that pops the 5 color dots above the capsule, closing after a pick.
  - Undo moves to the top bar.
  - Filmstrip floats just above the capsule; both fade while zoomed or on tap of the photo.
- Reject is icon-only: a red-outlined circle with a ✕ (off); filled red circle with a white ✕ when the photo is rejected. Same control in the capsule, iPad rail and Duo dock.
- Top bar right: ⓘ Info and Undo. Info opens a medium-detent sheet: Capture (time with subseconds, camera + serial, lens, exposure) and File (folder, size, marks + where they are stored, save status). Read-only for MVP; editing metadata comes later.
- Swipe-up rating shows a compact vertical star bar (empty stars that fill bottom-up as you drag, max = enabled levels) with a ✕ chip below for swipe-down Reject. The capsule stars preview the live step.

Figma: revised frames sit to the right of the original 03 Photo Detail row (default, label popover open, rating ladder), light and dark. Originals untouched.

## Detail states (2026-11-10)

- Rejected: capsule Reject becomes a filled red circle, stars and label go neutral, photo dims. Subtitle "1 / 11 · Rejected · ● Saved".
- Save failed: subtitle "1 / 11 · ● Save failed · Retry" (red, Retry tappable). Marks stay as set.
- 100% zoom: capsule, filmstrip, Info and Undo hide; subtitle shows "100%" and a small 100% chip fades out.
- Filmstrips everywhere: rejected thumbs are dimmed, no ✕ badge.

## Grid (decided 2026-11-10)

- No filter bar, status row or bottom toolbar. Top bar: back, title, subtitle "1,284 photos · ● Saved", then Filter and … (Sort, Select, Settings).
- Filter is a button opening a menu: All / Unmarked / Rejected with counts, Rating ≥, Label. When active the button turns blue and the subtitle names the filter.
- Groups are stacked tiles with a count; tapping opens group review. No outlines or "Burst" tags.
- Rejected photos are dimmed, no ✕ badge. Rating badge and label dot stay. RAW+JPEG badge moved to Info.
- Move Rejects is a small 48pt round icon button (tray with down arrow) at bottom-right, no count, shown only when rejects exist. The count lives in the confirmation sheet. Tapping it always opens the confirmation sheet first, so an accidental tap moves nothing.

## Move Rejects sheet (proposed 2026-11-10)

- Small sheet over the grid: fanned stack of the rejected thumbnails, "Move 42 rejected photos", one line "To _Rejected in this folder. Nothing is deleted.", one Move button. Swipe down to cancel.
- RAW/JPG/XMP counts and the folder tree are dropped from the sheet.
- Tapping the stack expands the sheet into a quick 4-column grid of the rejects (dimmed). Tap a photo to keep it: it returns to full brightness (no badge) and the button updates ("41 of 42 will move", "Move 41").
- After moving: "Moved 42 · Undo" toast.

## iPad and Duo (applied 2026-11-10)

- iPad grid: the sidebar is the filter, so no segmented bar and no filter button; top right is just "…"; stacks, dimmed rejects, Move Rejects as a small icon button in the top bar next to "…" (never bottom-right on iPad or Duo); save status in the subtitle.
- iPad detail: right rail kept (width + keyboard), now a vertical 5-star bar (fills bottom-up), red Reject, label dots. Sync Zoom, "Saved" and keyboard hints removed. Info and Undo in the top bar.
- Duo cover: same grid as iPhone; Groups button in the side rail replaced by Filter; Move Rejects sits in the right rail just below the signal/status (under Back); Select moved into "…".
- Duo expanded: iPad-like. Left pane = revised grid with Filter and "…" in its header; Move Rejects sits in the docking strip just below the signal/status; right pane = big photo with Info and Undo; the right docking strip holds the marking tools (vertical star bar, Reject, label dots). No capsule on Duo expanded.

## Group review (decided 2026-11-10)

- Same marking as detail: floating capsule, swipe-up star bar, Undo and "…" (Undecided only, group options) in the top bar.
- Header "Group · 12 photos", subtitle "6 undecided · ● Saved".
- The filmstrip is the progress: rejected thumbs dimmed (no ✕ badge), rated thumbs show stars. No separate progress bar.
- Sync zoom always on in group view; no toggle pill.
- One finishing action: pill "Reject 6 unmarked" above the capsule, shown once any photo is rated or labeled. It never touches rated or labeled photos. "Keep this, reject the rest" = rate it, then tap the pill.
- When all are decided the pill becomes "Continue →": it goes to the next item in grid order. A group opens in group review, a single photo opens in detail, and after the last item it returns to the grid where you left off.

## Grid select mode (2026-11-10)

- Title "7 selected", Done replaces Filter / … / Move. Selected tiles get the standard blue check (selection is the one place a check belongs).
- The same mark capsule appears and applies to the selection. Result toast above it: "Saved 5 · 2 failed · Retry".

## Still open

- Missing screens: empty state, scanning/grouping progress, Move progress/result, no-preview thumbnail, Settings.

## Themes (palettes)
- Figma variable collection "Clove Theme", one mode per theme: Light, Dark, Darkroom, Night, Catppuccin Latte, Catppuccin Mocha, Nord, Gruvbox. Switching a frame's mode re-themes it. Board: node 181:2391.
- Light / Dark: follow iOS system appearance (default).
- Darkroom: neutral mid-grey stage (#474747) and muted accents, for judging color and exposure without black or white surround.
- OLED was dropped as unnecessary.
- Editor-style palettes: Catppuccin Latte (light), Catppuccin Mocha, Nord and Gruvbox. Each maps the palette's own colors onto the same tokens, so the photo stage stays dark or neutral.
- Night: warm, dim chrome with no blue light (parchment text, amber accent and stars, muted labels). Replaced the earlier red-only version, which looked bad.
- Reject is a softer red that is tuned to each theme (Light #D4574E, Dark #E5675E, Darkroom #C7665F, Night #C8665A; editor themes use their palette's softer red). Status/failed uses the same red.
- Rule: photos are never tinted; only chrome changes.
- Tokens: bg/canvas, bg/stage, surface/glass, surface/sheet, surface/card, text/primary, text/secondary, separator, accent, rating/on, rating/off, reject, status/saved, status/failed, label/red|yellow|green|blue|purple, opacity/rejected. Code name: Color.clove.*
- Not yet done: binding the revised screens to the tokens.

## File organization (2026-11-10)
- Main page is now "Clove · MVP design", laid out in labeled rows: Themes, 01 Entry, 02 Grid, 03 Detail, 03 Detail states, 04 Group review, 05 Move rejects, 06–07 iPad, 08–09 Duo, 10 Duo half fold. "REVISED" was dropped from frame names.
- Superseded originals (old grid, detail, ladders, green label state, iPad, Duo, status-bar kit check) moved to the page "Archive · original concept". Nothing was deleted.
- Still original/unrevised: 01 Entry and 10 Duo half fold.

## Entry (decided: Resume first)
- Explored three directions (A Resume first, B Contact sheets, C Bare). The owner picked A. B and C sketches are on the Archive page.
- Your last folder is a hero photo card showing the photo you stopped on, with "Continue · Yesterday", the name, the source and "412 left", plus a thin progress line (marked / rejected in red / left). Tapping it resumes.
- "Earlier" rows each show a strip of 3 of the folder's own thumbnails, then the name and source, then the count and date. "Done" appears in the saved color.
- A missing drive shows as a faded row with a Reconnect chip, not red error text.
- Open folder is a small glass capsule at the bottom. Settings is a gear in the top right.
- First launch (no folders yet): fanned empty frames, "Cull where your photos live.", "Open a folder on a card, drive or Files. Nothing is imported or copied.", and a filled Open folder button.
- Built on the Clove Theme tokens.

## Duo half fold (quick refresh)
- A dedicated half-fold layout is still 1.1. This is only a quick refresh into the MVP style.
- Top half: the photo only. Move Rejects sits in the bottom half next to "…", because a control on the upper screen felt wrong.
- Bottom half: Filter and "…" icon buttons, the grid, and the floating mark capsule (reject circle, stars, label). The segmented filter bar and the Groups / Move Rejects (42) / Select toolbar were removed.
- Nothing crosses the hinge.

## Duo expanded additions
- The grid/photo split has an 8 pt gutter with a hairline and a drag handle. The split can be dragged; the "Split dragged" frame shows a 2-column grid with a bigger photo, where the narrow toolbar keeps only back, Filter and "…".
- A second layout option, "iPad-style detail", mirrors the iPad detail: a full-width photo, filename and counter centered at the top, a filmstrip at the bottom, and the same right dock (Move Rejects under the signal, star bar, reject, labels). It is an option to compare with the split view; nothing is decided yet.
- Dragging the divider changes the layout. Dragged all the way, the split becomes the iPad-style detail (owner confirmed).
- Back is at the top of the right dock, under the status bar, followed by Move Rejects and then the marking tools. This follows Apple's Duo guidance: in landscape, controls live in the side bar shared with the status bar, and Back/Close goes at the top.
- All icon-only buttons live in the right dock, following Apple's Duo guidance. From top to bottom: status bar, Back, Filter, "…", Info, the star bar, reject and labels, Undo, and Move Rejects at the bottom. The grid and photo have no buttons over them.
- The split never sits in the center (the fold). Expanded opens as a full-width 6-column grid; the dock then shows only Back, Filter, "…", Undo and Move Rejects. Tapping a photo opens Photo focus (grid 30 / photo 70). Sliding the divider left turns it into Photo only (the iPad-style detail). There is no 70/30 or 50/50 state.
- The Duo dock's marks are compact, like the iPhone capsule: a single star button showing the rating (★ 2; slide on it to change the rating, the same as the iPhone vertical star bar), the red reject circle, and one label circle showing the current color (tap it for the color popover). Undo and Move Rejects sit at the bottom of the dock.
- The dock is grouped into glass capsules: Back on its own at the top, then a view-tools capsule (Filter, "…", Info), a marks capsule (star rating, reject circle, label), and a bottom capsule (Undo, Move Rejects). The marks capsule only shows when a photo is open.

## Filmstrip (iPad detail, Duo Photo only)
- The filmstrip follows the grid. Other groups are collapsed into one stacked tile with a count badge. The current group is expanded in place on a muted accent tint (decided: option C), using the new theme token "group" at 25%, with no outline. The current frame has a thin ring in the primary text color. The "group" token (Color.clove.group) defaults to each theme's accent and should also drive the grid group outline. Note: Figma ignores opacity on a variable-bound paint, so tints use a layer with layer opacity.
- "group" token applied: the count badges on group stacks (in every grid and the filmstrip) and the Duo half-fold group outlines now use Color.clove.group. In the revised grids, a group shows as a stack with a group-colored count badge, which ties it to the tinted expanded group in the filmstrip.

## Opening a folder (scanning and grouping)
- Opening has no blocking screen. The grid shows straight away and fills in as photos are read.
- Stage 1, reading: the subtitle shows "412 of 1,284", a 2 pt progress line runs under the toolbar in the accent color, unread cells show as plain placeholders, and no stacks appear yet. Existing XMP marks show as they are read.
- Stage 2, grouping: the subtitle says "Finding similar shots…", the progress line switches to the group color, and stacks form one by one. The photo being viewed never jumps.
- Move Rejects is hidden while opening.

## After Move Rejects
- Success: the rejected photos leave the grid, and a glass toast at the bottom says "Moved 42 to _Rejected" with an Undo button.
- Partial failure: the same toast says "Moved 40 to _Rejected", then "2 couldn't be moved" in the reject color, with a Details button.

## Settings (11 Settings)
- Appearance: a "Match system light/dark" toggle and a theme picker of 8 mini previews (each drawn in its own theme mode). The footer reads "Photos are never tinted. Only the app around them changes."
- Culling: Similar groups (toggle), Auto-advance after marking (toggle), Rating scale (5 stars).
- Move rejects: Move Rejects (toggle) and Folder name (_Rejected), with a footer saying nothing is deleted.

## Grid "…" menu and no-preview tile
- "…" menu: Sort by (Capture time ✓ / Filename), Select, Find similar shots again, Settings.
- A photo with no preview is a plain tile showing the file type ("CR3") and "No preview".

## Error states (12 Error states)
- Drive disconnected: the grid dims, the subtitle reads "Not connected" (never Saved), and a glass banner says "The drive disconnected. Reconnect it, then reopen this folder." with a Reopen button.
- Lost access: the same pattern. The subtitle reads "View only", and the banner says "Access to this folder is no longer available." with an Open button.
- Leaving with unsaved marks: an alert says "Some marks haven't finished saving." with "Leave anyway" (red) and "Wait" (primary).

## Group review on iPad and Duo
- Built from each device's photo-only layout. The title reads "Group · 12 photos / 6 undecided", the filmstrip shows only this group (rejected frames faded, current frame ringed), and a "Reject 6 unmarked" pill sits above the strip. The right dock or rail keeps the marks. "Continue →" replaces the pill when the group is done, as on iPhone.

## Theming
- Every revised Light/Dark frame (35) now uses the theme tokens. Solid colors that exactly match a token were bound to it (about 5,000 paints). Device bezels and system status bars were skipped.
- "Themes · live demo" next to the Themes board shows the grid and detail in Darkroom, Mocha, Nord and Gruvbox.
- Known gap: colors that didn't exactly match a token (a few one-off greys, and badges drawn on photos) stay fixed.

## Still open
- Nothing for the MVP. The dedicated half-fold layout stays in 1.1.

## Polish
- "Couldn't move" Details sheet: opened from the toast. Title "2 photos couldn't be moved", subtitle "They stay rejected in Clove. Nothing was deleted.", one row per photo set with a thumbnail, file name and reason in red, then Done and Try again.
- Duo dock pickers: sliding on the star button opens a vertical star bar to the left of the dock (fills from the bottom; the button shows the live value). Tapping the label circle opens a horizontal color row (none, red, yellow, green, blue, purple) beside it, with the current color ringed.

## Keeping a photo in the Move Rejects quick grid
- Keeping a photo clears its reject flag, so it isn't dimmed and doesn't come back in the next Move Rejects. Rating and label are untouched.
- The keep is staged in the sheet and written only when Move is tapped. Cancelling the sheet discards it. Undo after the move restores both the files and the reject flags in one step.
