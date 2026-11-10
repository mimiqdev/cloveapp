import Foundation
import Testing

import CloveCore

/// PRD In-group culling, finishing actions, with PRD P0-09's per-photo results: a library
/// without C4's write queue applies the planned changes itself and reports the same result shape.
@Suite("Group finishing result without a queue")
struct GroupFinishingAppliedTests {
    private let kept = groupCullingPhoto("kept")
    private let rejected = groupCullingPhoto("rejected")
    private let rated = groupCullingPhoto("rated")

    private var group: BrowsingGroup {
        BrowsingGroup(id: GroupID(rawValue: "finish"), members: [kept, rejected, rated])
    }

    private var marks: [PhotoIdentity: PhotoMarks] {
        groupCullingMarks([
            (kept, PhotoMarks()),
            (rejected, PhotoMarks()),
            (rated, PhotoMarks(rating: groupCullingRating(4))),
        ])
    }

    /// A status for one planned photo, with the state its write reached.
    private func status(
        _ photo: PhotoIdentity, change: MarkChange, state: MarkChangeState
    ) -> MarkChangeStatus {
        MarkChangeStatus(
            id: MarkChangeID(), identity: photo, requested: change, state: state)
    }

    /// Keep this, reject the rest: the kept photo's rating and the rejected photo's Reject each
    /// report their own state, the rated photo is untouched, and the undo record holds both
    /// changes (PRD P0-12; DEV-PLAN C5).
    @Test func everyAppliedChangeReportsItsOwnStateAndUndoEntry() {
        let plan = GroupFinishingPlan(
            group: group, action: .keepThis, currentPhoto: kept, marks: marks,
            enabledRatings: groupCullingEnabledRatings([1, 3]))
        let keptChange = MarkChange(rating: groupCullingRating(1))
        let rejectChange = MarkChange(reject: true)
        let statuses: [PhotoIdentity: MarkChangeStatus] = [
            kept: status(kept, change: keptChange, state: .savedInSidecar),
            rejected: status(rejected, change: rejectChange, state: .storedInClove),
        ]

        let result = GroupFinishingResult.applied(plan, statuses: statuses)

        #expect(result.outcomes.map(\.photo) == [kept, rejected])
        #expect(result.savedCount == 2)
        #expect(result.failedCount == 0)
        #expect(result.partialFailureSummary == nil)
        #expect(result.droppedPhotos.isEmpty)
        #expect(result.undo.groupID == group.id)
        #expect(result.undo.action == .keepThis)
        #expect(result.undo.photoToReturnTo == kept)
        #expect(result.undo.entries.map(\.photo) == [kept, rejected])
        // The rated photo was never planned, so no finishing action can reject it (PRD P0-12).
        #expect(result.undo.entries.allSatisfy { $0.photo != rated })
    }

    /// A planned photo with no status was not written, so it is reported as dropped and stays
    /// out of the undo record, the same as one the executor could not write (PRD P0-12).
    @Test func aPlannedPhotoWithoutAStatusIsDropped() {
        let plan = GroupFinishingPlan(
            group: group, action: .keepThis, currentPhoto: kept, marks: marks,
            enabledRatings: groupCullingTwoAndFour)
        let statuses: [PhotoIdentity: MarkChangeStatus] = [
            kept: status(
                kept, change: MarkChange(rating: groupCullingRating(2)),
                state: .savedInSidecar)
        ]

        let result = GroupFinishingResult.applied(plan, statuses: statuses)

        #expect(result.outcomes.map(\.photo) == [kept])
        #expect(result.droppedPhotos == [rejected])
        #expect(result.undo.entries.map(\.photo) == [kept])
    }

    /// A failed change keeps its requested marks and produces the PRD's partial-failure wording,
    /// so the group view can offer a retry (PRD P0-09; PRD Failure and recovery).
    @Test func aFailedChangeProducesThePartialFailureSummary() {
        let plan = GroupFinishingPlan(
            group: group, action: .keepThis, currentPhoto: kept, marks: marks,
            enabledRatings: groupCullingTwoAndFour)
        let failure = MarkWriteFailure(
            reason: .notConfirmed, message: "The sidecar did not read back.")
        let statuses: [PhotoIdentity: MarkChangeStatus] = [
            kept: status(
                kept, change: MarkChange(rating: groupCullingRating(2)),
                state: .savedInSidecar),
            rejected: status(rejected, change: MarkChange(reject: true), state: .failed(failure)),
        ]

        let result = GroupFinishingResult.applied(plan, statuses: statuses)

        #expect(result.savedCount == 1)
        #expect(result.failedCount == 1)
        #expect(result.partialFailureSummary == "Saved 1 photos. 1 photos couldn't be saved.")
    }

    /// An unavailable action has no planned change, so applying it reports nothing to undo and
    /// no failure (PRD In-group culling, finishing actions).
    @Test func anUnavailablePlanHasNoOutcomes() {
        let noRating = groupCullingMarks([
            (kept, PhotoMarks()),
            (rejected, PhotoMarks()),
            (rated, PhotoMarks()),
        ])
        let plan = GroupFinishingPlan(
            group: group, action: .keepRated, currentPhoto: kept, marks: noRating,
            enabledRatings: groupCullingTwoAndFour)

        #expect(plan.availability == .noRatedPhoto)

        let result = GroupFinishingResult.applied(plan, statuses: [:])

        #expect(result.outcomes.isEmpty)
        #expect(result.droppedPhotos.isEmpty)
        #expect(result.undo.entries.isEmpty)
    }

    /// The marks read at execution decide what a plan still does: a kept photo's new rating is
    /// kept and a labelled photo is never rejected (PRD P0-12; PRD In-group culling, finishing
    /// actions).
    @Test func theMarksReadNowDecideWhichChangesStayAllowed() {
        let plan = GroupFinishingPlan(
            group: group, action: .keepThis, currentPhoto: kept, marks: marks,
            enabledRatings: groupCullingTwoAndFour)

        // Unchanged marks: the kept photo gets the lowest enabled rating and the other unmarked
        // photo is rejected.
        let unchanged = plan.changesAllowed { marks[$0] ?? PhotoMarks() }
        #expect(unchanged.map(\.kind) == [.keep, .reject])
        #expect(unchanged.first?.change.rating == groupCullingRating(2))

        // Both photos gained a mark after the plan was built: keeping has nothing left to
        // change, and the label makes the planned reject no longer allowed.
        let markedMeanwhile = groupCullingMarks([
            (kept, PhotoMarks(rating: groupCullingRating(4))),
            (rejected, PhotoMarks(label: ColourLabel(colour: .blue))),
        ])
        let allowed = plan.changesAllowed { markedMeanwhile[$0] ?? PhotoMarks() }
        #expect(allowed.isEmpty)
    }
}
