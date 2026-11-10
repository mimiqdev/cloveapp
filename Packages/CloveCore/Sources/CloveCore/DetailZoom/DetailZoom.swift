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

    /// The zoom scale that shows one image pixel per screen pixel (PRD P0-04 double-tap to 100%).
    ///
    /// The two axes answer the same scale; the larger is used so rounding can never leave the
    /// view below native resolution. The result is never below the fit scale
    /// of 1, because the scroll view cannot zoom out past the whole image; an image too small to
    /// fill its view already shows more than one screen pixel per image pixel at fit.
    public static func fullResolutionScale(
        imagePixels: CGSize, viewSize: CGSize, screenScale: CGFloat
    ) -> CGFloat {
        guard screenScale > 0 else { return 1 }
        let fitted = fittedSize(imagePixels: imagePixels, viewSize: viewSize)
        guard fitted.width > 0, fitted.height > 0 else { return 1 }
        let horizontal = imagePixels.width / (screenScale * fitted.width)
        let vertical = imagePixels.height / (screenScale * fitted.height)
        // `horizontal` and `vertical` agree for an aspect-preserved fit; max keeps the
        // measurement exact when the two differ by rounding.
        return max(1, horizontal, vertical)
    }

    /// The scroll view's largest zoom: enough for 100%, and at least ``inspectionScale``.
    public static func maximumScale(
        imagePixels: CGSize, viewSize: CGSize, screenScale: CGFloat
    ) -> CGFloat {
        max(
            inspectionScale,
            fullResolutionScale(
                imagePixels: imagePixels, viewSize: viewSize, screenScale: screenScale))
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
