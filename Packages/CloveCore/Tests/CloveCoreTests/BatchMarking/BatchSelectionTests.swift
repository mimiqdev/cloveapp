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
            id: .photo(photo), photo: BatchMarkFixtures.gridPhoto("a"))
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
            photos: photos, groups: BatchMarkFixtures.groups, display: .collapsed
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
            photos: photos, groups: BatchMarkFixtures.groups, display: .collapsed
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
            groups: BatchMarkFixtures.groups, display: .collapsed)
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
}
