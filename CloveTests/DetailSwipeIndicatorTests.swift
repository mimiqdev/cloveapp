import CloveCore
import SwiftUI
import Testing

@testable import Clove

@MainActor
struct DetailSwipeIndicatorTests {
    @Test func groupSwipeKeepsUndecidedNeighboursWhenTheCurrentPhotoIsDecided() throws {
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        let group = try #require(model.groups.first)
        model.openGroup(group)
        let current = try #require(model.groupPhotos.first)
        #expect(!current.marks.isUndecided)
        let shown = model.groupPhotos.filter { $0.marks.isUndecided }
        #expect(!shown.contains { $0.id == current.id })
        let view = DetailMarkingView(
            browsing: model, photo: current, settings: AppSettings(), images: SampleDetailImages(),
            zoomPolicy: .group, order: shown,
            actions: DetailMarkingActions(
                apply: { _, _ in }, marked: { _, _ in }, step: { _ in }, markingSwipeBegan: {}),
            groupReview: GroupReviewChrome(
                group: group, undecided: shown.count, undecidedOnly: .constant(true), action: nil))
        #expect(!view.navigationAvailability.previous)
        #expect(view.navigationAvailability.next)
    }

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
