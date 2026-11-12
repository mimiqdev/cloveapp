import CloveCore
import Testing

@Suite struct MarkingSwipeRulesTests {
    @Test(arguments: [
        (0.0, 30.0, true), (0, -30, true), (60, 10, false),
        (-40, 30, false), (30, 30, true), (30, 0, false),
    ])
    func initialAxis(horizontal: Double, vertical: Double, expected: Bool) {
        #expect(
            MarkingInputRules().beginsSwipe(
                horizontalTravel: horizontal, verticalTravel: vertical, isZoomed: false) == expected
        )
    }

    @Test func zoomAndSettingsDisableSwipes() {
        var settings = AppSettings()
        settings.gesturesEnabled = false
        #expect(
            !MarkingInputRules(settings: settings).beginsSwipe(
                horizontalTravel: 0, verticalTravel: -90, isZoomed: false))
        #expect(
            !MarkingInputRules().beginsSwipe(
                horizontalTravel: 0, verticalTravel: 90, isZoomed: true))
        #expect(
            !MarkingSwipeRules(verticalToHorizontalRatio: 1.5).beginsSwipe(
                horizontalTravel: 30, verticalTravel: 30, isZoomed: false, gesturesEnabled: true))
    }

    @Test func releaseGuardsAndLabelPreservation() throws {
        let marks = PhotoMarks(
            rating: try #require(Rating(rawValue: 3)), label: ColourLabel(colour: .green))
        let rules = MarkingInputRules()
        #expect(
            rules.result(forSwipeRating: marks.rating, marks: marks, isZoomed: false) == .noChange)
        for rating in [Rating.unrated, .rejected] {
            let result = rules.result(forSwipeRating: rating, marks: marks, isZoomed: false)
            #expect(
                result == .mark(MarkChange(rating: rating), rating == .rejected ? .reject : .rating)
            )
            #expect(marks.applying(MarkChange(rating: rating)).label == marks.label)
            #expect(rules.result(forSwipeRating: rating, marks: marks, isZoomed: true) == .noChange)
            var settings = AppSettings()
            settings.gesturesEnabled = false
            #expect(
                MarkingInputRules(settings: settings).result(
                    forSwipeRating: rating, marks: marks, isZoomed: false) == .noChange)
        }
    }
}
