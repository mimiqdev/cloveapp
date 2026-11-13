# Clove theme tokens

Exported from the Figma variable collection **Clove Theme** ([board](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=181-2391), [live demo](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=215-1878)). The machine-readable version is `clove-themes.json`. Colors are `#RRGGBB` or `#RRGGBBAA`, with alpha last.

Rules:
- Photos are never tinted by a theme. Only the chrome changes.
- Light and Dark follow the system when "Match system light/dark" is on. Otherwise, the chosen theme applies.
- Light-appearance themes are Light and Catppuccin Latte. All others are dark appearance, so they use the dark status bar and dark keyboard.
- If the design uses a token with extra transparency (the filmstrip group surface at 12%), apply the opacity on the layer, not to the token.
- The group count badge is a photo overlay, not a token: black at 56% with the number in white at 94%, the same in every theme (owner decision, 2026-11-13, #226).

| Token | Use | Light | Dark | Darkroom | Night | Catppuccin Latte | Catppuccin Mocha | Nord | Gruvbox |
|---|---|---|---|---|---|---|---|---|---|
| `bg/canvas` | App background behind lists, grids and chrome. | #FFFFFF | #000000 | #1E1E1E | #0C0908 | #EFF1F5 | #1E1E2E | #2E3440 | #282828 |
| `bg/stage` | Area around a photo in detail / zoom. Never tints the photo. | #E6E6EB | #000000 | #474747 | #000000 | #DCE0E8 | #11111B | #242933 | #1D2021 |
| `surface/glass` | Floating glass controls (capsule, dock, toasts, banners). Pair with a background blur of about 36 pt. | #FFFFFFCC | #1E1E20B8 | #2E2E2ED1 | #1C1614D9 | #EFF1F5CC | #313244D9 | #3B4252D9 | #3C3836D9 |
| `surface/sheet` | Sheets, menus, grouped-list background. | #F2F2F7 | #1C1C1E | #262626 | #141010 | #E6E9EF | #181825 | #2E3440 | #282828 |
| `surface/card` | Cells / cards on a sheet. | #FFFFFF | #2C2C2E | #333333 | #1E1816 | #EFF1F5 | #313244 | #3B4252 | #3C3836 |
| `text/primary` | Primary text and icons. | #000000 | #FFFFFF | #EDEDED | #E6C9B8 | #4C4F69 | #CDD6F4 | #ECEFF4 | #EBDBB2 |
| `text/secondary` | Secondary text, counts, metadata. | #3C3C4399 | #EBEBF599 | #BDBDBD | #9C8576 | #6C6F85 | #A6ADC8 | #D8DEE999 | #A89984 |
| `separator` | Hairlines and tracks. | #3C3C431F | #FFFFFF1F | #FFFFFF1A | #E6C9B81A | #4C4F691F | #CDD6F41A | #ECEFF41A | #EBDBB21A |
| `accent` | Buttons, links, selection, progress while reading. Light and Dark use the owner's warm pair (2026-11-13, #227); the other six themes keep their accents. | #8A6548 | #D4AA78 | #8AB4F8 | #E0A15E | #8839EF | #CBA6F7 | #88C0D0 | #83A598 |
| `rating/on` | Filled stars. | #FF9500 | #FF9F0A | #E8A33D | #E0A15E | #DF8E1D | #F9E2AF | #EBCB8B | #FABD2F |
| `rating/off` | Empty stars. | #3C3C434D | #EBEBF54D | #FFFFFF40 | #E6C9B838 | #4C4F6940 | #CDD6F438 | #D8DEE940 | #EBDBB238 |
| `reject` | Reject circle, destructive text. Softer than the system red on purpose. | #D4574E | #E5675E | #C7665F | #C8665A | #E64553 | #EBA0AC | #BF616A | #EA6962 |
| `status/saved` | Saved dot, toggles on. | #34C759 | #30D158 | #4CB86A | #8FA36A | #40A02B | #A6E3A1 | #A3BE8C | #B8BB26 |
| `status/failed` | Save or move failures. | #D4574E | #E5675E | #C7665F | #C8665A | #E64553 | #EBA0AC | #BF616A | #EA6962 |
| `label/red` | Color label red (XMP 'Red'). | #FF3B30 | #FF453A | #E5534B | #B85A4E | #D20F39 | #F38BA8 | #BF616A | #FB4934 |
| `label/yellow` | Color label yellow. | #FFCC00 | #FFD60A | #E0C04A | #C9A24A | #DF8E1D | #F9E2AF | #EBCB8B | #FABD2F |
| `label/green` | Color label green. | #34C759 | #30D158 | #4CB86A | #7F9A5A | #40A02B | #A6E3A1 | #A3BE8C | #B8BB26 |
| `label/blue` | Color label blue. | #007AFF | #0A84FF | #5A8FD8 | #6F86A8 | #1E66F5 | #89B4FA | #81A1C1 | #83A598 |
| `label/purple` | Color label purple. | #AF52DE | #BF5AF2 | #A374C9 | #9A7AA8 | #8839EF | #CBA6F7 | #B48EAD | #D3869B |
| `group` | Similar groups: the progress line while grouping. The count badges and the expanded filmstrip background no longer use it (owner decision, 2026-11-13, #226). | #007AFF | #0A84FF | #8AB4F8 | #E0A15E | #8839EF | #CBA6F7 | #88C0D0 | #83A598 |
| `opacity/rejected` | Opacity of a rejected photo in the grid and strips. | 0.28 | 0.3 | 0.35 | 0.3 | 0.28 | 0.3 | 0.3 | 0.3 |

Swift names (as set in Figma code syntax): `Color.clove.<group>.<name>`, for example `Color.clove.bg.canvas` and `Color.clove.rating.on`. `opacity/rejected` is a number, not a color.
