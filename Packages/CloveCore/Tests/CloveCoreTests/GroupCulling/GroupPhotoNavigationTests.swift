import Foundation
import Testing

@testable import CloveCore

/// PRD In-group culling, comparison and elimination: moving inside one group's member order.
@Suite("Group photo navigation")
struct GroupPhotoNavigationTests {
    /// Four members: unmarked, rated, rejected and label-only, in member order.
    private let members = ["a", "b", "c", "d"].map { groupCullingPhoto($0) }
    private var group: SimilarGroup {
        groupCullingGroup("navigation", members: members)
    }
    private var marks: [PhotoIdentity: PhotoMarks] {
        groupCullingMarks([
            (members[0], PhotoMarks()),
            (members[1], PhotoMarks(rating: groupCullingRating(2))),
            (members[2], PhotoMarks(isRejected: true)),
            (members[3], PhotoMarks(label: ColourLabel(colour: .blue))),
        ])
    }

    @Test func nextAndPreviousFollowMemberOrderWithoutWrapping() {
        let navigation = GroupPhotoNavigation(group: group)

        #expect(navigation.nextPhoto(after: members[0], marks: marks) == members[1])
        #expect(navigation.nextPhoto(after: members[2], marks: marks) == members[3])
        #expect(navigation.nextPhoto(after: members[3], marks: marks) == nil)
        #expect(navigation.previousPhoto(before: members[3], marks: marks) == members[2])
        #expect(navigation.previousPhoto(before: members[1], marks: marks) == members[0])
        #expect(navigation.previousPhoto(before: members[0], marks: marks) == nil)
    }

    @Test func undecidedOnlySkipsRatedAndRejectedButKeepsALabelOnlyPhoto() {
        let navigation = GroupPhotoNavigation(group: group, undecidedOnly: true)

        // PRD In-group culling: rated and rejected photos are skipped; a label alone is
        // still undecided, so d is a stop.
        #expect(navigation.nextPhoto(after: members[0], marks: marks) == members[3])
        #expect(navigation.previousPhoto(before: members[3], marks: marks) == members[0])
        #expect(navigation.nextPhoto(after: members[1], marks: marks) == members[3])
    }

    @Test func undecidedOnlyStopsAtTheEndsInsteadOfWrapping() {
        let navigation = GroupPhotoNavigation(group: group, undecidedOnly: true)
        let onlyFirstUndecided = groupCullingMarks([
            (members[0], PhotoMarks()),
            (members[1], PhotoMarks(rating: groupCullingRating(2))),
            (members[2], PhotoMarks(isRejected: true)),
            (members[3], PhotoMarks(rating: groupCullingRating(5))),
        ])

        #expect(navigation.nextPhoto(after: members[3], marks: onlyFirstUndecided) == nil)
        #expect(navigation.previousPhoto(before: members[0], marks: onlyFirstUndecided) == nil)
    }

    @Test func nextUndecidedWrapsToTheStartOfTheGroup() {
        let navigation = GroupPhotoNavigation(group: group)

        // d is the last member; the only earlier undecided photo is a.
        #expect(navigation.nextUndecidedPhoto(after: members[3], marks: marks) == members[0])
        #expect(navigation.nextUndecidedPhoto(after: members[1], marks: marks) == members[3])
    }

    @Test func nextUndecidedReturnsNothingWhenNoneIsLeft() {
        let navigation = GroupPhotoNavigation(group: group)
        let allMarked = groupCullingMarks([
            (members[0], PhotoMarks(rating: groupCullingRating(1))),
            (members[1], PhotoMarks(rating: groupCullingRating(2))),
            (members[2], PhotoMarks(isRejected: true)),
            (members[3], PhotoMarks(rating: groupCullingRating(5))),
        ])

        // PRD In-group culling: after marking, there is no next undecided photo.
        #expect(navigation.nextUndecidedPhoto(after: members[0], marks: allMarked) == nil)

        // The current photo is never its own answer, even when it is still undecided.
        let onlyCurrentUndecided = groupCullingMarks([
            (members[0], PhotoMarks(rating: groupCullingRating(2))),
            (members[1], PhotoMarks()),
            (members[2], PhotoMarks(isRejected: true)),
            (members[3], PhotoMarks(rating: groupCullingRating(4))),
        ])
        #expect(
            navigation.nextUndecidedPhoto(after: members[1], marks: onlyCurrentUndecided) == nil)
        #expect(
            navigation.nextUndecidedPhoto(after: members[1], marks: onlyCurrentUndecided)
                != members[1])
    }

    @Test func aPhotoOutsideTheGroupHasNoNeighbours() {
        let navigation = GroupPhotoNavigation(group: group, undecidedOnly: true)
        let outsider = groupCullingPhoto("outsider")

        #expect(navigation.nextPhoto(after: outsider, marks: marks) == nil)
        #expect(navigation.previousPhoto(before: outsider, marks: marks) == nil)
        #expect(navigation.nextUndecidedPhoto(after: outsider, marks: marks) == nil)
    }
}
