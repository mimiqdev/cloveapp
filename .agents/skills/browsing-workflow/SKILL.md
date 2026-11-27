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

The command checks source drift, runs the current model, and runs 52 model variants. A
successful run has these results:

- Covered source matches the reviewed sync commit.
- The current model passes every invariant with an empty TLC queue.
- All 52 model mutations fail on their named invariants.
- The mutation summary reports `Mutation score: 52/52 expected failures caught`.
- All 24 `Next` actions execute in full-depth reachability queries; 56 queries cover selected request
  and pre-state branches. The manifest must agree with `Next`, configured properties, and mutants.
- The separate reachability query finds the Rated-confirmed, Reject-pending, location-loss rollback
  state. Its intentionally failing predicate is a witness, not a failed safety invariant.

Use `--good-only` for only the current model. Use `--mutant <name>` to reproduce one counterexample.
Use `--witness-only` for the rollback reachability query. Use `--actions-only` for the 56 action
queries and regenerated coverage table. All modes enforce source drift.
The script prints each counterexample as an action path and stores full TLC output under
`.build/formal-verification/`. The TLA+ version, download URL, checksum, and Java selection are in
[the tool decision record](../../../docs/decisions/tla-plus-workflow-verification.md).

The normal command starts with a source-drift gate. `model/source-sync.json` records the reviewed
commit, the pure state-machine files tracked whole-file, and the exact modeled Swift declarations
tracked inside mixed files. If any whole-file target or tracked declaration differs from that
commit—or if a tracked declaration is missing, renamed, or ambiguous—the command exits 1 before
starting TLC and requires a maintenance review. This is Git drift detection, not semantic proof.
Review the changed source and update the model as needed before advancing the sync commit. Do not
advance the commit merely to bypass the gate.

When `statechart` is available, read every result with it. Give it the model, configuration, and
`model/BrowsingWorkflowView.mjs`. Use the full configuration for verification and
`BrowsingWorkflowChart.cfg` for the small graph. Read each failure as its shortest user-action path.
After a failure, `statechart` can leave other rules under `Rules not checked`; do not describe those
rules as passing or failing on that variant.

A tool or parse error is not a counterexample. Fix the runner or model encoding before interpreting
results. A passing variant is a failed check because the defect did not break its expected rule.

## Compare the model with the code

Source sync commit: `f4f6c34920365785882ed0895fcc5a2869709616`. The machine-readable copy,
whole-file list, and symbol-scoped declaration list used by the drift gate live in
`model/source-sync.json`.

Four pure state-machine files are tracked whole-file, and five mixed Swift files are tracked by
exact declaration tokens (`Scope :: member` when scoped inside a type, protocol, or extension),
active `#if`/`#elseif`/`#else`/`#endif` directive stack, and brace-matched body (preserving
string interpolation boundaries and operator runs, stripping Swift comments and whitespace-only
formatting differences outside string literals, and failing closed on missing, renamed, or
ambiguous symbols):

