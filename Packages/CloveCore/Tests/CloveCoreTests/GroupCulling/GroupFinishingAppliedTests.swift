import CloveCore
import Testing

@Suite("Group finishing results")
struct GroupFinishingAppliedTests {
    @Test func resultsRetainPerPhotoFailuresAndOneUndoRecord() {
        let photos = ["rated", "saved", "failed", "missing"].map { groupCullingPhoto($0) }
        let group = groupCullingGroup("results", members: photos)
        let plan = GroupFinishingPlan(
            group: group, action: .rejectUnmarked, currentPhoto: photos[0],
            marks: [photos[0]: PhotoMarks(rating: groupCullingRating(3))])
        let saved = MarkChangeStatus(
            id: MarkChangeID(), identity: photos[1], requested: .rating(.rejected),
            state: .savedInSidecar)
        let failed = MarkChangeStatus(
            id: MarkChangeID(), identity: photos[2], requested: .rating(.rejected),
            state: .failed(MarkWriteFailure(reason: .notConfirmed, message: "Read-back failed.")))
        let result = GroupFinishingResult.applied(
            plan, statuses: [photos[1]: saved, photos[2]: failed])
        #expect(result.failedCount == 1)
        #expect(result.droppedPhotos == [photos[3]])
        #expect(result.undo.entries.map(\.photo) == [photos[1], photos[2]])
        #expect(result.undo.entries.allSatisfy { $0.marksBefore == PhotoMarks() })
        #expect(result.undo.photoToReturnTo == photos[0])
    }
}
