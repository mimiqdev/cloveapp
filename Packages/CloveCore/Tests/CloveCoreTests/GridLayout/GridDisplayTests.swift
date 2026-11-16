import Foundation
import Testing

import CloveCore

/// Issue #304 decisions 1 & 2: Similar groups On collapses visible groups with 2+ members using
/// the unified Representative Photo, visible-member count/peeking/dimming, and standalone behavior
/// when fewer than 2 members are visible; Similar groups Off leaves every photo its own flat cell.
@Suite("Grid display cells")
struct GridDisplayTests {
    /// Collapsed display keeps one cover per active (2+ visible) group and treats 1-visible groups
    /// as standalone cells.
    @Test func activeGroupsCollapseAndSingleVisibleGroupBecomesStandalone() throws {
        let first = group("burst-one", photos(0...1))
        let singleton = group("burst-two", photos(3...3))
        let display = GridDisplay(photos: photos(0...3), groups: [first, singleton])
        #expect(
            display.cells.map(\.id) == [
                .group(first.id), .photo(photos(2...2)[0].id), .photo(photos(3...3)[0].id),
            ])
        let cover = try #require(display.cells.first?.group)
        #expect(cover.isCover)
        #expect(cover.showsCount)
        #expect(cover.count == 2)
        #expect(display.cells.first?.photo == photos(0...1)[0])
        #expect(display.cells[2].group == nil)
    }

    /// A filter that hides one of three members lowers the stack count to 2 and draws only visible
    /// members.
    @Test func aFilteredGroupCountsOnlyVisibleMembers() throws {
        let burst = group("burst-one", photos(0...2))
        let display = GridDisplay(photos: Array(photos(0...2).dropFirst()), groups: [burst])
        #expect(display.cells.count == 1)
        #expect(display.cells[0].id == .group(burst.id))
        #expect(display.cells[0].photo == photos(0...2)[1])
        #expect(display.cells[0].group?.count == 2)
    }

    /// Under a strict filter leaving only 1 visible member, the group renders as a standalone cell.
    @Test func aGroupNarrowedToOneVisibleMemberRendersStandalone() {
        let burst = group("burst-one", photos(0...2))
        let display = GridDisplay(photos: [photos(0...2)[1]], groups: [burst])
        #expect(display.cells.count == 1)
        #expect(display.cells[0].id == .photo(photos(0...2)[1].id))
        #expect(display.cells[0].group == nil)
    }

    /// Cover follows unified Representative Photo rule in `photos` order: highest rated beats
    /// labelled, labelled beats unmarked, unmarked beats rejected, ties broken by first visible.
    @Test func collapsedCoverUsesUnifiedRepresentativePriorityRule() {
        let rejected = photo("reject", time: capture(seconds(0)), marks: marks(rejected: true))
        let kept = photo("kept", time: capture(seconds(1)), marks: marks(stars: 3))
        let later = photo("later", time: capture(seconds(2)))
        let members = [rejected, kept, later]
        let cells = GridDisplay(
            photos: members, groups: [group("mixed", members.reversed())]
        ).cells
        #expect(cells.first?.photo.id == kept.id)
        #expect(cells.first?.isDimmed == false)

        let rated5 = photo("r5", time: capture(seconds(3)), marks: marks(stars: 5))
        let labelledRed = photo(
            "red", time: capture(seconds(0)), marks: PhotoMarks(label: ColourLabel(colour: .red)))
        let cellsHighest = GridDisplay(
            photos: [rejected, labelledRed, kept, rated5],
            groups: [group("prio", [rejected, labelledRed, kept, rated5])]
        ).cells
        #expect(cellsHighest.first?.photo.id == rated5.id)
    }

    @Test func collapsedAllRejectedUsesFirstShownAndDims() {
        let members = (0..<3).map {
            photo("r\($0)", time: capture(seconds(Double($0))), marks: marks(rejected: true))
        }
        let cells = GridDisplay(photos: members, groups: [group("rejected", members)]).cells
        #expect(cells.first?.photo.id == members[0].id)
        #expect(cells.first?.isDimmed == true)
    }

    @Test func collapsedFilterUsesOnlyShownMembersForCoverAndDimming() {
        let hiddenKept = photo("hidden", time: capture(seconds(0)), marks: marks(stars: 5))
        let rejected1 = photo("shown1", time: capture(seconds(1)), marks: marks(rejected: true))
        let rejected2 = photo("shown2", time: capture(seconds(2)), marks: marks(rejected: true))
        let burst = group("filtered", [hiddenKept, rejected1, rejected2])
        let cells = GridDisplay(photos: [rejected1, rejected2], groups: [burst]).cells
        #expect(cells.first?.id == .group(burst.id))
        #expect(cells.first?.photo.id == rejected1.id)
        #expect(cells.first?.isDimmed == true)
        #expect(cells.first?.group?.count == 2)
    }

    @Test func ungroupedAndFlatDimmingFollowsEachPhoto() {
        let members = [
            photo("r", time: capture(seconds(0)), marks: marks(rejected: true)),
            photo("k", time: capture(seconds(1))),
        ]
        let cells = GridDisplay(
            photos: members, groups: [group("pair", members)], groupsEnabled: false
        ).cells
        #expect(cells.map(\.isDimmed) == [true, false])
    }

    /// A group with no shown member has no cover, because a cover always names a drawn photo.
    @Test func aGroupWithNoShownMemberHasNoCover() {
        let burst = group("burst-one", photos(2...3))
        let display = GridDisplay(photos: photos(0...1), groups: [burst])
        #expect(display.cells.map(\.id) == photos(0...1).map { .photo($0.id) })
    }

    /// Grouping off hides every group mark (PRD Grid, PRD P0-11, issue #304 Decision 1).
    @Test func groupingOffLeavesEveryPhotoItsOwnCell() {
        let burst = group("burst-one", photos(0...1))
        let cells = GridDisplay(
            photos: photos(0...3), groups: [burst], groupsEnabled: false
        ).cells
        #expect(cells.map(\.id) == photos(0...3).map { .photo($0.id) })
        #expect(cells.allSatisfy { $0.group == nil })
    }

    /// A photo that two groups name stays in the first published group; the second group drops
    /// below 2 visible members so its remaining photo becomes standalone.
    @Test func theFirstPublishedGroupClaimsOverlappingPhoto() throws {
        let all = photos(0...3)
        let first = group("burst-one", [all[0], all[1]])
        let second = group("burst-two", [all[1], all[2], all[3]])
        let cells = GridDisplay(photos: all, groups: [first, second]).cells
        #expect(cells.map(\.id) == [.group(first.id), .group(second.id)])
        #expect(cells[0].group?.count == 2)
        #expect(cells[1].group?.count == 2)
    }

    @Test func collapsedCoverCarriesUpToTwoPeekingMembersInGridOrder() throws {
        let pair = group("pair", photos(0...1))
        let quad = group("quad", photos(2...5))
        let cells = GridDisplay(photos: photos(0...5), groups: [pair, quad]).cells
        #expect(cells[0].group?.peekingPhotos == [photos(0...5)[1].id])
        #expect(
            cells[1].group?.peekingPhotos == [photos(0...5)[3].id, photos(0...5)[4].id])
    }

    @Test func collapsedCoverExcludesRejectedSkippedCoverFromPeekingPhotos() throws {
        let rejected = photo("r", time: capture(seconds(0)), marks: marks(rejected: true))
        let kept = photo("k", time: capture(seconds(1)), marks: marks(stars: 3))
        let third = photo("t", time: capture(seconds(2)))
        let members = [rejected, kept, third]
        let cells = GridDisplay(photos: members, groups: [group("mixed", members)]).cells
        #expect(cells[0].photo.id == kept.id)
        #expect(cells[0].group?.peekingPhotos == [rejected.id, third.id])
    }

    @Test func collapsedFilteredCoverNeverFallsBackToHiddenGroupMembersForPeeking() throws {
        let members = photos(0...2)
        let burst = group("burst", members)
        let cells = GridDisplay(photos: [members[0], members[2]], groups: [burst]).cells
        #expect(cells[0].group?.count == 2)
        #expect(cells[0].group?.peekingPhotos == [members[2].id])
    }
}

