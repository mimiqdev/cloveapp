# Clove MVP: interactions and flows

Items tagged **(proposed)** were not reviewed in the design. They are sensible defaults for the implementer; confirm them with the owner before treating them as final.

## Core model

- A **mark** is a rating and a label (none or one of 5 colors). The rating can be −1, which is Reject, so a photo is never rated and rejected at once: rejecting replaces the stars, and undoing restores them. Marks are written to the photo's XMP sidecar, in the folder where the photos live; a standalone JPEG/HIF keeps its rating and label in Clove. Nothing is imported or copied.
- Every mark appears at once and saves in user action order. A pending mark is shown until its write finishes; otherwise the files supply the marks. There is no save status. Only folder access problems appear in the subtitle, as a glyph (`externaldrive.badge.xmark` or `lock.fill`); "Not connected" and "View only" are its VoiceOver labels.
- **Undo** (top bar, or the Duo dock) reverts the last mark change, a "Reject N unmarked", or a Move Rejects. It is a stack and works across photos.
- **Reject never deletes.** Rejected photos stay in place (dimmed in the grid and filmstrip; full brightness with a corner glyph in detail) until the person runs Move Rejects, which moves them to `_Rejected/` inside the same folder.

## App flow

```
Entry ──tap hero card──▶ Grid (scrolled to last photo) ──▶ Detail at that photo
  │                       │
  └─Open folder─▶ picker ─┘ (opening: reading ▶ grouping, grid usable throughout)

Grid ─tap photo or stack─▶ Detail (current group expanded in filmstrip)
Detail ─Back─▶ Grid (scroll position kept)
Grid ─Move Rejects─▶ Confirm sheet ─Move─▶ Grid + toast (Undo / Details)
```

## iPhone

| Where | Gesture | Result |
|---|---|---|
| Grid | Tap a tile | Opens detail; a stack starts at its first unmarked member, or its first member if all are marked. |
| Grid | Long press **(proposed)** | A context menu: Reject, Rate, Label, Select. |
| Grid | Filter button | Opens the filter menu. Picking an item applies it at once, and the button fills with `accent`. |
| Grid | "…" ▶ Select | Select mode: tap tiles to toggle, then use the marking toolbar to mark all of them. Done exits. |
| Detail | Swipe left or right | Next or previous photo in grid order (filtered order when a filter is on). |
| Detail | **Slow vertical drag** | Relative slider from the current rating: up raises, down lowers through enabled stars, 0 and −1, one step per 60 pt with a light haptic. Reverse across the start in the same gesture. The ladder stays beside the original touch and the toolbar/rail rating preview the value; clear shows an empty ladder with `star.slash`, Reject fills the `flag.slash` chip immediately. Release commits the preview once for undo, without changing the label. |
| Detail | **Quick swipe down** | Mode is chosen once from the first ~100 ms (starting threshold 500 pt/s downward). Three stops: starting rating, 0 at 60 pt (medium haptic), −1 at 180 pt (heavier haptic). Reverse from Reject to 0; up past the start restores the original. Unrated still passes through 0; Reject cannot lower further, and up steps −1 → 0 → enabled stars. Quick up is a slow slider. No hold or momentum. Distances and haptic strengths need device tuning. Glyphs only; stage words are VoiceOver labels. |
| Detail | Tap the marking toolbar's reject, rating or label | Reject toggles directly (owner decision, 2026-11-13, #227). The rating and label actions open the shared visual tap pickers (`RatingPicker` / `LabelPicker`, #229): `star.slash` + 5 stars or `circle.slash` + color dots horizontally (`288 × 52` pt) anchored above the toolbar by default (or vertically `52 × 288` pt where space calls for it); picking applies without clearing the other mark attribute and closes, and tapping outside dismisses without toggling detail chrome. On single-photo controls, tapping the already-selected star clears the rating; batch controls clear through the picker's Clear action. |
| Detail | Single tap on the photo | Hides or shows the chrome (marking toolbar, filmstrip, top bar buttons). |
| Detail | Double-tap or pinch | 100% zoom at the tapped point. The chrome hides. Double-tap again to fit. |
| Detail | Tap a filmstrip thumbnail | Jumps to that photo. Tapping a collapsed group jumps to its first photo, and the group expands in place in the filmstrip. A grid stack opens the same detail view on the first unmarked member, or the first member if all are marked. |
| Detail | ⓘ | Opens the Info sheet (medium detent). |
| Any | **Auto-advance** (Settings; default and timing **(proposed)**) | After a mark is set in detail, move to the next photo after a short beat (about 250 ms). The swipe-up star bar commits and then advances. |
| Hardware keyboard **(proposed)** | 0–5, X, 6–9, arrows, Z | Rating, reject, labels red to blue (purple has no key), next/previous, undo. No hints are shown on screen. |

