import Foundation
import Testing

import CloveCore

/// PRD P0-09 and PRD Grid: what one grid cell means to the multi-selection, and which selected
/// photos a batch marks. These tests pin the collapsed cover rule and the filter rule.
@Suite("Batch selection")
struct BatchSelectionTests {
    /// A photo's own cell selects that photo, and a second tap clears it.
    @Test func aPhotoCellSelectsAndTogglesOnlyThatPhoto() {
        let photo = BatchMarkFixtures.photo("a")
        let cell = GridCellItem(
            id: .photo(photo), photo: BatchMarkFixtures.gridPhoto("a"), isDimmed: false)
        let empty = BatchSelection()

        #expect(empty.identities(for: cell) == [photo])
        #expect(!empty.showsSelected(cell))
        #expect(empty.selecting(cell) == [photo])
        #expect(empty.toggling(cell) == [photo])

        let selected = BatchSelection(selection: empty.selecting(cell))
        #expect(selected.showsSelected(cell))
        #expect(selected.toggling(cell).isEmpty)
    }

    /// A collapsed group's cover stands for every photo in its group, and a second tap clears
    /// all of them.
    @Test func aCollapsedCoverSelectsItsWholeGroup() throws {
        let photos = ["a", "b", "c", "d"].map { BatchMarkFixtures.gridPhoto($0) }
        let cells = GridDisplay(
            photos: photos, groups: BatchMarkFixtures.groups
        ).cells
        let cover = try #require(cells.first)
        #expect(cover.id == .group(BatchMarkFixtures.burst))
        let group = Set(["a", "b", "c"].map(BatchMarkFixtures.photo))

        let empty = BatchSelection(groups: BatchMarkFixtures.groups)
        #expect(empty.identities(for: cover) == group)
        #expect(!empty.showsSelected(cover))
        #expect(empty.toggling(cover) == group)

        let selected = BatchSelection(groups: BatchMarkFixtures.groups, selection: group)
        #expect(selected.showsSelected(cover))
        #expect(selected.toggling(cover).isEmpty)
    }

    /// A partly selected cover completes its group instead of clearing the part already chosen,
    /// and Select all adds every photo the shown cells stand for.
    @Test func aPartlySelectedCoverCompletesItsGroup() throws {
        let photos = ["a", "b", "c", "d"].map { BatchMarkFixtures.gridPhoto($0) }
        let cells = GridDisplay(
            photos: photos, groups: BatchMarkFixtures.groups
        ).cells
        let cover = try #require(cells.first)
        let group: Set<PhotoIdentity> = ["a", "b", "c"].reduce(into: Set()) {
            $0.insert(BatchMarkFixtures.photo($1))
        }
        let partly = BatchSelection(
            groups: BatchMarkFixtures.groups, selection: [BatchMarkFixtures.photo("a")])
        #expect(!partly.showsSelected(cover))
        #expect(partly.toggling(cover) == group)

        let everything = partly.selectingAll(cells)
        #expect(everything == group.union([BatchMarkFixtures.photo("d")]))
    }

    /// A cover whose group is no longer published falls back to its own photo, so a stale cell
    /// never selects a group nobody can open.
    @Test func aCoverWithoutItsGroupSelectsItsOwnPhoto() throws {
        let display = GridDisplay(
            photos: ["a", "b"].map { BatchMarkFixtures.gridPhoto($0) },
            groups: BatchMarkFixtures.groups)
        let cover = try #require(display.cells.first)
        let stale = BatchSelection()
        #expect(stale.identities(for: cover) == [BatchMarkFixtures.photo("a")])
    }

    /// A batch marks the selected photos the grid shows, in grid order; a photo the filter
    /// hides stays selected and is not marked.
    @Test func aBatchMarksTheSelectedPhotosTheFilterShows() {
        let shown = ["b", "a"].map { BatchMarkFixtures.gridPhoto($0) }
        let selection: Set<PhotoIdentity> = [
            BatchMarkFixtures.photo("a"), BatchMarkFixtures.photo("c"),
        ]
        let targets = BatchSelection.targets(selection: selection, shown: shown)
        #expect(targets.map(\.id) == [BatchMarkFixtures.photo("a")])

        let both = BatchSelection.targets(
            selection: selection.union([BatchMarkFixtures.photo("b")]), shown: shown)
        #expect(both.map(\.id) == shown.map(\.id))
        #expect(both.map(\.id) == ["b", "a"].map(BatchMarkFixtures.photo))
    }

