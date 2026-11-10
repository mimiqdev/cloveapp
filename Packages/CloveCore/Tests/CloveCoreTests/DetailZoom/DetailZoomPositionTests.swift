import CoreGraphics
import Foundation
import Testing

import CloveCore

/// PRD In-group culling, synchronized zoom: the zoomed position is a point in unit image
/// coordinates, so the same spot stays under the viewport when the group view shows another
/// photo of the group.
@Suite("Synchronized zoom position")
struct DetailZoomPositionTests {
    /// The same 3000×2000 image on a 393×852 point view the other zoom tests use, so the numbers
    /// match theirs: fit is 393×262 points.
    private let imagePixels = CGSize(width: 3000, height: 2000)
    private let viewSize = CGSize(width: 393, height: 852)

    /// The content point an anchor lands on, turned into the offset a viewport shows there.
    private func visibleRect(
        centredOn anchor: DetailZoomAnchor, scale: CGFloat
    ) -> CGRect {
        DetailZoom.visibleRect(
            centredOn: DetailZoom.contentPoint(
                for: anchor, scale: scale, imagePixels: imagePixels, viewSize: viewSize),
            contentSize: CGSize(
                width: viewSize.width * scale, height: viewSize.height * scale),
            viewSize: viewSize)
    }

    /// A zoomed viewport's centre reads back as the image point it was centred on.
    @Test func aCentredViewportReadsBackTheImagePointItShows() {
        let anchor = DetailZoomAnchor(x: 0.3, y: 0.6)
        let rect = visibleRect(centredOn: anchor, scale: 2.5)

        let readBack = DetailZoom.centreAnchor(
            scale: 2.5, contentOffset: rect.origin, imagePixels: imagePixels, viewSize: viewSize)

        let expected = anchor
        #expect(readBack != nil)
        #expect(abs((readBack?.x ?? 0) - expected.x) < 0.0001)
        #expect(abs((readBack?.y ?? 0) - expected.y) < 0.0001)
    }

    /// The conversion works on both axes for an image narrower than its view, where the letterbox
    /// offsets the image inside the scroll view.
    @Test func aTallImageInAWideViewKeepsBothAxes() {
        let pixels = CGSize(width: 1000, height: 4000)
        let view = CGSize(width: 800, height: 600)
        let anchor = DetailZoomAnchor(x: 0.8, y: 0.2)
        let scale: CGFloat = 3
        let point = DetailZoom.contentPoint(
            for: anchor, scale: scale, imagePixels: pixels, viewSize: view)
        let rect = DetailZoom.visibleRect(
            centredOn: point,
            contentSize: CGSize(width: view.width * scale, height: view.height * scale),
            viewSize: view)

        let readBack = DetailZoom.centreAnchor(
            scale: scale, contentOffset: rect.origin, imagePixels: pixels, viewSize: view)

        #expect(readBack != nil)
        #expect(abs((readBack?.x ?? 0) - anchor.x) < 0.0001)
        #expect(abs((readBack?.y ?? 0) - anchor.y) < 0.0001)
    }

    /// A viewport clamped against an image edge reads back inside the image, never a value
    /// outside it, so the next photo opens inside its own bounds.
    @Test func anEdgeClampedViewportReadsBackInsideTheImage() {
        let scale: CGFloat = 2
        // The image fills the view's width at fit and is shorter, so it is drawn below the top
        // edge: the top of the scrolled content is the image's top edge and above it nothing.
        let origin = DetailZoom.centreAnchor(
            scale: scale, contentOffset: .zero, imagePixels: imagePixels, viewSize: viewSize)

        #expect(origin != nil)
        #expect(abs((origin?.x ?? -1) - 0.25) < 0.0001)
        #expect(origin?.y == 0)

        let farCorner = DetailZoom.centreAnchor(
            scale: scale,
            contentOffset: CGPoint(
                x: viewSize.width * scale - viewSize.width,
                y: viewSize.height * scale - viewSize.height),
            imagePixels: imagePixels, viewSize: viewSize)
        #expect(farCorner != nil)
        #expect(abs((farCorner?.x ?? -1) - 0.75) < 0.0001)
        #expect(farCorner?.y == 1)
    }

    /// At fit the whole image is visible, so there is no position to keep; a view or image that
    /// has not been laid out answers nothing rather than a misleading point.
    @Test func fitAndDegenerateViewsHaveNoPosition() {
        #expect(
            DetailZoom.centreAnchor(
                scale: 1, contentOffset: .zero, imagePixels: imagePixels, viewSize: viewSize)
                == nil)
        #expect(
            DetailZoom.centreAnchor(
                scale: 2, contentOffset: .zero, imagePixels: .zero, viewSize: viewSize) == nil)
        #expect(
            DetailZoom.centreAnchor(
                scale: 2, contentOffset: .zero, imagePixels: imagePixels, viewSize: .zero) == nil)
    }

    /// A position outside the image clamps into it, so a caller can never ask the viewport to
    /// centre empty space.
    @Test func positionsOutsideTheImageClampToItsEdges() {
        #expect(DetailZoomAnchor(x: -0.4, y: 1.7) == DetailZoomAnchor(x: 0, y: 1))
        #expect(DetailZoomAnchor.centre == DetailZoomAnchor(x: 0.5, y: 0.5))
    }

    /// The content point of the middle of a fitting image is the middle of its zoomed content.
    @Test func theCentreLandsOnTheMiddleOfTheContent() {
        let view = CGSize(width: 400, height: 800)
        let pixels = CGSize(width: 1000, height: 500)
        let point = DetailZoom.contentPoint(
            for: .centre, scale: 2, imagePixels: pixels, viewSize: view)

        // Fit is 400×200, drawn 300 points below the view's top edge.
        #expect(abs(point.x - 400) < 0.0001)
        #expect(abs(point.y - 800) < 0.0001)
    }
}