## Groups in detail

- A stack opens detail on the first unmarked photo, or the first photo when all are marked. Its filmstrip group expands in place; the filename, Info and marking controls stay the same.
- Zoom and pan stay synced between photos of the same group. Leaving the group follows the detail keep-zoom setting.
- "Reject 6 unmarked" sits centred in its own row above the filmstrip, once the visible group has both a rated or labeled photo and an unmarked photo. It rejects only visible photos with no rating, label or Reject. Undo restores the whole action and returns to the photo shown when it was tapped.
- The pill hides when nothing remains to reject, when marking is off, and with the chrome. Nothing replaces it. It stays clear of the marking toolbar and swipe ladder.
- With auto-advance on, a triggering mark moves to the next unmarked member, wrapping once. Once the group has no unmarked members, including after the pill, it moves to the first photo after the group in grid order. At the end it stays.

## Move Rejects

1. Tap Move Rejects. The confirm sheet always opens; nothing moves on the first tap.
2. Optionally, tap the fanned stack to see the rejects in a quick grid, and tap a photo to keep it. The button count updates. A keep is only staged here: nothing is written yet, and tapping again un-keeps.
3. Tap Move. The kept photos have their reject cleared by setting the rating to 0 (written to XMP; the label is untouched), then the rest of the files (RAW, JPEG and XMP together) move to `_Rejected/` (the name is configurable in Settings). Swiping the sheet down instead discards the keeps, and every photo stays rejected.
4. A toast offers Undo, which moves the files back and re-rejects the kept photos, as one step. A partial failure reports how many did not move; Details lists those photos without a retry action. The grid shows the files left on disk.

## iPad