| Tracked file | Mode | Covered declarations / scope |
| --- | --- | --- |
| `Packages/CloveCore/Sources/CloveCore/GroupCulling/DetailTimeline.swift` | Whole file | `representative`, `stageOrder`, `steppedPhoto`, `autoAdvancePlan`, Timeline slot and visible-member rules |
| `Clove/Detail/MarkAutoAdvance.swift` | Whole file | `schedule` and `cancel` |
| `Packages/CloveCore/Sources/CloveCore/Marking/DesiredPhotoMarks.swift` | Whole file | `apply`, `shown`, `finish`, `removeAll`, and `DesiredMarkRestore.change` |
| `Packages/CloveCore/Sources/CloveCore/Marking/PhotoActionPipeline.swift` | Whole file | `submit`, `beginNext`, `hasPendingMark`, `removePending`, and `finish` |
| `Clove/Browsing/BrowsingModel.swift` | Symbol-scoped (40) | `openGeneration`, `init`, `hasFinishedScan`, `isScanning`, `openFolder`, `openPickedFolder`, `openPickedFolderNow`, `reopen`, `reopenNow`, `reopenOpenFolder`, `openPhoto`, `openGroup`, `selectGroupPhoto`, `collapseGroup`, `setSimilarGroupsEnabled`, `back`, `shownMarks`, `canMark`, `apply(_ change:to:)`, `canUndoMark`, `undoLastMark`, `request`, `requestBatch`, `stageMark`, `applyShownMarks`, `recordUndo`, `submit`, `drainActions`, `consumeActions`, `finishPendingMarks`, `persist`, `discardDisconnectedChanges`, `leaveFolder`, `showEntryAfterLeaving`, `apply(_ update:)`, `showOpenFolder`, `applyReads`, `refresh`, `reconcileRemovedPhotos`, `reconcileExpandedGroup` |
| `Clove/Browsing/FolderLibrary.swift` | Symbol-scoped (25) | `FolderLibraryUpdate`, 14 `protocol FolderLibrary` requirements (`folder`, `photos`, `groups`, `updates`, `openGeneration`, `pick`, `reopen`, `openSavedFolder`, `rereadMarks`, `drainWrites`, `discardPendingChanges`, `closeFolder`, `apply`, `setSimilarGroupsEnabled`), and 10 `extension FolderLibrary` defaults (`openGeneration`, `pick`, `reopen`, `openSavedFolder`, `rereadMarks`, `drainWrites`, `discardPendingChanges`, `closeFolder`, `apply`, `setSimilarGroupsEnabled`) |
| `Clove/Folder/FolderLibrarySession.swift` | Symbol-scoped (28) | `photos`, `groups`, `openGeneration`, `drainWrites`, `discardPendingChanges`, `closeFolder`, `uninstallFolder`, `apply`, `rereadMarks`, `pick`, `reopen`, `openSavedFolder`, `open`, `install`, `endOpenFolder`, `scan`, `admit`, `applyReads`, `finishScan`, `failedScan`, `locationLost`, `record`, `applyConfirmedProgressChange`, `makeGrouping`, `startGrouping`, `publishGroups`, `setSimilarGroupsEnabled`, `publish` |
| `Clove/Browsing/DetailScreen.swift` | Symbol-scoped (14) | `groupsEnabled`, `timeline`, `activeExpandedGroup`, `actions`, `stepPhoto`, `openPhoto`, `selectGroupPhoto`, `expandGroup`, `collapseGroup`, `performUndo`, `performBackToGrid`, `startAutoAdvance`, `schedule`, `rules` |
| `Clove/Detail/DetailMarkingView.swift` | Symbol-scoped (27) | `currentTimelineGroup`, `captureZoomForPresentationTransition`, `loadPreview`, `refreshPrefetchForOrderChange`, `show`, `openingScale`, `nativeFullResolutionScale`, `renderFitAndPrefetch`, `zoomChanged`, `isAtFullResolution`, `doubleTap`, `focusRegionTapped`, `inspectFullResolution`, `retargetFullResolution`, `setZoom`, `beginToolbarMarking`, `beginMarkingGesture`, `undo`, `backToGrid`, `markKey`, `rate`, `choose`, `toggleReject`, `applyMarkingSwipe`, `apply(_ result:)`, `@MainActor static func apply(...)`, `rules` |

Two pure stateless UI dispatch shells are intentionally excluded from `model/source-sync.json`
because they own zero workflow state-machine rules (`GridScreen.swift` dispatches `openPhoto` /
`openGroup` to `BrowsingModel`, and `DetailFilmstrip.swift` dispatches Timeline/Group Focus closures
from `DetailScreen` / `DetailMarkingView`). Their tap and gesture wiring is verified by hosted and
UI tests (`CloveTests` / `CloveUITests`).

Before trusting a run after a source change, compare the tracked files against the sync commit and
run the drift gate:

```sh
git diff f4f6c34920365785882ed0895fcc5a2869709616 -- \
  Packages/CloveCore/Sources/CloveCore/GroupCulling/DetailTimeline.swift \
  Clove/Detail/MarkAutoAdvance.swift \
  Packages/CloveCore/Sources/CloveCore/Marking/DesiredPhotoMarks.swift \
  Packages/CloveCore/Sources/CloveCore/Marking/PhotoActionPipeline.swift \
  Clove/Browsing/BrowsingModel.swift \
  Clove/Browsing/FolderLibrary.swift \
  Clove/Folder/FolderLibrarySession.swift \
  Clove/Browsing/DetailScreen.swift \
  Clove/Detail/DetailMarkingView.swift
```

If this diff changes the workflow, update the model and its mutations before treating a pass as
evidence. Move the sync commit forward only after comparing every covered function at the new
commit. Use the `maintain-formal-verification-skill` method for that maintenance pass.

## Read the collapse contract

Owner-approved #304 has an explicit exception to fit-on-collapse. When `collapseGroup()` leaves the
same Representative on stage, Detail keeps scale and anchor. When collapse changes the displayed
photo to the Representative, Detail returns to fit. The current source implements that rule; it is
not a source defect.

`CollapseZoomFollowsRepresentative` checks both branches. Two mutations prove sensitivity:

