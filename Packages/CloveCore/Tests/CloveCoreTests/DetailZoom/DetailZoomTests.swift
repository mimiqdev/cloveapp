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

    /// 100% follows the photo's native size, not the smaller embedded preview on screen, so the
    /// first double-tap already lands on 100% of the RAW (PRD P0-04; G1 "Preview, detail (I2)").
    @Test func fullResolutionUsesTheNativeSizeWhileThePreviewIsShown() {
        let native = CGSize(width: 8640, height: 5760)
        let preview = CGSize(width: 2160, height: 1440)
        let view = CGSize(width: 393, height: 852)

        let scale = DetailZoom.fullResolutionScale(
            nativePixels: native, shownPixels: preview, viewSize: view, screenScale: 3)

        // The preview fills the 393 pt width at fit, so native 100% is 8640 image pixels across
        // 1179 screen pixels.
        #expect(abs(scale - 8640.0 / 1179.0) < 0.0001)
        #expect(scale > DetailZoom.inspectionScale)
        // A preview that is already its own full resolution answers the same way as before the
        // native size was known, which is the fallback for an unreadable header.
        #expect(
            DetailZoom.fullResolutionScale(
                nativePixels: .zero, shownPixels: preview, viewSize: view, screenScale: 3)
                == DetailZoom.fullResolutionScale(
                    imagePixels: preview, viewSize: view, screenScale: 3))
    }

    /// A pinch can reach native 100% while the preview is still shown, because the limit comes
    /// from the photo's native size rather than the preview's (PRD P0-04; G1 "Preview, detail
    /// (I2)").
    @Test func maximumScaleReachesNativeFullResolutionFromThePreview() {
        let native = CGSize(width: 8640, height: 5760)
        let preview = CGSize(width: 1616, height: 1080)
        let view = CGSize(width: 393, height: 852)

        let maximum = DetailZoom.maximumScale(
            nativePixels: native, shownPixels: preview, viewSize: view, screenScale: 3)
        let nativeScale = DetailZoom.fullResolutionScale(
            nativePixels: native, shownPixels: preview, viewSize: view, screenScale: 3)
        let previewScale = DetailZoom.fullResolutionScale(
            nativePixels: preview, shownPixels: preview, viewSize: view, screenScale: 3)

        #expect(abs(maximum - nativeScale) < 0.0001)
        #expect(maximum > DetailZoom.inspectionScale)
        #expect(previewScale < maximum)
    }

    /// The RAW render replaces the preview without changing the 100% scale, so the view does not
    /// zoom a second time when the pixels land (PRD P0-04; G1 "Preview, detail (I2)").
    @Test func replacingASameAspectPreviewWithTheRenderKeepsTheScale() {
        let native = CGSize(width: 8640, height: 5760)
        let preview = CGSize(width: 2160, height: 1440)
        let view = CGSize(width: 393, height: 852)

        let before = DetailZoom.fullResolutionScale(
            nativePixels: native, shownPixels: preview, viewSize: view, screenScale: 3)
        let after = DetailZoom.fullResolutionScale(
            nativePixels: native, shownPixels: native, viewSize: view, screenScale: 3)

        #expect(abs(before - after) < 0.0001)
        #expect(
            DetailZoom.maximumScale(
                nativePixels: native, shownPixels: preview, viewSize: view, screenScale: 3)
                >= before)
    }

    /// A preview cropped to another aspect than the photo still lands on the render's native
    /// 100%, because the scale follows the photo's size rather than the preview's shape; only the
    /// visible point has to be kept when the pixels change (PRD P0-04; G1 "Preview, detail
    /// (I2)").
    @Test func aCroppedPreviewStillUsesTheRendersNativeScale() {
        let native = CGSize(width: 6000, height: 4000)
        let preview = CGSize(width: 2000, height: 1125)
        let view = CGSize(width: 393, height: 852)

        let fromPreview = DetailZoom.fullResolutionScale(
            nativePixels: native, shownPixels: preview, viewSize: view, screenScale: 3)
        let fromRender = DetailZoom.fullResolutionScale(
            nativePixels: native, shownPixels: native, viewSize: view, screenScale: 3)

        #expect(abs(fromPreview - fromRender) < 0.0001)
        #expect(abs(fromPreview - 6000.0 / 1179.0) < 0.0001)
    }

    /// A kept zoom is native-relative: 100% stays 100% of the next photo's native size, and a
    /// pinched percentage of native stays that percentage (PRD P0-04; PRD In-group culling,
    /// synchronized zoom).
    @Test func aKeptZoomConvertsByTheNativeScaleRatio() {
        let landscape = CGSize(width: 8640, height: 5760)
        let portrait = CGSize(width: 5760, height: 8640)
        let crop = CGSize(width: 2768, height: 1848)
        let view = CGSize(width: 393, height: 852)
        func nativeScale(_ pixels: CGSize) -> CGFloat {
            DetailZoom.fullResolutionScale(
                nativePixels: pixels, shownPixels: pixels, viewSize: view, screenScale: 3)
        }
        let landscapeScale = nativeScale(landscape)
        let portraitScale = nativeScale(portrait)
        let cropScale = nativeScale(crop)

        // 100% of one frame is 100% of the next, portrait or crop.
        #expect(
            abs(
                DetailZoom.convertedScale(
                    landscapeScale, fromNativeScale: landscapeScale, toNativeScale: portraitScale)
                    - portraitScale) < 0.0001)
        #expect(
            abs(
                DetailZoom.convertedScale(
                    landscapeScale, fromNativeScale: landscapeScale, toNativeScale: cropScale)
                    - cropScale) < 0.0001)
        // 150% of native stays 150% of native.
        #expect(
            abs(
                DetailZoom.convertedScale(
                    landscapeScale * 1.5, fromNativeScale: landscapeScale,
                    toNativeScale: portraitScale) - portraitScale * 1.5) < 0.0001)
        // The same native size is unchanged.
        #expect(
            DetailZoom.convertedScale(
                2.5, fromNativeScale: landscapeScale, toNativeScale: landscapeScale) == 2.5)
        // A native size that is unknown leaves the screen scale alone.
        #expect(
            DetailZoom.convertedScale(2.5, fromNativeScale: 0, toNativeScale: portraitScale) == 2.5)
    }

    /// 100% names this photo's own native scale, not another photo's or a fraction of it
    /// (PRD P0-04).
    @Test func fullResolutionNameRequiresThisPhotosNativeScale() {
        let native = CGSize(width: 8640, height: 5760)
        let view = CGSize(width: 393, height: 852)
        let target = DetailZoom.fullResolutionScale(
            nativePixels: native, shownPixels: native, viewSize: view, screenScale: 3)

        #expect(
            DetailZoom.isFullResolution(
                scale: target, nativePixels: native, viewSize: view, screenScale: 3))
        #expect(
            !DetailZoom.isFullResolution(
                scale: target / 2, nativePixels: native, viewSize: view, screenScale: 3))
        // Another photo's 100% is not this photo's 100%.
        let smaller = CGSize(width: 4320, height: 2880)
        #expect(
            !DetailZoom.isFullResolution(
                scale: target, nativePixels: smaller, viewSize: view, screenScale: 3))
        #expect(
            DetailZoom.isFullResolution(
                scale: target / 2, nativePixels: smaller, viewSize: view, screenScale: 3))
    }

    /// A RAW's 100% is its sensor pixels, so a double tap while that size is unknown has no
    /// target: the preview's own 100% is never it. Once the render lands, the render's size is the
    /// target (PRD P0-04; G1 "Preview, detail (I2)"; #111).
    @Test func aRAWWithUnknownSizeNeverDoubleTapsToThePreviews100Percent() {
        let preview = CGSize(width: 1616, height: 1080)
        let render = CGSize(width: 8640, height: 5760)
        let view = CGSize(width: 393, height: 852)
        let previewTarget = DetailZoom.fullResolutionScale(
            imagePixels: preview, viewSize: view, screenScale: 3)
        let renderTarget = DetailZoom.fullResolutionScale(
            nativePixels: render, shownPixels: render, viewSize: view, screenScale: 3)

        // Unknown: no target at all, so the view cannot zoom to the preview's pixels.
        #expect(
            DetailZoom.fullResolutionTarget(
                nativePixels: nil, shownPixels: preview, viewSize: view, screenScale: 3) == nil)

        // The render's own size is the target, and it is not the preview's 100%.
        if let target = DetailZoom.fullResolutionTarget(
            nativePixels: render, shownPixels: preview, viewSize: view, screenScale: 3)
        {
            #expect(abs(target - renderTarget) < 0.0001)
            #expect(abs(target - previewTarget) > 0.0001)
        } else {
            Issue.record("The render's size gave no 100% target")
        }
    }

    /// A 100% zoom computed from a wrong size is corrected once when the render lands, and a zoom
    /// computed from the right size is left alone (PRD P0-04; G1 "Preview, detail (I2)"; #111).
    @Test func aWrongSizeIsCorrectedOnceWhenTheRenderLands() {
        let view = CGSize(width: 393, height: 852)
        let preview = CGSize(width: 1616, height: 1080)
        let render = CGSize(width: 8640, height: 5760)
        let renderTarget = DetailZoom.fullResolutionScale(
            nativePixels: render, shownPixels: render, viewSize: view, screenScale: 3)
        let previewTarget = DetailZoom.fullResolutionScale(
            imagePixels: preview, viewSize: view, screenScale: 3)

        // The size the zoom was computed with is the render's own: no second zoom.
        #expect(
            DetailZoom.retargetedFullResolutionScale(
                from: render, to: render, viewSize: view, screenScale: 3) == nil)

        // A wrong size — the preview's, or none at all — is corrected to the render's 100%.
        for wrong in [preview, nil] as [CGSize?] {
            if let corrected = DetailZoom.retargetedFullResolutionScale(
                from: wrong, to: render, viewSize: view, screenScale: 3)
            {
                #expect(abs(corrected - renderTarget) < 0.0001)
                #expect(abs(corrected - previewTarget) > 0.0001)
            } else {
                Issue.record("The render's size did not correct the zoom")
            }
        }
    }
}
