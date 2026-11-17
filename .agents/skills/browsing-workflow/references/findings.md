# Model correspondence and run evidence

Source sync commit: `29702ce651a7de77cf642b38d1898023ae775476`.
The two newly covered marking files were read at this revision and have no source diff from it.
The sync commit has not advanced. No product defect is diagnosed by this verification revision.

## Corrections to the verification

The earlier always-fit collapse interpretation was a specification error. Owner-approved #304 keeps
scale and anchor when collapse leaves the same Representative on stage. Collapse changes the photo
to the Representative at fit otherwise. `CollapseZoomFollowsRepresentative` still checks both
branches, with separate negative mutations. The current source follows the exception.

Independent review at verification head `266adf8615960bced07eb1dbbba22aa285e63994` found two further
model verification defects:

- Undo could restore nothing and still pass every invariant. The previous 9/9 mutation result did
  not demonstrate Undo correctness.
- Per-photo latest-value coalescing removed the intermediate state in which an older action was
  confirmed while a newer desired input remained queued. It did not describe `PhotoActionPipeline`.

The model replaces that abstraction with a bounded FIFO and immediate Undo restore, navigation,
and cancellation invariants. Those resolved checks are retained. These changes repair the model,
not Swift defects.

Fresh review at verification head `75ab5eaea6a620d4ce1183c07d21cb5f2563957e` found a systemic
coverage defect: valid-state safety did not assert that requested actions actually had their intended
effects. Keeping the old photo during FireAdvance, staying at fit during Inspect100, not moving a
group step, dropping the selected OpenPhoto target, remaining in Grid on Close, and ignoring a
grouping request all passed. These were verification defects, not diagnosed Swift defects.

The current audit covers every claimed Next action with a precondition/request/effect contract,
a reachable positive example, and a meaningful negative assignment mutation. See the complete
[action correspondence table](actions.md), generated from `model/action-contracts.json`.
Eight grouped contracts supplement the original safety checks. Expected effects are computed only
from the raw pre-state snapshot and request, independently of primed implementation assignments.
Shared pure domain helpers and observer capture are trusted model assumptions checked by review.

## Same-photo Undo zoom fidelity

Review at `9959de5830de3e624bfdc4ad835c2b5ae5449124` found that both the model action and its
reference incorrectly reset a same-photo Timeline Undo to fit. This was a source-correspondence
defect in the verification, not a Swift defect or a product specification decision.

`BrowsingModel.undoLastMark` restores marks and navigates through `openPhoto` or `openGroup`. In
`DetailMarkingView`, preview loading is keyed by `photo.id`, and order-only changes go through
`refreshPrefetchForOrderChange` without resetting zoom. The same-photo Undo therefore retains its
existing scale/anchor. When the photo changes, `loadPreview` keeps the crop if both the previous
and target photos belong to the resulting expanded group. Its predicate reads the new group, not
the previous route. This also preserves zoom when Undo re-enters Group Focus from Timeline on
another member. A changed target outside that resulting group resets to fit.

The action now checks same photo first, then target-group membership. The reference separately
derives the result from `event.before.currentPhoto`, the old Undo target, and the resulting group.
Neither reads the action's primed scale/anchor. No covered product source or sync commit changed.

| Undo transition at 100% | Expected zoom | Focused witness length | Executed bad-effect mutation |
| --- | --- | --- | --- |
| Timeline, same standalone photo | Retain scale and anchor | 6 | `undo-same-photo-timeline-resets-zoom` |
| Group Focus, another member | Retain scale and anchor | 7 | Existing group-preservation path retained |
| Timeline, another member in the resulting Group Focus | Retain scale and anchor | 7 | `undo-group-reentry-resets-zoom` |
| Changed photo outside the resulting group | Fit, centre | 7 | `undo-outside-change-keeps-zoom` |

The first mutation gives the requested six-action counterexample:

```text
OpenFolder -> ScanFinish -> OpenPhoto(aS) -> Inspect100 -> Mark -> UndoLastMark
Invariant UndoActionEffects is violated.
```

Direct siblings were checked against the same identity rule. Expand preserves the current photo
and zoom; #304 Collapse already keeps zoom only when its Representative stays on stage. Nonzero
steps and advance targets change the photo in this small world. OpenPhoto/OpenBurst model Grid
entry, not a same-photo retap within an already-mounted Detail view. No other action or domain
was expanded by this correction. The zoom fields model the resulting inspection presentation,
not UIKit task scheduling or rendering correctness.

## Source boundaries and abstractions

