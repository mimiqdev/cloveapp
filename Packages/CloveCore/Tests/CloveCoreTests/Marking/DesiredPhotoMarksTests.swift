import Foundation
import Testing

@testable import CloveCore

struct DesiredPhotoMarksTests {
    let photo = PhotoIdentity(
        folderID: FolderIdentity(rawValue: "test"), relativeFolderPath: "", stem: "image")

    @Test func doubleTapTogglesBeforeTheWriteFinishes() throws {
        var desired = DesiredPhotoMarks()
        let three = try #require(Rating(rawValue: 3))
        let first = desired.apply(.rating(three), to: photo, confirmed: PhotoMarks())
        #expect(desired.shown(for: photo, confirmed: PhotoMarks()).rating == three)
        let second = desired.apply(.rating(.unrated), to: photo, confirmed: PhotoMarks())
        #expect(second.before.rating == three)
        #expect(desired.shown(for: photo, confirmed: first.after).rating == .unrated)
        desired.finish(for: second.photo)
        #expect(!desired.hasPending(for: photo))
    }

    @Test func finishingAWriteDropsItsPendingMarkRegardlessOfItsResult() {
        var desired = DesiredPhotoMarks()
        let edit = desired.apply(.rating(.rejected), to: photo, confirmed: PhotoMarks())
        desired.finish(for: edit.photo)
        #expect(desired.shown(for: photo, confirmed: PhotoMarks()) == PhotoMarks())
        let later = desired.apply(
            .label(ColourLabel(colour: .blue)), to: photo, confirmed: PhotoMarks())
        #expect(later.change.rating == nil)
        #expect(!later.after.isRejected)
    }

    @Test func moveUndoLeavesLaterStarsAlone() throws {
        let kept = PhotoMarks()
        let newer = PhotoMarks(rating: try #require(Rating(rawValue: 4)))
        #expect(
            DesiredMarkRestore.change(
                photo: photo, current: newer, expected: kept,
                target: PhotoMarks(rating: .rejected), fields: .rating(.unrated)) == nil)
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
        let root = URL(fileURLWithPath: "/photos")
        let plan = RejectMovePlan(
            rootURL: root, configuration: RejectMoveConfiguration(), sets: [], entries: [],
            destinationURL: root.appendingPathComponent("_Rejected"))
        let move = queue.submit(.move(plan, kept: []))
        let later = queue.submit(.mark(edit))
        #expect(queue.beginNext()?.id == mark)
        #expect(queue.beginNext() == nil)
        queue.finish(mark)
        #expect(queue.hasPendingMark(for: photo))
        #expect(queue.beginNext()?.id == move)
        queue.finish(move)
        #expect(queue.beginNext()?.id == later)
        queue.finish(later)
        #expect(!queue.hasPendingMark(for: photo))
        #expect(queue.isEmpty)
    }
}
