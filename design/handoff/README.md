# Clove MVP: design handoff

This package is everything an implementation session needs to build the Clove MVP UI from the reviewed Figma design. It contains no code. It describes what to build and points at the exact Figma frames. For UI work it takes precedence over the screen descriptions in `docs/PRD.en.md`.

**Figma file:** [Clove — Native concept](https://www.figma.com/design/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept), page **"Clove · MVP design"**. The page "Archive · original concept" holds superseded work. **Do not build from the Archive page.** The frames were last synced to the app on 12 Nov 2026 (main at `7470617`); the 10 Nov versions of changed frames are on the Archive page under "Superseded · 10 Nov handoff". The iPad frames are provisional until #152 and #163 land.

**Prototype:** the page "Prototype · iPhone" holds copies of the Light iPhone frames wired for clicking: open the [iPhone prototype](https://www.figma.com/proto/xJcgQ7FziNyPM7UToZvkmq/Clove-%E2%80%94-Native-concept?node-id=248-2165&starting-point-node-id=248-2165) (flow "iPhone · Open a folder and cull"). It covers Entry, the grid with its menus and Select mode, detail (swipe star bar, 100% zoom, Reject, Label, Info), a stack in detail, Move Rejects with the quick grid and the Undo toast, and Settings. Transitions are placeholders, not the motion design. The copies don't follow edits to the MVP page; recopy them after a change.

## What's in here

| File | What it is | Read it when |
|---|---|---|
| `screens.md` | Every screen and state per device, with Figma links and behavior notes. **The main spec.** | Building any screen. |
| `screens/` | A 1x PNG of each of the 51 frames, Light and Dark side by side. | Seeing what a state looks like without Figma. |
| `frames.json` | The same frame list in machine-readable form (section, name, node id, URL, device, screenshot path). | Scripting Figma MCP calls or splitting work across agents. |
| `tokens/clove-themes.json` | All 21 tokens × 8 themes as hex, with the Swift names and usage notes. | Generating the color assets or the `Color.clove` theme struct. |
| `tokens/tokens.md` | The same tokens as a readable table, plus the theming rules. | Checking a color by eye. |
| `components.md` | The reusable component inventory with sizes and token usage. | Building shared views before screens. |
| `interactions.md` | Gestures, flows, state machines (Duo split), opening and error behavior. | Wiring navigation and gestures. |
| `copy.md` | All UI strings with suggested localization keys. | Building `Localizable.xcstrings`. |
| `decisions-log.md` | The design review history, in order. Later sections override earlier ones. | Understanding *why*, or resolving a conflict. |

If two sources disagree, the order of trust is: the **Figma frame** for layout and visuals, then **`screens.md` / `interactions.md`** for behavior, then `decisions-log.md` (history; early entries were superseded, for example the first Duo expanded layout). The PRD is a guide, not the source of truth. Where the design differs from the PRD, follow the design.

## How to use the Figma frames

`screens/` has a 1x PNG of every frame (Light and Dark side by side), linked from each state in `screens.md`, so the spec works without Figma access. For exact spacing, token bindings or a higher resolution, use the Figma MCP server with the links:
- `get_screenshot` (fileKey `xJcgQ7FziNyPM7UToZvkmq`, nodeId from `frames.json`) to see a state.
- `get_design_context` for layout, spacing and token bindings. Treat its output as a reference to adapt, not code to paste.
- `get_variable_defs` on a frame to see the bound `Clove Theme` variables.

Things to know about the frames:
- **Each frame holds the Light and Dark versions side by side.** Build one view; the theme does the rest.
- Device bezels, iOS status bars and home indicators are drawn for context. Use the system ones.
- Some frames still carry **hidden legacy layers** named "… · local (hidden)", "… · source …", "Segmented" or "Toolbar". Ignore anything that isn't visible in the screenshot.
- Sample photos are placeholders.
- A few one-off greys and the badges drawn on photos are not bound to tokens. Map them to the nearest token.

## Design principles (apply to anything not specified)

1. **Each device gets the layout that suits it.** Device fit beats cross-device consistency (iPhone capsule, iPad rail, Duo dock).
2. **Less is more.** Show a control only when it's needed, with no always-on bars. Move Rejects appears only when there are rejects.
3. **Let the layout tell.** Encode state in the image and layout (stacks, dimming, position, the filmstrip as progress) before adding labels or badges. Rejected photos are dimmed without badges in the grid, filmstrip and Move Rejects quick grid. Detail shows them at full brightness with a corner reject glyph.
4. **Photos are never tinted.** Themes change only the chrome.
5. **Nothing is destructive.** Reject never deletes; Move Rejects always confirms first and can be undone.

## Scope

**In the MVP:** Entry (resume first, first launch), grid (filter, select, opening, "…" menu), detail (all states, including groups expanded in the filmstrip), Move Rejects (confirm, quick grid, results), iPad grid and detail, Duo cover and expanded (grid, 30/70, photo only, dock pickers), Duo half fold (quick refresh), Settings, error states, and 8 themes.

**Not in the MVP:** a dedicated Duo half-fold layout (1.1), metadata editing in Info, and the Archive explorations (Entry B and C, the old ladders and toolbars).

**Not designed, so decide or ask:** the empty-folder state, the keyboard shortcut list, and accessibility labels beyond `copy.md`. Items tagged **(proposed)** in `interactions.md` and `components.md` are sensible defaults that were not reviewed.

## A suggested build order

1. The theme tokens and the glass style (`tokens/`, `components.md` → Shared glass style).
2. The shared controls: the glass icon button, mark capsule, reject circle, stars, label picker and vertical star bar.
3. The iPhone grid and detail with groups expanded in the filmstrip, then Move Rejects.
4. Entry, Settings and the error states.
5. The iPad layouts, then Duo cover and expanded (the dock and the split state machine), then the half-fold refresh.
