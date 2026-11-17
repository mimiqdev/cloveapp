# Clove MVP: interactions and flows

Items tagged **(proposed)** were not reviewed in the design. They are sensible defaults for the implementer; confirm them with the owner before treating them as final.

## Core model

- A **mark** is a rating and a label (none or one of 5 colors). The rating can be −1, which is Reject, so a photo is never rated and rejected at once: rejecting replaces the stars, and undoing restores them. Marks are written to the photo's XMP sidecar, in the folder where the photos live; a standalone JPEG/HIF keeps its rating and label in Clove. Nothing is imported or copied.
- Every mark appears at once and saves in user action order. A pending mark is shown until its write finishes; otherwise the files supply the marks. There is no save status. Only folder access problems appear in the subtitle, as a glyph (`externaldrive.badge.xmark` or `lock.fill`); "Not connected" and "View only" are its VoiceOver labels.
- **Undo** (top bar, or the Duo dock) reverts the last mark change, a "Reject N unmarked", or a Move Rejects. It is a stack and works across photos.
- **Reject never deletes.** Rejected photos stay in place (dimmed in the grid and filmstrip; full brightness with a corner glyph in detail) until the person runs Move Rejects, which moves them to `_Rejected/` inside the same folder.

## App flow

```
Entry ──tap hero card──▶ Grid (scrolled to last photo) ──▶ Detail at that photo (Timeline)
  │                       │
  └─Open folder─▶ picker ─┘ (opening: reading ▶ grouping, grid usable throughout)

Grid ─tap standalone photo─▶ Detail (Timeline, expandedGroup = nil)
Grid ─tap group stack─────▶ Detail (Group Focus at Representative Photo, expandedGroup = group.id)
Detail ─Back───────────────▶ Grid (expandedGroup cleared, scroll position kept)
Grid ─Move Rejects─▶ Confirm sheet ─Move─▶ Grid + toast (Undo / Details)
```

## iPhone

