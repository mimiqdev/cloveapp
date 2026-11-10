import CoreGraphics

/// The zoom geometry of one detail preview (PRD P0-04; G1 "Preview, detail (I2)").
///
/// PRD Detail and marking asks for a full-width preview, pinch zoom, a double-tap to 100%
/// around the tapped point and a double-tap back to fit. The arithmetic that decides those
/// zooms lives here rather than in the scroll view, so it runs on macOS without a simulator:
/// the image's fit size, the scale that makes one image pixel fill one screen pixel, the part
/// of the zoomed image a viewport shows around a point, and the edge zones that navigate.
///
/// The caller keeps one unit per value: the view and the image's on-screen size in points, the
/// bitmap in pixels, and `screenScale` as device pixels per point. A zero or negative size
/// answers the neutral value instead of dividing by zero, because a view that has not been
/// laid out yet must not disturb the zoom the user asked for.
public enum DetailZoom {
    /// The largest zoom the scroll view offers when 100% needs less (PRD P0-04 pinch zoom).
    ///
    /// Focus inspection is useful past one screen pixel per image pixel, so the view allows at
    /// least this much. It is a starting value, not a measured one.
    public static let inspectionScale: CGFloat = 4

    /// The size that shows a whole image in a view, aspect preserved (PRD P0-04 full-width
    /// preview).
    ///
    /// The image fills one axis of the view and is smaller than the other, which is what the
    /// scroll view draws at its fit scale of 1. A degenerate image or view answers `.zero`.
    public static func fittedSize(imagePixels: CGSize, viewSize: CGSize) -> CGSize {
        guard imagePixels.width > 0, imagePixels.height > 0,
            viewSize.width > 0, viewSize.height > 0
        else { return .zero }
        let factor = min(viewSize.width / imagePixels.width, viewSize.height / imagePixels.height)
        return CGSize(width: imagePixels.width * factor, height: imagePixels.height * factor)
    }

    /// The zoom scale that shows one full-resolution image pixel per screen pixel (PRD P0-04
    /// double-tap to 100%; G1 "Preview, detail (I2)").
    ///
    /// The photo's full-resolution size is read before a RAW render arrives, so the 100% target is
    /// the same for the embedded preview and for the render that replaces it (G1 "Preview, detail
    /// (I2)"). The preview is drawn enlarged, soft, at that scale; the render then supplies the
    /// pixels without a second zoom (PRD P0-04).
    ///
    /// The scale is one native image pixel per screen pixel for the image as the render will fit
    /// it, so it follows `nativePixels`. `shownPixels` supplies that size only when the read could
    /// not give one, which is the behaviour before the native size was known; a preview
    /// with another aspect than the photo — a camera that crops its embedded preview — still
    /// lands at the render's native 100%, and only the unit image point at the viewport has to be
    /// kept when the pixels change (PRD P0-04; G1 "Preview, detail (I2)").
    ///
    /// The two axes answer the same scale for an aspect-preserved size; the larger is used so
    /// rounding can never leave the view below native resolution. The result is never below the
    /// fit scale of 1, because the scroll view cannot zoom out past the whole image; an image too
    /// small to fill its view already shows more than one screen pixel per image pixel at fit.
    public static func fullResolutionScale(
        nativePixels: CGSize, shownPixels: CGSize, viewSize: CGSize, screenScale: CGFloat
    ) -> CGFloat {
        guard screenScale > 0 else { return 1 }
        let native =
            nativePixels.width > 0 && nativePixels.height > 0 ? nativePixels : shownPixels
        let fitted = fittedSize(imagePixels: native, viewSize: viewSize)
        guard fitted.width > 0, fitted.height > 0 else { return 1 }
        let horizontal = native.width / (screenScale * fitted.width)
        let vertical = native.height / (screenScale * fitted.height)
        return max(1, horizontal, vertical)
    }