| Model action | Source boundary |
| --- | --- |
| `Mark` | `DetailMarkingView.apply` plans auto-advance before `BrowsingModel.apply` synchronously calls `request` and `submit`. `DesiredPhotoMarks.apply` captures shown before/after marks and the pipeline appends an immutable action. No await occurs within that input turn. |
| `UndoLastMark` | `DetailMarkingView.undo` calls `beginMarkingGesture` to cancel the timer, then `BrowsingModel.undoLastMark` applies `DesiredMarkRestore.change`, submits one batch, and navigates with `openGroup` or `openPhoto`. The rating-only model requires the expected shown mark, restores the prior rating, and consumes the one Undo record synchronously. |
| `BeginWrite` | The consumer calls `PhotoActionPipeline.beginNext`, then `persist` checks location loss before awaiting `library.apply`. The model treats this as an admitted active write reaching storage. Admission failures before file access are excluded. |
| `CompleteDisk` | The admitted asynchronous write finishes on disk. It uses the immutable active head's value, never the newest queued value. A successful already-admitted file operation can finish after location loss. The model excludes failed write outcomes. This step does not change the library, scene-confirmed marks, or desired overlay. |
| `RecordWrite` | `FolderLibrarySession.apply` receives completed write results and synchronously calls `record`; `applyConfirmedProgressChange` updates the library's store and yields a `.reads` update. The model records one successful rating action in the library store separately from disk completion. |
| `ReadConfirmation` | The scene consumes the buffered `.reads` update in `applyReads`, taking current `library.photos`, updating `confirmedPhotos`, and overlaying `DesiredPhotoMarks.shown`. The modeled read refreshes from the current library store, not the old message payload. It can occur before or after consumer completion and after loss. |
| `FinishWrite` | `persist` resumes after `library.apply`. Its location/generation guard precedes `finishPendingMarks` and `refresh`. `hasPendingMark` preserves desired marks when a later same-photo action is queued. `finish` and the next `beginNext` run without suspension in the consumer loop, so the model immediately starts the next queued write in this transition. |
| `LoseLocation` | `discardDisconnectedChanges` sets the loss, drops queued pipeline entries, clears desired marks and Undo, and replaces shown marks with the scene's `confirmedPhotos` before awaiting `library.discardPendingChanges`. The active entry survives. This rollback uses scene-confirmed marks, not an unpublished disk write. |

The global FIFO has capacity two total, including its active head. Its phases are `idle`, `writing`,
`diskDone`, and `recorded`. A full queue bounds further Mark and Undo admission. This is an explicit
small-world limit; it does not claim the production queue has capacity two. The model preserves
FIFO order among admitted actions, including two actions for one photo. Multi-item batch semantics,
longer queues, and the full cross-photo scheduling design are excluded.

`ReadConfirmation` abstracts a refresh of the current library store. It does not enumerate individual
buffered `.reads` deliveries or duplicate record notifications. Same-photo desired/confirmed
interleavings are represented, but this is not an exhaustive simulation of the entire AsyncStream.

Close, Open, and Reconnect require a drained model FIFO. The source's immediate departure UI,
replacement waits, and concurrent open requests are outside the bounded model. Active writes cannot
cross replacement in this abstraction. The generation mutation therefore probes a deliberately
hostile old scan/preparation callback, not an impossible stale active-write completion.

The connection properties guard new write admission and `persist` publication. They do not forbid
an admitted disk completion or a buffered confirmed-mark read after loss. Conflating those events
would incorrectly erase source interleavings.

## Current executable results

Run from the repository root:

```sh
.agents/skills/browsing-workflow/scripts/check
```

The current run uses TLA+ tools 1.7.4, one TLC worker, depth 12, two folders with three photos each,
and `MaxPending = 2`. It generated 1,245,725 states, found 370,189 distinct states, exhausted the
queue, and passed all 35 configured safety and transition-effect invariants. All 50 model mutations
failed on relevant configured properties. The separate full-depth reachability pass found all 24
actions and all 53 selected branch witnesses. The full normal gate on this revision's final
verification content exited 0 in 101.666 seconds. No new run mode was added.

No world, queue, or depth bound changed in the action audit or Undo zoom correction. The state
count remains 1,245,725 generated and 370,189 distinct after the zoom fix. The earlier increase
from the FIFO-only model came from capturing pre-state/request observations. The normal command now makes 105 TLC runs,
so a 60-second shell invocation window was insufficient for the complete batch. The same normal
command was allowed to finish with logged output and exit 0; no checker limit was reduced.

The six independently reproduced action-effect failures are now rejected:

| Incorrect executed assignment | Relevant effect property | Shortest steps |
| --- | --- | --- |
| FireAdvance keeps current photo instead of old plan target | `NavigationActionEffects` | 5 |
| Inspect100 keeps fit scale and centre anchor | `InspectionActionEffects` | 4 |
| StepGroup keeps the same member | `NavigationActionEffects` | 4 |
| OpenPhoto selects NoPhoto | `NavigationActionEffects` | 3 |
| CloseFolder stays in Grid | `SessionActionEffects` | 2 |
| SetGrouping ignores the requested value | `GroupingActionEffects` | 3 |

These are action effects, not eventual-progress properties. Expected values come from pre-state or
request inputs, never a resulting state copied into event metadata. Negative assignment mutations
retain executable actions. The extra boundary mutations allow an invalid outward request rather than
disabling actions. Positive queries keep every normal invariant and succeed only when their
`NoActionWitness` predicate is intentionally violated. A completed search without reaching the
action fails. Existential action witnesses are not an exhaustive proof of all guards or liveness.

The new Undo counterexamples are:

```text
Undo does not restore: OpenFolder -> ScanFinish -> OpenPhoto -> Mark -> UndoLastMark
Undo goes to wrong photo: OpenFolder -> ScanFinish -> OpenPhoto -> Mark -> UndoLastMark
Undo uses wrong level: OpenFolder -> ScanFinish -> OpenBurst -> Mark -> UndoLastMark
Undo keeps timer: OpenFolder -> ScanFinish -> OpenBurst -> Mark -> UndoLastMark
```

The write counterexamples include:

```text
Older consumer completion overwrites or clears newer desired:
OpenFolder -> ScanFinish -> OpenPhoto -> Mark -> Mark -> BeginWrite -> CompleteDisk -> RecordWrite -> FinishWrite

Older read confirmation overrides desired:
OpenFolder -> ScanFinish -> OpenPhoto -> Mark -> Mark -> BeginWrite -> CompleteDisk -> RecordWrite -> ReadConfirmation

Disk commits newest queued value instead of immutable head:
OpenFolder -> ScanFinish -> OpenPhoto -> Mark -> Mark -> BeginWrite -> CompleteDisk

Loss uses disk state before scene confirmation:
OpenFolder -> ScanFinish -> OpenPhoto -> Mark -> BeginWrite -> CompleteDisk -> LoseLocation
```

`--witness-only` adds `NoRatedRollbackWitness` as a separate reachability query. TLC intentionally
violates it after ten steps:

```text
OpenFolder -> ScanFinish -> OpenPhoto(aS)
-> Mark Rated -> Mark Rejected -> BeginWrite(Rated)
-> CompleteDisk(Rated) -> RecordWrite(Rated) -> ReadConfirmation
-> LoseLocation
```

Immediately before loss the active entry is the recorded Rated action, the second queued entry is
Rejected, the scene-confirmed and disk values are Rated, and the desired/shown value is Rejected.
After loss the queued Reject and desired overlay are gone, the active head remains, and shown marks
are Rated. The query requires those values and queue length, not just an action-name sequence. Its
intentional violation is evidence of reachability, not a failed safety invariant or a source bug.

`statechart` reads the full result, mutation counterexamples, and reachability queries. The full model
exceeds the 500-state chart budget. Mutant reruns can leave other rules under `Rules not checked`;
those are not counted as passes on broken variants.

## Real-source drift experiments

The earlier scratch experiment in `BrowsingModel.collapseGroup()` remains valid drift evidence:

```diff
- let representative = active.representative.id
+ let representative = active.visibleMembers[0].id
```

The normal command exited 1 before TLC, named `Clove/Browsing/BrowsingModel.swift` as changed, and
required source/model review. The line was restored before the passing rerun.

On 2026-11-17 the expanded drift coverage was also exercised on the real covered
`DesiredPhotoMarks.apply` implementation:

```diff
- pending[photo] = edit.after
+ pending[photo] = confirmed
```

The unchanged normal command exited 1 before TLC and named
`Packages/CloveCore/Sources/CloveCore/Marking/DesiredPhotoMarks.swift`. It stated:

```text
This is drift detection, not semantic proof. Review the source and model, then rerun. Do not advance the sync commit merely to bypass review.
```

The source was restored. Covered product files have no diff, the sync commit is unchanged, and the
normal command passed the drift gate, the model, mutation checks, and the rollback witness.
The current action audit additionally checks all 35 invariants, 50 mutants, and 53 action/branch
witnesses. The reviewed source commit and 12 covered paths have not changed.

## Evidence limits

Bounded model safety, model mutation sensitivity, and source correspondence are separate claims.
Source correspondence starts with manual review at the sync commit and requires review when the
Git drift gate finds changes. Neither the model nor the gate executes or semantically verifies
Swift or UIKit. No liveness or unbounded correctness is established. No macOS or iOS check was run
for these verification-only changes on Linux. Final merge remains with the owner.
