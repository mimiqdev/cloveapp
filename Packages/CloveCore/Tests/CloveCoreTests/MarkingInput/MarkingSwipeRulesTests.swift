import Testing

import CloveCore

@Suite struct MarkingSwipeRulesTests {
    private let rules = MarkingSwipeRules.standard

    @Test func aSteepUpwardDragBeginsARatingSwipe() {
        #expect(
            rules.swipe(
                horizontalTravel: 0, verticalTravel: 30, isZoomed: false, gesturesEnabled: true)
                == .rating)
    }

    @Test func aSteepDownwardDragBeginsARejectSwipe() {
        #expect(
            rules.swipe(
                horizontalTravel: 0, verticalTravel: -30, isZoomed: false, gesturesEnabled: true)
                == .reject)
    }

    @Test func aHorizontalDragNeverBeginsAMarkingSwipe() {
        // A sideways drag stays free for navigation (PRD Detail gestures).
        #expect(
            rules.swipe(
                horizontalTravel: 60, verticalTravel: 10, isZoomed: false, gesturesEnabled: true)
                == nil)
    }

    @Test func aDragFlatterThanTheSplitNeverBeginsAMarkingSwipe() {
        #expect(
            rules.swipe(
                horizontalTravel: -40, verticalTravel: 30, isZoomed: false, gesturesEnabled: true)
                == nil)
    }

    @Test func aDragAtTheSplitBeginsAMarkingSwipe() {
        // The launch ratio of 1 puts the split at 45°; the boundary belongs to marking.
        #expect(
            rules.swipe(
                horizontalTravel: 30, verticalTravel: 30, isZoomed: false, gesturesEnabled: true)
                == .rating)
    }

    @Test func aDragWithNoVerticalTravelNeverBeginsAMarkingSwipe() {
        #expect(
            rules.swipe(
                horizontalTravel: 30, verticalTravel: 0, isZoomed: false, gesturesEnabled: true)
                == nil)
    }

    @Test func aZoomedViewNeverBeginsAMarkingSwipe() {
        // Zoomed, a one-finger drag pans instead (PRD Detail gestures).
        #expect(
            rules.swipe(
                horizontalTravel: 0, verticalTravel: 120, isZoomed: true, gesturesEnabled: true)
                == nil)
        #expect(
            rules.swipe(
                horizontalTravel: 0, verticalTravel: -120, isZoomed: true, gesturesEnabled: true)
                == nil)
    }

    @Test func markingGesturesOffNeverBeginAMarkingSwipe() {
        // PRD Gesture-related settings: gestures on or off.
        #expect(
            rules.swipe(
                horizontalTravel: 0, verticalTravel: 120, isZoomed: false, gesturesEnabled: false)
                == nil)
    }

    @Test func aStricterRatioRefusesADiagonalDrag() {
        let strict = MarkingSwipeRules(verticalToHorizontalRatio: 1.5)

        #expect(
            strict.swipe(
                horizontalTravel: 30, verticalTravel: 30, isZoomed: false, gesturesEnabled: true)
                == nil)
        #expect(
            strict.swipe(
                horizontalTravel: 10, verticalTravel: 30, isZoomed: false, gesturesEnabled: true)
                == .rating)
    }

    @Test func theSettingsDecideWhetherASwipeBegins() {
        // The preview asks the rules, which read the setting, so the recognizer and the settings
        // cannot disagree (PRD Gesture-related settings).
        var off = AppSettings()
        off.gesturesEnabled = false
        let withoutGestures = MarkingInputRules(settings: off)
        let on = MarkingInputRules()

        #expect(
            withoutGestures.beginSwipe(horizontalTravel: 0, verticalTravel: 90, isZoomed: false)
                == nil)
        #expect(
            on.beginSwipe(horizontalTravel: 0, verticalTravel: 90, isZoomed: false) == .rating)
        #expect(
            on.beginSwipe(horizontalTravel: 0, verticalTravel: -90, isZoomed: false) == .reject)
        #expect(
            on.beginSwipe(horizontalTravel: 90, verticalTravel: 4, isZoomed: false) == nil)
        #expect(on.beginSwipe(horizontalTravel: 0, verticalTravel: 90, isZoomed: true) == nil)
    }
}
