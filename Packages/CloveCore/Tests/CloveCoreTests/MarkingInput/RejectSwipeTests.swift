import Testing

import CloveCore

@Suite struct RejectSwipeTests {
    @Test func theLaunchThresholdIsDocumentedInOnePlace() {
        #expect(RejectSwipeRules.standard.threshold == 100)
        #expect(RejectSwipeRules.standard.isPastThreshold(travel: -100))
        #expect(!RejectSwipeRules.standard.isPastThreshold(travel: -99.9))
        #expect(!RejectSwipeRules.standard.isPastThreshold(travel: 100))
    }

    @Test func aSessionReportsWhetherReleasingWouldReject() {
        var session = RejectSwipeSession()

        session.update(travel: -60)
        #expect(!session.isPastThreshold)
        session.update(travel: -120)
        #expect(session.isPastThreshold)
        #expect(session.travel == -120)
    }

    @Test func releasingPastTheThresholdRejects() {
        var session = RejectSwipeSession()

        session.update(travel: -60)
        let rejected = session.release(atTravel: -120)
        #expect(rejected)
    }

    @Test func releasingBackInsideTheThresholdDoesNothing() {
        var session = RejectSwipeSession()

        session.update(travel: -200)
        #expect(session.isPastThreshold)
        let released = session.release(atTravel: -30)
        #expect(!released)
        #expect(!session.isPastThreshold)
    }

    @Test func theThresholdAtReleaseRejects() throws {
        let rules = MarkingInputRules()
        let marks = try MarkingFixtures.marks(stars: 4)

        #expect(
            rules.result(forSwipeDownTravel: -100, marks: marks, isZoomed: false)
                == .mark(MarkChange(rating: .rejected), .reject))
        #expect(rules.result(forSwipeDownTravel: -99, marks: marks, isZoomed: false) == .noChange)
    }

    @Test func releasingBackInsideTheThresholdChangesNothing() throws {
        let rules = MarkingInputRules()

        #expect(
            rules.result(forSwipeDownTravel: -30, marks: PhotoMarks(), isZoomed: false)
                == .noChange)
    }

    @Test func anAlreadyRejectedPhotoYieldsNoChange() throws {
        let rules = MarkingInputRules()

        #expect(
            rules.result(
                forSwipeDownTravel: -500, marks: try MarkingFixtures.marks(rejected: true),
                isZoomed: false) == .noChange)
    }

    @Test func rejectingReplacesTheRatingAndKeepsTheLabel() throws {
        let rules = MarkingInputRules()
        let marks = try MarkingFixtures.marks(stars: 3, label: .red)

        // Reject is the rating −1, so it replaces the stars; the label is untouched (PRD P0-05).
        #expect(
            rules.result(forSwipeDownTravel: -120, marks: marks, isZoomed: false)
                == .mark(MarkChange(rating: .rejected), .reject))
    }
}
