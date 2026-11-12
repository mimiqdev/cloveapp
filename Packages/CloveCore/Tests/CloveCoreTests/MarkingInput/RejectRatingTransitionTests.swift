import Testing

@testable import CloveCore

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
                rules.result(forSwipeRating: .rejected, marks: marks, isZoomed: false)
                    == .mark(MarkChange(rating: .rejected), .reject))
            #expect(
                rules.result(for: .reject, marks: marks)
                    == .mark(MarkChange(rating: .rejected), .reject))
        }
    }

    /// Rejecting a photo that is already rejected changes nothing (PRD P0-06 acceptance).
    @Test func rejectingAnAlreadyRejectedPhotoChangesNothing() {
        #expect(
            rules.result(forSwipeRating: .rejected, marks: rejected, isZoomed: false) == .noChange)
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

    /// The HUD's Reject toggle turns on to −1 and off to 0, and never touches the label.
    @Test func theRejectToggleTurnsOnToMinusOneAndOffToUnrated() throws {
        let labelled = PhotoMarks(rating: .rejected, label: ColourLabel(colour: .green))
        for marks in [PhotoMarks(), try threeStars()] {
            #expect(
                rules.result(forRejectToggle: marks)
                    == .mark(MarkChange(rating: .rejected), .reject))
        }
        #expect(
            rules.result(forRejectToggle: labelled)
                == .mark(MarkChange(rating: .unrated), .reject))
        // Applying the toggle's change leaves the label alone in both directions.
        #expect(labelled.applying(MarkChange(rating: .unrated)).label == labelled.label)
        #expect(PhotoMarks().applying(MarkChange(rating: .rejected)).isRejected)
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