    @Test func deselectingAllRemovesShownCellsWhileKeepingHiddenSelection() {
        let cells = GridDisplay(
            photos: ["a", "b", "c", "d"].map { BatchMarkFixtures.gridPhoto($0) },
            groups: BatchMarkFixtures.groups
        ).cells
        let hidden = BatchMarkFixtures.photo("hidden")
        let all = BatchSelection(groups: BatchMarkFixtures.groups, selection: [hidden])
            .selectingAll(cells)
        let batch = BatchSelection(groups: BatchMarkFixtures.groups, selection: all)

        #expect(batch.showsAllSelected(cells))
        #expect(
            !BatchSelection(groups: BatchMarkFixtures.groups, selection: []).showsAllSelected([]))

        let deselected = batch.deselectingAll(cells)
        #expect(deselected == [hidden])
        #expect(
            !BatchSelection(groups: BatchMarkFixtures.groups, selection: deselected)
                .showsAllSelected(cells))
    }

    @Test func rangeSelectionSelectsForwardBackwardAndRestoresBaselineOnPullBack() {
        let cells = ["a", "b", "c", "d", "e"].map { name in
            let photo = BatchMarkFixtures.gridPhoto(name)
            return GridCellItem(id: .photo(photo.id), photo: photo, isDimmed: false)
        }
        let baseline: Set<PhotoIdentity> = [BatchMarkFixtures.photo("a")]
        let base = BatchSelection(selection: baseline)

        // Forward drag from index 1 (b) to 3 (d): adds b, c, d on top of baseline {a}.
        let forward = base.rangeSelection(
            in: cells, anchorIndex: 1, currentIndex: 3, selecting: true)
        #expect(forward == Set(["a", "b", "c", "d"].map(BatchMarkFixtures.photo)))

        // Pulling back to index 2 (c) from the same baseline cleanly drops d.
        let pulledBack = base.rangeSelection(
            in: cells, anchorIndex: 1, currentIndex: 2, selecting: true)
        #expect(pulledBack == Set(["a", "b", "c"].map(BatchMarkFixtures.photo)))

        // Backward drag from index 3 (d) to 1 (b).
        let backward = base.rangeSelection(
            in: cells, anchorIndex: 3, currentIndex: 1, selecting: true)
        #expect(backward == Set(["a", "b", "c", "d"].map(BatchMarkFixtures.photo)))

        // Deselect drag from index 3 to 1 on full selection leaves e (and baseline restoration).
        let full = Set(["a", "b", "c", "d", "e"].map(BatchMarkFixtures.photo))
        let deselectBase = BatchSelection(selection: full)
        let deselected = deselectBase.rangeSelection(
            in: cells, anchorIndex: 3, currentIndex: 1, selecting: false)
        #expect(deselected == Set(["a", "e"].map(BatchMarkFixtures.photo)))

        // Pulling back deselect drag to index 2 restores b.
        let deselectPulledBack = deselectBase.rangeSelection(
            in: cells, anchorIndex: 3, currentIndex: 2, selecting: false)
        #expect(deselectPulledBack == Set(["a", "b", "e"].map(BatchMarkFixtures.photo)))

        // Out-of-bounds indices return baseline untouched.
        #expect(
            base.rangeSelection(in: cells, anchorIndex: -1, currentIndex: 2, selecting: true)
                == baseline)
        #expect(
            base.rangeSelection(in: cells, anchorIndex: 1, currentIndex: 99, selecting: true)
                == baseline)
        #expect(
            base.rangeSelection(in: [], anchorIndex: 0, currentIndex: 0, selecting: true)
                == baseline)
    }

    @Test func rangeSelectionExpandsCollapsedGroupCoversInSpan() throws {
        let cells = GridDisplay(
            photos: ["a", "b", "c", "d", "e"].map { BatchMarkFixtures.gridPhoto($0) },
            groups: BatchMarkFixtures.groups
        ).cells
        // cells[0] is collapsed cover for {a, b, c}, cells[1] is d, cells[2] is e.
        #expect(cells.count == 3)
        let base = BatchSelection(groups: BatchMarkFixtures.groups, selection: [])
        let span = base.rangeSelection(in: cells, anchorIndex: 0, currentIndex: 1, selecting: true)
        #expect(span == Set(["a", "b", "c", "d"].map(BatchMarkFixtures.photo)))

        let deselect = BatchSelection(groups: BatchMarkFixtures.groups, selection: span)
            .rangeSelection(in: cells, anchorIndex: 0, currentIndex: 0, selecting: false)
        #expect(deselect == [BatchMarkFixtures.photo("d")])
    }
}
