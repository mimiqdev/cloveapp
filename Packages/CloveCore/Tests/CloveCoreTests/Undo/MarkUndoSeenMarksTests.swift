import Testing

import CloveCore

/// What undo treats as the mark before a change, folding in every request still being written
/// (PRD P0-05's Undo row).
///
/// The names stay inside this suite, so the tests share no free symbols with the rest of the
/// target.
@Suite struct MarkUndoSeenMarksTests {
    /// Three stars, the value a first request asks for.
    static var three: Rating { stars(3) }

    /// Four stars, the value a later request asks for.
    static var four: Rating { stars(4) }

    /// A rating, or a recorded issue when the value is outside the 0–5 range.
    static func stars(_ value: Int) -> Rating {
        guard let rating = Rating(rawValue: value) else {
            Issue.record("\(value) is not a valid rating")
            return .unrated
        }
        return rating
    }

    /// The green label the label step applies.
    static let green = ColourLabel(colour: .green)

    @Test func aRatingALabelAndAnotherRatingAllWritingKeepTheirOrder() {
        // Tap ★3, then the green label, then ★4 before any of them confirms. The value the last
        // request replaced is ★3 with the label, not the unrated marks before all three.
        let seen = MarkUndoSeenMarks.marks(
            confirmed: PhotoMarks(),
            requests: [.rating(Self.three), .label(Self.green), .rating(Self.four)])
        #expect(seen.rating == Self.four)
        #expect(seen.label == Self.green)
        #expect(seen.isRejected == false)
    }

    @Test func twoRequestsBeforeTheFirstIsAdmittedBothCount() {
        // The queue has not admitted the first tap yet, so the confirmed marks are still the
        // original ones; both requests still shape what the user saw.
        let seen = MarkUndoSeenMarks.marks(
            confirmed: PhotoMarks(), requests: [.rating(Self.three), .rating(Self.four)])
        #expect(seen.rating == Self.four)
    }

    @Test func aFailedRequestInTheMiddleDropsOut() {
        // ★3, then a green label whose write failed, then ★4: the caller removes the failed label
        // when its write returns, so the fold reads ★4 with no label — what the screen shows. Undo
        // of ★4 puts ★3 back and leaves the label alone.
        let seen = MarkUndoSeenMarks.marks(
            confirmed: PhotoMarks(), requests: [.rating(Self.three), .rating(Self.four)])
        #expect(seen.rating == Self.four)
        #expect(seen.label == .clear)
    }

    @Test func aRejectRequestClearsItself() {
        let seen = MarkUndoSeenMarks.marks(
            confirmed: PhotoMarks(rating: Self.three, isRejected: true),
            requests: [MarkChange(reject: false)])
        #expect(seen.isRejected == false)
        #expect(seen.rating == Self.three)
    }

    @Test func aRequestLeavesTheFieldsItDoesNotName() {
        let confirmed = PhotoMarks(rating: Self.three, label: Self.green)
        let seen = MarkUndoSeenMarks.marks(
            confirmed: confirmed, requests: [MarkChange(reject: true)])
        #expect(seen.rating == Self.three)
        #expect(seen.label == Self.green)
        #expect(seen.isRejected)
    }

    @Test func noRequestLeavesTheConfirmedMarks() {
        let confirmed = PhotoMarks(rating: Self.three, label: Self.green)
        #expect(MarkUndoSeenMarks.marks(confirmed: confirmed, requests: []) == confirmed)
    }
}
