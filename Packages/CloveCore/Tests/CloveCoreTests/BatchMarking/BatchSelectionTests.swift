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

    /// Even when a cell is a collapsed cover, interacting with it operates strictly on its visible
    /// cover photo (`cell.photo.id`) and never pulls in hidden or other group members.
    @Test func aCollapsedCoverSelectsAndTogglesOnlyItsVisibleCoverPhoto() throws {
        let photos = ["a", "b", "c", "d"].map { BatchMarkFixtures.gridPhoto($0) }
        let cells = GridDisplay(
            photos: photos, groups: BatchMarkFixtures.groups
        ).cells
        let cover = try #require(cells.first)
        #expect(cover.id == .group(BatchMarkFixtures.burst))
        let coverPhoto = BatchMarkFixtures.photo("a")

        let empty = BatchSelection(groups: BatchMarkFixtures.groups)
        #expect(empty.identities(for: cover) == [coverPhoto])
        #expect(!empty.showsSelected(cover))
        #expect(empty.selecting(cover) == [coverPhoto])
        #expect(empty.toggling(cover) == [coverPhoto])

        let selected = BatchSelection(groups: BatchMarkFixtures.groups, selection: [coverPhoto])
        #expect(selected.showsSelected(cover))
        #expect(selected.toggling(cover).isEmpty)
    }

    /// Selecting a collapsed cover when another hidden or sibling member happens to be in the
    /// selection only affects the cover's visible photo; Select all on visible `photos` adds all
    /// visible photos without pulling in hidden group members.
    @Test func selectingCoverAndSelectAllVisibleNeverPullInHiddenMembers() throws {
        let visiblePhotos = ["a", "b", "d"].map { BatchMarkFixtures.gridPhoto($0) }
        let collapsedCells = GridDisplay(
            photos: visiblePhotos, groups: BatchMarkFixtures.groups
        ).cells
        let unfoldedCells = GridDisplay(
            photos: visiblePhotos, groups: BatchMarkFixtures.groups,
            expandGroupsInline: true
        ).cells
        let cover = try #require(collapsedCells.first)
        let batch = BatchSelection(
            groups: BatchMarkFixtures.groups, selection: [BatchMarkFixtures.photo("a")])
        #expect(batch.showsSelected(cover))
        #expect(!batch.showsAllSelected(visiblePhotos))
        #expect(!batch.showsAllSelected(unfoldedCells))

        let selectedVisible = batch.selectingAll(visiblePhotos)
        #expect(
            selectedVisible
                == Set(["a", "b", "d"].map(BatchMarkFixtures.photo)))
        #expect(!selectedVisible.contains(BatchMarkFixtures.photo("c")))

        let selectedFromUnfolded = batch.selectingAll(unfoldedCells)
        #expect(selectedFromUnfolded == selectedVisible)
        #expect(
            BatchSelection(groups: BatchMarkFixtures.groups, selection: selectedVisible)
                .showsAllSelected(visiblePhotos))
    }

    /// Unfolded group cells each select and toggle independently on their own photo identity.
    @Test func unfoldedGroupCellsSelectAndToggleIndividually() throws {
        let photos = ["a", "b", "c", "d"].map { BatchMarkFixtures.gridPhoto($0) }
        let cells = GridDisplay(
            photos: photos, groups: BatchMarkFixtures.groups, expandGroupsInline: true
        ).cells
        #expect(cells.count == 4)

        let batch = BatchSelection(groups: BatchMarkFixtures.groups)
        let afterFirst = batch.toggling(cells[0])
        #expect(afterFirst == [BatchMarkFixtures.photo("a")])

        let afterSecond = BatchSelection(groups: BatchMarkFixtures.groups, selection: afterFirst)
            .toggling(cells[1])
        #expect(afterSecond == Set([BatchMarkFixtures.photo("a"), BatchMarkFixtures.photo("b")]))

        let afterUntoggle = BatchSelection(groups: BatchMarkFixtures.groups, selection: afterSecond)
            .toggling(cells[0])
        #expect(afterUntoggle == [BatchMarkFixtures.photo("b")])
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

    @Test func deselectingAllRemovesVisiblePhotosWhileKeepingHiddenSelection() {
        let photos = ["a", "b", "c", "d"].map { BatchMarkFixtures.gridPhoto($0) }
        let cells = GridDisplay(
            photos: photos, groups: BatchMarkFixtures.groups, expandGroupsInline: true
        ).cells
        let hidden = BatchMarkFixtures.photo("hidden")
        let all = BatchSelection(groups: BatchMarkFixtures.groups, selection: [hidden])
            .selectingAll(photos)
        let batch = BatchSelection(groups: BatchMarkFixtures.groups, selection: all)

        #expect(batch.showsAllSelected(photos))
        #expect(batch.showsAllSelected(cells))
        #expect(
            !BatchSelection(groups: BatchMarkFixtures.groups, selection: []).showsAllSelected(
                [GridPhoto]()))
        #expect(
            !BatchSelection(groups: BatchMarkFixtures.groups, selection: []).showsAllSelected(
                [GridCellItem]()))

        let deselected = batch.deselectingAll(photos)
        #expect(deselected == [hidden])
        #expect(
            !BatchSelection(groups: BatchMarkFixtures.groups, selection: deselected)
                .showsAllSelected(photos))
        #expect(batch.deselectingAll(cells) == [hidden])
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

    @Test func rangeSelectionOperatesOnIndividualUnfoldedGroupCells() throws {
        let cells = GridDisplay(
            photos: ["a", "b", "c", "d", "e"].map { BatchMarkFixtures.gridPhoto($0) },
            groups: BatchMarkFixtures.groups,
            expandGroupsInline: true
        ).cells
        // Unfolded: cells[0]=a, cells[1]=b, cells[2]=c, cells[3]=d, cells[4]=e.
        #expect(cells.count == 5)
        let base = BatchSelection(groups: BatchMarkFixtures.groups, selection: [])
        let span = base.rangeSelection(in: cells, anchorIndex: 0, currentIndex: 1, selecting: true)
        #expect(span == Set(["a", "b"].map(BatchMarkFixtures.photo)))

        let deselect = BatchSelection(groups: BatchMarkFixtures.groups, selection: span)
            .rangeSelection(in: cells, anchorIndex: 0, currentIndex: 0, selecting: false)
        #expect(deselect == [BatchMarkFixtures.photo("b")])
    }
}
