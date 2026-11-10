import CoreGraphics
import Foundation
import Testing

import CloveCore

/// PRD P0-04 and the G1 detail row: 100% shows one image pixel per screen pixel, a zoomed
/// viewport is centred on the tapped point and clamped to the image, and the edge zones
/// navigate without a double-tap delay.
@Suite("Detail zoom")
struct DetailZoomTests {
    /// A 3000×2000 image on a 393×852 point view at 3x: fit is 393×262 points, and 100% fills
    /// 3000 image pixels across 1179 screen pixels.
    @Test func fullResolutionOnAThreeTimesScreenShowsOneImagePixelPerScreenPixel() {
        let imagePixels = CGSize(width: 3000, height: 2000)
        let viewSize = CGSize(width: 393, height: 852)
        let fitted = DetailZoom.fittedSize(imagePixels: imagePixels, viewSize: viewSize)
        #expect(abs(fitted.width - 393) < 0.0001)
        #expect(abs(fitted.height - 262) < 0.0001)

        let scale = DetailZoom.fullResolutionScale(
            imagePixels: imagePixels, viewSize: viewSize, screenScale: 3)
        #expect(abs(scale - 3000.0 / 1179.0) < 0.0001)
    }

    /// A small image already fills more than one screen pixel per image pixel at fit, so 100%
    /// never zooms out below the whole image.
    @Test func fullResolutionNeverZoomsOutBelowFit() {
        let scale = DetailZoom.fullResolutionScale(
            imagePixels: CGSize(width: 300, height: 200),
            viewSize: CGSize(width: 400, height: 800), screenScale: 3)
        #expect(scale == 1)
    }

    /// A tapped point near a corner keeps the viewport inside the image on both axes.
    @Test func tappedPointNearAnEdgeIsClampedToTheImage() {
        let content = CGSize(width: 800, height: 1200)
        let view = CGSize(width: 400, height: 800)

        let nearOrigin = DetailZoom.visibleRect(
            centredOn: CGPoint(x: 10, y: 10), contentSize: content, viewSize: view)
        #expect(nearOrigin == CGRect(x: 0, y: 0, width: 400, height: 800))

        let nearFarCorner = DetailZoom.visibleRect(
            centredOn: CGPoint(x: 795, y: 1195), contentSize: content, viewSize: view)
        #expect(nearFarCorner == CGRect(x: 400, y: 400, width: 400, height: 800))
    }

    /// A tapped point inside the image centres the viewport on it.
    @Test func tappedPointInsideTheImageIsCentred() {
        let rect = DetailZoom.visibleRect(
            centredOn: CGPoint(x: 400, y: 600),
            contentSize: CGSize(width: 800, height: 1200),
            viewSize: CGSize(width: 400, height: 800))
        #expect(rect == CGRect(x: 200, y: 200, width: 400, height: 800))
    }

    /// Double-tapping back to fit shows the whole image with no offset, because the fit content
    /// is the image's fitted size.
    @Test func fitAfterFullResolutionShowsTheWholeImage() {
        let fitted = DetailZoom.fittedSize(
            imagePixels: CGSize(width: 3000, height: 2000),
            viewSize: CGSize(width: 393, height: 852))
        let rect = DetailZoom.visibleRect(
            centredOn: CGPoint(x: fitted.width, y: fitted.height),
            contentSize: fitted,
            viewSize: CGSize(width: 393, height: 852))
        #expect(rect == CGRect(origin: .zero, size: fitted))
    }

    /// Edge-zone hits: the outer 18% of the width on each side navigates, the middle does not.
    @Test func edgeZonesCoverTheOuterEighteenPercentOfEachSide() {
        let view = CGSize(width: 400, height: 700)
        #expect(DetailZoom.edgeZone(for: CGPoint(x: 0, y: 350), in: view) == .previous)
        #expect(DetailZoom.edgeZone(for: CGPoint(x: 71, y: 350), in: view) == .previous)
        #expect(DetailZoom.edgeZone(for: CGPoint(x: 72, y: 350), in: view) == .centre)
        #expect(DetailZoom.edgeZone(for: CGPoint(x: 200, y: 350), in: view) == .centre)
        #expect(DetailZoom.edgeZone(for: CGPoint(x: 327, y: 350), in: view) == .centre)
        #expect(DetailZoom.edgeZone(for: CGPoint(x: 328, y: 350), in: view) == .next)
        #expect(DetailZoom.edgeZone(for: CGPoint(x: 400, y: 350), in: view) == .next)
    }

    /// The edge zone follows the width, so a wide iPad preview keeps the same proportions.
    @Test func edgeZonesScaleWithTheViewWidth() {
        let view = CGSize(width: 1000, height: 700)
        #expect(DetailZoom.edgeZone(for: CGPoint(x: 179, y: 350), in: view) == .previous)
        #expect(DetailZoom.edgeZone(for: CGPoint(x: 180, y: 350), in: view) == .centre)
        #expect(DetailZoom.edgeZone(for: CGPoint(x: 819, y: 350), in: view) == .centre)
        #expect(DetailZoom.edgeZone(for: CGPoint(x: 820, y: 350), in: view) == .next)
    }

    /// A view that has not been laid out answers neutral values instead of dividing by zero.
    @Test func aDegenerateViewAnswersNeutralGeometry() {
        #expect(
            DetailZoom.fittedSize(
                imagePixels: CGSize(width: 3000, height: 2000), viewSize: .zero) == .zero)
        #expect(
            DetailZoom.fittedSize(
                imagePixels: .zero, viewSize: CGSize(width: 393, height: 852)) == .zero)
        #expect(
            DetailZoom.fullResolutionScale(
                imagePixels: CGSize(width: 3000, height: 2000), viewSize: .zero, screenScale: 3)
                == 1)
        #expect(
            DetailZoom.fullResolutionScale(
                imagePixels: .zero, viewSize: CGSize(width: 393, height: 852), screenScale: 3)
                == 1)
        #expect(
            DetailZoom.fullResolutionScale(
                imagePixels: CGSize(width: 3000, height: 2000),
                viewSize: CGSize(width: 393, height: 852), screenScale: 0) == 1)
        #expect(
            DetailZoom.visibleRect(
                centredOn: .zero, contentSize: .zero, viewSize: CGSize(width: 393, height: 852))
                == .zero)
        #expect(DetailZoom.edgeZone(for: .zero, in: .zero) == .centre)
    }

    /// The scroll view may always reach 100%, and a small image still remains inspectable.
    @Test func maximumScaleReachesFullResolutionAndStaysInspectable() {
        let phone = DetailZoom.maximumScale(
            imagePixels: CGSize(width: 3000, height: 2000),
            viewSize: CGSize(width: 393, height: 852), screenScale: 3)
        #expect(
            phone
                >= DetailZoom.fullResolutionScale(
                    imagePixels: CGSize(width: 3000, height: 2000),
                    viewSize: CGSize(width: 393, height: 852), screenScale: 3))

        let raw = DetailZoom.maximumScale(
            imagePixels: CGSize(width: 8640, height: 5760),
            viewSize: CGSize(width: 393, height: 852), screenScale: 3)
        #expect(raw >= DetailZoom.inspectionScale)
        #expect(
            raw > DetailZoom.fullResolutionScale(
                imagePixels: CGSize(width: 8640, height: 5760),
                viewSize: CGSize(width: 393, height: 852), screenScale: 3) - 0.0001)
    }
}
