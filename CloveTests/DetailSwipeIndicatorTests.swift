import CloveCore
import SwiftUI
import Testing

@testable import Clove

@MainActor
struct DetailSwipeIndicatorTests {
    @Test func indicatorCentresAboveVisibleControlsAndInTheWholePreviewWhenHidden() {
        let size = CGSize(width: 390, height: 650)
        #expect(
            DetailSwipeFeedbackBadge.position(in: size, controlsHeight: 140, chromeIsVisible: true)
                == CGPoint(x: 354, y: 255))
        #expect(
            DetailSwipeFeedbackBadge.position(in: size, controlsHeight: 140, chromeIsVisible: false)
                == CGPoint(x: 354, y: 325))
    }
}
