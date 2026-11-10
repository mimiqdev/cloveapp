import CloveCore
import SwiftUI
import UIKit

/// One zoom the screen asks the preview to show (PRD P0-04).
///
/// The screen computes the scale and the image point from ``DetailZoom``'s geometry; the view
/// only applies them. The identifier makes a command happen once, because SwiftUI calls
/// `updateUIView` for every state change and a re-applied zoom would fight the user's pinch.
struct DetailZoomCommand: Equatable {
    /// The command's identity, unique per request from the screen.
    let id: Int

    /// What to show.
    let kind: Kind

    /// A zoom the screen wants, or the fit view the PRD returns to.
    enum Kind: Equatable {
        /// The whole image, at the scroll view's fit scale (PRD P0-04 double-tap to fit).
        case fit

        /// Zoom to the scale, keeping the image point at the unit point centred (PRD P0-04
        /// double-tap to 100% around the tapped point).
        case scale(CGFloat, anchor: UnitPoint)
    }
}

/// The detail preview: a scroll view with pinch zoom, pan, one centre double-tap and single
/// taps on the two edges (PRD P0-04, PRD Gestures and keyboard).
///
/// The scroll view is the system zoom container the plan names: pinch and one-finger pan are its
/// own, the image is drawn aspect-fit in it, and the minimum scale of 1 is the fit view. The
/// edges carry a single-tap recognizer with no failure requirement, so a tap there navigates
/// immediately instead of waiting to see whether a double tap follows (PRD Detail and marking).
/// The centre carries the double-tap recognizer and no single-tap action, so a single tap in the
/// middle does nothing and the double tap is never delayed by an action that does not exist.
///
/// A double tap on an edge is therefore two single taps: the edge belongs to navigation only,
/// and the document states that width in ``DetailEdgeZone/edgeFraction``. Double taps while
/// zoomed are reported to the screen, which decides between 100% and fit.
///
/// Design placeholder: the dark canvas and the plain image are replaced by the visual design;
/// the gestures themselves are the ones P0-04 fixes.
struct DetailZoomView: UIViewRepresentable {
    /// The pixels to show, or nil while the screen is loading or has nothing to show.
    let image: CGImage?

    /// The zoom the screen wants, or nil to leave the view's own pinch alone.
    let command: DetailZoomCommand?

    /// Whether the centre double-tap does anything (C12's `doubleTap` setting).
    let doubleTapZoomEnabled: Bool

    /// Reports every scale the scroll view shows, for the screen's pixel-demand decision.
    let onZoomChange: (CGFloat) -> Void

    /// Reports a single tap on an edge that navigates.
    let onEdgeTap: (DetailEdgeZone) -> Void

    /// Reports a double tap in the centre area, with the tapped point in unit image coordinates.
    let onDoubleTap: (UnitPoint) -> Void

    func makeUIView(context: Context) -> DetailZoomContainerView {
        let view = DetailZoomContainerView()
        view.onZoomChange = onZoomChange
        view.onEdgeTap = onEdgeTap
        view.onDoubleTap = onDoubleTap
        return view
    }

    func updateUIView(_ view: DetailZoomContainerView, context: Context) {
        view.onZoomChange = onZoomChange
        view.onEdgeTap = onEdgeTap
        view.onDoubleTap = onDoubleTap
        view.setDoubleTapEnabled(doubleTapZoomEnabled)
        // The image goes in before the command, so a 100% command for new pixels uses the new
        // pixel size and a quality change never needs a second pass.
        view.setImage(image)
        if let command { view.apply(command) }
    }
}

