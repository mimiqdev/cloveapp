import Foundation
import Testing

import CloveCore

/// PRD In-group culling, group completion, and P0-12: a complete group either stays on screen or
/// moves to the next incomplete group in grid order, and the folder's last group returns to the
/// grid.
@Suite("Group view completion")
struct GroupViewCompletionTests {
    private let first = groupCullingPhoto("a")
    private let second = groupCullingPhoto("b")
    private let third = groupCullingPhoto("c")
    private let fourth = groupCullingPhoto("d")

    private var firstGroup: BrowsingGroup {
        BrowsingGroup(id: GroupID(rawValue: "first"), members: [first, second])
    }
    private var secondGroup: BrowsingGroup {
        BrowsingGroup(id: GroupID(rawValue: "second"), members: [third, fourth])
    }

    /// Every photo rated, so both groups complete by their marks alone (PRD P0-12).
    private var allRated: [PhotoIdentity: PhotoMarks] {
        groupCullingMarks([
            (first, PhotoMarks(rating: groupCullingRating(3))),
            (second, PhotoMarks(rating: groupCullingRating(4))),
            (third, PhotoMarks(rating: groupCullingRating(5))),
            (fourth, PhotoMarks(rating: groupCullingRating(1))),
        ])
    }

    /// One group stays incomplete, so the view has nowhere to go from it.
    private var firstGroupUndecided: [PhotoIdentity: PhotoMarks] {
        groupCullingMarks([
            (first, PhotoMarks(rating: groupCullingRating(3))),
            (second, PhotoMarks()),
            (third, PhotoMarks(rating: groupCullingRating(5))),
            (fourth, PhotoMarks()),
        ])
    }

    /// A group stays incomplete while the first one completes, so it is the next group to open.
    private var secondGroupUndecided: [PhotoIdentity: PhotoMarks] {
        groupCullingMarks([
            (first, PhotoMarks(rating: groupCullingRating(3))),
            (second, PhotoMarks(isRejected: true)),
            (third, PhotoMarks(rating: groupCullingRating(5))),
        ])
    }

    /// A group with undecided photos is not complete, so there is nowhere to go
    /// (PRD In-group culling).
    @Test func anUndecidedGroupIsInProgress() async {
        let tracker = GroupCompletionTracker()
        let completion = await tracker.viewCompletion(
            after: firstGroup.id, in: [firstGroup, secondGroup], behaviour: .nextGroup,
            marks: firstGroupUndecided)

        #expect(completion == .inProgress)
    }

    /// The completed group stays when C12 says stay, even with an incomplete group after it.
    @Test func theSettingKeepsACompletedGroupOnScreen() async {
        let tracker = GroupCompletionTracker()
        let completion = await tracker.viewCompletion(
            after: firstGroup.id, in: [firstGroup, secondGroup], behaviour: .stay,
            marks: allRated)

        #expect(completion == .stay)
    }

    /// The default setting opens the next incomplete group, skipping a completed one between.
    @Test func theNextIncompleteGroupIsOpened() async {
        let tracker = GroupCompletionTracker()
        let skipped = BrowsingGroup(
            id: GroupID(rawValue: "skipped"), members: [groupCullingPhoto("e")])
        let target = BrowsingGroup(
            id: GroupID(rawValue: "target"), members: [first, second])
        var marks = allRated
        marks[groupCullingPhoto("e")] = PhotoMarks(rating: groupCullingRating(2))
        marks[first] = PhotoMarks()
        let completion = await tracker.viewCompletion(
            after: secondGroup.id, in: [secondGroup, skipped, target], behaviour: .nextGroup,
            marks: marks)

        #expect(completion == .nextGroup(target))
    }

    /// The last group has nothing after it, so a completed one returns to the grid instead of
    /// wrapping to an earlier group.
    @Test func theLastCompletedGroupReturnsToTheGrid() async {
        let tracker = GroupCompletionTracker()
        let completion = await tracker.viewCompletion(
            after: secondGroup.id, in: [firstGroup, secondGroup], behaviour: .nextGroup,
            marks: allRated)

        #expect(completion == .grid)
    }

    /// A finishing action completes a group whose photos are not all marked, and the view moves
    /// on from it (PRD In-group culling, group completion; PRD P0-12).
    @Test func aFinishingActionCompletesTheGroup() async {
        let tracker = GroupCompletionTracker()
        let marks = groupCullingMarks([
            (first, PhotoMarks(rating: groupCullingRating(3))),
            (second, PhotoMarks()),
            (third, PhotoMarks()),
            (fourth, PhotoMarks()),
        ])
        await tracker.recordFinishingAction(on: firstGroup.id)

        let completion = await tracker.viewCompletion(
            after: firstGroup.id, in: [firstGroup, secondGroup], behaviour: .nextGroup,
            marks: marks)

        #expect(completion == .nextGroup(secondGroup))
    }

    /// A group the folder does not publish has no place in the order, so it never reports a
    /// completion that would move the view somewhere else.
    @Test func anUnknownGroupIsInProgress() async {
        let tracker = GroupCompletionTracker()
        let completion = await tracker.viewCompletion(
            after: GroupID(rawValue: "gone"), in: [firstGroup, secondGroup],
            behaviour: .nextGroup, marks: allRated)

        #expect(completion == .inProgress)
    }

    /// The browsing bridge reads the same key and member order C10's rules do, which is what
    /// the group view's navigation needs (PRD In-group culling).
    @Test func theBrowsingGroupCarriesItsKeyAndMemberOrder() {
        let navigation = GroupPhotoNavigation(group: secondGroup, undecidedOnly: true)
        let marks = groupCullingMarks([
            (third, PhotoMarks()),
            (fourth, PhotoMarks()),
        ])

        #expect(navigation.group.id == secondGroup.id)
        #expect(navigation.group.members == secondGroup.members)
        #expect(navigation.nextPhoto(after: third, marks: marks) == fourth)
        #expect(navigation.nextPhoto(after: fourth, marks: marks) == nil)
    }
}
