import CloveCore
import SwiftUI
import Testing
import UIKit

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

    @Test func markingDragsAtDifferentHeightsKeepTheSameRenderedIndicatorFrame() throws {
        let size = CGSize(width: 390, height: 650)
        let container = DetailZoomContainerView(frame: CGRect(origin: .zero, size: size))
        let feedback = DetailSwipeFeedback()
        container.feedback = feedback
        var frames: [CGRect] = []
        for startHeight in [CGFloat(250), 450] {
            #expect(container.beginSwipe(translation: CGPoint(x: 0, y: -15)))
            let drag = IndicatorTestPan(startHeight: startHeight)
            container.perform(NSSelectorFromString("handleMarkingPan:"), with: drag)
            drag.sampleState = .changed
            drag.travel = -150
            container.perform(NSSelectorFromString("handleMarkingPan:"), with: drag)
            #expect(feedback.rating != nil)
            let renderer = ImageRenderer(
                content: DetailSwipeFeedbackBadge(feedback: feedback, bottomInset: 140)
                    .frame(width: size.width, height: size.height)
                    .environment(\.cloveTheme, .light))
            renderer.scale = 1
            // On a CI runner's virtual GPU the first render can time out while the
            // render pipelines build, and comes back empty; measure a warm render.
            _ = renderer.cgImage
            let image = try #require(renderer.cgImage)
            frames.append(try visibleBounds(image))
            drag.sampleState = .cancelled
            container.perform(NSSelectorFromString("handleMarkingPan:"), with: drag)
        }
        #expect(frames[0] == frames[1])
        #expect(frames[0].minX >= size.width - 60)
        #expect(frames[0].maxX <= size.width - 10)
        #expect(abs(frames[0].midY - (size.height - 140) / 2) < 15)
    }

    /// Read the rendered read-out, including the chip below the stars, on a transparent stage.
    private func visibleBounds(_ image: CGImage) throws -> CGRect {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(
            CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 128 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        #expect(maxX >= minX && maxY >= minY)
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

@MainActor
private final class IndicatorTestPan: UIPanGestureRecognizer {
    let startHeight: CGFloat
    var travel: CGFloat = 0
    var sampleState: UIGestureRecognizer.State = .began

    init(startHeight: CGFloat) {
        self.startHeight = startHeight
        super.init(target: nil, action: nil)
    }

    override var state: UIGestureRecognizer.State {
        get { sampleState }
        set { sampleState = newValue }
    }

    override func translation(in view: UIView?) -> CGPoint { CGPoint(x: 0, y: travel) }
    override func location(in view: UIView?) -> CGPoint { CGPoint(x: 195, y: startHeight + travel) }
}
