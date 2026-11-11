import Testing

import CloveCore

/// C13's marking rules with Reject as the rating −1 (PRD P0-05, P0-06; decision record
/// `reject-as-rating.md`): every input that rejects writes −1, and every input that rates
/// replaces it.
@Suite("Reject as a rating transition")
struct RejectRatingTransitionTests {
    private let rules = MarkingInputRules()

    private func threeStars() throws -> PhotoMarks {
        PhotoMarks(rating: try #require(Rating(rawValue: 3)))
    }

    private var rejected: PhotoMarks { PhotoMarks(rating: .rejected) }

    /// A swipe down and the `↓` key both set −1, replacing any stars.
    @Test func rejectInputsSetMinusOneAndReplaceStars() throws {
        for marks in [PhotoMarks(), try threeStars()] {
            #expect(
                rules.result(forSwipeDownTravel: -100, marks: marks, isZoomed: false)
                    == .mark(MarkChange(rating: .rejected), .reject))
            #expect(
                rules.result(for: .reject, marks: marks)
                    == .mark(MarkChange(rating: .rejected), .reject))
        }
    }

    /// Rejecting a photo that is already rejected changes nothing (PRD P0-06 acceptance).
    @Test func rejectingAnAlreadyRejectedPhotoChangesNothing() {
        #expect(
            rules.result(forSwipeDownTravel: -100, marks: rejected, isZoomed: false) == .noChange)
        #expect(rules.result(for: .reject, marks: rejected) == .noChange)
    }

    /// Turning Reject off leaves the photo unrated: the same value the `0` key writes.
    @Test func unrejectSetsUnrated() {
        #expect(
            rules.result(forRating: .unrated, marks: rejected)
                == .mark(MarkChange(rating: .unrated), .rating))
        #expect(
            rules.result(for: .rating(.unrated), marks: rejected)
                == .mark(MarkChange(rating: .unrated), .rating))
    }

    /// A star rating on a rejected photo replaces −1 with those stars.
    @Test func ratingARejectedPhotoReplacesMinusOne() throws {
        let two = try #require(Rating(rawValue: 2))
        #expect(
            rules.result(forRating: two, marks: rejected)
                == .mark(MarkChange(rating: two), .rating))
        #expect(
            rules.result(for: .rating(two), marks: rejected)
                == .mark(MarkChange(rating: two), .rating))
    }

    /// The `↑` key starts at the lowest enabled level on a rejected photo.
    @Test func theNextRatingOnARejectedPhotoStartsAtTheLowestEnabledLevel() throws {
        let settings = AppSettings(
            enabledRatings: try #require(EnabledRatings([3, 5].compactMap(Rating.init(rawValue:)))))
        let rules = MarkingInputRules(settings: settings)
        #expect(
            rules.result(for: .nextRating, marks: rejected)
                == .mark(MarkChange(rating: try #require(Rating(rawValue: 3))), .rating))
    }

    /// A swipe up from a rejected photo starts at step 0 and applies the step's enabled level;
    /// inside the dead zone it writes nothing.
    @Test func swipeUpFromARejectedPhotoStartsAtZero() throws {
        let one = try #require(Rating(rawValue: 1))
        let three = try #require(Rating(rawValue: 3))
        #expect(
            rules.result(forSwipeUpTravel: 20, marks: rejected, isZoomed: false) == .noChange)
        #expect(
            rules.result(forSwipeUpTravel: 45, marks: rejected, isZoomed: false)
                == .mark(MarkChange(rating: one), .rating))
        #expect(
            rules.result(forSwipeUpTravel: 160, marks: rejected, isZoomed: false)
                == .mark(MarkChange(rating: three), .rating))
    }

    /// The ladder's live rating never reaches −1, whatever the travel.
    @Test func theRatingLadderNeverProducesReject() throws {
        var session = SwipeRatingSession(enabledRatings: .all)
        #expect(session.release(atTravel: -500) == nil)
        #expect(session.release(atTravel: 20) == nil)
        for travel in stride(from: 40.0, through: 400.0, by: 30.0) {
            let released = session.release(atTravel: travel)
            #expect(released != .rejected, "step at \(travel) produced Reject")
            #expect(released != .unrated)
        }
    }

    /// A label change never changes the rating or Reject (PRD Marking rules).
    @Test func labelChangesNeverChangeTheRating() throws {
        let green = ColourLabel(colour: .green)
        #expect(
            rules.result(forLabel: green, marks: rejected)
                == .mark(MarkChange(label: green), .colourLabel))
        #expect(
            rules.result(for: .colourLabel(.green), marks: rejected)
                == .mark(MarkChange(label: green), .colourLabel))
    }
}
