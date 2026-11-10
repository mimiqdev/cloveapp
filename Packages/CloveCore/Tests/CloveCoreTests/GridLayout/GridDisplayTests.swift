import Foundation
import Testing

import CloveCore

/// PRD Grid's similar-group display and PRD P0-11: expanded shows every photo with the group's
/// outline and one count, collapsed shows one cover per group with its count, and grouping off
/// hides the group marks. These tests pin how the grid's cells are composed.
@Suite("Grid display cells")
struct GridDisplayTests {
    /// Expanded display keeps every photo and draws the count once, on the group's first cell.
    @Test func expandedMarksEveryMemberAndCountsTheGroupOnce() throws {
        let burst = group("burst-one", photos(0...1))
        let display = GridDisplay(
            photos: photos(0...3), groups: [burst], display: .expanded)
        #expect(display.cells.count == 4)
        #expect(display.cells.map(\.id) == photos(0...3).map { .photo($0.id) })

        let first = try #require(display.cells[0].group)
        #expect(first.id == burst.id)
        #expect(first.count == 2)
        #expect(first.showsCount)
        #expect(!first.isCover)

        let second = try #require(display.cells[1].group)
        #expect(second.showsCount == false)
        #expect(display.cells[2].group == nil)
    }

    /// A filter that hides the group's first member moves the count to the first shown member,
    /// and the count stays the published group's count rather than the shown count.
    @Test func aFilteredGroupKeepsItsPublishedCountOnTheFirstShownCell() throws {
        let burst = group("burst-one", photos(0...2))
        let shown = Array(photos(0...2).dropFirst())
        let display = GridDisplay(photos: shown, groups: [burst], display: .expanded)
        let mark = try #require(display.cells.first?.group)
        #expect(mark.count == 3)
        #expect(mark.showsCount)
        #expect(display.cells.dropFirst().allSatisfy { $0.group?.showsCount == false })
    }

    /// Collapsed display keeps one cover per group, on its first shown member, and leaves the
    /// ungrouped photos as their own cells.
    @Test func collapsedShowsOneCoverPerGroup() throws {
        let first = group("burst-one", photos(0...1))
        let second = group("burst-two", photos(3...3))
        let display = GridDisplay(
            photos: photos(0...3), groups: [first, second], display: .collapsed)
        #expect(
            display.cells.map(\.id) == [
                .group(first.id), .photo(photos(2...2)[0].id), .group(second.id),
            ])
        let cover = try #require(display.cells.first?.group)
        #expect(cover.isCover)
        #expect(cover.showsCount)
        #expect(cover.count == 2)
        #expect(display.cells.first?.photo == photos(0...1)[0])
        #expect(display.cells[2].group?.count == 1)
    }

    /// A collapsed cover follows the group's first member that the filter still shows.
    @Test func aCollapsedCoverFollowsTheFirstShownMember() {
        let burst = group("burst-one", photos(0...2))
        let display = GridDisplay(
            photos: Array(photos(0...2).dropFirst()), groups: [burst], display: .collapsed)
        #expect(display.cells.count == 1)
        #expect(display.cells[0].photo == photos(0...2)[1])
        #expect(display.cells[0].group?.count == 3)
    }

    /// A group with no shown member has no cover, because a cover always names a drawn photo.
    @Test func aGroupWithNoShownMemberHasNoCover() {
        let burst = group("burst-one", photos(2...3))
        let display = GridDisplay(
            photos: photos(0...1), groups: [burst], display: .collapsed)
        #expect(display.cells.map(\.id) == photos(0...1).map { .photo($0.id) })
    }

    /// Grouping off hides every group mark in both displays (PRD Grid, PRD P0-11).
    @Test func groupingOffLeavesEveryPhotoItsOwnCell() {
        let burst = group("burst-one", photos(0...1))
        for display in [GridGroupDisplay.expanded, .collapsed] {
            let cells = GridDisplay(
                photos: photos(0...3), groups: [burst], groupsEnabled: false, display: display
            ).cells
            #expect(cells.map(\.id) == photos(0...3).map { .photo($0.id) })
            #expect(cells.allSatisfy { $0.group == nil })
        }
    }

    /// A photo that two groups name carries the first published group, never two outlines.
    @Test func theFirstPublishedGroupMarksAPhotoNamedByTwo() throws {
        let first = group("burst-one", photos(0...1))
        let second = group("burst-two", photos(1...2))
        let cells = GridDisplay(photos: photos(0...2), groups: [first, second]).cells
        let named = try #require(cells[1].group)
        #expect(named.id == first.id)
        let secondNamed = try #require(cells[2].group)
        #expect(secondNamed.id == second.id)
    }
}

