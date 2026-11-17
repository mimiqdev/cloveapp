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

    /// Group Focus keeps its members' own cells, so the grid holds the member on screen in place
    /// instead of resolving it to a cover it no longer draws (issue #309).
    @Test func aFocusedMemberResolvesToItsOwnCell() throws {
        let all = photos(0...2)
        let burst = group("burst", all)
        let active = try #require(
            DetailTimeline(photos: all, groups: [burst]).activeGroup(with: burst.id))
        let grid = GridDisplay(focusing: active)
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

/// Issue #304 decision 6 and issue #309: the grid draws one Detail level at a time — the full
/// folder's own run, or Group Focus's single run of the active group's visible members.
@Suite("Grid sections")
struct GridSectionTests {
    /// A grid without Group Focus is one run of the folder's own cells.
    @Test func aTimelineGridIsOneFolderRun() {
        let burst = group("burst-one", photos(1...2))
        let grid = GridDisplay(photos: photos(0...3), groups: [burst])
        #expect(grid.sections.map(\.id) == [.photos])
        #expect(grid.sections[0].cells == grid.cells)
        #expect(grid.sections[0].expandedGroup == nil)
    }

    /// Group Focus draws only the focused group's visible members, in the active order Focus View
    /// uses, and nothing else from the folder.
    @Test func groupFocusDrawsOnlyTheFocusedGroupsVisibleMembers() throws {
        let all = photos(0...6)
        let focused = group("focused", [all[1], all[3], all[5]])
        let other = group("other", [all[2], all[4]])
        let timeline = DetailTimeline(photos: all, groups: [focused, other])
        let active = try #require(timeline.activeGroup(with: focused.id))
        let grid = GridDisplay(focusing: active)
        #expect(grid.sections.map(\.id) == [.group(focused.id)])
        #expect(grid.sections[0].expandedGroup == focused.id)
        #expect(grid.cells.map(\.id) == [.photo(all[1].id), .photo(all[3].id), .photo(all[5].id)])
        #expect(active.visibleMembers.map(\.id) == grid.cells.map(\.photo.id))
    }

    /// The focused run marks its members as the group's, without a count badge or cover, and dims
    /// only the members that are rejected.
    @Test func focusedMembersCarryTheGroupWithoutACountBadge() throws {
        let kept = photo("kept", time: capture(seconds(0)))
        let rejected = photo(
            "rejected", time: capture(seconds(1)), marks: marks(rejected: true))
        let members = [kept, rejected]
        let burst = group("burst", members)
        let active = try #require(
            DetailTimeline(photos: members, groups: [burst]).activeGroup(with: burst.id))
        let grid = GridDisplay(focusing: active)
        #expect(
            grid.cells.allSatisfy {
                $0.group?.id == burst.id && $0.group?.showsCount == false
                    && $0.group?.isCover == false
            })
        #expect(grid.cells.map(\.isDimmed) == [false, true])
    }

    /// Opening another group shows only that group's visible members.
    @Test func focusingAnotherGroupShowsOnlyItsMembers() throws {
        let all = photos(0...5)
        let first = group("first", [all[0], all[1]])
        let second = group("second", [all[3], all[4], all[5]])
        let timeline = DetailTimeline(photos: all, groups: [first, second])
        let secondActive = try #require(timeline.activeGroup(with: second.id))
        let grid = GridDisplay(focusing: secondActive)
        #expect(grid.cells.map(\.id) == [.photo(all[3].id), .photo(all[4].id), .photo(all[5].id)])
        #expect(!grid.cells.contains { $0.group?.id == first.id })
        #expect(!grid.cells.contains { $0.photo.id == all[0].id || $0.photo.id == all[2].id })
    }

    /// A filter narrows the focused run the same way it narrows the group everywhere: only the
    /// members the active filter shows, in the active order.
    @Test func aFilterNarrowsTheFocusedRun() throws {
        let all = photos(0...3)
        let burst = group("burst", all)
        let shown = [all[0], all[2], all[3]]
        let active = try #require(
            DetailTimeline(photos: shown, groups: [burst]).activeGroup(with: burst.id))
        let grid = GridDisplay(focusing: active)
        #expect(grid.cells.map(\.id) == [.photo(all[0].id), .photo(all[2].id), .photo(all[3].id)])
    }

    /// A group narrowed below two visible members has no Group Focus at all, so the folder's run
    /// stays the only level (issue #304, decision 2).
    @Test func aGroupNarrowedToOneVisibleMemberCannotBeFocused() {
        let all = photos(0...3)
        let burst = group("burst", Array(all[1...3]))
        let shown = [all[0], all[2]]
        let timeline = DetailTimeline(photos: shown, groups: [burst])
        #expect(timeline.activeGroup(with: burst.id) == nil)
        let grid = GridDisplay(photos: shown, groups: [burst])
        #expect(grid.sections.map(\.id) == [.photos])
        #expect(grid.cells.map(\.id) == shown.map { .photo($0.id) })
    }

    /// Grouping off leaves one folder run with no marks.
    @Test func groupingOffLeavesOnePlainRun() {
        let burst = group("burst", photos(1...2))
        let grid = GridDisplay(
            photos: photos(0...3), groups: [burst], groupsEnabled: false)
        #expect(grid.sections.map(\.id) == [.photos])
        #expect(grid.cells.allSatisfy { $0.group == nil })
    }

    /// An empty grid keeps one run, so the collection view always has a section to draw.
    @Test func anEmptyGridKeepsOneRun() {
        let grid = GridDisplay(photos: [], groups: [])
        #expect(grid.sections.map(\.id) == [.photos])
        #expect(grid.cells.isEmpty)
    }

    /// Only Group Focus's run is drawn with a header; the folder's run never is.
    @Test func onlyTheFocusedRunNamesAGroup() throws {
        let all = photos(0...4)
        let burst = group("burst", [all[1], all[2], all[3]])
        let timeline = DetailTimeline(photos: all, groups: [burst])
        let active = try #require(timeline.activeGroup(with: burst.id))
        let grid = GridDisplay(focusing: active)
        #expect(grid.sections.compactMap(\.expandedGroup) == [burst.id])
        #expect(grid.sections.filter { $0.expandedGroup == nil }.isEmpty)
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
