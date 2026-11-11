import Testing

@testable import CloveCore

/// PRD In-group culling and PRD P0-12: undecided, marked and unmarked, and the header count.
@Suite("Group culling marks")
struct GroupCullingMarksTests {
    @Test func aRatingLabelOrRejectDecidesAPhoto() {
        let unmarked = PhotoMarks()
        let labelOnly = PhotoMarks(label: ColourLabel(colour: .red))
        let rated = PhotoMarks(rating: groupCullingRating(3))
        let rejected = PhotoMarks(rating: .rejected)

        #expect(unmarked.isUndecided)
        #expect(unmarked.isUnmarked)
        #expect(!unmarked.isMarked)

        #expect(!labelOnly.isUndecided)
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

        #expect(count.undecided == 1)
        #expect(count.total == 4)
        #expect(!count.isCompleteByMarks)
    }

    @Test func rejectingUnmarkedFinishesAGroupWithOnlyALabelledKeep() {
        let photos = ["labelled", "b", "c", "d"].map { groupCullingPhoto($0) }
        let group = groupCullingGroup("labelled-keep", members: photos)
        var marks = [photos[0]: PhotoMarks(label: ColourLabel(colour: .green))]
        let plan = GroupFinishingPlan(
            group: group, action: .rejectUnmarked, currentPhoto: photos[1], marks: marks)
        #expect(GroupUndecidedCount(group: group, marks: marks).undecided == 3)
        #expect(plan.changes.map(\.photo) == Array(photos.dropFirst()))
        for change in plan.changes {
            marks[change.photo] = (marks[change.photo] ?? PhotoMarks()).applying(change.change)
        }
        #expect(GroupUndecidedCount(group: group, marks: marks).isCompleteByMarks)
        #expect(marks[photos[0]] == PhotoMarks(label: ColourLabel(colour: .green)))
    }

    @Test func aMemberWithoutAMarksEntryReadsAsUndecided() {
        let group = groupCullingGroup(
            "missing", members: [groupCullingPhoto("a"), groupCullingPhoto("b")])
        let marked = GroupUndecidedCount(
            group: group,
            marks: [group.members[0]: PhotoMarks(rating: groupCullingRating(4))])

        #expect(marked.undecided == 1)
        #expect(marked.total == 2)
    }

    @Test func aGroupIsCompleteWhenEveryMemberHasAnyMark() {
        let members = [groupCullingPhoto("a"), groupCullingPhoto("b"), groupCullingPhoto("c")]
        let group = groupCullingGroup("complete", members: members)
        let labelledGroup = groupCullingMarks([
            (members[0], PhotoMarks(rating: groupCullingRating(3))),
            (members[1], PhotoMarks(rating: .rejected)),
            (members[2], PhotoMarks(label: ColourLabel(colour: .purple))),
        ])

        #expect(GroupUndecidedCount(group: group, marks: labelledGroup).isCompleteByMarks)

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
