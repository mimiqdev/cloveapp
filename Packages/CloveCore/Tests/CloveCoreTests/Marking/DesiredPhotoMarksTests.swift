import Testing

@testable import CloveCore

struct DesiredPhotoMarksTests {
    let photo = PhotoIdentity(
        folderID: FolderIdentity(rawValue: "test"), relativeFolderPath: "", stem: "image")

    @Test func doubleTapTogglesBeforeAnyConfirmation() throws {
        var desired = DesiredPhotoMarks()
        let three = try #require(Rating(rawValue: 3))
        let rules = MarkingInputRules(settings: AppSettings())
        let first = desired.apply(.rating(three), to: photo, confirmed: PhotoMarks())
        #expect(first.before.rating == .unrated)
        #expect(desired.shown(for: photo, confirmed: PhotoMarks()).rating == three)
        let shown = desired.shown(for: photo, confirmed: PhotoMarks())
        guard case .mark(let change, _) = rules.result(forRating: three, marks: shown) else {
            Issue.record("The second tap must toggle the shown rating")
            return
        }
        let second = desired.apply(change, to: photo, confirmed: PhotoMarks())
        #expect(second.before.rating == three)
        #expect(second.after.rating == .unrated)
        desired.finish(first, state: .savedInSidecar)
        #expect(desired.entry(for: photo)?.edit == second)
        #expect(desired.shown(for: photo, confirmed: first.after).rating == .unrated)
        desired.finish(second, state: .savedInSidecar)
        #expect(desired.entry(for: photo) == nil)
    }

    @Test func failureRetainsMarksAndFieldsUntilConfirmed() throws {
        var desired = DesiredPhotoMarks()
        let red = ColourLabel(colour: .red)
        let edit = desired.apply(.label(red), to: photo, confirmed: PhotoMarks())
        let failure = MarkChangeState.failed(
            MarkWriteFailure(reason: .notConfirmed, message: "Read-back failed"))
        desired.finish(edit, state: failure)
        #expect(desired.shown(for: photo, confirmed: PhotoMarks()).label == red)
        #expect(desired.entry(for: photo)?.state == failure)
        let newer = desired.apply(.rating(.rejected), to: photo, confirmed: PhotoMarks())
        #expect(newer.change.label == red)
        #expect(newer.after.isRejected)
        desired.finish(edit, state: .savedInSidecar)
        #expect(desired.entry(for: photo)?.edit == newer)
        desired.finish(newer, state: .savedInSidecar)
        #expect(desired.entry(for: photo) == nil)
    }

    @Test func keepRetryAndMoveUndoLeaveLaterStarsAlone() throws {
        let kept = PhotoMarks()
        for count in [3, 4] {
            let newer = PhotoMarks(rating: try #require(Rating(rawValue: count)))
            let restore = DesiredMarkRestore.change(
                photo: photo, current: newer, expected: kept,
                target: PhotoMarks(rating: .rejected), fields: .rating(.unrated))
            #expect(restore == nil)
        }
        #expect(
            DesiredMarkRestore.change(
                photo: photo, current: kept, expected: kept,
                target: PhotoMarks(rating: .rejected), fields: .rating(.unrated))
                == .rating(.rejected))
    }

    @Test func moveWaitsForWritesAndLaterMarkWaitsForMove() {
        var desired = DesiredPhotoMarks()
        let edit = desired.apply(.rating(.rejected), to: photo, confirmed: PhotoMarks())
        var queue = PhotoActionPipeline()
        let mark = queue.submit(.mark(edit))
        let move = queue.submit(
            .moveUndo(
                RejectMoveUndoEntry(batch: RejectMoveBatchID(), photoToReturnTo: photo), []))
        let later = queue.submit(.mark(edit))
        #expect(queue.beginNext()?.id == mark)
        #expect(queue.beginNext() == nil)
        queue.finish(mark)
        #expect(queue.beginNext()?.id == move)
        #expect(queue.beginNext() == nil)
        queue.finish(move)
        #expect(queue.beginNext()?.id == later)
        queue.finish(later)
        #expect(queue.isEmpty)
    }
}