| Where | Gesture | Result |
|---|---|---|
| Grid | Tap a tile | A standalone photo opens Detail in **Timeline**. When Similar groups is on (default), groups with `>= 2` visible members appear as collapsed stacks (count badge + peeking cards reflect visible members only, dimmed only when all visible members are rejected). Tapping a stack opens Detail directly in **Group Focus** (`expandedGroup = group.id`) at the group's **Representative Photo** (`Highest rated > Non-rejected labeled > First unmarked > First visible`). Groups with only 1 visible member under a filter behave as standalone photos. |
| Grid | Long press **(proposed)** | A context menu: Reject, Rate, Label, Select. |
| Grid | Filter button | Opens the filter menu. Picking an item applies it at once, and the button fills with `accent`. |
| Grid | "…" ▶ Select | Select mode: tap tiles to toggle (tapping a stack toggles all visible members), then use the marking toolbar to mark all of them. Done exits. |
| Detail | Swipe left or right | **Timeline**: steps 1-by-1 across Timeline slots (skipping collapsed groups in one swipe, landing on each stack's Representative Photo) and resets zoom to fit. **Group Focus**: steps strictly within `visibleMembers` (`1 … N`), stopping at both ends without leaving the group and preserving synchronized zoom. At fit and in the default `Rate & switch` zoomed mode; `Pan` gives one-finger drags back to panning. |
| Detail | **Vertical drag** (single-finger; also single-finger while zoomed in `Rate & switch`, two-finger in `Pan`) | Position-driven anchor-symmetric slider (`sortedUnique([-1, 0, startingRating] ∪ { enabledStars > startingRating })`) with `deadZone = 30 pt`, `stepDistance = 45 pt`, `reversalHysteresis = 8 pt`, and endpoint overshoot clamping. From unrated, up selects between enabled stars and down 30 pt reaches −1 (Reject) immediately at any speed. From 1–5★, up raises through higher enabled stars, down once (−30 pt) clears to 0, and down twice (−75 pt) reaches −1 (Reject), independent of starting star. From Reject (−1), up steps through 0 to enabled stars. Returning to the starting bucket cancels to the original rating. Preview and semantic haptics (light step, medium clear, heavy reject) fire from the first movement. Release commits once for undo without changing the label. **On an unexpanded group stack in Timeline**, marking is disabled and a vertical drag pulses the `"Expand {n} photos"` pill instead. |
| Detail | Tap the marking toolbar's reject, rating or label | Disabled on an unexpanded group stack in Timeline. Otherwise Reject toggles directly (`#227`), and rating/label open `RatingPicker` / `LabelPicker` (`#229`). On single-photo controls, tapping the already-selected star clears the rating; batch controls clear through Clear. |
| Detail | Single tap anywhere on the photo | Hides or shows all togglable chrome together (marking toolbar or rail's stage companions, filmstrip, `Expand {n} photos` / `Reject {n} unmarked` pill, top bar Info/Undo and status line), at fit and while zoomed, waiting for the double-tap window; never navigates from any zone (#252, #273, #302). |
| Detail | Double-tap anywhere or pinch | At fit, double-tap centres 100% zoom and isolates an `accent` outline: with `Zoom to focus` (default) the most relevant presented region, with `Zoom to tap point` always the tapped point, with `Off` nothing (#302). Chrome stays steady across fit and zoom (#273, #302). Double-tap anywhere again to fit. |
| Detail | Tap Focus regions (`viewfinder`) | Toggles camera AF, face, and eye overlays (and their hit/accessibility targets) together for the browsing session without restarting or canceling analysis. Preserved across photo changes. |
| Detail | Tap an actionable focus region | Centres native 100% zoom on that region and isolates its `accent` outline until returning to fit; does not alter marks or trigger navigation. Unavailable regions stay non-actionable. |
| Detail | Tap a filmstrip item or vertical-swipe strip | **Timeline**: tapping a standalone thumbnail or unselected stack opens it in Timeline (with a stack's Representative Photo); tapping the already-selected stack, tapping `"Expand {n} photos"`, or swiping upward (`>= 24 pt`) on any stack enters **Group Focus**. **Group Focus**: tapping a member switches within the group keeping zoom; tapping the leading `chevron.down` collapse button (`clove.detail.filmstrip.group.fold`) or swiping downward (`>= 24 pt`) anywhere on the strip collapses back to **Timeline** on the Representative Photo. |
| Detail | ⓘ | Opens the Info sheet (medium detent). |
| Any | **Auto-advance** (Settings; default and timing **(proposed)**) | After a triggering mark completes (~250 ms beat), advances according to `After marking`: standalone photos step across Timeline slots; **first-pass** Group Focus visits remaining `unmarked` visible members (wrapping once) and, after the final unmarked member or `"Reject {n} unmarked"`, collapses to Timeline and advances to the next Timeline slot; **second-pass** edits on an already-decided group never auto-collapse or eject out of the group. |
| Hardware keyboard **(proposed)** | 0–5, X, 6–9, arrows, Return, Escape, Z | Rating, reject, labels red to blue (purple has no key), Timeline or Group Focus navigation (`←`/`→`), expand/collapse current group (`Return`), collapse Group Focus (`Escape`), undo (`Z`/`⌘Z`). Marking keys are disabled on unexpanded group stacks in Timeline. No hints are shown on screen. |

## Groups in detail

- **Two-level model**: Detail operates at either **Timeline** (`expandedGroup == nil`, showing standalone photos and collapsed multi-photo group stacks) or **Group Focus** (`expandedGroup == group.id`, isolating the filmstrip, synchronized zoom, and bounded `←` / `→` swipes to that group's visible members `1 … N`). There is no inline accordion expansion inside the filmstrip and no separate group route/sidebar. Top-bar Back always returns to Grid View in one tap.
- **Representative Photo rule**: a single priority rule governs Grid stack covers, Timeline stack covers, Timeline stack landing photos, and initial Group Focus entry (and collapse snap): `Highest star rating > Non-rejected colour label > First unmarked > First visible`.
- **Read-only protection on collapsed stacks**: when browsing an unexpanded multi-photo group stack in Timeline, marking toolbar/rail controls, vertical stage marking swipes, and marking keys are disabled so you never accidentally rate or batch-reject an entire burst while collapsed; vertical stage drags gently pulse `"Expand {n} photos"` above the filmstrip.
- **"Expand {n} photos"** pill floats centred above the filmstrip without taking its layout height (or at the bottom of the stage in Photo Preview) while on an unexpanded stack in Timeline; tapping it, double-tapping the strip stack, swiping up on the strip stack, or pressing `Return` enters Group Focus without reloading pixels.
- **"Reject {n} unmarked"** pill floats centred above the filmstrip, outside its layout height, in Group Focus once the visible group has both a rated or labeled photo and an unmarked photo. It rejects only visible unmarked photos; Undo restores the whole action and returns to the photo shown when it was tapped.
- Both pills hide with chrome, and `"Reject {n} unmarked"` also hides when marking is off or no unmarked members remain.
- **Auto-advance in Group Focus**: during first-pass culling (while unmarked visible members remain), a triggering mark moves to the next unmarked member, wrapping once; marking the last unmarked member or tapping `"Reject {n} unmarked"` exits Group Focus and advances across Timeline slots (`Next photo` -> next Timeline slot; `Next unmarked photo` -> next unmarked standalone photo or stack with visible unmarked members; `Stay` stays in Group Focus). During second-pass review (entering or editing a group that already had 0 unmarked visible members), marks never auto-collapse or leave the group.
- Zoom and pan stay synchronized within Group Focus; collapsing to Timeline (or switching between Timeline slots) resets zoom to fit if the displayed photo changes or leaves the group (#302).

## Move Rejects

1. Tap Move Rejects. The confirm sheet always opens; nothing moves on the first tap.
2. Optionally, tap the fanned stack to see the rejects in a quick grid, and tap a photo to keep it. The button count updates. A keep is only staged here: nothing is written yet, and tapping again un-keeps.
3. Tap Move. The kept photos have their reject cleared by setting the rating to 0 (written to XMP; the label is untouched), then the rest of the files (RAW, JPEG and XMP together) move to `_Rejected/` (the name is configurable in Settings). Swiping the sheet down instead discards the keeps, and every photo stays rejected.
4. A toast offers Undo, which moves the files back and re-rejects the kept photos, as one step. A partial failure reports how many did not move; Details lists those photos without a retry action. The grid shows the files left on disk.

## iPad

- The sidebar is the filter. Selecting a row sets the grid's filter and title, and clears any other sidebar filter. There is no Filter button, and "…" and Move Rejects are in the top bar.
- Tapping a photo opens Detail in **Photo Preview** (`30%` filtered folder grid beside `70%` photo stage + right rail, no filmstrip) when regular width (`>= 680` pt × `>= 420` pt); tapping a standalone tile opens Timeline, and tapping a group stack opens Group Focus with that group expanded inline in the split grid. "‹ All" (the selected row's name) goes back to **Grid View** with the same filter from either Photo Preview or Focus View.
- Tapping the **Photo Preview / Focus View** (`sidebar.left`, "Hide photo grid" / "Show photo grid") button beside Back toggles between **Photo Preview** and **Focus View** (full photo stage with the two-level filmstrip, no folder grid) for the same photo and `expandedGroup` without altering marks, zoom, filter, sort, or reloading pixels. Narrow/compact sizes (`< 680` pt or `.compact`) hide the toggle and fall back to Focus View while preserving the chosen wide presentation for widening back.
- Detail has a right rail instead of the toolbar: tap or drag the quick-rating ladder, tap the shared Reject action, or open the label picker from the label action (all disabled on unexpanded group stacks in Timeline). Tapping the current rating clears it. The rail never hides; single tap hides the filmstrip (in Focus View), active group pill, and top bar buttons together, at fit and while zoomed, and the stage keeps its size (#273, #302).
- Swipe marking stays on the photo as on iPhone: vertical drags use the position-driven anchor-symmetric slider (`sortedUnique([-1, 0, startingRating] ∪ { enabledStars > startingRating })`) with live feedback in the rail's ladder (or pulse `"Expand {n} photos"` on an unexpanded stack in Timeline).
- Full keyboard support as above **(proposed)**. Pointer hover shows the rail's tooltips.

## Duo cover (folded)

- The same as iPhone. Back, Filter and Move Rejects are in the side rail next to the status bar, following Apple's Duo guidance.
- Tapping Rating or Label in the vertical side toolbar opens the shared visual `RatingPicker` (`5..1, Clear` top to bottom) or `LabelPicker` popover alongside the toolbar button (disabled on unexpanded group stacks in Timeline); picking or tapping outside dismisses. Dragging from the Rating button still scrubs ratings directly.

## Duo expanded (unfolded, landscape)

States and transitions:

```
Grid View (full width, 6 col) ──tap photo / stack──▶ Photo Preview (grid 30 / photo 70, no filmstrip)
Photo Preview ──tap Hide photo grid (sidebar.left) or drag divider left──▶ Focus View (photo + two-level filmstrip, no grid)
Focus View ──tap Show photo grid (sidebar.left)──▶ Photo Preview
Photo Preview ──drag divider right, or Back──▶ Grid View
Focus View ──Back──▶ Grid View
```

- The divider snaps only to **Photo Preview (30/70)** or **Focus View (0/100)**. It never rests at 50/50 or on the fold.
- **Two-level Group Focus parity**: Photo Preview's split grid and Focus View's two-level filmstrip share `browsing.expandedGroup`:
  - When `expandedGroup == nil` (Timeline), Photo Preview's split grid keeps every group collapsed as a stack (highlighting the current stack), while the photo stage shows `"Expand {n} photos"` when on a stack and disables marking. Tapping a stack enters Group Focus (`expandedGroup = group.id`) and expands that group inline in the split grid; tapping a standalone photo opens it in Timeline.
  - When `expandedGroup == group.id` (Group Focus), Photo Preview expands only that group inline at its stack position with `{n} photos` and a `chevron.up` fold button, while Focus View isolates the filmstrip to `visibleMembers` with a leading `chevron.down` fold button and `"Group · {i} / {n}"` counter. Folding from either view returns to Timeline on the Representative Photo without leaving Detail or reloading pixels, and tapping a photo outside the expanded group in the split grid switches to it in Timeline (or into the newly tapped stack's Group Focus). Toggling `sidebar.left` / divider preserves `expandedGroup`, `currentPhoto`, marks, and zoom. Back still exits to Grid View.
- **The dock** (right column, top to bottom): Back; Filter, "…", Photo Preview / Focus View (`sidebar.left`), Info; Undo, Move Rejects. **Focus regions** (`viewfinder`) sits at the leading edge of the photo stage header in both Photo Preview and Focus View, unobstructed by the grid, fitted photo, filename/subtitle, or status / Live Activities area (#292). There are no buttons over the grid or the photo.
- **Marking toolbar** (owner changes, #200 and #227): the shared 168 × 48 marking toolbar sits in a reserved bottom-right marking area beside the filmstrip, beneath the right-hand photo, inside the photo pane. In Focus View the toolbar itself is the one reservation: it narrows the filmstrip's viewport so nothing scrolls under it, and the strip's content fills that viewport up to the toolbar with no second, content-side gap (#237); the toolbar region shares the photo stage's background.
- **Fit containment** (#199): in expanded Duo the fitted photo stays stationary while a horizontal drag is in progress; the swipe still commits navigation on release. Photo pixels never draw over the divider or the left grid, including during transitions. Zoomed panning stays inside the pane and returning to fit centers the photo.
- In Photo Preview, tapping a grid tile changes the photo (or enters Group Focus when tapping a stack), and the swipe gestures on the photo work as on iPhone.

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

- Settings ▶ Appearance offers an independent three-way appearance mode (`Light` / `Dark` / `System`, default `System`) and six paired theme families (`Default`, `Catppuccin`, `Darkroom`, `Night`, `Nord`, `Gruvbox`, default `Default`).
- Changing mode preserves the selected family, and changing family preserves the selected mode. In `System` mode, the resolved palette follows the device appearance within the selected family without falling back to `Default`.
- Apply by swapping the resolved token set at the app root (`mode` + `family` + actual device appearance). Photos are never tinted.
