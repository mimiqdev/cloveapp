import Testing

@testable import CloveCore

struct DuoSplitTests {
    @Test func dividerSettlesOnlyAtDesignedPresentations() {
        #expect(DuoSplit.focus.gridFraction == 0.3)
        #expect(DuoSplit.photoOnly.gridFraction == 0)
        #expect(DuoSplit.focus.released(translation: -135, contentWidth: 900) == .photoOnly)
        #expect(DuoSplit.focus.released(translation: 135, contentWidth: 900) == .grid)
        for distance in [-134.0, -20, 0, 20, 134] {
            #expect(DuoSplit.focus.released(translation: distance, contentWidth: 900) == .focus)
        }
        #expect(DuoSplit.focus.released(translation: -150, contentWidth: 1200) == .focus)
        #expect(DuoSplit.focus.released(translation: -180, contentWidth: 1200) == .photoOnly)
        #expect(DuoSplit.focus.released(translation: 100, contentWidth: 0) == .focus)
    }
}