    /// The scroll-view scale a double tap to 100% adopts, or nil while the photo's 100% is
    /// unknown (PRD P0-04; G1 "Preview, detail (I2)").
    ///
    /// A photo whose 100% is its RAW's sensor pixels has no target until that size is known: the
    /// preview on screen is smaller than the sensor, so its own pixels are never 100% (G1 "Preview,
    /// detail (I2)"). The view keeps its zoom, starts the native render, and asks again with the
    /// render's size.
    ///
    /// A photo without a RAW always has a size of its own, so nil is only the RAW's unknown size.
    /// That is why the caller passes nil rather than the preview's pixels: ``fullResolutionScale``
    /// already answers those for the photos where they are the truth.
    public static func fullResolutionTarget(
        nativePixels: CGSize?, shownPixels: CGSize, viewSize: CGSize, screenScale: CGFloat
    ) -> CGFloat? {
        guard let nativePixels, nativePixels.width > 0, nativePixels.height > 0 else { return nil }
        return fullResolutionScale(
            nativePixels: nativePixels, shownPixels: shownPixels, viewSize: viewSize,
            screenScale: screenScale)
    }

    /// The zoom a requested 100% must move to when pixels of another size arrive, or nil when it
    /// already shows the photo's 100% (PRD P0-04; G1 "Preview, detail (I2)").
    ///
    /// The 100% target is computed from the size known when the double tap happens, which may be
    /// a header that describes the preview or nothing at all. The render that replaces the preview
    /// is the photo's own pixels, so its size is 100% from then on: when it differs from the size
    /// the zoom was computed with, the view retargets once, at the same unit image point. Equal
    /// sizes answer nil, so a correct size and a same-sized render never move the zoom a second
    /// time.
    ///
    /// - Parameters:
    ///   - requestedSize: The size the current 100% zoom was computed with, or nil while it is
    ///     unknown.
    ///   - pixels: The arriving image's oriented full-resolution size.
    public static func retargetedFullResolutionScale(
        from requestedSize: CGSize?, to pixels: CGSize, viewSize: CGSize, screenScale: CGFloat
    ) -> CGFloat? {
        guard requestedSize != pixels else { return nil }
        return fullResolutionTarget(
            nativePixels: pixels, shownPixels: pixels, viewSize: viewSize, screenScale: screenScale)
    }

    /// The zoom scale that shows one image pixel per screen pixel for a bitmap whose own size
    /// is its full resolution (PRD P0-04 double-tap to 100%).
    ///
    /// A shown bitmap with no separate full-resolution size, such as a HIF that is never fully
    /// decoded or a file whose size could not be read, answers as it did before the native size was
    /// known.
    public static func fullResolutionScale(
        imagePixels: CGSize, viewSize: CGSize, screenScale: CGFloat
    ) -> CGFloat {
        fullResolutionScale(
            nativePixels: imagePixels, shownPixels: imagePixels, viewSize: viewSize,
            screenScale: screenScale)
    }

    /// The scroll view's largest zoom: enough for native 100%, and at least
    /// ``inspectionScale`` (PRD P0-04 pinch zoom; G1 "Preview, detail (I2)").
    ///
    /// The photo's full-resolution size, not the shown bitmap, sets the limit, so a pinch can
    /// reach native 100% while the embedded preview is still on screen. Native sizes large
    /// enough that 100% needs more than ``inspectionScale`` stop there, because focus inspection
    /// needs native pixels and nothing beyond them (G1 "Preview, detail (I2)").
    public static func maximumScale(
        nativePixels: CGSize, shownPixels: CGSize, viewSize: CGSize, screenScale: CGFloat
    ) -> CGFloat {
        max(
            inspectionScale,
            fullResolutionScale(
                nativePixels: nativePixels, shownPixels: shownPixels, viewSize: viewSize,
                screenScale: screenScale))
    }

