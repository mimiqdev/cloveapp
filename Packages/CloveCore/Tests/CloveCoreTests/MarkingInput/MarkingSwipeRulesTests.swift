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

    @Test func zoomedModeAllowsSingleOrTwoFingerPerSettingAndRespectsGesturesEnabled() throws {
        let marks = PhotoMarks(rating: .unrated, label: .clear)
        let four = try #require(Rating(rawValue: 4))

        var twoFinger = AppSettings()
        twoFinger.zoomedRatingSwipe = .twoFinger
        let twoFingerRules = MarkingInputRules(settings: twoFinger)
        #expect(
            !twoFingerRules.beginsSwipe(horizontalTravel: 0, verticalTravel: 40, isZoomed: true))
        #expect(!twoFingerRules.allowsSwipe(isZoomed: true, touchCount: 1))
        #expect(twoFingerRules.allowsSwipe(isZoomed: true, touchCount: 2))
        #expect(
            twoFingerRules.result(forSwipeRating: four, marks: marks, isZoomed: true, touchCount: 1)
                == .noChange)
        #expect(
            twoFingerRules.result(forSwipeRating: four, marks: marks, isZoomed: true, touchCount: 2)
                == .mark(MarkChange(rating: four), .rating))

        var axisLock = AppSettings()
        axisLock.zoomedRatingSwipe = .singleFingerAxisLock
        let axisLockRules = MarkingInputRules(settings: axisLock)
        #expect(axisLockRules.beginsSwipe(horizontalTravel: 0, verticalTravel: 40, isZoomed: true))
        #expect(
            !axisLockRules.beginsSwipe(horizontalTravel: 40, verticalTravel: 10, isZoomed: true))
        #expect(axisLockRules.allowsSwipe(isZoomed: true, touchCount: 1))
        #expect(!axisLockRules.allowsSwipe(isZoomed: true, touchCount: 2))
        #expect(
            axisLockRules.result(forSwipeRating: four, marks: marks, isZoomed: true, touchCount: 1)
                == .mark(MarkChange(rating: four), .rating))
        #expect(
            axisLockRules.result(forSwipeRating: four, marks: marks, isZoomed: true, touchCount: 2)
                == .noChange)

        var disabledTwoFinger = twoFinger
        disabledTwoFinger.gesturesEnabled = false
        #expect(
            !MarkingInputRules(settings: disabledTwoFinger).allowsSwipe(
                isZoomed: true, touchCount: 2))

        var disabledAxisLock = axisLock
        disabledAxisLock.gesturesEnabled = false
        #expect(
            !MarkingInputRules(settings: disabledAxisLock).beginsSwipe(
                horizontalTravel: 0, verticalTravel: 40, isZoomed: true))
        #expect(
            !MarkingInputRules(settings: disabledAxisLock).allowsSwipe(
                isZoomed: true, touchCount: 1))
    }

    @Test func twoFingerDisambiguationSeparatesVerticalSwipesFromPinchesAndPans() {
        // Below decision travel stays undecided.
        #expect(
            ZoomedTwoFingerSwipeRules.classify(
                first: .init(horizontal: 0, vertical: 4),
                second: .init(horizontal: 0, vertical: 5)
            ) == .undecided)

        // Parallel vertical up and down swipes (exact and realistic slight finger variance).
        #expect(
            ZoomedTwoFingerSwipeRules.classify(
                first: .init(horizontal: 0, vertical: 16),
                second: .init(horizontal: 0, vertical: 16)
            ) == .swipe)
        #expect(
            ZoomedTwoFingerSwipeRules.classify(
                first: .init(horizontal: -2, vertical: -18),
                second: .init(horizontal: 3, vertical: -14)
            ) == .swipe)

        // Symmetric and asymmetric pinches never classify as swipe.
        #expect(
            ZoomedTwoFingerSwipeRules.classify(
                first: .init(horizontal: 0, vertical: -12),
                second: .init(horizontal: 0, vertical: 12)
            ) == .pinchOrOther)
        #expect(
            ZoomedTwoFingerSwipeRules.classify(
                first: .init(horizontal: -10, vertical: -10),
                second: .init(horizontal: 10, vertical: 10)
            ) == .pinchOrOther)
        // Anchored pinch (one finger stationary, other moves vertically).
        #expect(
            ZoomedTwoFingerSwipeRules.classify(
                first: .init(horizontal: 0, vertical: 1),
                second: .init(horizontal: 0, vertical: 20)
            ) == .pinchOrOther)
        // Diagonal diverging pinch with shared vertical drift.
        #expect(
            ZoomedTwoFingerSwipeRules.classify(
                first: .init(horizontal: -10, vertical: 12),
                second: .init(horizontal: 10, vertical: 12)
            ) == .pinchOrOther)
        // Two-finger horizontal pan.
        #expect(
            ZoomedTwoFingerSwipeRules.classify(
                first: .init(horizontal: 20, vertical: 3),
                second: .init(horizontal: 20, vertical: 4)
            ) == .pinchOrOther)
    }
}
