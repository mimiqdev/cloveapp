import CloveCore
import Testing

@Suite("Reject unmarked planning")
struct GroupFinishingPlanTests {
    private let photos = ["a", "b", "c", "d"].map { groupCullingPhoto($0) }

    @Test func requiresARatingOrLabelRatherThanOnlyRejects() {
        let group = groupCullingGroup("availability", members: photos)
        for marks: [PhotoIdentity: PhotoMarks] in [[:], [photos[0]: PhotoMarks(rating: .rejected)]]
        {
            let plan = GroupFinishingPlan(
                group: group, action: .rejectUnmarked, currentPhoto: photos[0], marks: marks)
            #expect(plan.availability == .noRatedOrLabelledPhoto)
            #expect(plan.changes.isEmpty)
        }
        for kept in [
            PhotoMarks(rating: groupCullingRating(1)),
            PhotoMarks(label: ColourLabel(colour: .blue)),
        ] {
            let plan = GroupFinishingPlan(
                group: group, action: .rejectUnmarked, currentPhoto: photos[1],
                marks: [photos[0]: kept])
            #expect(plan.availability.isAvailable)
            #expect(plan.rejects.map(\.photo) == Array(photos.dropFirst()))
        }
    }

    @Test func preservesRatedLabelledAndRejectedPhotosAndOtherGroups() {
        let group = groupCullingGroup("protected", members: photos)
        let outside = groupCullingPhoto("outside")
        let marks = [
            photos[0]: PhotoMarks(rating: groupCullingRating(5)),
            photos[1]: PhotoMarks(label: ColourLabel(colour: .red)),
            photos[2]: PhotoMarks(rating: .rejected),
            outside: PhotoMarks(),
        ]
        let plan = GroupFinishingPlan(
            group: group, action: .rejectUnmarked, currentPhoto: photos[0], marks: marks)
        #expect(plan.changes.map(\.photo) == [photos[3]])
        #expect(plan.changes.first?.change == .rating(.rejected))
        #expect(plan.changes.first?.marksBefore == PhotoMarks())
    }

    @Test func submissionProtectsPhotosMarkedSincePlanning() {
        let group = groupCullingGroup("recheck", members: photos)
        let marks = [photos[0]: PhotoMarks(rating: groupCullingRating(3))]
        let plan = GroupFinishingPlan(
            group: group, action: .rejectUnmarked, currentPhoto: photos[0], marks: marks)
        let now = [
            photos[1]: PhotoMarks(rating: groupCullingRating(2)),
            photos[2]: PhotoMarks(label: ColourLabel(colour: .green)),
            photos[3]: PhotoMarks(rating: .rejected),
        ]
        #expect(plan.changesAllowed { now[$0] ?? marks[$0] ?? PhotoMarks() }.isEmpty)
    }
}
