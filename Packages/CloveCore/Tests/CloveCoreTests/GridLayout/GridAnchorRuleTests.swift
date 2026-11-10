import Foundation
import Testing

import CloveCore

/// PRD Grid and P0-11: a similar-group refinement, a streaming scan, arriving times, a filter or
/// an order change must not move the photo the user is looking at. These tests pin the rule the
/// grid uses to hold that photo in place.
@Suite("Grid anchor rule")
struct GridAnchorRuleTests {
    /// Photos inserted before the anchor: the anchor's index moves, the same cell stays in place.
    @Test func insertionBeforeTheAnchorReturnsItsNewIndex() {
        let previous = ["a", "b", "c"]
        let cells = ["x", "y", "a", "b", "c"]
        #expect(GridAnchorRule.newIndex(of: "b", previous: previous, in: cells) == 3)
        #expect(GridAnchorRule.newIndex(of: "a", previous: previous, in: cells) == 2)
    }

    /// Photos inserted after the anchor, including a streaming scan's tail, leave it where it was.
    @Test func insertionAfterTheAnchorKeepsItsIndex() {
        let previous = ["a", "b"]
        let cells = ["a", "b", "x", "y"]
        #expect(GridAnchorRule.newIndex(of: "a", previous: previous, in: cells) == 0)
        #expect(GridAnchorRule.newIndex(of: "b", previous: previous, in: cells) == 1)
    }

    /// Capture times arriving reorder photos; the anchor's own new index is what the view holds.
    @Test func reorderingReturnsTheAnchorsNewIndex() {
        let previous = ["a", "b", "c", "d"]
        let cells = ["c", "a", "d", "b"]
        #expect(GridAnchorRule.newIndex(of: "b", previous: previous, in: cells) == 3)
        #expect(GridAnchorRule.newIndex(of: "a", previous: previous, in: cells) == 1)
    }

    /// A group refining away the anchor's collapsed cover falls to the next old cell that survives.
    @Test func aGroupChangeFallsToTheNextSurvivingCell() {
        let first = GroupID(rawValue: "burst-one")
        let second = GroupID(rawValue: "burst-two")
        let solo = PhotoIdentity(
            folderID: orderingFolder, relativeFolderPath: "DCIM/100CAM", stem: "solo")
        let previous: [GridCellItem.ID] = [.group(first), .group(second), .photo(solo)]
        // Refinement merged the first burst into the second, so its own cover is gone.
        let cells: [GridCellItem.ID] = [.group(second), .photo(solo)]
        #expect(GridAnchorRule.newIndex(of: .group(first), previous: previous, in: cells) == 0)
    }

    /// A filter that hides the anchor holds the view on the old cell just after it.
    @Test func aFilteredOutAnchorFallsToTheFollowingOldCell() {
        let previous = ["a", "b", "c"]
        let cells = ["a", "c"]
        #expect(GridAnchorRule.newIndex(of: "b", previous: previous, in: cells) == 1)
    }

    /// A removed anchor at the end of the list falls back to the old cell before it.
    @Test func aRemovedLastAnchorFallsToThePrecedingOldCell() {
        let previous = ["a", "b", "c"]
        let cells = ["a", "b"]
        #expect(GridAnchorRule.newIndex(of: "c", previous: previous, in: cells) == 1)
    }

    /// A removed anchor in the middle searches forward, then backward, then further out.
    @Test func aRemovedAnchorSearchesOutwardWithForwardFirst() {
        let previous = ["a", "b", "c", "d", "e"]
        #expect(GridAnchorRule.newIndex(of: "c", previous: previous, in: ["a", "b", "d"]) == 2)
        #expect(GridAnchorRule.newIndex(of: "c", previous: previous, in: ["a", "e"]) == 1)
        #expect(GridAnchorRule.newIndex(of: "c", previous: previous, in: ["b", "e"]) == 0)
    }

    /// Nothing to hold, or nothing that survives, leaves the caller starting from the top.
    @Test func noAnchorOrNoSurvivorReturnsNothing() {
        #expect(GridAnchorRule.newIndex(of: nil, previous: ["a"], in: ["a"]) == nil)
        #expect(GridAnchorRule.newIndex(of: "z", previous: ["a"], in: ["a"]) == nil)
        #expect(GridAnchorRule.newIndex(of: "a", previous: ["a"], in: ["z"]) == nil)
        // An anchor that was not in the old list has no old place to keep.
        #expect(GridAnchorRule.newIndex(of: "a", previous: [], in: ["a"]) == nil)
    }

    /// The same rule works on the cell identities the collection view tracks, not just on strings.
    @Test func cellIdentitiesHoldTheirPlace() {
        let first = PhotoIdentity(
            folderID: orderingFolder, relativeFolderPath: "DCIM/100CAM", stem: "one")
        let second = PhotoIdentity(
            folderID: orderingFolder, relativeFolderPath: "DCIM/100CAM", stem: "two")
        let previous: [GridCellItem.ID] = [.photo(first), .photo(second)]
        let cells: [GridCellItem.ID] = [.photo(second), .photo(first)]
        #expect(GridAnchorRule.newIndex(of: .photo(first), previous: previous, in: cells) == 1)
    }
}
