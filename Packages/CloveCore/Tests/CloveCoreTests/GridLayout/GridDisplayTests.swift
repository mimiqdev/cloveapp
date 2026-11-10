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
        #expect(first.group == burst.id)
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
        #expect(display.cells.map(\.id) == [
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
        #expect(named.group == first.id)
        let secondNamed = try #require(cells[2].group)
        #expect(secondNamed.group == second.id)
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
