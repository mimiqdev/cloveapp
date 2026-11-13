import Foundation
import Testing

import CloveCore

/// PRD Grid's similar-group display and PRD P0-11: expanded shows every photo with the group's
/// membership and one count, collapsed shows one cover per group with its count, and grouping off
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

    @Test func collapsedCoverSkipsRejectedMembersInShownOrder() {
        let rejected = photo("reject", time: capture(seconds(0)), marks: marks(rejected: true))
        let kept = photo("kept", time: capture(seconds(1)), marks: marks(stars: 3))
        let later = photo("later", time: capture(seconds(2)))
        let members = [rejected, kept, later]
        let cells = GridDisplay(
            photos: members, groups: [group("mixed", members.reversed())], display: .collapsed
        ).cells
        #expect(cells.first?.photo.id == kept.id)
        #expect(cells.first?.isDimmed == false)
    }

    @Test func collapsedAllRejectedUsesFirstShownAndDims() {
        let members = (0..<3).map {
            photo("r\($0)", time: capture(seconds(Double($0))), marks: marks(rejected: true))
        }
        let cells = GridDisplay(
            photos: members, groups: [group("rejected", members)], display: .collapsed
        ).cells
        #expect(cells.first?.photo.id == members[0].id)
        #expect(cells.first?.isDimmed == true)
    }

    @Test func collapsedFilterUsesOnlyShownMembersForCoverAndDimming() {
        let hiddenKept = photo("hidden", time: capture(seconds(0)), marks: marks(stars: 5))
        let rejected = photo("shown", time: capture(seconds(1)), marks: marks(rejected: true))
        let burst = group("filtered", [hiddenKept, rejected])
        let cells = GridDisplay(photos: [rejected], groups: [burst], display: .collapsed).cells
        #expect(cells.first?.photo.id == rejected.id)
        #expect(cells.first?.isDimmed == true)
        #expect(cells.first?.group?.count == 2)
    }

    @Test func expandedAndUngroupedDimmingFollowsEachPhoto() {
        let members = [
            photo("r", time: capture(seconds(0)), marks: marks(rejected: true)),
            photo("k", time: capture(seconds(1))),
        ]
        for enabled in [true, false] {
            let cells = GridDisplay(
                photos: members, groups: [group("pair", members)], groupsEnabled: enabled
            ).cells
            #expect(cells.map(\.isDimmed) == [true, false])
        }
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

    /// A photo that two groups name carries the first published group.
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

    /// An expanded group keeps its members' own cells, so the grid holds the member on screen
    /// in place rather than resolving it to the cover it no longer draws (owner decision, #225).
    @Test func anExpandedMemberResolvesToItsOwnCell() {
        let all = photos(0...2)
        let burst = group("burst", all)
        let grid = GridDisplay(
            photos: all, groups: [burst], display: .collapsed, expandedGroup: burst.id)
        let shown = Set(all.map(\.id))
        for member in all {
            #expect(
                GridCellItem.cell(
                    for: member.id, in: grid.cells, groups: [burst], shown: shown)
                    == .photo(member.id))
        }
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

/// Owner decision, #225: the Duo's split expands the photo's group in place, so its members
/// draw at the group's folder position while the surrounding photos and other collapsed groups
/// keep theirs. These tests pin the runs the grid draws from, which is what the collection view
/// turns into a header, a shared surface and cells.
@Suite("Grid sections")
struct GridSectionTests {
    /// A grid without an expanded group is one run, so the iPhone, iPad and folded Duo grids keep
    /// exactly the cells and the single run they had.
    @Test func aPlainGridIsOneRun() {
        let burst = group("burst-one", photos(1...2))
        for display in [GridGroupDisplay.expanded, .collapsed] {
            let grid = GridDisplay(photos: photos(0...3), groups: [burst], display: display)
            #expect(grid.sections.map(\.id) == [.photos(0)])
            #expect(grid.sections[0].cells == grid.cells)
            #expect(grid.sections[0].expandedGroup == nil)
        }
    }

    /// The expanded group replaces its cover, at the group's own place in the folder, with its
    /// shown members. The photos and the other groups around it stay where they were.
    @Test func theExpandedGroupDrawsAtItsCoverPosition() throws {
        let all = photos(0...5)
        let expanded = group("expanded", [all[1], all[3]])
        let other = group("other", [all[4], all[5]])
        let grid = GridDisplay(
            photos: all, groups: [expanded, other], display: .collapsed,
            expandedGroup: expanded.id)
        #expect(
            grid.sections.map(\.id) == [.photos(0), .group(expanded.id), .photos(1)])
        #expect(grid.sections[0].cells.map(\.id) == [.photo(all[0].id)])
        #expect(grid.sections[1].cells.map(\.id) == [.photo(all[1].id), .photo(all[3].id)])
        #expect(
            grid.sections[2].cells.map(\.id) == [.photo(all[2].id), .group(other.id)])
        // The expanded members carry no badge and no cover: the run's header names the group.
        #expect(grid.sections[1].cells.allSatisfy { $0.group == nil })
        let cover = try #require(grid.sections[2].cells.last?.group)
        #expect(cover.isCover)
        #expect(cover.count == 2)
    }

    /// A group whose members are scattered in the folder draws as one contiguous block at its
    /// first shown member, and the standalone photo between them follows the block. That is the
    /// position the collapsed cover already took, so the expansion changes one cell, not the
    /// folder's arrangement.
    @Test func theExpandedGroupIsContiguousAtItsFirstMember() {
        let all = photos(0...3)
        let burst = group("burst", [all[0], all[2]])
        let grid = GridDisplay(
            photos: all, groups: [burst], display: .collapsed, expandedGroup: burst.id)
        #expect(
            grid.sections.map(\.id) == [.group(burst.id), .photos(1)])
        #expect(
            grid.sections[0].cells.map(\.id) == [.photo(all[0].id), .photo(all[2].id)])
        #expect(grid.sections[1].cells.map(\.id) == [.photo(all[1].id), .photo(all[3].id)])
    }

    /// A filter narrows the expanded group the same way it narrows a cover: only the shown
    /// members draw, and the run's member count is what the block can show.
    @Test func aFilterNarrowsTheExpandedGroup() {
        let all = photos(0...3)
        let burst = group("burst", all)
        let shown = [all[0], all[2], all[3]]
        let grid = GridDisplay(
            photos: shown, groups: [burst], display: .collapsed, expandedGroup: burst.id)
        let run = grid.sections.first { $0.expandedGroup == burst.id }
        #expect(run?.cells.map(\.id) == [.photo(all[0].id), .photo(all[2].id), .photo(all[3].id)])
        #expect(run?.cells.count == 3)
    }

    /// A group the filter hides has no cover either, so there is nothing to expand: the grid
    /// stays one run instead of drawing an empty header.
    @Test func aHiddenGroupIsNotExpanded() {
        let all = photos(0...4)
        let burst = group("burst", [all[3], all[4]])
        let shown = Array(all[0...2])
        let grid = GridDisplay(
            photos: shown, groups: [burst], display: .collapsed, expandedGroup: burst.id)
        #expect(grid.sections.map(\.id) == [.photos(0)])
        #expect(grid.cells.map(\.id) == shown.map { .photo($0.id) })
    }

    /// An unknown key, such as a group the folder no longer publishes, expands nothing.
    @Test func anUnknownGroupExpandsNothing() {
        let all = photos(0...3)
        let burst = group("burst", [all[1], all[2]])
        let grid = GridDisplay(
            photos: all, groups: [burst], display: .collapsed,
            expandedGroup: GroupID(rawValue: "gone"))
        #expect(grid.sections.map(\.id) == [.photos(0)])
        #expect(
            grid.cells.map(\.id) == [.photo(all[0].id), .group(burst.id), .photo(all[3].id)])
    }

    /// Expanded display already draws every member and has no cover to replace, so the split's
    /// expansion changes nothing there.
    @Test func expandedDisplayIgnoresTheExpansion() {
        let burst = group("burst", photos(1...2))
        let plain = GridDisplay(photos: photos(0...3), groups: [burst], display: .expanded)
        let expanded = GridDisplay(
            photos: photos(0...3), groups: [burst], display: .expanded,
            expandedGroup: burst.id)
        #expect(expanded.sections.map(\.id) == [.photos(0)])
        #expect(expanded.cells == plain.cells)
    }

    /// Grouping off leaves one run with no marks, whichever group the split names.
    @Test func groupingOffLeavesOnePlainRun() {
        let burst = group("burst", photos(1...2))
        let grid = GridDisplay(
            photos: photos(0...3), groups: [burst], groupsEnabled: false, display: .collapsed,
            expandedGroup: burst.id)
        #expect(grid.sections.map(\.id) == [.photos(0)])
        #expect(grid.cells.allSatisfy { $0.group == nil })
    }

    /// An empty grid keeps one run, so the collection view always has a section to draw.
    @Test func anEmptyGridKeepsOneRun() {
        let grid = GridDisplay(photos: [], groups: [], display: .collapsed)
        #expect(grid.sections.map(\.id) == [.photos(0)])
        #expect(grid.cells.isEmpty)
    }

    /// The expanded group is the only run drawn with a header, and the folder's runs never are.
    @Test func onlyTheGroupRunNamesAGroup() {
        let all = photos(0...4)
        let burst = group("burst", [all[1], all[2], all[3]])
        let grid = GridDisplay(
            photos: all, groups: [burst], display: .collapsed, expandedGroup: burst.id)
        #expect(grid.sections.compactMap(\.expandedGroup) == [burst.id])
        #expect(grid.sections.filter { $0.expandedGroup == nil }.count == 2)
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
