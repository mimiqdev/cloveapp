import Testing

import CloveCore

/// What undo treats as the mark before a change, including a mark still being written
/// (PRD P0-05's Undo row).
///
/// The names stay inside this suite, so the tests share no free symbols with the rest of the
/// target.
@Suite struct MarkUndoSeenMarksTests {
    /// The photo every fixture change names.
    static let photo = PhotoIdentity(
        folderID: FolderIdentity(rawValue: "seen-marks-folder"),
        relativeFolderPath: "DCIM/100CAM", stem: "MMQ00001")

    @Test func anUnfinishedRequestIsWhatTheUserSaw() throws {
        // ★3 is still writing when the user presses ★4; the previous mark is ★3, not unrated.
        let three = try #require(Rating(rawValue: 3))
        let status = MarkChangeStatus(
            id: MarkChangeID(), identity: Self.photo, requested: .rating(three),
            state: .pending)
        let seen = MarkUndoSeenMarks.marks(confirmed: PhotoMarks(), latest: status)
        #expect(seen.rating == three)
    }

    @Test func aWritingRequestCountsToo() throws {
        let four = try #require(Rating(rawValue: 4))
        let status = MarkChangeStatus(
            id: MarkChangeID(), identity: Self.photo, requested: .rating(four),
            state: .writing)
        #expect(MarkUndoSeenMarks.marks(confirmed: PhotoMarks(), latest: status).rating == four)
    }

    @Test func aConfirmedRequestIsAlreadyOnThePhoto() throws {
        let three = try #require(Rating(rawValue: 3))
        let confirmed = PhotoMarks(rating: three)
        let status = MarkChangeStatus(
            id: MarkChangeID(), identity: Self.photo, requested: .rating(three),
            state: .savedInSidecar)
        #expect(MarkUndoSeenMarks.marks(confirmed: confirmed, latest: status) == confirmed)
    }

    @Test func aFailedRequestIsNotWhatTheUserSaw() throws {
        let three = try #require(Rating(rawValue: 3))
        let status = MarkChangeStatus(
            id: MarkChangeID(), identity: Self.photo, requested: .rating(three),
            state: .failed(
                MarkWriteFailure(reason: .notConfirmed, message: "The sample failure.")))
        // The write never landed, so undo restores the confirmed marks rather than the request.
        #expect(MarkUndoSeenMarks.marks(confirmed: PhotoMarks(), latest: status) == PhotoMarks())
    }

    @Test func aSupersededRequestIsNotWhatTheUserSaw() throws {
        let three = try #require(Rating(rawValue: 3))
        let confirmed = PhotoMarks(label: ColourLabel(colour: .green))
        let status = MarkChangeStatus(
            id: MarkChangeID(), identity: Self.photo, requested: .rating(three),
            state: .superseded(by: MarkChangeID()))
        #expect(MarkUndoSeenMarks.marks(confirmed: confirmed, latest: status) == confirmed)
    }

    @Test func noRequestLeavesTheConfirmedMarks() {
        #expect(MarkUndoSeenMarks.marks(confirmed: PhotoMarks(), latest: nil) == PhotoMarks())
    }
}
