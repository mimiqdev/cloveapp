import CoreGraphics

/// A point in an image's own coordinates, 0 to 1 from its top-left corner (PRD In-group
/// culling, synchronized zoom).
///
/// A group view keeps the zoomed position while it moves between the group's photos, so the same
/// spot — an eye, a face — stays under the viewport. The position is one value for both axes of
/// the image and does not depend on either photo's size, which is why it survives the move
/// (PRD In-group culling, comparison and elimination; PRD P0-12). Values outside 0 to 1 are
/// clamped, because a viewport clamped to the image can never be centred outside it.
public struct DetailZoomAnchor: Hashable, Sendable {
    /// The horizontal position, 0 at the image's left edge and 1 at its right edge.
    public let x: CGFloat

    /// The vertical position, 0 at the image's top edge and 1 at its bottom edge.
    public let y: CGFloat

    /// Creates one position, clamped to the image (PRD In-group culling).
    public init(x: CGFloat, y: CGFloat) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    /// The image's own middle, the position a fresh photo starts from (PRD P0-04).
    public static let centre = DetailZoomAnchor(x: 0.5, y: 0.5)
}

/// Keeping the zoomed position while another photo is shown (PRD In-group culling, synchronized
/// zoom; PRD P0-12).
///
/// The scroll view reports its zoom as a scale plus a content offset, and the position that has
/// to survive the move is the image point at the centre of what it shows. These two conversions
/// are the whole rule: one reads that point from a zoomed viewport, the other finds the content
/// point a position lands on at a scale. Both are pure, so they run on macOS without a simulator,
/// and both answer the neutral value for a view or image that has not been laid out yet.
extension DetailZoom {
    /// The image point at the centre of a zoomed viewport, or nil at fit (PRD In-group culling,
    /// synchronized zoom).
    ///
    /// At the fit scale the whole image is on screen, so there is no position to keep and the
    /// answer is nil. A degenerate image or view answers nil too, because a view that has not been
    /// laid out must not disturb the zoom a later photo opens with.
    ///
    /// - Parameters:
    ///   - scale: The scroll view's zoom scale; at or below 1 the view is at fit.
    ///   - contentOffset: The visible origin, in content points.
    ///   - imagePixels: The shown bitmap's size in pixels.
    ///   - viewSize: The view's size in points.
    public static func centreAnchor(
        scale: CGFloat,
        contentOffset: CGPoint,
        imagePixels: CGSize,
        viewSize: CGSize
    ) -> DetailZoomAnchor? {
        guard scale > 1, imagePixels.width > 0, imagePixels.height > 0,
            viewSize.width > 0, viewSize.height > 0
        else { return nil }
        let fitted = fittedSize(imagePixels: imagePixels, viewSize: viewSize)
        guard fitted.width > 0, fitted.height > 0 else { return nil }
        // The content is the view scaled up, so the middle of the visible rect is the offset plus
        // half a view; dividing by the scale puts it back in the fit view's coordinates.
        let centre = CGPoint(
            x: contentOffset.x + viewSize.width / 2, y: contentOffset.y + viewSize.height / 2)
        let origin = CGPoint(
            x: (viewSize.width - fitted.width) / 2, y: (viewSize.height - fitted.height) / 2)
        return DetailZoomAnchor(
            x: (centre.x / scale - origin.x) / fitted.width,
            y: (centre.y / scale - origin.y) / fitted.height)
    }

    /// The content point an image point lands on at a zoom scale (PRD In-group culling,
    /// synchronized zoom).
    ///
    /// The image is drawn aspect-fit and centred, so its fit rect's origin is offset inside the
    /// view and both axes scale from there. ``DetailZoom/visibleRect(centredOn:contentSize:viewSize:)``
    /// turns the answer into the offset a viewport needs, clamped to the image.
    ///
    /// - Parameters:
    ///   - anchor: The image point to centre, in unit image coordinates.
    ///   - scale: The zoom scale the viewport shows.
    ///   - imagePixels: The bitmap's size in pixels.
    ///   - viewSize: The view's size in points.
    public static func contentPoint(
        for anchor: DetailZoomAnchor,
        scale: CGFloat,
        imagePixels: CGSize,
        viewSize: CGSize
    ) -> CGPoint {
        let fitted = fittedSize(imagePixels: imagePixels, viewSize: viewSize)
        guard fitted.width > 0, fitted.height > 0, scale > 0 else { return .zero }
        return CGPoint(
            x: ((viewSize.width - fitted.width) / 2 + anchor.x * fitted.width) * scale,
            y: ((viewSize.height - fitted.height) / 2 + anchor.y * fitted.height) * scale)
    }
}