```text
Changed photo incorrectly keeps zoom:
OpenFolder -> ScanFinish -> OpenBurst -> StepGroup -> Inspect100 -> CollapseGroup

Unchanged Representative incorrectly resets zoom:
OpenFolder -> ScanFinish -> OpenBurst -> Inspect100 -> CollapseGroup
```

The earlier always-fit interpretation was a specification error. Correcting it follows the
owner-approved exception; it does not weaken a rule to conceal a product bug. See
[the correspondence record](references/findings.md).

Marking a collapsed group's representative in Timeline (`#507`, PR `#512`) immediately enters Group
Focus on that representative (preserving zoom), plans auto-advance against the expanded group, and
applies the mark. `CollapsedStackMarkEntersGroupFocus` checks all three effects and is verified by
three dedicated mutants (`collapsed-stack-mark-stays-timeline`,
`collapsed-stack-mark-plans-before-expand`, `collapsed-stack-mark-resets-zoom`). Undo reverts the
mark while remaining in Group Focus.

## Audit every claimed action

Read [the complete action/property/mutation table](references/actions.md). The authoritative inventory
is `model/action-contracts.json`. Each of the 24 actions lists its agreed precondition, input or
request, intended target and effect, configured properties, positive witnesses, and negative mutations.
The runner refuses an omitted action, unassigned mutant, or unconfigured property. After changing
an intentional contract, run the normal command and copy the regenerated
`.build/formal-verification/action-coverage.md` to `references/actions.md`.

The original safety properties constrained allowed states but missed requested action effects.
For example, keeping the old photo on auto-advance could preserve zoom and membership while failing
to navigate. The eight additional grouped contracts cover session effects, navigation targets,
inspection, grouping requests, Mark, Undo, FIFO phases, and request admissibility.

The observer captures the raw pre-state and request before each atomic action. Reference functions
use only those inputs. In particular, FireAdvance expects the pre-state plan's target, OpenPhoto
expects the selected input photo, and inspection expects the bounded eye anchor at 100%. Group
and Timeline steps check requested direction and valid indices, not just post-state membership.
The reference must never read a primed value or use a value copied from the resulting state as its
expected target. Shared pure domain functions and the observer capture remain reviewed model
assumptions; these checks are not an independent proof of arbitrary Swift or those functions.

All outcome mutations execute their actions with an incorrect assignment. Extra boundary mutations
admit illegal outward requests; none is credited for merely making an action unreachable. Each
positive query retains all normal properties and intentionally violates only its action witness.
An unreachable action or branch causes that query to fail. The 56 witnesses establish existence,
not that every enabled request is eventually performed or that every possible guard change is caught.
These are transition postconditions and bounded safety checks, not liveness.

The full command now makes 110 TLC runs: one baseline, 52 mutations, one rollback witness, and
56 action/branch witnesses. Its total runtime can exceed a shell tool's 60-second invocation window;
allow the command to finish and inspect its exit code. No depth, queue, state, or mutation-search
bound was reduced. Logs and generated tables remain under the ignored build directory.

## Check Undo and ordered writes

Read [the correspondence and evidence record](references/findings.md) for the source await boundaries
and the exact limitations of each action. The prior model could pass when Undo restored nothing and
coalesced same-photo actions into one latest value. Those were model verification defects, not
Swift defects. The old 9/9 mutation result provides no evidence of Undo correctness.

The current model checks immediate prior-mark restoration, return to the edited photo and correct
Timeline or Group Focus level, and cancellation of pending auto-advance. Four mark/target/timer
mutants and three focused zoom mutants break those guarantees. Undo uses the source's
compare-and-restore guard and one latest edit, with rating-only marks in this small world.

Undo keeps scale and anchor when the target is the currently displayed photo, including Timeline
at 100%. For a changed target, it also keeps the crop when both photos belong to the resulting
Group Focus. This includes re-entering Group Focus from a collapsed Timeline stack. A changed photo
outside that resulting group returns to fit. The implementation action and independent pre-state
reference encode these conditions separately. Four focused reachability queries cover same-photo
Timeline Undo, changed-member Focus Undo, changed-member group reentry, and outside-photo reset.

The directly related Expand and #304 Collapse transitions already preserve same-photo zoom. In this
bounded world nonzero step and pending advance targets change the photo. OpenPhoto and OpenBurst
model Grid entry; retapping a photo inside an already-mounted Detail view remains excluded.