- The sidebar is the filter. Selecting a row sets the grid's filter and title, and clears any other sidebar filter. There is no Filter button, and "…" and Move Rejects are in the top bar.
- Tapping a photo opens detail full screen; "‹ All" (the selected row's name) goes back with the same filter.
- Detail has a right rail instead of the toolbar: tap or drag the quick-rating ladder, tap the shared Reject action, or open the label picker from the label action. Tapping the current rating clears it. The rail never hides; single tap and zoom hide the filmstrip, Reject N unmarked pill and top bar buttons while the stage keeps its size.
- Swipe marking stays on the photo as on iPhone: slow vertical drags use the relative slider with live feedback in the rail's ladder; quick down clears then rejects by distance. A downward swipe on Reject leaves it rejected; up steps through 0 to enabled stars.
- Full keyboard support as above **(proposed)**. Pointer hover shows the rail's tooltips.

## Duo cover (folded)

- The same as iPhone. Back, Filter and Move Rejects are in the side rail next to the status bar, following Apple's Duo guidance.
- Tapping Rating or Label in the vertical side toolbar opens the shared visual `RatingPicker` (`5..1, Clear` top to bottom) or `LabelPicker` popover alongside the toolbar button; picking or tapping outside dismisses. Dragging from the Rating button still scrubs ratings directly.

## Duo expanded (unfolded, landscape)

States and transitions:

```
Grid (full width, 6 col) ──tap photo──▶ Photo focus (grid 30 / photo 70)
Photo focus ──drag divider left──▶ Photo only (iPad-style detail with filmstrip)
Photo only ──drag from left edge (proposed)──▶ Photo focus
Photo focus ──drag divider right, or Back──▶ Grid
Photo only ──Back──▶ Grid
```

- The divider snaps only to **30/70** or **photo only**. It never rests at 50/50 or on the fold.
- **Folding a group** (owner change, #225): in the split's grid the group's header chevron folds its members to the group's stack, and in photo only the expanded group's chevron does the same in the filmstrip. Both keep the photo, its marks and the route, and the stack reopens the group in place. Back still leaves the whole detail.
- **The dock** (right column, top to bottom): Back; Filter, "…", Info; Undo, Move Rejects. There are no buttons over the grid or the photo.
- **Marking toolbar** (owner changes, #200 and #227): the shared 168 × 48 marking toolbar sits in a reserved bottom-right marking area beside the filmstrip, beneath the right-hand photo, inside the photo pane. In photo only the filmstrip narrows so nothing scrolls under it; the toolbar region shares the photo stage's background. The rating action opens the quick-rating ladder; the label action opens the color picker. Marking never competes with system island/status activity for toolbar space, and there are no marking items in the side toolbar. The cover keeps its compact dock controls.
- **Fit containment** (#199): in expanded Duo the fitted photo stays stationary while a horizontal drag is in progress; the swipe still commits navigation on release. Photo pixels never draw over the divider or the left grid, including during transitions. Zoomed panning stays inside the pane and returning to fit centers the photo.
- **Group expansion** (owner change, #225): the left pane is the folder grid, with the folder's own photos and the other groups' stacks in place. The photo's own group expands at its stack's position: its header names the members the filter shows, and its chevron folds them back into the stack. Tapping a member changes the preview and its marks; navigation and auto-advance keep the current member visible. Folding and reopening change the thumbnails only, and Back returns to the full folder grid with its browsing position. There is no group route or page.
- In photo focus, tapping a grid tile changes the photo, and the swipe gestures on the photo work as on iPhone.

## Duo half fold (MVP behavior)

- The photo is on the top half, and the controls, grid and marking toolbar are on the bottom half. Nothing is interactive on the top half except swiping the photo and double-tap zoom.
- The dedicated half-fold layout is planned for 1.1.

## Opening a folder

1. The picker returns a folder. The grid appears at once with placeholders.
2. **Reading**: the subtitle reads "412 of 1,284", and the 2 pt progress line fills in `accent`. Thumbnails and existing XMP marks fill in as they are read. The person can already open and mark photos.
3. **Grouping**: the subtitle reads "Finding similar shots…", and the line turns `group`. Stacks form one by one. The photo being viewed never moves, and the grid keeps its scroll anchor.
4. When done, the subtitle returns to "1,284 photos". Move Rejects is hidden until then.
- If Similar groups is off in Settings, stage 2 is skipped.

## Errors

- **Drive disconnected**: drop queued work and pending marks. Show the banner, dim the grid, and show the photos' last-read marks. Marking is off until **Reopen**, which reads the XMP sidecars fresh. An operation already touching a file finishes normally.
- **Lost access** (the security-scoped bookmark is stale): view only from the cache. **Open** re-runs the folder picker.
- **Leaving the folder**: leave immediately without a prompt. Pending writes finish in the background or are dropped when the folder closes.
- **A connected write fails**: show one "Couldn't save the mark." toast, read that photo's marks from the files again and show them. Retain no failed mark and do not retry.
- **Entry**: a folder whose drive is gone shows a faded row with Reconnect, which re-runs the picker for that folder.

## Batch rename (draft, #176)

1. In select mode, tap Rename…. The order view shows only the selected photos.
2. Drag tiles to set the order; the numbers update live. VoiceOver gets "Move earlier", "Move later", "Move to start" and "Move to end". Tap a tile to check focus in a zoomable viewer that swipes in this order. Cancel drops the order.
3. Tap Next. The name sheet previews every new name live. A name already used in the folder warns and is replaced, with the old file set moved to `_Rejected`. Names that can't exist (invalid characters, too long, duplicates in the batch) block Rename.
4. Tap Rename. Pending marks finish first, then the sheet shows progress and can't be dismissed. Afterwards the folder is read again, the mark undo history is cleared, select mode ends, and a toast reports the result. Renaming has no Undo.

## Theme switching

- Settings ▶ Appearance. With "Match system light/dark" on, Light and Dark follow the system, and the picker selection is ignored for those two. Picking another theme turns the toggle off.
- Apply by swapping the token set at the app root. The change is immediate, with a short crossfade **(proposed)**. Photos are never tinted.