/// PRD Grid and P0-11: the grid holds the current photo's cell in place, including a collapsed
/// cover that stands for the photo and a cover keyed by a refined group.
@Suite("Grid cell lookup")
struct GridCellLookupTests {
    /// Standalone cell resolves a photo to its own cell.
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
        let cells = GridDisplay(photos: shown, groups: [burst]).cells
        #expect(
            GridCellItem.cell(
                for: shown[2].id, in: cells, groups: [burst], shown: Set(shown.map(\.id)))
                == .group(burst.id))
    }

    /// A group narrowed to one visible member resolves that member to its own photo cell.
    @Test func aSingleVisibleMemberResolvesToItsOwnCell() {
        let all = photos(0...2)
        let shown = [all[1]]
        let burst = group("burst-one", all)
        let cells = GridDisplay(photos: shown, groups: [burst]).cells
        #expect(
            GridCellItem.cell(
                for: all[0].id, in: cells, groups: [burst], shown: Set(shown.map(\.id))) == nil)
        #expect(
            GridCellItem.cell(
                for: shown[0].id, in: cells, groups: [burst], shown: Set(shown.map(\.id)))
                == .photo(shown[0].id))
    }

    /// Refinement can move the photo into a group with a new key; each update resolves against
    /// its own cells and groups, so the mapping survives the key change.
    @Test func aRefinedGroupResolvesToItsNewCover() {
        let all = photos(0...2)
        let before = group("burst-one", all)
        let after = group("burst-two", Array(all[1...]))
        let shown = Set(all.map(\.id))
        let oldCells = GridDisplay(photos: all, groups: [before]).cells
        let newCells = GridDisplay(photos: all, groups: [after]).cells
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
        let grid = GridDisplay(photos: all, groups: [burst], expandedGroup: burst.id)
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
        let cells = GridDisplay(photos: shown, groups: [burst]).cells
        let shownIDs = Set(shown.map(\.id))
        #expect(
            GridCellItem.cell(
                for: all[2].id, in: cells, groups: [burst], shown: shownIDs) == nil)
        #expect(
            GridCellItem.cell(
                for: all[5].id, in: cells, groups: [burst], shown: shownIDs) == nil)
    }
}

