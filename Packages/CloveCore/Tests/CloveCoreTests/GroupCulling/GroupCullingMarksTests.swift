import Testing

@testable import CloveCore

/// PRD In-group culling and PRD P0-12: undecided, marked and unmarked, and the header count.
@Suite("Group culling marks")
struct GroupCullingMarksTests {
    @Test func undecidedAndUnmarkedDifferForAColourLabel() {
        let unmarked = PhotoMarks()
        let labelOnly = PhotoMarks(label: ColourLabel(colour: .red))
        let rated = PhotoMarks(rating: groupCullingRating(3))
        let rejected = PhotoMarks(rating: .rejected)

        #expect(unmarked.isUndecided)
        #expect(unmarked.isUnmarked)
        #expect(!unmarked.isMarked)

        // PRD In-group culling: a colour label does not decide a photo.
        #expect(labelOnly.isUndecided)
        #expect(!labelOnly.isUnmarked)
        #expect(labelOnly.isMarked)

        #expect(!rated.isUndecided)
        #expect(!rated.isUnmarked)
        #expect(rated.isMarked)

        #expect(!rejected.isUndecided)
        #expect(!rejected.isUnmarked)
        #expect(rejected.isMarked)
    }

    @Test func undecidedCountsLabelOnlyRatedRejectedAndUnmarkedPhotos() {
        let count = GroupUndecidedCount([
            PhotoMarks(),
            PhotoMarks(label: ColourLabel(colour: .green)),
            PhotoMarks(rating: groupCullingRating(2)),
            PhotoMarks(rating: .rejected),
        ])

        #expect(count.undecided == 2)
        #expect(count.total == 4)
        #expect(!count.isCompleteByMarks)
        #expect(count.headerText == "Undecided 2 / 4 total")
    }

    @Test func aMemberWithoutAMarksEntryReadsAsUndecided() {
        let group = groupCullingGroup(
            "missing", members: [groupCullingPhoto("a"), groupCullingPhoto("b")])
        let marked = GroupUndecidedCount(
            group: group,
            marks: [group.members[0]: PhotoMarks(rating: groupCullingRating(4))])

        #expect(marked.undecided == 1)
        #expect(marked.total == 2)
        #expect(marked.headerText == "Undecided 1 / 2 total")
    }

    @Test func aGroupIsCompleteByMarksOnlyWhenEveryMemberIsRatedOrRejected() {
        let members = [groupCullingPhoto("a"), groupCullingPhoto("b"), groupCullingPhoto("c")]
        let group = groupCullingGroup("complete", members: members)
        let partly = groupCullingMarks([
            (members[0], PhotoMarks(rating: groupCullingRating(3))),
            (members[1], PhotoMarks(rating: .rejected)),
            (members[2], PhotoMarks(label: ColourLabel(colour: .purple))),
        ])

        // PRD In-group culling, group completion: a label is not a rating and not a Reject.
        #expect(!GroupUndecidedCount(group: group, marks: partly).isCompleteByMarks)

        let complete = groupCullingMarks([
            (members[0], PhotoMarks(rating: groupCullingRating(3))),
            (members[1], PhotoMarks(rating: .rejected)),
            (members[2], PhotoMarks(rating: groupCullingRating(1))),
        ])
        let count = GroupUndecidedCount(group: group, marks: complete)
        #expect(count.undecided == 0)
        #expect(count.isCompleteByMarks)
    }
}
