# Clove app icon: Split print

One instant print, split on the diagonal: the kept half bright, the rejected half dimmed (30%), the way Clove dims rejects. "Clove" read as "cleave"; the warm amber nods to the spice.

## Files
- `preview.png`: default, dark and tinted at 220 / 120 / 60 / 40 / 29 pt.
- `xcode/`: 1024 px PNGs for the Xcode asset catalog (no alpha): `AppIcon.png` (default), `AppIcon-Dark.png`, `AppIcon-Tinted.png` (grayscale).
- `svg/`: full-bleed masters for each appearance (the system applies the rounded mask).
- `layers/`: transparent SVG + PNG layers for Icon Composer, back to front: print, photo window, kept half, rejected half. Set the rejected half to 30% opacity and put the background fill in Icon Composer.

## Colors
| | Background (top → bottom) | Print | Photo window | Photo halves |
|---|---|---|---|---|
| Default | #E8953A → #D27A26 | #FFFFFF | #2A1D15 | #D9822B |
| Dark | #241B16 → #0C0908 | #EFE4D8 | #1A1310 | #F0A24E |
| Tinted | #000000 | #F2F2F2 | #1C1C1C | #C8C8C8 |

Geometry (100-unit grid, the print group rotated −6° about the center): print 63×76 at (18.5, 11.5), r 2.5; window 53×53 at (23.5, 16.5); kept half (28,21)(69,21)(28,62); rejected half (72,24)(72,65)(31,65); both halves with a 3-unit round join.