    /// The scale a kept zoom becomes on a photo whose native 100% needs another scale
    /// (PRD P0-04; PRD In-group culling, synchronized zoom).
    ///
    /// A group, and a detail view that keeps the zoom level while navigating, compare photos of
    /// the same scene that can differ in native size: a portrait frame of the same sensor, or an
    /// APS-C crop. The zoom level that survives that move is the native-relative one, so 100% of
    /// the previous photo stays 100% of the next one and a pinched 150% of native stays 150% of
    /// native. The ratio of the two native scales is the whole rule; a degenerate scale keeps the
    /// screen scale, which is what a caller uses when a native size is unknown.
    ///
    /// - Parameters:
    ///   - scale: The previous photo's scroll-view zoom scale.
    ///   - previousNativeScale: The previous photo's 100% scale, from
    ///     ``fullResolutionScale(nativePixels:shownPixels:viewSize:screenScale:)``.
    ///   - nativeScale: The next photo's 100% scale, from the same call.
    public static func convertedScale(
        _ scale: CGFloat, fromNativeScale previousNativeScale: CGFloat,
        toNativeScale nativeScale: CGFloat
    ) -> CGFloat {
        guard previousNativeScale > 0, nativeScale > 0 else { return scale }
        return scale * nativeScale / previousNativeScale
    }

    /// Whether a zoom scale shows this photo's native 100% (PRD P0-04).
    ///
    /// A view that keeps the zoom level across photos, or shows a group whose photos have
    /// different native sizes, can sit at a scale that is another photo's 100%. The HUD reads
    /// 100% only when this photo's own native scale is on screen; half a percent absorbs rounding
    /// in a layout, so a pinch that settles just off 100% still reports its own percentage.
    public static func isFullResolution(
        scale: CGFloat, nativePixels: CGSize, viewSize: CGSize, screenScale: CGFloat
    ) -> Bool {
        let target = fullResolutionScale(
            nativePixels: nativePixels, shownPixels: nativePixels, viewSize: viewSize,
            screenScale: screenScale)
        return abs(scale - target) <= max(target, 1) * 0.005
    }

    /// The scroll view's largest zoom when the shown bitmap is its own full resolution
    /// (PRD P0-04 pinch zoom).
    public static func maximumScale(
        imagePixels: CGSize, viewSize: CGSize, screenScale: CGFloat
    ) -> CGFloat {
        maximumScale(
            nativePixels: imagePixels, shownPixels: imagePixels, viewSize: viewSize,
            screenScale: screenScale)
    }

    /// The part of `contentSize` a viewport of `viewSize` shows, centred on `point` as far as
    /// the content allows (PRD P0-04 "centred on the tapped point").
    ///
    /// The result is clamped to the content, so a point near an edge shows the edge instead of
    /// empty space. Content smaller than the viewport on an axis shows that whole axis from its
    /// origin, and a degenerate content or viewport answers `.zero`.
    public static func visibleRect(
        centredOn point: CGPoint, contentSize: CGSize, viewSize: CGSize
    ) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0,
            viewSize.width > 0, viewSize.height > 0
        else { return .zero }
        let size = CGSize(
            width: min(viewSize.width, contentSize.width),
            height: min(viewSize.height, contentSize.height))
        let origin = CGPoint(
            x: min(max(point.x - size.width / 2, 0), contentSize.width - size.width),
            y: min(max(point.y - size.height / 2, 0), contentSize.height - size.height))
        return CGRect(origin: origin, size: size)
    }

    /// Which edge zone owns a tap at `point` (PRD P0-04, PRD Detail and marking).
    ///
    /// The zones are the outer 18% of the preview's width on each side, the width the design's
    /// edge hints cover (``DetailEdgeZone/edgeFraction``). A degenerate width has no edge.
    public static func edgeZone(for point: CGPoint, in viewSize: CGSize) -> DetailEdgeZone {
        guard viewSize.width > 0 else { return .centre }
        let edge = viewSize.width * DetailEdgeZone.edgeFraction
        if point.x < edge { return .previous }
        if point.x >= viewSize.width - edge { return .next }
        return .centre
    }
}