/// The scroll view and its one image view, plus the page's tap zones and the zoom application.
@MainActor
final class DetailZoomContainerView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let edgeTap = UITapGestureRecognizer()
    private let centreDoubleTap = UITapGestureRecognizer()

    /// The pixels on screen, so a command can clamp and a double tap can report an image point.
    private var shownPixels: CGSize = .zero

    /// The last command applied, so a repeated SwiftUI update never re-applies it.
    private var lastCommand: Int?

    /// The last bounds layout, so a resize re-applies the zoom instead of resetting it.
    private var laidOutSize: CGSize = .zero

    /// Whether the view is applying a zoom the screen asked for, so its delegate callback does
    /// not write SwiftUI state during a view update. A user's pinch is always reported.
    private var isApplyingCommand = false

    var onZoomChange: ((CGFloat) -> Void)?
    var onEdgeTap: ((DetailEdgeZone) -> Void)?
    var onDoubleTap: ((UnitPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        addSubview(scrollView)

        edgeTap.addTarget(self, action: #selector(handleEdgeTap))
        centreDoubleTap.numberOfTapsRequired = 2
        centreDoubleTap.addTarget(self, action: #selector(handleDoubleTap))
        scrollView.addGestureRecognizer(edgeTap)
        scrollView.addGestureRecognizer(centreDoubleTap)

        isAccessibilityElement = true
        accessibilityIdentifier = "clove.detail.preview"
        accessibilityLabel = "Detail preview"
        accessibilityTraits = .image
        accessibilityValue = "Loading"
    }

    /// SwiftUI never decodes this view from a storyboard; the initializer exists because UIView
    /// requires it of every subclass and refuses to build.
    required init?(coder: NSCoder) {
        return nil
    }

    /// Replaces the pixels without touching the zoom or the position (PRD P0-04).
    ///
    /// A quality change from a preview to a native render is the same call, so the view keeps
    /// whatever scale and offset the user had; the screen issues a command only when the photo
    /// changes or a 100% target must follow the new pixel size.
    func setImage(_ pixels: CGImage?) {
        guard pixels !== imageView.image?.cgImage else { return }
        imageView.image = pixels.map { UIImage(cgImage: $0) }
        shownPixels = pixels.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        updateMaximumZoom()
        accessibilityValue = pixels == nil ? "Loading" : "Loaded"
    }

    /// Enables or disables the centre double-tap (C12's `doubleTap` setting).
    func setDoubleTapEnabled(_ isEnabled: Bool) {
        centreDoubleTap.isEnabled = isEnabled
    }

    /// Applies one command exactly once (PRD P0-04).
    func apply(_ command: DetailZoomCommand) {
        guard lastCommand != command.id else { return }
        lastCommand = command.id
        isApplyingCommand = true
        defer { isApplyingCommand = false }
        switch command.kind {
        case .fit:
            scrollView.setZoomScale(1, animated: false)
            scrollView.setContentOffset(.zero, animated: false)
        case .scale(let scale, let anchor):
            zoom(to: scale, around: anchor)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        let previous = laidOutSize
        let previousScale = scrollView.zoomScale
        laidOutSize = bounds.size
        isApplyingCommand = true
        // Reset the zoomed frame first, so the scroll view's fit content is the new bounds
        // rather than the old ones, then re-apply the scale around the middle. A fold, rotation
        // or split resize therefore keeps the zoom instead of dropping back to fit.
        scrollView.setZoomScale(1, animated: false)
        scrollView.frame = bounds
        imageView.frame = bounds
        scrollView.contentSize = bounds.size
        updateMaximumZoom()
        if previous != .zero, previousScale > 1 {
            zoom(to: previousScale, around: .center)
        }
        isApplyingCommand = false
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !isApplyingCommand else { return }
        onZoomChange?(scrollView.zoomScale)
    }

    // MARK: - Taps

    @objc private func handleEdgeTap() {
        let zone = DetailZoom.edgeZone(for: edgeTap.location(in: self), in: bounds.size)
        guard zone != .centre else { return }
        onEdgeTap?(zone)
    }

    @objc private func handleDoubleTap() {
        let location = centreDoubleTap.location(in: self)
        // The edge keeps single taps only, so a double tap there never changes the zoom.
        guard DetailZoom.edgeZone(for: location, in: bounds.size) == .centre else { return }
        onDoubleTap?(imageAnchor(of: location))
    }

    // MARK: - Geometry

    /// Zooms to a scale and centres the image point, clamped to the image (PRD P0-04).
    private func zoom(to scale: CGFloat, around anchor: UnitPoint) {
        guard bounds.width > 0, bounds.height > 0, shownPixels.width > 0, shownPixels.height > 0
        else { return }
        let target = min(max(scale, 1), max(scrollView.maximumZoomScale, scale))
        scrollView.maximumZoomScale = max(scrollView.maximumZoomScale, target)
        let contentSize = CGSize(
            width: bounds.width * target, height: bounds.height * target)
        let imageRect = imageRectAtFit()
        let point = CGPoint(
            x: (imageRect.minX + anchor.x * imageRect.width) * target,
            y: (imageRect.minY + anchor.y * imageRect.height) * target)
        let visible = DetailZoom.visibleRect(
            centredOn: point, contentSize: contentSize, viewSize: bounds.size)
        scrollView.setZoomScale(target, animated: false)
        scrollView.setContentOffset(visible.origin, animated: false)
    }

    /// The point a view location names, in unit image coordinates.
    private func imageAnchor(of location: CGPoint) -> UnitPoint {
        let rect = imageRectAtFit()
        guard rect.width > 0, rect.height > 0 else { return .center }
        return UnitPoint(
            x: min(max((location.x - rect.minX) / rect.width, 0), 1),
            y: min(max((location.y - rect.minY) / rect.height, 0), 1))
    }

    /// Where the aspect-fit image is drawn in the scroll view's own bounds at the fit scale.
    private func imageRectAtFit() -> CGRect {
        let fitted = DetailZoom.fittedSize(imagePixels: shownPixels, viewSize: bounds.size)
        return CGRect(
            x: (bounds.width - fitted.width) / 2, y: (bounds.height - fitted.height) / 2,
            width: fitted.width, height: fitted.height)
    }

    /// The largest zoom: enough to reach 100%, and at least the inspection scale.
    private func updateMaximumZoom() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = DetailZoom.maximumScale(
            imagePixels: shownPixels, viewSize: bounds.size,
            screenScale: traitCollection.displayScale)
        scrollView.maximumZoomScale = max(scale, scrollView.zoomScale)
    }
}
