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
| **Mark capsule** | iPhone detail, select mode, half fold | 358 × 56, radius 28, horizontal, gap 12, padding 16, glass. Children: Reject circle (36), Rating 1–5 (five stars, gap 6, about 159 wide), Label circle (36). Floats above the home indicator. |
| **Reject circle** | Capsule, iPad rail, Duo dock | Off: a 36 pt circle with a 1.5 pt `reject` outline and a `reject` ✕ (14 pt). On: filled `reject` with a white ✕. Icon only. iPad 40, Duo 32. |
| **Stars** | Capsule | Filled stars in `rating/on`, empty in `rating/off`. Tapping the current value clears it. |
| **Label circle** | Capsule, Duo dock | A 36 pt circle filled with the current label color, or an empty outlined circle for none. Tapping opens the label picker. |
| **Label picker** | Above the capsule (iPhone); beside the dock (Duo) | A glass capsule of 6 dots: none, red, yellow, green, blue, purple (`label/*`). The current one is ringed. Picking closes it. |
| **Vertical star bar (swipe-up)** | iPhone detail on swipe up; Duo dock on slide | A narrow glass pill of 5 stars stacked vertically that **fill from the bottom** while dragging, plus a ✕ chip below it for the swipe-down reject. iPad rail version: 43 × 174, radius 22, padding 10, gap 6, tap or drag. |
| **Duo dock** | Duo expanded, right edge | A vertical column under the status bar, centered on the signal icon. Back alone (36 circle), then 41 pt wide capsules (radius 20, padding 2/4, gap 2): **view tools** (Filter, "…", Info), **marks** (★ value button 36 × 48 showing "★ 2", Reject 32, Label 36; only while a photo is open), **bottom** (Undo, Move Rejects). |
| **iPad rail** | iPad detail, right, 96 wide | The vertical star bar, a hairline, the Reject circle (40), and the label dots, top aligned with padding 18 and gap 10. |
| **Split divider** | Duo expanded, photo focus | An 8 pt gutter with a hairline in `separator` and a small centered drag handle. Snap points: 30/70 and photo only. Never 50/50. |

## Grid

| Component | Spec |
|---|---|
| **Photo tile** | Square, aspect fill. iPhone: 3 columns of 129 with about 1.5 gaps. Duo cover: 3 columns. Duo expanded: 6 columns (143) at full width, 2 columns in photo focus. iPad: adaptive, about 6 columns. Overlays: a rating badge (bottom left, a small dark pill with "★3") and a label dot (bottom right, 8 pt, `label/*`). |
| **Rejected tile** | The same tile at `opacity/rejected`. No ✕ badge. |
| **Group stack** | The cover photo with 1–2 offset "cards" peeking behind it, and a count badge at the top right: a pill (radius 8, padding 6/2) filled with `group`, white bold 11 pt number. No outline and no "Burst" tag. |
| **No-preview tile** | `surface/card` fill, the file extension ("CR3") in `text/secondary` semibold, and "No preview" below it. |
| **Placeholder tile** (opening) | A plain `surface/card` square, no shimmer. |
| **Selection check** | The standard iOS blue checkmark circle at the bottom right of a selected tile. Used only in select mode. |

## Detail and filmstrip

| Component | Spec |
|---|---|
| **Photo stage** | The photo is aspect fit on `bg/stage`. It is never tinted or dimmed, including when rejected. Double-tap zooms to 100%. |
| **Detail reject glyph** | A white `xmark` in a 22 pt filled `reject` circle, inset 8 pt in the stage's top-trailing corner inside the safe area. Shown only for rejected photos. Fixed while zooming or panning and visible with chrome hidden. Decorative and ignores taps. VoiceOver reads "Rejected" in the photo label, with no separate glyph element. |
| **Nav title and subtitle** | The filename (or folder name), with a subtitle built from counts and companion segments joined by " · ". Only folder access problems add an indicator: Not connected or View only. |
| **Filmstrip** | Thumbnails 54 × 60 with a gap of 8. Follows grid order. **Other groups** are collapsed to one stacked thumbnail with a count badge (radius 8, `group`). The **current group** is expanded in place on a rounded rectangle (radius 9, padding 3, gap 3) of `group` at **25% layer opacity**, with no outline. The **current frame** has a 1.5–2 pt ring in `text/primary` (radius 5). Rejected thumbnails are dimmed. The Reject N unmarked pill sits above the strip, attached to the expanded group, with space clear of the capsule and swipe star bar. |
| **100% chip** | A small glass pill reading "100%", fading out after about 1 s. |
| **Info sheet** | System sheet at the medium detent, with grouped list sections Capture and File. |

## Feedback

| Component | Spec |
|---|---|
| **Progress line** | 2 pt high, full width under the toolbar. Fills in `accent` while reading and in `group` while grouping. Hidden when done. |
| **Toast** | A glass pill, 358 × 55, radius 26, padding 18/8, gap 12. Text on the left (with an optional second line in `reject`) and a button on the right (Undo or Details, a 72 × 38 capsule in `accent`). Sits above the capsule or the Move Rejects button. Auto-hides after about 6 s; Undo stays available in the top bar. |
| **Banner** (errors) | A glass card pinned under the toolbar, with the message, then one button (Reopen or Open). The grid behind it is dimmed. |
| **Alert** | A system alert. The destructive option is red, and the safe option is bold. |
| **Pill action** (detail) | A glass capsule above the filmstrip, attached to its expanded group: "Reject 6 unmarked" (text in `reject`). Requires both a rated or labeled member and an unmarked member. Hides with chrome, when marking is off, or when no unmarked photos remain; nothing replaces it. |
| **Move Rejects sheet** | A small detent. A fanned stack of 3–4 reject thumbnails (tap to expand into a 4-column quick grid), the title, a one-line explanation, and a full-width **Move** button in `accent`. |
| **Couldn't move sheet** | A list sheet with rows of a thumbnail, file name and reason (in `reject`), then **Done** and **Try again**. |

## Entry and Settings

| Component | Spec |
|---|---|
| **Hero resume card** | Full-width rounded card (radius about 20) showing the last photo viewed. A gradient scrim at the bottom carries "Continue · Yesterday", the name, the source and "412 left", plus a 3-segment progress line (marked in `accent`, rejected in `reject`, left in `rating/off`). |
| **Recent row** | A strip of 3 small thumbnails (rounded 6), the name and source, then the count and date on the right. "Done" is in `status/saved`. The missing-drive variant is faded with a **Reconnect** chip (a small capsule, `accent` text). |
| **Open folder capsule** | A glass capsule at the bottom center with `folder` + "Open folder". On first launch it is a filled `accent` button. |
| **Theme tile** | A mini preview (a grid strip and a capsule) drawn in that theme's own tokens, with the name below it. The selected tile has a 2 pt `accent` ring. |
| **Settings rows** | A standard inset grouped list with toggles and value rows. |

## Icons (SF Symbols)

`chevron.left` (Back), `line.3.horizontal.decrease` (Filter), `ellipsis` ("…"), `info.circle` (Info), `arrow.uturn.backward` (Undo), `tray.and.arrow.down` (Move Rejects), `xmark` (Reject), `star` / `star.fill`, `circle` / `circle.fill` (Label), `folder` (Open folder), `gearshape` (Settings), `checkmark.circle.fill` (Selection), `externaldrive.badge.xmark` (Disconnected).
