# Clove theme tokens

Exported from the Figma variable collections **Clove Theme** and **Clove · Light companions** ([board](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=181-2391), [live demo](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=215-1878)). The machine-readable version is `clove-themes.json`. Colors are `#RRGGBB` or `#RRGGBBAA`, with alpha last.

Rules:
- Photos are never tinted by a theme. Only the chrome changes.
- Three-way appearance mode (`Light`, `Dark`, `System`) is independent of the six paired theme families (`Default`, `Catppuccin`, `Darkroom`, `Night`, `Nord`, `Gruvbox`). `System` follows the actual device appearance within the selected family without falling back to `Default`; explicit `Light` and `Dark` force that palette's appearance regardless of device appearance.
- Six families resolve to twelve palettes: light-appearance palettes are `Light`, `Catppuccin Latte`, `Darkroom Light`, `Night Light`, `Nord Light`, `Gruvbox Light`; dark-appearance palettes are `Dark`, `Catppuccin Mocha`, `Darkroom`, `Night`, `Nord`, `Gruvbox`. Darkroom Light, Night Light, Nord Light, and Gruvbox Light are Clove-designed light companions, not official upstream variants.
- If the design uses a token with extra transparency (the expanded group surface at 12% in the filmstrip and the grid), apply the opacity on the layer, not to the token.
- The group count badge is a photo overlay, not a token: black at 56% with the number in white at 94%, the same in every theme (owner decision, 2026-11-13, #226).

| Token | Use | Light | Dark | Catppuccin Latte | Catppuccin Mocha | Darkroom Light | Darkroom | Night Light | Night | Nord Light | Nord | Gruvbox Light | Gruvbox |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `bg/canvas` | App background behind lists, grids and chrome. | #FFFFFF | #000000 | #EFF1F5 | #1E1E2E | #F3F3F3 | #1E1E1E | #F7F0E8 | #0C0908 | #ECEFF4 | #2E3440 | #FBF1C7 | #282828 |
| `bg/stage` | Area around a photo in detail / zoom. Never tints the photo. | #E6E6EB | #000000 | #DCE0E8 | #11111B | #D3D3D3 | #474747 | #E6DBD0 | #000000 | #D8DEE9 | #242933 | #EBDBB2 | #1D2021 |
| `surface/glass` | Floating glass controls (capsule, dock, toasts, banners). Pair with a background blur of about 36 pt. | #FFFFFFCC | #1E1E20B8 | #EFF1F5CC | #313244D9 | #FAFAFACC | #2E2E2ED1 | #FFFAF5CC | #1C1614D9 | #F8FAFCCC | #3B4252D9 | #F9F5D7CC | #3C3836D9 |
| `surface/sheet` | Sheets, menus, grouped-list background. | #F2F2F7 | #1C1C1E | #E6E9EF | #181825 | #E9E9E9 | #262626 | #EFE5DB | #141010 | #E5E9F0 | #2E3440 | #F2E5BC | #282828 |
| `surface/card` | Cells / cards on a sheet. | #FFFFFF | #2C2C2E | #EFF1F5 | #313244 | #FAFAFA | #333333 | #FFFAF5 | #1E1816 | #F8FAFC | #3B4252 | #F9F5D7 | #3C3836 |
| `text/primary` | Primary text and icons. | #000000 | #FFFFFF | #4C4F69 | #CDD6F4 | #222222 | #EDEDED | #3B2B23 | #E6C9B8 | #2E3440 | #ECEFF4 | #3C3836 | #EBDBB2 |
| `text/secondary` | Secondary text, counts, metadata. | #3C3C4399 | #EBEBF599 | #6C6F85 | #A6ADC8 | #666666 | #BDBDBD | #7C6254 | #9C8576 | #4C566A | #D8DEE999 | #665C54 | #A89984 |
| `separator` | Hairlines and tracks. | #3C3C431F | #FFFFFF1F | #4C4F691F | #CDD6F41A | #2222221F | #FFFFFF1A | #3B2B231F | #E6C9B81A | #2E34401F | #ECEFF41A | #3C38361F | #EBDBB21A |
| `accent` | Buttons, links, selection, progress while reading. Light and Dark use the owner's warm pair (2026-11-13, #227). | #8A6548 | #D4AA78 | #8839EF | #CBA6F7 | #536579 | #8AB4F8 | #8A5123 | #E0A15E | #3B7080 | #88C0D0 | #356748 | #83A598 |
| `rating/on` | Filled stars. | #FF9500 | #FF9F0A | #DF8E1D | #F9E2AF | #98671F | #E8A33D | #AA690A | #E0A15E | #9C722C | #EBCB8B | #B57614 | #FABD2F |
| `rating/off` | Empty stars. | #3C3C434D | #EBEBF54D | #4C4F6940 | #CDD6F438 | #22222240 | #FFFFFF40 | #3B2B2340 | #E6C9B838 | #2E344040 | #D8DEE940 | #3C383640 | #EBDBB238 |
| `reject` | Reject circle, destructive text. Softer than the system red on purpose. | #D4574E | #E5675E | #E64553 | #EBA0AC | #A74640 | #C7665F | #AE4B3E | #C8665A | #9B4852 | #BF616A | #9D0006 | #EA6962 |
| `status/saved` | Saved dot, toggles on. | #34C759 | #30D158 | #40A02B | #A6E3A1 | #41684B | #4CB86A | #596E36 | #8FA36A | #526D40 | #A3BE8C | #79740E | #B8BB26 |
| `status/failed` | Save or move failures. | #D4574E | #E5675E | #E64553 | #EBA0AC | #A74640 | #C7665F | #AE4B3E | #C8665A | #9B4852 | #BF616A | #9D0006 | #EA6962 |
| `label/red` | Color label red (XMP 'Red'). | #FF3B30 | #FF453A | #D20F39 | #F38BA8 | #B6423B | #E5534B | #A43D32 | #B85A4E | #9B4852 | #BF616A | #9D0006 | #FB4934 |
| `label/yellow` | Color label yellow. | #FFCC00 | #FFD60A | #DF8E1D | #F9E2AF | #9C781B | #E0C04A | #9A6B0E | #C9A24A | #9C722C | #EBCB8B | #B57614 | #FABD2F |
| `label/green` | Color label green. | #34C759 | #30D158 | #40A02B | #A6E3A1 | #41684B | #4CB86A | #526D36 | #7F9A5A | #526D40 | #A3BE8C | #79740E | #B8BB26 |
| `label/blue` | Color label blue. | #007AFF | #0A84FF | #1E66F5 | #89B4FA | #486B99 | #5A8FD8 | #485F7D | #6F86A8 | #486B8D | #81A1C1 | #076678 | #83A598 |
| `label/purple` | Color label purple. | #AF52DE | #BF5AF2 | #8839EF | #CBA6F7 | #77578F | #A374C9 | #70557F | #9A7AA8 | #795374 | #B48EAD | #8F3F71 | #D3869B |
| `group` | Similar groups: the progress line while grouping. The count badges and the expanded group backgrounds no longer use it (owner decisions, 2026-11-13, #226 and #227). | #007AFF | #0A84FF | #8839EF | #CBA6F7 | #536579 | #8AB4F8 | #8A5123 | #E0A15E | #3B7080 | #88C0D0 | #356748 | #83A598 |
| `focus/outline` | Camera-style focus overlay normal outline (1.25 pt white, invariant over photos; selected inspection uses `accent` at 1.5 pt). | #FFFFFF | #FFFFFF | #FFFFFF | #FFFFFF | #FFFFFF | #FFFFFF | #FFFFFF | #FFFFFF | #FFFFFF | #FFFFFF | #FFFFFF | #FFFFFF |
| `focus/edge` | Subtle dark contrast edge behind camera-style focus overlay outlines. | #00000073 | #00000073 | #00000073 | #00000073 | #00000073 | #00000073 | #00000073 | #00000073 | #00000073 | #00000073 | #00000073 | #00000073 |
| `opacity/rejected` | Opacity of a rejected photo in the grid and strips. | 0.28 | 0.3 | 0.28 | 0.3 | 0.28 | 0.35 | 0.28 | 0.3 | 0.28 | 0.3 | 0.28 | 0.3 |

Swift names (as set in Figma code syntax): `Color.clove.<group>.<name>`, for example `Color.clove.bg.canvas` and `Color.clove.rating.on`. `opacity/rejected` is a number, not a color.
