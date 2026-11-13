# Duo inline group expansion: visible evidence (#225)

Generated from the in-memory sample library on the Air worker, never from owner
photos, on the merge of `main` at `7b590cd` (#227 marking toolbar, #229 pickers,
#233 toolbar geometry). Each file is one whole launch's screen, Light and Dark.

| File | What it shows | Device |
| --- | --- | --- |
| `grid-groups-light.png`, `grid-groups-dark.png` | The folder grid with groups expanded in place: the shared neutral group surface behind each member, the invariant count badge and the current ring | iPhone 17 Pro simulator |
| `grid-stacks-light.png`, `grid-stacks-dark.png` | The folder grid with groups stacked, count badges and the selected stack | iPhone 17 Pro simulator |
| `filmstrip-expanded-light.png`, `filmstrip-expanded-dark.png` | Detail with the photo's group expanded in the folder-order filmstrip: the neutral `text/primary` 12% surface, the count badge and the current-frame ring, above the compact marking toolbar | iPhone 17 Pro simulator |
| `duo-cover-grid-light.png` | The Duo's cover grid and dock, a real Duo device check of the shared grid | iPhone Duo simulator, Closed pose |

The split's group run uses the same neutral surface as `grid-groups-*`, plus the
header with the member count and the fold chevron.

## Missing: the expanded Duo split

The expanded Duo (the Open pose) has no headless runner. The pose exists only
as Xcode's Device Hub control, and this machine's GUI session is locked
(`scripts/duo-pose.sh --check-access`), so the 30/70 split's group run — its
header, surface and fold chevron — has no screenshot here. The behaviour is
asserted by `CloveFlowTests.testDuoExpandedGroupMembersBrowseBesideThePhoto`,
which skips until it runs on an unlocked Duo in the Open pose. The arrangement
behind it is covered by `GridSectionTests` in `CloveCore`.