/// PRD Grid and P0-11: the grid holds the current photo's cell in place, including a collapsed
/// cover that stands for the photo and a cover keyed by a refined group.
@Suite("Grid cell lookup")
struct GridCellLookupTests {
    /// Expanded display resolves a photo to its own cell.
    @Test func aPhotoResolvesToItsOwnCell() {
        let shown = photos(0...2)
        let cells = GridDisplay(photos: shown, groups: []).cells
        #expect(
            GridCellItem.cell(
                for: shown[1].id, in: cells, groups: [], shown: Set(shown.map(\.id)))
                == .photo(shown[1].id))
    }

    /// Collapsed display resolves a member to its group's cover, not to a photo cell it does
    /// not show.
    @Test func aCollapsedMemberResolvesToItsCover() {
        let shown = photos(0...2)
        let burst = group("burst-one", shown)
        let cells = GridDisplay(photos: shown, groups: [burst], display: .collapsed).cells
        #expect(
            GridCellItem.cell(
                for: shown[2].id, in: cells, groups: [burst], shown: Set(shown.map(\.id)))
                == .group(burst.id))
    }

    /// A member the filter hides has no cell, even though its group's cover is on screen.
    ///
    /// The cover stands for the group, not for every member: holding it for a hidden photo
    /// would move the visible photo the cover actually draws (PRD Grid, P0-03).
    @Test func aHiddenMemberHasNoCellEvenWhenItsCoverShows() {
        let all = photos(0...2)
        let shown = [all[1]]
        let burst = group("burst-one", all)
        let cells = GridDisplay(photos: shown, groups: [burst], display: .collapsed).cells
        #expect(
            GridCellItem.cell(
                for: all[0].id, in: cells, groups: [burst], shown: Set(shown.map(\.id))) == nil)
        #expect(
            GridCellItem.cell(
                for: shown[0].id, in: cells, groups: [burst], shown: Set(shown.map(\.id)))
                == .group(burst.id))
    }

    /// Refinement can move the photo into a group with a new key; each update resolves against
    /// its own cells and groups, so the mapping survives the key change.
    @Test func aRefinedGroupResolvesToItsNewCover() {
        let all = photos(0...2)
        let before = group("burst-one", all)
        let after = group("burst-two", Array(all[1...]))
        let shown = Set(all.map(\.id))
        let oldCells = GridDisplay(photos: all, groups: [before], display: .collapsed).cells
        let newCells = GridDisplay(photos: all, groups: [after], display: .collapsed).cells
        let photo = all[1].id
        #expect(
            GridCellItem.cell(for: photo, in: oldCells, groups: [before], shown: shown)
                == .group(before.id))
        #expect(
            GridCellItem.cell(for: photo, in: newCells, groups: [after], shown: shown)
                == .group(after.id))
    }

    /// A photo the grid does not draw has no cell.
    @Test func aHiddenPhotoHasNoCell() {
        let all = photos(0...5)
        let shown = Array(all[0...1])
        let burst = group("burst-one", Array(all[2...3]))
        let cells = GridDisplay(photos: shown, groups: [burst], display: .collapsed).cells
        let shownIDs = Set(shown.map(\.id))
        #expect(
            GridCellItem.cell(
                for: all[2].id, in: cells, groups: [burst], shown: shownIDs) == nil)
        // A photo outside the shown list and outside every group has no cell either.
        #expect(
            GridCellItem.cell(
                for: all[5].id, in: cells, groups: [burst], shown: shownIDs) == nil)
    }
}

/// The photos for one display test, in capture order, built on the ordering tests' helpers.
private func photos(_ range: ClosedRange<Int>) -> [GridPhoto] {
    range.map { index in
        photo("p\(index)", time: capture(seconds(Double(index))), fileName: "P\(index).ARW")
    }
}

/// A published group with the supplied members.
private func group(_ id: String, _ members: [GridPhoto]) -> BrowsingGroup {
    BrowsingGroup(id: GroupID(rawValue: id), members: members.map(\.id))
}
