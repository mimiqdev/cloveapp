# Clove MVP: interactions and flows

Items tagged **(proposed)** were not reviewed in the design. They are sensible defaults for the implementer; confirm them with the owner before treating them as final.

## Core model

- A **mark** is a rating and a label (none or one of 5 colors). The rating can be −1, which is Reject, so a photo is never rated and rejected at once: rejecting replaces the stars, and undoing restores them. Marks are written to the photo's XMP sidecar, in the folder where the photos live; a standalone JPEG/HIF keeps its rating and label in Clove. Nothing is imported or copied.
- Every mark change saves right away. The subtitle shows the state: "● Saved", "● Save failed · Retry", "Not connected" or "View only".
- **Undo** (top bar, or the Duo dock) reverts the last mark change, a "Reject N unmarked", or a Move Rejects. It is a stack and works across photos.
- **Reject never deletes.** Rejected photos stay in place, dimmed, until the person runs Move Rejects, which moves them to `_Rejected/` inside the same folder.

## App flow

```
Entry ──tap hero card──▶ Grid (scrolled to last photo) ──▶ Detail at that photo
  │                       │
  └─Open folder─▶ picker ─┘ (opening: reading ▶ grouping, grid usable throughout)

Grid ─tap photo─▶ Detail          Grid ─tap stack─▶ Group review
Detail / Group review ─Back─▶ Grid (scroll position kept)
Group review ─Continue →─▶ next item in grid order (group ▶ group review, photo ▶ detail; after last ▶ grid)
Grid ─Move Rejects─▶ Confirm sheet ─Move─▶ Grid + toast (Undo / Details)
```

## iPhone

| Where | Gesture | Result |
|---|---|---|
| Grid | Tap a tile | Opens detail (or group review for a stack). |
| Grid | Long press **(proposed)** | A context menu: Reject, Rate, Label, Select. |
| Grid | Filter button | Opens the filter menu. Picking an item applies it at once, and the button fills with `accent`. |
| Grid | "…" ▶ Select | Select mode: tap tiles to toggle, then use the capsule to mark all of them. Done exits. |
| Detail | Swipe left or right | Next or previous photo in grid order (filtered order when a filter is on). |
| Detail | **Swipe up** and hold | Shows the vertical star bar. Dragging up fills stars from the bottom; release commits. The capsule stars preview the live value. |
| Detail | **Swipe down** | Reject (the ✕ chip under the star bar). Swiping down again on a rejected photo clears the reject. |
| Detail | Tap the capsule's reject, stars or label | Sets the mark directly. Tapping the current star value clears it. The label opens the picker, and picking closes it. |
| Detail | Single tap on the photo | Hides or shows the chrome (capsule, filmstrip, top bar buttons). |
| Detail | Double-tap or pinch | 100% zoom at the tapped point. The chrome hides. Double-tap again to fit. |
| Detail | Tap a filmstrip thumbnail | Jumps to that photo. Tapping a collapsed group opens it in group review. |
| Detail | ⓘ | Opens the Info sheet (medium detent). |
| Any | **Auto-advance** (Settings; default and timing **(proposed)**) | After a mark is set in detail, move to the next photo after a short beat (about 250 ms). The swipe-up star bar commits and then advances. |
| Hardware keyboard **(proposed)** | 0–5, X, 6–9, arrows, Z | Rating, reject, labels red to blue (purple has no key), next/previous, undo. No hints are shown on screen. |

## Group review

- It opens on the first undecided photo of the group, and the marking gestures are the same as in detail.
- Zoom and pan are synced across the group, so swiping keeps the same crop.
- "Reject 6 unmarked" shows once any photo in the group is rated or labeled. It rejects only photos with no rating, no label and no reject. It is one undo step.
- When nothing is undecided, the pill becomes "Continue →".
- "…" ▶ "Undecided only" hides the decided photos from the filmstrip.

## Move Rejects

1. Tap Move Rejects. The confirm sheet always opens; nothing moves on the first tap.
2. Optionally, tap the fanned stack to see the rejects in a quick grid, and tap a photo to keep it. The button count updates. A keep is only staged here: nothing is written yet, and tapping again un-keeps.
3. Tap Move. The kept photos have their reject cleared by setting the rating to 0 (written to XMP; the label is untouched), then the rest of the files (RAW, JPEG and XMP together) move to `_Rejected/` (the name is configurable in Settings). Swiping the sheet down instead discards the keeps, and every photo stays rejected.
4. A toast offers Undo, which moves the files back and re-rejects the kept photos, as one step. On a partial failure the toast offers Details, which lists the failures with Try again. Photos that failed stay rejected in place.

## iPad

- The sidebar is the filter. There is no Filter button, and "…" and Move Rejects are in the top bar.
- Detail has a right rail: tap or drag the vertical star bar, Reject, label dots.
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
4. When done, the subtitle returns to "1,284 photos · ● Saved". Move Rejects is hidden until then.
- If Similar groups is off in Settings, stage 2 is skipped.

## Errors

- **Drive disconnected**: marks can't save. Show the banner, dim the grid, and keep marks in memory. **Reopen** retries when the drive is back.
- **Lost access** (the security-scoped bookmark is stale): view only from the cache. **Open** re-runs the folder picker.
- **Leaving with unsaved marks**: on Back or app switch, if a write is pending, show the alert. "Wait" stays; "Leave anyway" drops the pending writes.
- **Save failed** on one photo: the subtitle shows Retry. Marks stay set in the UI and are retried on the next change as well.
- **Entry**: a folder whose drive is gone shows a faded row with Reconnect, which re-runs the picker for that folder.

## Theme switching

- Settings ▶ Appearance. With "Match system light/dark" on, Light and Dark follow the system, and the picker selection is ignored for those two. Picking another theme turns the toggle off.
- Apply by swapping the token set at the app root. The change is immediate, with a short crossfade **(proposed)**. Photos are never tinted.
