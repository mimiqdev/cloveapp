import Testing

@testable import CloveCore

/// PRD In-group culling and PRD P0-12: marked and unmarked photos.
@Suite("Group culling marks")
struct GroupCullingMarksTests {
    @Test func aRatingLabelOrRejectDecidesAPhoto() {
        let unmarked = PhotoMarks()
        let labelOnly = PhotoMarks(label: ColourLabel(colour: .red))
        let rated = PhotoMarks(rating: groupCullingRating(3))
        let rejected = PhotoMarks(rating: .rejected)

        #expect(unmarked.isUnmarked)
        #expect(!unmarked.isMarked)

        #expect(!labelOnly.isUnmarked)
        #expect(labelOnly.isMarked)

        #expect(!rated.isUnmarked)
        #expect(rated.isMarked)

        #expect(!rejected.isUnmarked)
        #expect(rejected.isMarked)
    }

    @Test func rejectingUnmarkedFinishesAGroupWithOnlyALabelledKeep() {
        let photos = ["labelled", "b", "c", "d"].map { groupCullingPhoto($0) }
        let group = groupCullingGroup("labelled-keep", members: photos)
        var marks = [photos[0]: PhotoMarks(label: ColourLabel(colour: .green))]
        let plan = GroupFinishingPlan(
            group: group, action: .rejectUnmarked, currentPhoto: photos[1], marks: marks)
        #expect(plan.rejects.count == 3)
        #expect(plan.changes.map(\.photo) == Array(photos.dropFirst()))
        for change in plan.changes {
            marks[change.photo] = (marks[change.photo] ?? PhotoMarks()).applying(change.change)
        }
        #expect(group.members.allSatisfy { marks[$0]?.isUnmarked == false })
        #expect(marks[photos[0]] == PhotoMarks(label: ColourLabel(colour: .green)))
    }

}
