# Source correspondence and specification correction

Source sync commit: `29702ce651a7de77cf642b38d1898023ae775476`.

## Collapse semantics were corrected

An earlier version of this verification treated every Group Focus collapse as a return to fit. That
summary was imprecise. Owner-approved #304 explicitly keeps scale and anchor when collapse leaves
the same Representative on stage. Detail returns to fit only when collapse changes the displayed
photo to the Representative.

The current `DetailMarkingView` behavior matches that exception. There is no current-source finding
for Representative collapse. The model now implements both branches in
`CollapseZoomFollowsRepresentative`:

- `changed-collapse-retains-zoom` breaks the changed-photo branch. Its counterexample is
  `OpenBurst -> StepGroup -> Inspect100 -> CollapseGroup`.
- `representative-collapse-resets-zoom` breaks the unchanged-Representative branch. Its
  counterexample is `OpenBurst -> Inspect100 -> CollapseGroup`.

This is a specification correction based on the owner-approved rule, not an invariant weakened to
hide a source defect. No product code was changed.

## Evidence has separate meanings

The depth-12 TLA+ run establishes bounded model safety for all enabled action orders in the small
world. The nine mutations establish sensitivity to selected model defects. Manual review at the
sync commit establishes the initial source correspondence. The Git source-drift gate detects later
changes to covered paths and requires another review.

The drift gate does not parse Swift, prove that the model matches a changed function, or establish
Swift or UIKit correctness. The TLA+ run also does not establish liveness. These limitations apply
to every passing result.

## A real covered-source scratch break

On 2026-11-17, the normal workflow was exercised against a temporary semantic break in the covered
`BrowsingModel.collapseGroup()` function. The experiment changed this real Swift line:

```diff
- let representative = active.representative.id
+ let representative = active.visibleMembers[0].id
```

The unchanged normal command, `.agents/skills/browsing-workflow/scripts/check`, exited 1 before
starting TLC and printed:

```text
FAIL source-drift gate: covered source changed since reviewed sync 29702ce651a7de77cf642b38d1898023ae775476
  Clove/Browsing/BrowsingModel.swift
This is drift detection, not semantic proof. Review the source and model, then rerun. Do not advance the sync commit merely to bypass review.
```

The Swift line was then restored to `active.representative.id`. `git diff` for the product file was
empty and the sync commit remained `29702ce651a7de77cf642b38d1898023ae775476`. The same normal
command then passed the drift gate, completed the depth-12 model with 2,449,379 generated states,
883,363 distinct states, and an empty queue, and caught all nine expected mutation failures.

This experiment demonstrates drift detection and the required maintenance stop on an actual covered
Swift edit. It does not claim semantic verification of that edit. Product code was restored, and no
macOS or iOS checks were claimed on the Linux host.
