import Foundation
import Testing

@testable import CloveCore

@Suite("Undo Reject unmarked")
struct MarkUndoGroupFinishingTests {
    @Test func undoRestoresRejectsAsOneStepAndRedoRestoresCompletion() async throws {
        let fixture = try UndoTestFixture(stems: ["A", "B", "C"])
        defer { fixture.remove() }
        let photos = fixture.photoSets.map(\.id)
        let rating = undoRating(4)
        await undoSeedSidecar(PhotoMarks(rating: rating), at: fixture.sidecar(0))
        let group = groupCullingGroup("finish", members: photos)
        let plan = GroupFinishingPlan(
            group: group, action: .rejectUnmarked, currentPhoto: photos[0],
            marks: [photos[0]: PhotoMarks(rating: rating)])
        await fixture.completion.recordFinishingAction(on: group.id)
        var statuses: [PhotoIdentity: MarkChangeStatus] = [:]
        for change in plan.changes {
            let set = try #require(fixture.photoSets.first { $0.id == change.photo })
            statuses[change.photo] = await fixture.queue.apply(change.change, to: set)
        }
        let result = GroupFinishingResult.applied(plan, statuses: statuses)
        let entry = await fixture.history.recordGroupFinishing(result.undo)
        #expect(entry != nil)
        #expect(result.savedCount == 2)
        #expect(await fixture.history.undoCount == 1)
        #expect(await fixture.history.nextUndoActionName == "Reject unmarked")

        let undo = try #require(await undoStep(fixture))
        #expect(undo.savedCount == 2)
        #expect(undo.photoToReturnTo == photos[1])
        #expect(undo.completion?.state == .cleared)
        #expect(await fixture.completion.hasFinishingAction(on: group.id) == false)
        #expect(try undoSidecarMarks(at: fixture.sidecar(0)).rating == .rated(rating))
        for index in 1...2 {
            #expect(try undoSidecarMarks(at: fixture.sidecar(index)).rating == .rated(.unrated))
        }
        let redo = try #require(await undoRedoStep(fixture))
        #expect(redo.completion?.state == .restored)
        #expect(await fixture.completion.hasFinishingAction(on: group.id))
        for index in 1...2 {
            #expect(try undoSidecarMarks(at: fixture.sidecar(index)).rating == .rated(.rejected))
        }
        #expect(try undoSidecarMarks(at: fixture.sidecar(0)).rating == .rated(rating))
    }
}
