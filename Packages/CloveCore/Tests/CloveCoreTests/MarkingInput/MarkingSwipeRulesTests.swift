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
        // The default zoomed mode keeps the fit axis split, so a vertical drag while zoomed rates.
        #expect(
            MarkingInputRules().beginsSwipe(
                horizontalTravel: 0, verticalTravel: 90, isZoomed: true))
        var panSettings = AppSettings()
        panSettings.zoomedGestures = .pan
        #expect(
            !MarkingInputRules(settings: panSettings).beginsSwipe(
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
            #expect(
                rules.result(forSwipeRating: rating, marks: marks, isZoomed: true, touchCount: 2)
                    == .noChange)
            var settings = AppSettings()
            settings.gesturesEnabled = false
            #expect(
                MarkingInputRules(settings: settings).result(
                    forSwipeRating: rating, marks: marks, isZoomed: false) == .noChange)
        }
    }

    @Test func zoomedGesturesChooseWhichDragRatesAndRespectGesturesEnabled() throws {
        let marks = PhotoMarks(rating: .unrated, label: .clear)
        let four = try #require(Rating(rawValue: 4))

        // Rate & switch keeps the fit single-finger rating and switching while zoomed.
        var rateAndSwitch = AppSettings()
        rateAndSwitch.zoomedGestures = .rateAndSwitch
        let rateAndSwitchRules = MarkingInputRules(settings: rateAndSwitch)
        #expect(
            rateAndSwitchRules.beginsSwipe(horizontalTravel: 0, verticalTravel: 40, isZoomed: true))
        #expect(
            !rateAndSwitchRules.beginsSwipe(
                horizontalTravel: 40, verticalTravel: 10, isZoomed: true))
        #expect(rateAndSwitchRules.allowsSwipe(isZoomed: true, touchCount: 1))
        #expect(!rateAndSwitchRules.allowsSwipe(isZoomed: true, touchCount: 2))
        #expect(
            rateAndSwitchRules.result(
                forSwipeRating: four, marks: marks, isZoomed: true, touchCount: 1)
                == .mark(MarkChange(rating: four), .rating))
        #expect(
            rateAndSwitchRules.result(
                forSwipeRating: four, marks: marks, isZoomed: true, touchCount: 2)
                == .noChange)

        // Pan leaves one-finger drags to the scroll view and rates with two fingers.
        var pan = AppSettings()
        pan.zoomedGestures = .pan
        let panRules = MarkingInputRules(settings: pan)
        #expect(!panRules.beginsSwipe(horizontalTravel: 0, verticalTravel: 40, isZoomed: true))
        #expect(!panRules.allowsSwipe(isZoomed: true, touchCount: 1))
        #expect(panRules.allowsSwipe(isZoomed: true, touchCount: 2))
        #expect(
            panRules.result(forSwipeRating: four, marks: marks, isZoomed: true, touchCount: 1)
                == .noChange)
        #expect(
            panRules.result(forSwipeRating: four, marks: marks, isZoomed: true, touchCount: 2)
                == .mark(MarkChange(rating: four), .rating))

        // Marking gestures off stops both zoomed modes at either touch count.
        for mode in ZoomedGestures.allCases {
            var disabled = AppSettings()
            disabled.zoomedGestures = mode
            disabled.gesturesEnabled = false
            let disabledRules = MarkingInputRules(settings: disabled)
            #expect(
                !disabledRules.beginsSwipe(
                    horizontalTravel: 0, verticalTravel: 40, isZoomed: true))
            #expect(!disabledRules.allowsSwipe(isZoomed: true, touchCount: 1))
            #expect(!disabledRules.allowsSwipe(isZoomed: true, touchCount: 2))
        }
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
