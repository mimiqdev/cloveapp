# Clove MVP: component inventory

These are the reusable pieces behind every screen. Sizes are in points, measured on the iPhone frames (390 × 844) unless noted. Token names refer to `tokens/` (code name `Color.clove.<token>`). Icons are SF Symbols, and text is SF Pro at the system text styles. Use Dynamic Type styles rather than the fixed sizes in Figma. Timings (toast auto-hide, chip fade) and SF Symbol names are **proposed** defaults, not reviewed design decisions.

Figma note: the frames still contain some **hidden legacy layers**, named "… · local (hidden)", "… · source …" or "Segmented / Toolbar". They are left over from the original concept. Only build what is visible in a screenshot of the node.

## Shared glass style

All floating controls use one glass material:
- Fill `surface/glass`, a background blur of about 36, and a soft drop shadow (about 16 blur).
- On iOS 26 and later, use the system Liquid Glass (`.glassEffect()`), with `surface/glass` as the fallback. Never put glass on the photo itself, only over it.

## Controls

| Component | Where | Spec |
|---|---|---|
| **Glass icon button** | Top bar (Info, Undo, Filter, "…") | 44 × 44 circle, 20 pt symbol in `text/primary`. iPad 40 × 40. Duo dock 36 × 36. **Filter active** state: filled with `accent`, white glyph. |
| **Move Rejects button** | iPhone grid bottom right; iPad top bar next to "…"; Duo dock bottom capsule; half fold next to "…" | 48 × 48 glass circle on iPhone, `tray.and.arrow.down` at 22 pt. Shown only when rejects exist and the folder is not opening. No count. Always opens the confirm sheet. |
| **Marking toolbar** | iPhone detail, select mode, half fold, iPad rail, Duo cover and expanded (owner decision, 2026-11-13, #227) | One compact 168 × 48 native glass group with three actions split by hairlines: **Reject**, **Rating**, **Label**. Reject draws `flag.slash` in `text/primary` off and `flag.slash.fill` in `reject` on — never an ✕, so it cannot read as Close. The rating action shows an outlined `star` in `text/secondary` when unrated and `star.fill` in `rating/on` plus the 1–5 value in 13 pt Medium when rated; the whole icon-and-number group is centred, with a fixed one-digit slot (monospaced digits, about 15 pt star, about 2 pt gap) so 1 and 5 stay balanced. Tapping it opens the tap rating picker (#229). The label action is a 16 pt circle in the current label colour, or an outlined circle for none, and opens the tap color picker. Hit targets are the full action thirds, not the glyph bounds. |
| **Quick-rating ladder** | Swipe feedback in detail; the Duo cover's rating button | A 48 × 204 native glass column of five `star`/`star.fill` at about 15 pt that **fill from the bottom**, radius 24, padding 10, gap 7, plus a **44 pt chip** about **10 pt** below it. The chip is the swipe-down reject stage: `flag.slash` in `text/secondary`, filled `flag.slash.fill` in `reject` when the swipe reaches it. The **clear stage** shows `star.slash` in `text/secondary` with all stars empty. All five levels always show; disabled levels are dimmed and are not input. A tap picks the star it lands on; tapping the photo's current value clears it. The display-only swipe indicator appears beside the touch start (24 pt to the left of the finger, or to its right when the touch starts in the left third) and does not move during the swipe. iPad rail version: 43 × 174, radius 22, padding 10, gap 6, tap or drag, no chip. |
| **Tap rating picker** | Floating glass capsule anchored above the marking toolbar's rating action, bottom bars or beside vertical side rails | `star.slash` Clear + five SF stars (`star` / `star.fill`) at `44 × 44` pt targets (`4 pt` padding, `3.2 pt` gap). Horizontal default (`288 × 52` pt): Clear, 1–5 left to right. Vertical (`52 × 288` pt) on side rails or tight widths: 5–1, Clear top to bottom. Stars fill cumulatively in `rating/on` (empty in `rating/off`) with a subtle circle on the current value (`isSelected`); mixed batches show no selection. Picking (or tapping the current star on single-photo controls) applies and dismisses; Clear sets `0` without affecting the color label. Tapping outside dismisses. |
| **Label picker (tap color picker)** | Floating glass capsule above the marking toolbar's label action and bottom bars, or vertical beside side rails | `circle.slash` None + red, yellow, green, blue, purple dots (`label/*`, plus extended colors when enabled) at `44 × 44` pt targets (`4 pt` padding, `3.2 pt` gap). Horizontal default (`288 × 52` pt for 6 items): None, Red…Purple left to right; vertical (`52 × 288` pt): top to bottom. The current choice carries a `2 pt` `text/primary` ring; mixed batches show no ring. Picking applies without changing the rating and closes; tapping outside dismisses. The iPad rail embeds an unglassed inline column (`showsGlass: false`). |
| **iPad rail** | iPad detail, right, 96 wide | The quick-rating ladder (43 × 174, tap or drag, fills from the bottom), a hairline, the marking family's shared Reject action (`flag.slash`), and the label picker's unglassed inline column below. No action is duplicated. It sits beside the stage and never hides. Each control has a hover tooltip (`.help`) with its VoiceOver label: a small `surface/card` pill, radius 6, 12 pt text, to the left of the control. |
| **Duo dock** | Duo expanded, right edge | A vertical column under the status bar, centered on the signal icon. Back alone (36 circle), then 41 pt wide capsules (radius 20, padding 2/4, gap 2): **view tools** (Filter, "…", Info), **bottom** (Undo, Move Rejects). Marking lives in the reserved bottom-right area beside the filmstrip, not here (#200, #227). |

| **iPad sidebar** | iPad grid, left, 280 wide | Folder name and source, then Locations (only with subfolders), Filters (Unmarked, Rejected, one ★n+ row per rating that has photos), Color labels (only labels in use) and Similar groups (one row with a regroup glyph button; a spinner while grouping). One selected row in `accent`. Counts trail each row. |
| **Split divider** | Duo expanded, photo focus | An 8 pt gutter with a hairline in `separator` and a small centered drag handle. Snap points: 30/70 and photo only. Never 50/50. |
| **Filter star row** | Grid filter menu | Five compact stars in the rating colours that fill to the chosen rating floor; tapping the current floor clears it back to All. A filter control, not a marking input: enabled-rating settings do not apply. |

## Grid

| Component | Spec |
|---|---|
| **Photo tile** | Square, aspect fill. iPhone: 3 columns of 129 with about 1.5 gaps. Duo cover: 3 columns. Duo expanded: 6 columns (143) at full width, 2 columns in photo focus. iPad: adaptive, about 6 columns. Overlays: a rating badge (bottom left, a small dark pill with "★3") and a label dot (bottom right, 8 pt, `label/*`). |
| **Rejected tile** | The same tile at `opacity/rejected`. No flag badge. |
| **Group stack** | The cover photo with 1–2 offset "cards" peeking behind it, and a count badge at the top right: a compact rounded rectangle (radius 4, padding 6/2) filled with black at 56%, with the number in white at 94% at system Medium 11 pt. The badge is a photo overlay, not a theme colour, so it looks the same in every theme and never uses `group` or another accent. No outline and no "Burst" tag. |
| **Expanded group surface** | The grid's expanded group members sit on the same neutral surface as the filmstrip's group extent: `text/primary` at 12% layer opacity on the background shape alone, radius 6 per tile (owner decision, 2026-11-13, #226 filmstrip, #227 grid). The opacity never tints photo pixels, and the current-photo ring stays the solid `text/primary` stroke. |
| **No-preview tile** | `surface/card` fill, the file extension ("CR3") in `text/secondary` semibold, and "No preview" below it. |
| **Placeholder tile** (opening) | A plain `surface/card` square, no shimmer. |
| **Selection check** | The standard iOS blue checkmark circle at the bottom right of a selected tile. Used only in select mode. |

## Detail and filmstrip

| Component | Spec |
|---|---|
| **Photo stage** | The photo is aspect fit on `bg/stage`. It is never tinted or dimmed, including when rejected. Double-tap zooms to 100%. |
| **Detail reject glyph** | A white `flag.slash.fill` in a 22 pt filled `reject` circle, inset 8 pt in the stage's top-trailing corner inside the safe area (owner decision, 2026-11-13, #227; it was an `xmark`). Shown only for rejected photos. Fixed while zooming or panning and visible with chrome hidden. Decorative and ignores taps. VoiceOver reads "Rejected" in the photo label, with no separate glyph element. |
| **Nav title and subtitle** | The filename (or folder name), with a subtitle built from counts and companion segments joined by " · ". Only folder access problems add an indicator: the `externaldrive.badge.xmark` or `lock.fill` glyph in `text/secondary` after the count, with "Not connected" or "View only" as its VoiceOver label. No save dot, Saved, Saving or loading word. |
| **Filmstrip** | Thumbnails 54 × 60 with a gap of 8. Follows grid order. **Other groups** are collapsed to one stacked thumbnail with the same count badge in its filmstrip presentation (radius 3, system Medium 9 pt on the same black 56% fill and white 94% number). The **current group** is expanded in place on a rounded rectangle (radius 9, padding 3, gap 3) filled with `text/primary` at **12% layer opacity**, with no outline. The opacity is on that background shape alone: the container and the thumbnails stay untinted. The **current frame** has a 1.5–2 pt ring in `text/primary` (radius 5), so it stays distinct from the group's extent. Rejected thumbnails are dimmed. The Reject N unmarked pill sits centred in its own row above the strip, with space clear of the capsule and swipe star bar. |
| **100% chip** | A small glass pill reading "100%", fading out after about 1 s. |
| **Info sheet** | System sheet at the medium detent, with grouped list sections Capture and File. |

## Feedback

| Component | Spec |
|---|---|
| **Progress line** | 2 pt high, full width under the toolbar. Fills in `accent` while reading and in `group` while grouping. Hidden when done. |
| **Toast** | A glass pill, 358 × 55, radius 26, padding 18/8, gap 12. Text on the left (with an optional second line in `reject`) and a button on the right (Undo or Details, a 72 × 38 capsule in `accent`). Sits above the capsule or the Move Rejects button. Auto-hides after about 6 s; Undo stays available in the top bar. **Failure toast** variant: one line, no button: "Couldn't save the mark." or "Couldn't read some marks." In detail it sits above the filmstrip. |
| **Banner** (errors) | A glass card pinned under the toolbar, with the message, then one button (Reopen or Open). The grid behind it is dimmed. |
| **Alert** | A system alert. The destructive option is red, and the safe option is bold. |
| **Pill action** (detail) | A glass capsule centred in its own row above the filmstrip: "Reject 6 unmarked" (text in `reject`). Requires both a rated or labeled visible member and an unmarked visible member. Hides with chrome, when marking is off, or when no unmarked photos remain; nothing replaces it. |
| **Move Rejects sheet** | A small detent. A fanned stack of 3–4 reject thumbnails (tap to expand into a 4-column quick grid), the title, a one-line explanation, and a full-width **Move** button in `accent`. |
| **Couldn't move sheet** | A list sheet with rows of a thumbnail, file name and reason (in `reject`), then one full-width **Done**. No Try again. |

## Entry and Settings

| Component | Spec |
|---|---|
| **Hero resume card** | Full-width rounded card (radius about 20) showing the last photo viewed. A gradient scrim at the bottom carries "Continue · Yesterday", the name, the source and "412 left", plus a 3-segment progress line (marked in `accent`, rejected in `reject`, left in `rating/off`). |
| **Recent row** | A strip of 3 small thumbnails (rounded 6), the name and source, then the count and date on the right. "Done" is in `status/saved`. The missing-drive variant is faded with a **Reconnect** chip (a small capsule, `accent` text). |
| **Open folder button** | A text-only capsule at the bottom center, 168 × 48, centred label, no folder or plus glyph (owner decision, 2026-11-13, #227). Resume uses the native bordered-prominent style; first launch fills it with `accent`. |
| **Theme tile** | A mini preview (a grid strip and a capsule) drawn in that theme's own tokens, with the name below it. The selected tile has a 2 pt `accent` ring. |
| **Settings rows** | A standard inset grouped list with toggles and value rows. |

## Icons (SF Symbols)

`chevron.left` (Back), `line.3.horizontal.decrease` (Filter), `ellipsis` ("…"), `info.circle` (Info), `arrow.uturn.backward` (Undo), `tray.and.arrow.down` (Move Rejects), `flag.slash` / `flag.slash.fill` (Reject, owner decision 2026-11-13, #227; the old `xmark` is reserved for Close/Dismiss), `star` / `star.fill`, `star.slash` (Clear rating), `circle` / `circle.fill` (Label), `circle.slash` (Clear label), `gearshape` (Settings), `checkmark.circle.fill` (Selection), `externaldrive.badge.xmark` (Disconnected).