/// Owner decision, #225 & #304 Decision 6: the split expands `expandedGroup` in place, so its
/// visible members draw at the group's folder position while surrounding photos and other collapsed
/// groups keep theirs.
@Suite("Grid sections")
struct GridSectionTests {
    /// A grid without an expanded group is one run.
    @Test func aPlainGridIsOneRun() {
        let burst = group("burst-one", photos(1...2))
        let grid = GridDisplay(photos: photos(0...3), groups: [burst])
        #expect(grid.sections.map(\.id) == [.photos(0)])
        #expect(grid.sections[0].cells == grid.cells)
        #expect(grid.sections[0].expandedGroup == nil)
    }

    /// The expanded group replaces its cover, at the group's own place in the folder, with its
    /// shown members. The photos and the other groups around it stay where they were.
    @Test func theExpandedGroupDrawsAtItsCoverPosition() throws {
        let all = photos(0...5)
        let expanded = group("expanded", [all[1], all[3]])
        let other = group("other", [all[4], all[5]])
        let grid = GridDisplay(
            photos: all, groups: [expanded, other], expandedGroup: expanded.id)
        #expect(
            grid.sections.map(\.id) == [.photos(0), .group(expanded.id), .photos(1)])
        #expect(grid.sections[0].cells.map(\.id) == [.photo(all[0].id)])
        #expect(grid.sections[1].cells.map(\.id) == [.photo(all[1].id), .photo(all[3].id)])
        #expect(
            grid.sections[2].cells.map(\.id) == [.photo(all[2].id), .group(other.id)])
        #expect(
            grid.sections[1].cells.allSatisfy {
                $0.group?.id == expanded.id && $0.group?.showsCount == false
                    && $0.group?.isCover == false
            })
        let cover = try #require(grid.sections[2].cells.last?.group)
        #expect(cover.isCover)
        #expect(cover.count == 2)
    }

    /// A group whose members are scattered in the folder draws as one contiguous block at its
    /// first shown member, and the standalone photo between them follows the block.
    @Test func theExpandedGroupIsContiguousAtItsFirstMember() {
        let all = photos(0...3)
        let burst = group("burst", [all[0], all[2]])
        let grid = GridDisplay(photos: all, groups: [burst], expandedGroup: burst.id)
        #expect(grid.sections.map(\.id) == [.group(burst.id), .photos(1)])
        #expect(grid.sections[0].cells.map(\.id) == [.photo(all[0].id), .photo(all[2].id)])
        #expect(grid.sections[1].cells.map(\.id) == [.photo(all[1].id), .photo(all[3].id)])
    }

    /// A filter narrows the expanded group the same way it narrows a cover: only the shown
    /// members draw, and the run's member count is what the block can show.
    @Test func aFilterNarrowsTheExpandedGroup() {
        let all = photos(0...3)
        let burst = group("burst", all)
        let shown = [all[0], all[2], all[3]]
        let grid = GridDisplay(photos: shown, groups: [burst], expandedGroup: burst.id)
        let run = grid.sections.first { $0.expandedGroup == burst.id }
        #expect(run?.cells.map(\.id) == [.photo(all[0].id), .photo(all[2].id), .photo(all[3].id)])
        #expect(run?.cells.count == 3)
    }

    /// A group narrowed below 2 visible members cannot remain expanded.
    @Test func aGroupNarrowedToOneVisibleMemberIsNotExpanded() {
        let all = photos(0...3)
        let burst = group("burst", Array(all[1...3]))
        let shown = [all[0], all[2]]
        let grid = GridDisplay(photos: shown, groups: [burst], expandedGroup: burst.id)
        #expect(grid.sections.map(\.id) == [.photos(0)])
        #expect(grid.cells.map(\.id) == shown.map { .photo($0.id) })
        #expect(grid.cells.allSatisfy { $0.group == nil })
    }

    /// An unknown key, such as a group the folder no longer publishes, expands nothing.
    @Test func anUnknownGroupExpandsNothing() {
        let all = photos(0...3)
        let burst = group("burst", [all[1], all[2]])
        let grid = GridDisplay(
            photos: all, groups: [burst], expandedGroup: GroupID(rawValue: "gone"))
        #expect(grid.sections.map(\.id) == [.photos(0)])
        #expect(
            grid.cells.map(\.id) == [.photo(all[0].id), .group(burst.id), .photo(all[3].id)])
    }

    /// Grouping off leaves one run with no marks, whichever group the split names.
    @Test func groupingOffLeavesOnePlainRun() {
        let burst = group("burst", photos(1...2))
        let grid = GridDisplay(
            photos: photos(0...3), groups: [burst], groupsEnabled: false, expandedGroup: burst.id)
        #expect(grid.sections.map(\.id) == [.photos(0)])
        #expect(grid.cells.allSatisfy { $0.group == nil })
    }

    /// An empty grid keeps one run, so the collection view always has a section to draw.
    @Test func anEmptyGridKeepsOneRun() {
        let grid = GridDisplay(photos: [], groups: [])
        #expect(grid.sections.map(\.id) == [.photos(0)])
        #expect(grid.cells.isEmpty)
    }

    /// The expanded group is the only run drawn with a header, and the folder's runs never are.
    @Test func onlyTheGroupRunNamesAGroup() {
        let all = photos(0...4)
        let burst = group("burst", [all[1], all[2], all[3]])
        let grid = GridDisplay(photos: all, groups: [burst], expandedGroup: burst.id)
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
