# Clove concept design: review decisions

Figma: https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept

Working rule: the PRD is a guide, not the source of truth. Design decisions here can override it.

iPad: sidebar and full grid; detail opens full screen; no grid-beside-detail layout (supervisor, 2026-11-12, issue #150).

iPad detail: the right rail replaces the capsule and never hides; swipe marking stays (supervisor, 2026-11-12, issue #150)

## Neutral group count badges and filmstrip surfaces (owner, 2026-11-13, #226)

Saturated blue group counts read as notifications and pull attention away from the photos, and a blue wash behind the expanded filmstrip group distracts from the thumbnails. Both now use restrained neutral treatments in every theme. This supersedes the `group` colour on count badges and `group` at 25% behind an expanded filmstrip group, including #225's styling sentence; #225's expansion and navigation behaviour is unchanged.

- **Group count badge** (grid stacks on iPhone, iPad and the Duo cover, and every filmstrip stack): a compact rounded rectangle filled with black at 56%, the count in white at 94% at system Medium, 11 pt with radius 4 in a grid and 9 pt with radius 3 in the filmstrip. No coloured fill, border or shadow. Badges are photo overlays, so they are deliberately invariant across themes; the anchors, padding, count text and accessibility labels stay as they are. The expanded Duo's member pane shows no count badges, before or after this decision.
- **Expanded filmstrip group**: the rounded background shape (radius 9) is `text/primary` at 12% layer opacity, so it follows the theme's Light or Dark text colour. The opacity is on that shape alone; the container and photo thumbnails are never tinted. The current photo keeps its own `text/primary` ring, so the group's extent and the selection stay distinguishable.
- Photo pixels, Reject dimming, the bottom marking row (#204), fit containment (#199), group membership, expansion, navigation and marks are unchanged.

The `group` token keeps its per-theme values and is not recoloured or removed: the progress line while grouping is its remaining use in the app.

## Groups expand in place in the Duo's grid and filmstrip (owner, 2026-11-13, #225)

The expanded Duo no longer replaces its left pane with the current group's members. A group is a temporary expansion inside the folder grid or the filmstrip, using the same browsing model as iPhone and iPad: the folder keeps its filter, order and position around it, and Back is only Back. This supersedes #198's group-only pane; none of that pane remains, and no group route or page returns.

- **Split (30/70)**. The left pane is the folder grid in two columns: its groups are stacks, and the photo's own group expands in place at its stack's position with a header naming how many of its members the filter shows. The header's chevron folds the group back into its stack. Folding changes only the thumbnails: the photo, its marks and the route stay, and the stack reopens the group in place. The run draws its members on the shared expanded-group surface (`text/primary` at 12% on each tile's background, radius 6, the same surface as the filmstrip and the grid's expanded display from #226/#227) with the current member ringed in `text/primary`; photos are never tinted and members show no count badge, because the header names the group.
- **Photo only**. The same folder-order filmstrip, with only the photo's own group expanded. That group ends with the same fold chevron, and its stack reopens it without changing the photo.
- **Back** returns to the full folder grid with its filter and browsing position. Member counts and the counter stay in folder order, and selecting a member moves the same preview, filename, highlight and marks.
- Same-group zoom, Reject N unmarked, Undo and auto-advance are unchanged, as are #200's marking row, #199's fit containment and the iPhone, iPad and folded Duo grids. The Duo's grid display setting still governs the full-width grid; the split reads the pane's width, so its groups stay stacked except the one on screen.
- There is no persisted expansion, fold or navigation state. The fold is what the person is doing in this detail session.

Frames: [30/70 photo focus, the group expanded in the folder grid](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove?node-id=196-1119) and [photo only, the group expanded in the filmstrip](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove?node-id=214-3214), Light and Dark. They show group presentation only; the marking controls stay as #200/#204 built them.

## Batch rename: select, order, rename; a name in use is replaced, not refused (owner, 2026-11-12, #173)

Batch rename is select, order, rename, with no undo (#176). A target name already used by a file outside the batch shows a warning, and Rename replaces it, instead of forcing the person to choose another name (owner, 2026-11-12). The replaced file set moves to `_Rejected`, so nothing is deleted (owner, 2026-11-12). #175 and #176 are updated to match. Names that can't exist (invalid characters, over 255 bytes, duplicates within the batch) still block.

## Swipe star bar sits beside the touch (owner, 2026-11-12)

The swipe star bar is no longer fixed at the right edge. It appears beside where the swipe started, vertically centred on the touch start and 24 pt to the left of the finger (to its right when the touch starts in the left third), clamped inside the stage clear of the top bar and filmstrip. It stays put for the whole swipe, so it never sits under the finger and does not chase it. This supersedes "a fixed indicator at the right edge, never under the finger" (#125 comment, built in #145). Frames: `03-detail-swipe-up-star-bar` and the #125 proposal board.

## Figma frames synced to the build (2026-11-12)

The frames on the "Clove · MVP design" page now match the app on main at `7470617` (owner's implementation notes, 2026-11-12). The 10 Nov versions of every removed or redrawn frame are on the Archive page under "Superseded · 10 Nov handoff".

- **Removed:** Batch result (02), Group done (04) and Leaving with unsaved marks (12).
- **Redrawn:** every subtitle without a save dot, Saved, Saving or loading word; Rejected (03) with the photo at full brightness and the 22 pt corner glyph; Save failed (03) as the "Couldn't save the mark." toast; the Info sheet without its save status line; the three group frames (04) as normal detail with the group expanded in the filmstrip and the pill above it; the Couldn't move sheet (05) with the new subtitle and Done only; Not connected and View only (12) as `externaldrive.badge.xmark` and `lock.fill`.
- **iPad (provisional, #152 and #163):** the sidebar has no Skipped row and no Analyzed word, shows only ratings and labels that have photos, and has a regroup glyph button on the Similar groups row. The grid title is the selected row's name. Detail shows a rail hover tooltip.
- **New frames:** read failure toast (02), iPad Locations with a subfolder selected, iPad detail rejected, Duo expanded photo focus rejected, and a proposal for the swipe star bar's cleared step (#125), which is open for the designer.
- **Open:** the save failure toast. The frame puts it above the filmstrip so it doesn't cover the mark capsule; the build draws it at the bottom edge, over the capsule. One of the two should change.

## Detail shows rejects at full brightness with a corner glyph (owner, 2026-11-12)

Detail keeps rejected photos at full brightness so the person can judge them. A small `xmark` in a filled `reject` circle stays in the stage's top-trailing corner during zoom and pan, including with chrome hidden. It is decorative, ignores taps and adds no status word. VoiceOver includes "Rejected" in the photo label. Grid, filmstrip and Move Rejects quick grid thumbnails keep dimming rejects without badges. This supersedes the detail dimming rule and the `03-detail-rejected` frame on this point.

## Detail never shows a loading label (owner decision, 2026-11-12)

The grid thumbnail stands in until the detail preview arrives.

## Files are the truth; no save status (owner decision, 2026-11-11)

This supersedes the save glyphs and save-failure behavior below. Photos, XMP sidecars and Clove's standalone JPEG/HIF mark store are the truth. Show a tap immediately and write in action order. On a connected failure, say "Couldn't save the mark." once, re-read the photo and show its file's marks. Keep only pending marks, with no retained failure, retry, save subtitle or leave prompt. Disconnect drops queued work and pending marks; marking stays off until Reopen reads the files. Do not cancel an operation already touching a file. Move Rejects runs behind writes and uses the marks on disk, reports failures without a retry, and keeps Undo.

## Drive disconnected drops unsaved marks (owner decision, 2026-11-11)

When the drive disconnects, stop the action and write queues and drop the folder's pending and failed marks and their status. Show the photos' last-read marks and the existing disconnected banner. Marking stays off until Reopen. Reopen reads the XMP sidecars fresh; no unfinished edits, retries or conflict state carry across the open. The XMP and photo are the source of truth.

## Groups in detail (owner decision, 2026-11-12)

No group view: detail with an expanded group; Reject N unmarked pill above the strip (owner, 2026-11-12). A grid stack opens the first unmarked member, or the first member if all are marked. Zoom and position stay synced within the group. Auto-advance visits unmarked members, then leaves a finished group for the first photo after it in grid order. The sidebar and saved group routes are deleted without migration. This supersedes the group-screen decisions below.

## Filmstrip group tap (owner decision, 2026-11-11)

In detail, tapping a collapsed group in the filmstrip jumps to the group's first photo, and the group expands in place on its tint. It no longer opens group review, which replaced the whole filmstrip with the group's photos. Group review opens from the grid's group stack.

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
- The filmstrip follows the grid. Other groups are collapsed into one stacked tile with a count badge. The current group is expanded in place on a muted tint (decided: option C), with no outline. The current frame has a thin ring in the primary text color. **Superseded (owner, 2026-11-13, #226):** the surface is `text/primary` at 12% layer opacity, not `group` at 25%; it adapts to the theme. Figma ignores opacity on a variable-bound paint, so any tint uses a layer with layer opacity.
- **Superseded (owner, 2026-11-13, #226):** the count badges on group stacks (in every grid and the filmstrip) and the Duo half-fold group outlines originally used `Color.clove.group`. Count badges now use the invariant black 56% / white 94% overlay, and the progress line while grouping is `group`'s remaining use.

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

## Duo expanded right-pane fixes (owner feedback, 2026-11-12; #198, #199, #200)
- Marking moves out of the expanded Duo's side toolbar: Reject, the stars and the label circle form one horizontal marking capsule in its own reserved layout row beneath the right-hand photo, so system island/status activity cannot push marking into overflow or cover the image (#200). The stars rate and clear like the iPhone capsule. The side toolbar keeps Back, view tools, Undo and Move Rejects. The cover keeps its compact dock controls and pickers; iPhone and iPad are unchanged.
- The fitted photo in expanded Duo stays stationary during a fit drag and never draws over the divider or left grid; the swipe still commits navigation on release, zoomed panning stays clipped to the pane, and returning to fit centers the photo (#199). iPhone navigation keeps its slide.
- Opening a group in expanded Duo shows its member thumbnails in the left pane with the current member ringed, instead of leaving only the collapsed stack (#198). This supersedes the assumption that the folder grid alone replaces member navigation on the expanded Duo. It is a presentation of the existing grid derived from the current photo's group, not a restored group screen: no group business logic, save/retry state or new routes. Back — or navigating out of the group — returns to the folder grid with its position. iPhone, iPad and folded Duo group browsing are unchanged. **Superseded (owner, 2026-11-13, #225):** the group now expands in place inside the folder grid, so the photos and other stacks around it stay reachable and folding is a thumbnail change only. See "Groups expand in place in the Duo's grid and filmstrip" above.

## Native shared marking controls and palette refinements (owner, 2026-11-13; #227)

Supersedes the 358 pt marking capsule, its five-inline-star row, the xmark-based Reject circle, the system-blue accents in Light and Dark, and the contrasting expanded-Duo side-region treatment.

- **Shared marking toolbar (168 × 48):** Reject, Rating and Label in one compact native glass group, reused by iPhone detail, select mode, the half fold, the iPad rail, the Duo cover and expanded Duo, and the batch bar. Layout wrappers adapt placement only; actions, state and styling are never duplicated. Reject is `flag.slash` off / `flag.slash.fill` in `reject` on — never an ✕, which stays reserved for Close/Dismiss. The rating action centres one icon-and-number group with a fixed one-digit slot (about 15 pt star, 13 pt Medium number), outlined `star` when unrated. Tapping it opens the quick-rating ladder; tapping the current level clears the rating.
- **Quick-rating ladder (48 × 204, 44 pt chip, ~10 pt gap):** five stars filling from the bottom in native glass, with a separate reject chip below. Clear shows `star.slash` in `text/secondary`; Reject fills `flag.slash.fill` in `reject`. Clove's existing swipe recognizer, enabled-rating rules, live preview, haptics, cancellation and commit-on-release behavior are unchanged; the display-only indicator never intercepts touch.
- **Accent pair:** Light `accent` is #8A6548, Dark is #D4AA78; the other six themes keep their accents. Native controls follow the Clove accent, so no generic control keeps a system-blue tint. `rating/on`, `reject` and `label/*` keep their semantics, including the actual Blue photo label.
- **Expanded grid group surface:** the expanded grid's group members sit on `text/primary` at 12% on the background shape alone, the same neutral surface as the filmstrip group extent (#226). Photos are never tinted; the current-photo ring stays the solid `text/primary` stroke.
- **Duo marking placement:** in expanded Duo the marking toolbar sits in a reserved bottom-right marking area beside a filmstrip whose viewport narrows accordingly, beneath the photo and outside the status / Live Activities area. The toolbar region shares the photo stage's background; no contrasting sidebar slab. System layout and safe areas place it; #204's clipping and containment stay.
- **Entry:** Open folder is text-only at 168 × 48 with no folder or plus glyph, in both the resume and first-launch states, with bottom safe-area clearance. The Reconnect chip stays legible on a `surface/card` capsule, never a filled accent pill.

## Camera-style focus overlays, local overlap handling, and shared toggle (#231)

Supersedes the earlier global camera-AF-vs-analysis toggle concept and filled multi-color ROI overlays.

- **One shared native toggle (`viewfinder`, "Focus regions"):** placed next to Back on iPhone, alongside navigation controls on iPad, and in Duo's right action rail (~44 pt hit target). Uses `accent` when On and neutral `text/primary` when Off. Session-scoped (`showsFocusRegions`, default On, unpersisted); Off removes all overlay visuals, status badge, and hit/accessibility targets, and late analysis callbacks or photo navigation never override Off.
- **Per-person presentation selection (analysis evidence unchanged):** full evidence and scores remain intact (`retainedRegions`), while presentation uses typed `groupIndex` to select at most one usable eye per person via deterministic geometric tie-break (`centerX, centerY, width, height, id` — independent of score and zoom), omitting that person's face frame when an eye is shown and falling back to the face frame when no usable eye exists.
- **Local AF overlap suppression:** instead of globally hiding analysis when AF metadata exists, camera AF markers suppress only analysis markers whose compact normalized marker footprint (`normalizedMarkerRect`, using a compact centred footprint for eyes rather than Vision's measurement ROI or 44 pt touch target) collides with AF within `localOverlapMargin = 0.015`. Separated AF and unrelated subjects remain visible together; missing AF metadata never fabricates an AF frame.
- **Camera-style rendering & zoom stability:** no tinted fill; normal `1.25 pt` `focus/outline` (`#FFFFFF`) with `focus/edge` (`#00000073`) contrast edge, selected inspection `1.5 pt` in Clove `accent`, and subdued dashed outlines for unavailable regions. AF draws a closed fine-line rectangle, face draws four corner L-brackets, and eye draws a small centred square (`16 pt` screen-space actionable, `12 pt` unavailable). Screen-space strokes, eye square dimensions, and >= 44 pt hit targets stay invariant through zoom with deterministic nearest-centre hit resolution for overlapping targets.
- **Figma note:** the live Figma nodes referenced in #231 (`464-2452`, `491-4124`) require the owner's Figma session; token definitions (`focus/outline`, `focus/edge`) and written handoff docs were updated in-repo to match the owner specification.