The write FIFO has a total capacity of two immutable actions, including the active action. It can
hold an older Rated action and a newer Rejected action for the same photo. Disk completion, library
recording, scene confirmation reads, and consumer completion are distinct transitions. Pending
desired input wins over an older confirmation. Location loss drops queued work and desired marks,
then shows the scene's latest confirmed marks. An admitted disk operation can still complete after
loss; a new write cannot start and the disconnected persist return cannot publish desired state.

The normal command also queries reachability of this state sequence:

```text
enqueue Rated -> enqueue Rejected -> start older Rated -> complete Rated on disk -> record Rated
-> scene confirms Rated but still shows desired Rejected -> lose location -> show confirmed Rated
```

Git drift detection covers both the desired-mark store and the FIFO implementation. It does not
prove those Swift implementations. Keep the full and chart configurations' invariant lists aligned.

## Separate the evidence

- Bounded model safety covers all enabled action orders through depth 12 in the stated small world.
- Model mutation sensitivity covers 52 injected defects and their expected invariants.
- Source correspondence comes from manual review at the sync commit and Git drift detection after
  that review. The drift gate requires another review when covered source changes. It does not
  establish arbitrary Swift behavior with regexes or model-only mutations.
- The checks establish neither Swift or UIKit correctness nor liveness. Existing Swift, app, and UI
  tests remain necessary.

## Know the bounds

The current model uses these limits and assumptions:

- Two folders each contain one two-photo burst and one standalone photo. Group membership and
  visibility do not change.
- A mark is unmarked, rated, or rejected. Representative selection covers rated, then unmarked, then
  first visible. Star levels and labels are outside the model.
- TLC explores all enabled action orders through depth 12. Deadlock checking is off because the
  depth bound creates terminal states. This is a bounded safety check, not liveness or a proof at
  every folder size.
- OpenFolder models a successful pick or reopen. Picker cancellation and access failures are
  excluded. Scan completion is atomic; partial-scan interaction and group refinement are excluded.
- Auto-advance uses the default `nextPhoto` destination and an explicit fire action. The 300 ms
  timer, `stay`, `nextUnmarkedPhoto`, and `Reject N unmarked` finishing are outside the model.
- One latest rating-only Undo is modeled. A global FIFO holds at most two actions total, including
  its active head. Admission is bounded when full. It never coalesces newer input into an active
  write. Same-photo ordering and both confirmation/publication paths are explicit. Multi-item
  batches, longer queues, the full cross-photo scheduling design, connected write failures, and
  storage retries are outside the model.
- Close, Open, and Reconnect are modeled only after this FIFO drains. The UI's immediate departure
  while writes drain, concurrent open requests, and delayed close installation are outside this
  bounded check. Pending-write states are explored within Detail and across Back to Grid.
  Session clearing means Entry, no active folder/current photo/expanded group, and cleared Undo
  and advance. The global per-photo maps remain bookkeeping for the small world, not displayed
  Entry state or a proof of the source arrays being deallocated.
- A successful admitted disk write may finish after loss. The physical disk, library-confirmed
  store, scene-confirmed marks, desired overlay, and shown marks are separate. A queued read
  confirmation may still update confirmed marks after loss, as the source stream permits.
  The connection invariant guards new admission and the persist-return publication, not every
  physical completion or confirmation read.
- Replaced sessions cannot carry active writes across a drained replacement. A deliberately
  hostile old-generation scan/preparation callback probes the generation-publication boundary
  instead. It over-approximates a buffered callback; it is not a stale-write interleaving.
- Inspection assumes a shown, inspectable image and a known native 100% target. The model does
  not represent waiting for image readiness or a disabled double-tap setting. Zoom has only fit
  and 100%, with centre and eye anchors. Pinch values, native-scale conversion,
  pan geometry, RAW rendering, Vision, focus analysis, and UIKit layout are outside the model.
- Filters, one-visible-member groups, several bursts per folder, selection, batch marks, Move
  Rejects, rename, Save to Photos, Settings navigation, and device posture changes are outside the
  model.

The model does not execute Swift. Existing CloveCore, app, and UI tests remain necessary.

## Maintain the verification

Map each atomic model action to one synchronous `@MainActor` transition or one pure CloveCore rule.
Keep rendering and layout out of the top-level model. Keep the full and chart configurations'
invariant lists in sync. When behavior changes, update the model, add a variant that breaks the
changed rule, and run the complete script. Do not weaken an invariant to make a source defect pass.
Report real source defects with code-level evidence, not model-only mutations. Do not change product
code unless the task authorizes a fix.

Before advancing the sync commit, review every covered change and exercise the source-to-model
maintenance connection on an isolated scratch break in real covered code. Restore the source and
rerun the normal command. The drift experiment at this sync commit is recorded in
[references/findings.md](references/findings.md).
