---
name: browsing-workflow
description: Model-check Clove's complete browsing workflow with TLA+. Use when changing folder open, scan, close, reconnect, generation, Grid grouping, Detail Timeline, Group Focus, Representative selection, zoom preservation, marking, Undo, auto-advance, or location-loss behavior. Also use after merging changes to those areas without rechecking the model.
compatibility: Git repository, Python 3, Java 11+ or mise, and network access for the first TLA+ download. Optional statechart skill for readable paths and charts.
---

# Browsing workflow formal verification

Check the two-level browsing design against action sequences that Swift examples may miss. The
model covers Entry, folder opening and scanning, Grouped and Flat Grid, Detail Timeline, Group Focus,
fit and 100% inspection, marking, Undo, auto-advance, Back, Close, and Reconnect.

## Run the check

From the repository root, run:

```sh
.agents/skills/browsing-workflow/scripts/check
```

The command runs the current model and eight behavior variants. A successful run has these results:

- The current model passes every invariant with an empty TLC queue.
- Seven injected defects and one source-comparison variant fail on their named invariants.
- The final line reports `Mutation score: 8/8 expected failures caught`.

Use `--good-only` for only the current model. Use `--mutant <name>` to reproduce one counterexample.
The script prints each counterexample as an action path and stores full TLC output under
`.build/formal-verification/`. The TLA+ version, download URL, checksum, and Java selection are in
[the tool decision record](../../../docs/decisions/tla-plus-workflow-verification.md).

When `statechart` is available, read every result with it. Give it the model, configuration, and
`model/BrowsingWorkflowView.mjs`. Use the full configuration for verification and
`BrowsingWorkflowChart.cfg` for the small graph. Read each failure as its shortest user-action path.
After a failure, `statechart` can leave other rules under `Rules not checked`; do not describe those
rules as passing or failing on that variant.

A tool or parse error is not a counterexample. Fix the runner or model encoding before interpreting
results. A passing variant is a failed check because the defect did not break its expected rule.

## Compare the model with the code

Source sync commit: `29702ce651a7de77cf642b38d1898023ae775476`.

The model was compared with these functions at that commit:

| Covered file | Functions and properties |
| --- | --- |
| `Clove/Browsing/BrowsingModel.swift` | `openPickedFolderNow`, `reopenNow`, `showOpenFolder`, `leaveFolder`, `back`, `openPhoto`, `openGroup`, `selectGroupPhoto`, `collapseGroup`, `canMark`, `apply`, `undoLastMark`, `persist`, `discardDisconnectedChanges`, `apply(_ update:)`, `refresh` |
| `Clove/Browsing/FolderLibrary.swift` | `FolderLibraryUpdate`, the `FolderLibrary` generation, write, close, and reopen contracts |
| `Clove/Folder/FolderLibrarySession.swift` | `install`, `scan`, `admit`, `applyReads`, `finishScan`, `closeFolder`, `locationLost`, `record` |
| `Clove/Browsing/GridScreen.swift` | Grid `openPhoto` and `openGroup` dispatch |
| `Clove/Browsing/DetailScreen.swift` | `stepPhoto`, `openPhoto`, `selectGroupPhoto`, `expandGroup`, `collapseGroup`, `startAutoAdvance`, `schedule` |
| `Packages/CloveCore/Sources/CloveCore/GroupCulling/DetailTimeline.swift` | `representative`, `stageOrder`, `steppedPhoto`, `autoAdvancePlan`, Timeline slot and visible-member rules |
| `Clove/Detail/DetailMarkingView.swift` | `isReadOnlyCollapsedGroup`, `allowsMarkingInput`, `apply`, `loadPreview`, `refreshPrefetchForOrderChange`, zoom capture and restoration |
| `Clove/Detail/DetailFilmstrip.swift` | Timeline and Group Focus dispatch to open, select, expand, and collapse |
| `Clove/Detail/MarkAutoAdvance.swift` | `schedule` and `cancel` |
| `design/handoff/interactions.md` | App flow, Groups in detail, Opening a folder, and Errors |

