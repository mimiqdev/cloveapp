# Source finding: Representative collapse keeps zoom

Source sync commit: `29702ce651a7de77cf642b38d1898023ae775476`.

## Contract

The requested workflow rule says that leaving Group Focus returns to fit. Group Focus navigation
keeps scale and anchor, but Timeline navigation and leaving the group reset them.

## Code path

1. `BrowsingModel.collapseGroup()` sets `expandedGroup = nil` and snaps `currentPhoto` to the active
   group's Representative.
2. `DetailScreen.collapseGroup()` cancels auto-advance and calls that model function.
3. `DetailMarkingView` reloads preview state through `.task(id: photo.id)`.
4. If the previous Group Focus photo was not the Representative, the photo ID changes and
   `loadPreview` resets zoom to fit.
5. If the previous photo already was the Representative, the photo ID does not change. Only
   `refreshPrefetchForOrderChange` runs for the new Timeline order. Its comment explicitly says it
   keeps pixels and zoom untouched when expanding or collapsing on the Representative.

The relevant files are `Clove/Browsing/BrowsingModel.swift`, `Clove/Browsing/DetailScreen.swift`,
and `Clove/Detail/DetailMarkingView.swift`. `CloveUITests/CloveFlowTests.swift` covers the
Representative-changed case and says that it resets zoom. It does not clear the same-photo case.

## Executable comparison

The `representative-collapse-keeps-zoom` variant in `scripts/check` changes only the collapse zoom
rule. It keeps scale and anchor when the current photo is already the Representative and resets them
otherwise, matching the code path above. TLC produces:

```text
OpenFolder -> ScanFinish -> OpenBurst -> Inspect100 -> CollapseGroup
Invariant OutsideGroupNavigationReturnsFit is violated.
```

The default model uses fit on every collapse and passes after all injected variants are removed.
The source-comparison variant remains a report of the current code, not a product fix. This finding
was established by source inspection and TLC on Linux. An iOS runtime reproduction remains undone.
