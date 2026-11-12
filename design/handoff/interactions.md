# Clove MVP: interactions and flows

Items tagged **(proposed)** were not reviewed in the design. They are sensible defaults for the implementer; confirm them with the owner before treating them as final.

## Core model

- A **mark** is a rating and a label (none or one of 5 colors). The rating can be −1, which is Reject, so a photo is never rated and rejected at once: rejecting replaces the stars, and undoing restores them. Marks are written to the photo's XMP sidecar, in the folder where the photos live; a standalone JPEG/HIF keeps its rating and label in Clove. Nothing is imported or copied.
- Every mark appears at once and saves in user action order. A pending mark is shown until its write finishes; otherwise the files supply the marks. There is no save status. Only folder access problems appear in the subtitle: "Not connected" or "View only".
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
| Grid | "…" ▶ Select | Select mode: tap tiles to toggle, then use the capsule to mark all of them. Done exits. |
| Detail | Swipe left or right | Next or previous photo in grid order (filtered order when a filter is on). |
| Detail | **Swipe up** and hold | Shows the vertical star bar. Dragging up fills stars from the bottom; release commits. The capsule stars preview the live value. |
| Detail | **Swipe down** | Reject (the ✕ chip under the star bar). Swiping down again on a rejected photo clears the reject. |
| Detail | Tap the capsule's reject, stars or label | Sets the mark directly. Tapping the current star value clears it. The label opens the picker, and picking closes it. |
| Detail | Single tap on the photo | Hides or shows the chrome (capsule, filmstrip, top bar buttons). |
| Detail | Double-tap or pinch | 100% zoom at the tapped point. The chrome hides. Double-tap again to fit. |
| Detail | Tap a filmstrip thumbnail | Jumps to that photo. Tapping a collapsed group jumps to its first photo, and the group expands in place in the filmstrip. A grid stack opens the same detail view on the first unmarked member, or the first member if all are marked. |
| Detail | ⓘ | Opens the Info sheet (medium detent). |
| Any | **Auto-advance** (Settings; default and timing **(proposed)**) | After a mark is set in detail, move to the next photo after a short beat (about 250 ms). The swipe-up star bar commits and then advances. |
| Hardware keyboard **(proposed)** | 0–5, X, 6–9, arrows, Z | Rating, reject, labels red to blue (purple has no key), next/previous, undo. No hints are shown on screen. |

## Groups in detail

- A stack opens detail on the first unmarked photo, or the first photo when all are marked. Its filmstrip group expands in place; the filename, Info and marking controls stay the same.
- Zoom and pan stay synced between photos of the same group. Leaving the group follows the detail keep-zoom setting.
- "Reject 6 unmarked" sits centred in its own row above the filmstrip, once the visible group has both a rated or labeled photo and an unmarked photo. It rejects only visible photos with no rating, label or Reject. Undo restores the whole action and returns to the photo shown when it was tapped.
- The pill hides when nothing remains to reject, when marking is off, and with the chrome. Nothing replaces it. It stays clear of the mark capsule and swipe star bar.
- With auto-advance on, a triggering mark moves to the next unmarked member, wrapping once. Once the group has no unmarked members, including after the pill, it moves to the first photo after the group in grid order. At the end it stays.

## Move Rejects

1. Tap Move Rejects. The confirm sheet always opens; nothing moves on the first tap.
2. Optionally, tap the fanned stack to see the rejects in a quick grid, and tap a photo to keep it. The button count updates. A keep is only staged here: nothing is written yet, and tapping again un-keeps.
3. Tap Move. The kept photos have their reject cleared by setting the rating to 0 (written to XMP; the label is untouched), then the rest of the files (RAW, JPEG and XMP together) move to `_Rejected/` (the name is configurable in Settings). Swiping the sheet down instead discards the keeps, and every photo stays rejected.
4. A toast offers Undo, which moves the files back and re-rejects the kept photos, as one step. A partial failure reports how many did not move; Details lists those photos without a retry action. The grid shows the files left on disk.

## iPad

- The sidebar is the filter. There is no Filter button, and "…" and Move Rejects are in the top bar.
- Detail has a right rail instead of the capsule: tap or drag the vertical star bar, tap Reject, or tap a label dot. Tapping the current rating or label clears it. The rail never hides; single tap and zoom hide the filmstrip, Reject N unmarked pill and top bar buttons while the stage keeps its size.
- Swipe marking stays on the photo as on iPhone: swipe up to rate with live feedback in the rail's stars, and swipe down to toggle Reject.
- Full keyboard support as above **(proposed)**. Pointer hover shows the rail's tooltips.

## Duo cover (folded)

- The same as iPhone. Back, Filter and Move Rejects are in the side rail next to the status bar, following Apple's Duo guidance.

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
- **The dock** (right column, top to bottom): Back; Filter, "…", Info; ★ rating, Reject, Label (only while a photo is open); Undo, Move Rejects. There are no buttons over the grid or the photo.
- **★ button**: tap and slide up or down to change the rating. A vertical star bar opens to the left of the dock and fills from the bottom; release commits. A tap without sliding opens the bar **(proposed)**.
- **Label circle**: tap it to open a horizontal color row beside the dock, with the current color ringed. Picking closes it.
- In photo focus, tapping a grid tile changes the photo, and the swipe gestures on the photo work as on iPhone.

## Duo half fold (MVP behavior)

- The photo is on the top half, and the controls, grid and capsule are on the bottom half. Nothing is interactive on the top half except swiping the photo and double-tap zoom.
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

## Theme switching

- Settings ▶ Appearance. With "Match system light/dark" on, Light and Dark follow the system, and the picker selection is ignored for those two. Picking another theme turns the toggle off.
- Apply by swapping the token set at the app root. The change is immediate, with a short crossfade **(proposed)**. Photos are never tinted.
