import Testing

import CloveCore

@Test func defaultAutoAdvanceFollowsThePRD() {
    let advance = AutoAdvance()
    #expect(advance.destination == .nextPhoto)
    #expect(advance.triggers.rating)
    #expect(advance.triggers.reject)
    #expect(!advance.triggers.colourLabel)
    #expect(advance.shouldAdvance(after: .rating))
    #expect(advance.shouldAdvance(after: .reject))
    #expect(!advance.shouldAdvance(after: .colourLabel))
}

@Test func triggerSwitchesChooseEachMarkKind() {
    let labelsOnly = AutoAdvance(
        destination: .nextUnmarkedPhoto,
        triggers: AutoAdvanceTriggers(rating: false, reject: false, colourLabel: true)
    )
    #expect(!labelsOnly.shouldAdvance(after: .rating))
    #expect(!labelsOnly.shouldAdvance(after: .reject))
    #expect(labelsOnly.shouldAdvance(after: .colourLabel))

    let ratingsOnly = AutoAdvance(
        destination: .nextPhoto,
        triggers: AutoAdvanceTriggers(rating: true, reject: false, colourLabel: false)
    )
    #expect(ratingsOnly.shouldAdvance(after: .rating))
    #expect(!ratingsOnly.shouldAdvance(after: .reject))
    #expect(!ratingsOnly.shouldAdvance(after: .colourLabel))
}

@Test func stayingNeverAdvances() {
    let stay = AutoAdvance(
        destination: .stay,
        triggers: AutoAdvanceTriggers(rating: true, reject: true, colourLabel: true)
    )
    for mark in MarkKind.allCases {
        #expect(!stay.shouldAdvance(after: mark))
    }
}