Before trusting a run after a source change, compare the covered files with the sync commit:

```sh
git diff 29702ce651a7de77cf642b38d1898023ae775476 -- \
  Clove/Browsing/BrowsingModel.swift \
  Clove/Browsing/FolderLibrary.swift \
  Clove/Folder/FolderLibrarySession.swift \
  Clove/Browsing/GridScreen.swift \
  Clove/Browsing/DetailScreen.swift \
  Packages/CloveCore/Sources/CloveCore/GroupCulling/DetailTimeline.swift \
  Clove/Detail/DetailMarkingView.swift \
  Clove/Detail/DetailFilmstrip.swift \
  Clove/Detail/MarkAutoAdvance.swift \
  design/handoff/interactions.md
```

If this diff changes the workflow, update the model and its mutations before treating a pass as
evidence. Move the sync commit forward only after comparing every covered function at the new
commit. Use the `maintain-formal-verification-skill` method for that maintenance pass.

## Interpret the source-comparison finding

`representative-collapse-keeps-zoom` mirrors the current `DetailMarkingView` path, not an injected
hypothetical defect. `collapseGroup()` snaps to the Representative. When the current photo already
is that Representative, `photo.id` and `loadPreview` do not change.
`refreshPrefetchForOrderChange` then keeps scale and anchor. This breaks the requested rule that
leaving Group Focus returns to fit. The shortest model path is:

```text
OpenFolder -> ScanFinish -> OpenBurst -> Inspect100 -> CollapseGroup
```

The default model encodes the requested fit-on-collapse contract and passes. Its pass does not clear
this source finding. The finding is a static code comparison at the sync commit; Linux did not run
the iOS view. Do not change product code from this skill alone. Report the path and let the product
change owner resolve the contract. See [the finding record](references/findings.md).

## Know the bounds

The current model uses these limits and assumptions:

- Two folders each contain one two-photo burst and one standalone photo. Group membership and
  visibility do not change.
- A mark is unmarked, rated, or rejected. Representative selection covers rated, then unmarked, then
  first visible. Star levels and labels are outside the model.
- TLC explores all enabled action orders through depth 12. Deadlock checking is off because the
  depth bound creates terminal states. This is a bounded safety check, not liveness or a proof at
  every folder size.
- Scan completion is atomic. The model does not open photos from partial scan batches or refine
  groups over time.
- Auto-advance uses the default `nextPhoto` destination and an explicit fire action. The 300 ms
  timer, `stay`, `nextUnmarkedPhoto`, and `Reject N unmarked` finishing are outside the model.
- One latest Undo is modeled. Pending writes coalesce per photo. FIFO ordering across different
  photos, write failures other than location loss, and storage retries are outside the model.
  Open and Reconnect retain abstract old completion events to stress the generation guard, even
  though the implementation drains admitted writes. This over-approximates possible schedules.
  Location loss blocks new result publication; an operation already touching a file is outside
  the model.
- Zoom has only fit and 100%, with centre and eye anchors. Pinch values, native-scale conversion,
  pan geometry, RAW rendering, Vision, focus analysis, and UIKit layout are outside the model.
- Filters, one-visible-member groups, several bursts per folder, selection, batch marks, Move
  Rejects, rename, Settings navigation, and device posture changes are outside the model.

The model does not execute Swift. Existing CloveCore, app, and UI tests remain necessary.

## Maintain the verification

Map each atomic model action to one synchronous `@MainActor` transition or one pure CloveCore rule.
Keep rendering and layout out of the top-level model. Keep the full and chart configurations'
invariant lists in sync. When behavior changes, update the model, add a variant that breaks the
changed rule, and run the complete script. Do not weaken an invariant to make a source defect pass.
Record a real defect as a source-comparison variant and report it without changing product code
unless the task authorizes a fix.
