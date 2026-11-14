# #237 Duo filmstrip evidence (2026-11-14)

Captured on real iPhone Duo hardware emulation (Closed/cover pose, headless) from the
sample library: no owner photos. `before-*` builds are `main` at `f0f8d66` with the fix
stashed; `after-*` builds are the task branch.

- `before/after-filmstrip-end-{light,dark}.png` — the detail filmstrip dragged to the
  folder's last photo, on the cover display. The strip is the same layout code as the
  expanded photo-only strip; on the cover no marking toolbar sits beside it, so these
  document the settled end geometry and the Light/Dark rendering, not the 200 pt
  content-side reservation that only exists beside the expanded photo-only toolbar.
- `after-strip-after-group-exit.png`, `after-strip-after-navigation-exit.png` — the strip
  immediately after leaving the current group, by filmstrip tap and by edge navigation:
  the stack and the current thumbnail are on screen, not blank.
- `after-strip-last-photo.png` — the strip after the far jump to the folder's last photo.

## Limit

The expanded Duo **photo-only** strip beside the marking toolbar — the layout with the
reported 200 pt double reservation and the reported blank strip — has **no headless
runner**: the Open pose exists only as a Device Hub control on an unlocked GUI session
(`docs/duo-simulator.md`), and this Mac's session is locked. The geometry is covered by
content-level assertions in `testDuoGridFocusDockMarkAndPhotoOnly`, which run only on an
unlocked Duo in the Open pose; the owner's TestFlight re-check is final.
