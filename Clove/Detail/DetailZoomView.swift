import CloveCore
import SwiftUI
import UIKit

/// The scale above fit at which the preview counts as zoomed (PRD Detail gestures, PRD P0-04).
///
/// A pinch that comes back to fit can settle a hair above the minimum scale, and the marking
/// gesture, the zoom name and the double-tap action all have to agree on where "fit" ends; one
/// tolerance keeps them from drifting apart.
enum DetailFitScale {
    /// How far above the fit scale a view may sit and still count as fit.
    static let tolerance: CGFloat = 1.005
}

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

extension DetailZoomAnchor {
    /// The same position as SwiftUI's unit point, for the preview's zoom command (PRD P0-04).
    var unitPoint: UnitPoint { UnitPoint(x: x, y: y) }
}

/// The zoom one preview shows, so the next photo can keep it (PRD In-group culling,
/// synchronized zoom).
///
/// The scale is the zoom level and the anchor is the image point at the centre of what the view
/// shows, in unit image coordinates, so the same spot stays under the viewport when another photo
/// takes the place of this one (PRD In-group culling, comparison and elimination).
struct DetailZoomSnapshot: Hashable {
    /// The scroll view's zoom scale, one or more.
    let scale: CGFloat

    /// The image point at the centre of the visible rect (PRD P0-04, PRD P0-12).
    let anchor: DetailZoomAnchor
}

/// A handle on the preview's UIKit view, so the screen can read the zoom it shows.
///
/// The synchronized zoom rule needs the position the view is on *before* the next photo's pixels
/// replace the current ones: the view is the only place that zoom is known, and a screen cannot
/// read it from SwiftUI state without reporting every scroll event (PRD In-group culling,
/// synchronized zoom). The reference is weak, so a preview that leaves the screen leaves nothing
/// behind.
@MainActor
final class DetailZoomProbe {
    /// The preview's container view, alive while the preview is on screen.
    weak var container: DetailZoomContainerView?
}

/// The detail preview: a scroll view with pinch zoom, pan, one centre double-tap and single
/// taps on the two edges (PRD P0-04, PRD Gestures and keyboard), plus the vertical marking
/// swipes that rate and reject (PRD P0-06, PRD Detail gestures).
///
/// The scroll view is the system zoom container the plan names: pinch and one-finger pan are its
/// own, the image is drawn aspect-fit in it, and the minimum scale of 1 is the fit view. The
/// edges carry a single-tap recognizer with no failure requirement, so a tap there navigates
/// immediately instead of waiting to see whether a double tap follows (PRD Detail and marking).
/// The centre's presentation tap waits for its double tap, so toggling chrome cannot interrupt
/// a focus check, and it is off while zoomed, where a tap does nothing (PRD Detail gestures).
/// Edge taps keep their immediate navigation path.
///
/// A double tap on an edge is therefore two single taps: the edge belongs to navigation only,
/// and the document states that width in ``DetailEdgeZone/edgeFraction``. Double taps while
/// zoomed are reported to the screen, which decides between 100% and fit.
///
/// At fit, the container's one-finger pan locks its initial dominant axis. Horizontal drags
/// navigate; vertical drags use the unchanged marking rules. While zoomed, only the scroll
/// view pans. Pinch and taps retain their existing recognizers.
struct DetailZoomView: UIViewRepresentable {
    /// The pixels to show, or nil while the screen is loading or has nothing to show.
    let image: CGImage?

    /// The photo's oriented full-resolution pixel size, or nil when it is unknown.
    ///
    /// The scroll view's zoom limit follows it, so a pinch can reach native 100% while a smaller
    /// embedded preview is still on screen (PRD P0-04; G1 "Preview, detail (I2)"). The limit is
    /// still at least ``DetailZoom/inspectionScale``, so a photo whose native 100% needs less can
    /// be inspected past it. Without a size the shown bitmap is the full resolution, which is the
    /// behaviour before the native size was known.
    let fullResolutionPixels: CGSize?

    /// The zoom the screen wants, or nil to leave the view's own pinch alone.
    let command: DetailZoomCommand?

    /// Whether the centre double-tap does anything (C12's `doubleTap` setting).
    let doubleTapZoomEnabled: Bool

    /// The current settings and initial axis split for marking.
    let rules: MarkingInputRules

    /// Captured once by the session as the relative slider's starting value.
    let currentRating: Rating

    /// The live rating or Reject indicator (PRD P0-06).
    let feedback: DetailSwipeFeedback

    /// Reports every scale the scroll view shows, for the screen's pixel-demand decision.
    let onZoomChange: (CGFloat) -> Void

    /// Reports edge navigation from a tap or a completed swipe.
    let onEdgeTap: (DetailEdgeZone) -> Void

    /// Reports a double tap in the centre area, with the tapped point in unit image coordinates.
    let onDoubleTap: (UnitPoint) -> Void

    /// Reports the preview value once per release; cancellation reports nothing.
    let onMarkingSwipe: (Rating) -> Void

    /// Cancels pending auto-advance when navigation or marking starts.
    let onSwipeBegin: () -> Void

    let hasPrevious: Bool
    let hasNext: Bool

    /// A handle the screen reads the shown zoom from, or nil when it needs none
    /// (PRD In-group culling, synchronized zoom).
    var probe: DetailZoomProbe?

    func makeUIView(context: Context) -> DetailZoomContainerView {
        let view = DetailZoomContainerView()
        probe?.container = view
        view.onZoomChange = onZoomChange
        view.onEdgeTap = onEdgeTap
        view.onDoubleTap = onDoubleTap
        view.onMarkingSwipe = onMarkingSwipe
        view.onSwipeBegin = onSwipeBegin
        view.hasPrevious = hasPrevious
        view.hasNext = hasNext
        view.feedback = feedback
        view.rules = rules
        view.currentRating = currentRating
        return view
    }

    func updateUIView(_ view: DetailZoomContainerView, context: Context) {
        view.onZoomChange = onZoomChange
        view.onEdgeTap = onEdgeTap
        view.onDoubleTap = onDoubleTap
        view.onMarkingSwipe = onMarkingSwipe
        view.onSwipeBegin = onSwipeBegin
        view.hasPrevious = hasPrevious
        view.hasNext = hasNext
        view.feedback = feedback
        view.rules = rules
        view.currentRating = currentRating
        view.setDoubleTapEnabled(doubleTapZoomEnabled)
        // The image goes in before the command, so a 100% command for new pixels uses the new
        // pixel size and a quality change never needs a second pass.
        view.setImage(image, fullResolutionPixels: fullResolutionPixels)
        if let command { view.apply(command) }
    }
}

/// The scroll view and its one image view, plus the page's tap zones, the marking pan and the
/// zoom application.
@MainActor
final class DetailZoomContainerView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let edgeTap = UITapGestureRecognizer()
    private let centreDoubleTap = UITapGestureRecognizer()
    private let centreChromeTap = UITapGestureRecognizer()
    private let markingPan = UIPanGestureRecognizer()
    private let haptics = MarkingSwipeHaptics()
    private var isNavigating = false

    /// One preview session for either direction, discarded on cancel.
    private var markingSession: MarkingSwipeSession?
    private var markingStartTime: TimeInterval = 0
    private var markingTouchStart: CGPoint = .zero
    private var velocitySample: Task<Void, Never>?
    var currentRating: Rating = .unrated

    /// The pixels on screen, so a command can clamp and a double tap can report an image point.
    private var shownPixels: CGSize = .zero

    /// The photo's full-resolution size, which sets the zoom limit before the render lands
    /// (PRD P0-04; G1 "Preview, detail (I2)").
    private var fullResolutionPixels: CGSize = .zero

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
    var onMarkingSwipe: ((Rating) -> Void)?
    var onSwipeBegin: (() -> Void)?
    var hasPrevious = false
    var hasNext = false

    /// The live marking indicator (PRD P0-06).
    var feedback: DetailSwipeFeedback?

    /// The rules for the current settings, which also say whether marking gestures are on
    /// (PRD Detail gestures, PRD Gesture-related settings).
    var rules = MarkingInputRules() {
        didSet { updateGestureAvailability() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
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

        edgeTap.delegate = self
        centreChromeTap.delegate = self
        edgeTap.addTarget(self, action: #selector(handleEdgeTap))
        centreDoubleTap.numberOfTapsRequired = 2
        centreDoubleTap.addTarget(self, action: #selector(handleDoubleTap))
        scrollView.addGestureRecognizer(edgeTap)
        scrollView.addGestureRecognizer(centreDoubleTap)
        centreChromeTap.addTarget(self, action: #selector(handleChromeTap))
        centreChromeTap.require(toFail: centreDoubleTap)
        scrollView.addGestureRecognizer(centreChromeTap)

        // The marking pan belongs to the container rather than the scroll view, so it is not one
        // of the scroll view's own gestures. One finger only: a second finger is a pinch, which
        // stays the scroll view's (PRD Detail gestures: pinch always zooms).
        markingPan.maximumNumberOfTouches = 1
        markingPan.delegate = self
        markingPan.addTarget(self, action: #selector(handleMarkingPan))
        addGestureRecognizer(markingPan)

        isAccessibilityElement = true
        accessibilityIdentifier = "clove.detail.preview"
        accessibilityLabel = "Detail preview"
        accessibilityTraits = .image
        accessibilityValue = "Loading"
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "Show or hide controls", target: self,
                selector: #selector(toggleChromeFromAccessibility))
        ]
        updateGestureAvailability()
    }

    /// The zoom the view shows, or nil at fit (PRD In-group culling, synchronized zoom).
    ///
    /// Detail reads this before it shows another photo of the group, so the next photo
    /// opens on the same spot at the same zoom (PRD In-group culling, comparison and elimination).
    /// A view at fit has no position to keep and answers nil.
    var zoomSnapshot: DetailZoomSnapshot? {
        guard
            let anchor = DetailZoom.centreAnchor(
                scale: scrollView.zoomScale, contentOffset: scrollView.contentOffset,
                imagePixels: shownPixels, viewSize: bounds.size)
        else { return nil }
        return DetailZoomSnapshot(scale: scrollView.zoomScale, anchor: anchor)
    }

    /// SwiftUI never decodes this view from a storyboard; the initializer exists because UIView
    /// requires it of every subclass and refuses to build.
    required init?(coder: NSCoder) {
        return nil
    }

    /// Whether a centre tap can show or hide the chrome, which it can only at fit (PRD Detail and
    /// marking).
    var chromeTapIsEnabled: Bool { centreChromeTap.isEnabled }

    /// Replaces the pixels without touching the zoom or the position (PRD P0-04).
    ///
    /// A quality change from an embedded preview to a native render is the same call, so the
    /// view keeps whatever scale and offset the user had, and the render only sharpens the
    /// picture (G1 "Preview, detail (I2)"). The screen issues a command only when the photo
    /// changes, a group keeps a zoom, or a 100% taken from a preview whose size was not known finds
    /// the render's own size.
    ///
    /// A preview and its render share the photo's aspect, so the image's drawn rect does not
    /// move. A camera that crops its embedded preview can give it another aspect; that rect then
    /// changes, so the image point at the viewport's centre is kept as a unit coordinate. With a
    /// crop that unit point names a slightly different pixel, so the visible spot can shift by
    /// the crop margin, but it does not jump to a corner (PRD P0-04; G1 "Preview, detail (I2)").
    func setImage(_ pixels: CGImage?, fullResolutionPixels: CGSize? = nil) {
        let fullResolution = fullResolutionPixels ?? .zero
        guard pixels !== imageView.image?.cgImage || fullResolution != self.fullResolutionPixels
        else { return }
        let previousPixels = shownPixels
        // Read before the pixels change: the point the viewport centres on in the old bitmap.
        let kept = zoomSnapshot
        imageView.image = pixels.map { UIImage(cgImage: $0) }
        if !isNavigating { scrollView.transform = .identity }
        shownPixels = pixels.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        self.fullResolutionPixels = fullResolution
        updateMaximumZoom()
        accessibilityValue = pixels == nil ? "Loading" : "Loaded"
        if let kept, Self.aspectDiffers(previousPixels, shownPixels) {
            isApplyingCommand = true
            zoom(to: kept.scale, around: kept.anchor)
            isApplyingCommand = false
        }
    }

    /// Whether two bitmaps have a materially different aspect ratio.
    ///
    /// Rounding in a camera's embedded preview moves the ratio by far less than this; a preview
    /// cropped to another shape moves it by more, and only that needs the visible point restored
    /// (PRD P0-04; G1 "Preview, detail (I2)").
    private static func aspectDiffers(_ first: CGSize, _ second: CGSize) -> Bool {
        guard first.width > 0, first.height > 0, second.width > 0, second.height > 0
        else { return false }
        let firstAspect = first.width / first.height
        let secondAspect = second.width / second.height
        return abs(firstAspect - secondAspect) / max(firstAspect, secondAspect) > 0.005
    }

    /// Enables or disables the centre double-tap (C12's `doubleTap` setting).
    func setDoubleTapEnabled(_ isEnabled: Bool) {
        centreDoubleTap.isEnabled = isEnabled
    }

    /// Switches the fit-only inputs off while zoomed, where a one-finger drag pans the image and a
    /// tap changes nothing (PRD Detail gestures).
    ///
    /// The scroll view's own pan stays enabled throughout: at fit there is nothing to scroll, so
    /// the two pans cannot compete, and simultaneous recognition below means neither cancels the
    /// other. Turning the scroll view's pan off at fit would also cost U5's pinch, which needs it
    /// for two-finger panning as it zooms.
    ///
    /// The chrome tap is off rather than left to fail its zoom check when it is delivered. A tap
    /// made while zoomed is held until the double tap it may belong to fails, so under load its
    /// action can arrive after a double tap has already returned the view to fit; it would then
    /// toggle the chrome and hide Info, Undo and the capsule for a tap the person made while
    /// zoomed (#131). A disabled recognizer never starts, so that tap has nothing to deliver.
    private func updateGestureAvailability() {
        let isZoomed = scrollView.zoomScale > DetailFitScale.tolerance
        markingPan.isEnabled = !isZoomed
        centreChromeTap.isEnabled = !isZoomed
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
            zoom(to: scale, around: DetailZoomAnchor(x: anchor.x, y: anchor.y))
        }
        // A programmatic zoom is the same handoff as a pinch, whether or not the delegate fires.
        updateGestureAvailability()
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
            zoom(to: previousScale, around: .centre)
        }
        isApplyingCommand = false
        updateGestureAvailability()
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        markingPan.isEnabled = false
        markingPan.isEnabled = true
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // The zoom level decides whether a one-finger drag pans or marks, so the split follows
        // every pinch, including one the screen did not ask for (PRD Detail gestures).
        updateGestureAvailability()
        guard !isApplyingCommand else { return }
        onZoomChange?(scrollView.zoomScale)
    }

    // MARK: - Marking swipe

    /// UIPan translation starts at recognition, losing more distance on a fast swipe. Capture
    /// touch-down so the continuous ladder always measures the full travel from the same origin.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool
    {
        if recognizer === markingPan { markingTouchStart = touch.location(in: self) }
        return true
    }

    /// Locks the dominant axis once. Later samples cannot switch between navigation and marking.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        if recognizer === edgeTap {
            return DetailZoom.edgeZone(for: recognizer.location(in: self), in: bounds.size)
                != .centre
        }
        if recognizer === centreChromeTap {
            return DetailZoom.edgeZone(for: recognizer.location(in: self), in: bounds.size)
                == .centre
        }
        guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
        guard scrollView.zoomScale <= DetailFitScale.tolerance else { return false }
        let translation = pan.translation(in: self)
        isNavigating =
            NavigationSwipeRules.axis(
                horizontal: Double(translation.x), vertical: Double(translation.y)) == .horizontal
        if isNavigating { return true }
        return rules.beginsSwipe(
            horizontalTravel: Double(translation.x),
            verticalTravel: -Double(translation.y),
            isZoomed: scrollView.zoomScale > DetailFitScale.tolerance)
    }

    /// Lets the fit pan read drags alongside scrolling and yield to pinch.
    /// Zoomed one-finger drags belong to the scroll view alone.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === markingPan
            && (other === scrollView.panGestureRecognizer
                || other === scrollView.pinchGestureRecognizer)
    }

    /// Feeds one sample of the drag to the session and shows the step it reached.
    ///
    /// UIKit counts down as positive; the session counts up as positive and samples the first
    /// approximately 100 ms once to choose slow or quick.
    @objc func handleMarkingPan(_ pan: UIPanGestureRecognizer) {
        if isNavigating {
            handleNavigationPan(pan)
            return
        }
        let travel = Double(markingTouchStart.y - pan.location(in: self).y)
        switch pan.state {
        case .began:
            beginMarkingSwipe(at: markingTouchStart)
            updateMarkingSwipe(travel: travel)
        case .changed:
            updateMarkingSwipe(travel: travel)
        case .ended:
            updateMarkingSwipe(travel: travel, releasing: true)
            let rating = markingSession?.rating
            clearMarkingSwipe()
            if let rating { onMarkingSwipe?(rating) }
        case .cancelled, .failed:
            // A system cancel writes nothing and leaves the marks as they were (PRD P0-06).
            clearMarkingSwipe()
        default:
            break
        }
    }

    private func beginMarkingSwipe(at startLocation: CGPoint) {
        onSwipeBegin?()
        haptics.prepare()
        markingStartTime = ProcessInfo.processInfo.systemUptime
        markingSession = rules.swipeSession(startingRating: currentRating)
        feedback?.startLocation = startLocation
        feedback?.rating = currentRating
        // Resolve the initial speed even if the finger stops moving inside the sample window.
        // This timer only chooses the mode; holding never advances clear to Reject.
        velocitySample = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(MarkingSwipeRules.velocityWindow))
            } catch { return }
            guard let self else { return }
            self.updateMarkingSwipe(
                travel: Double(self.markingTouchStart.y - self.markingPan.location(in: self).y))
        }
    }

    /// Every crossing previews and ticks; only the release callback writes a mark.
    private func updateMarkingSwipe(travel: Double, releasing: Bool = false) {
        guard var session = markingSession else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - markingStartTime
        let crossings =
            releasing
            ? session.release(travel: travel, elapsed: elapsed)
            : session.update(travel: travel, elapsed: elapsed)
        for crossing in crossings { haptics.crossed(crossing.haptic) }
        markingSession = session
        feedback?.rating = session.rating
    }

    private func clearMarkingSwipe() {
        velocitySample?.cancel()
        velocitySample = nil
        markingSession = nil
        feedback?.clear()
    }

    // MARK: - Navigation swipe

    private func handleNavigationPan(_ pan: UIPanGestureRecognizer) {
        let travel = Double(pan.translation(in: self).x)
        switch pan.state {
        case .began:
            onSwipeBegin?()
            fallthrough
        case .changed:
            scrollView.layer.removeAllAnimations()
            let offset = NavigationSwipeRules.offset(
                travel: travel, width: Double(bounds.width),
                hasPrevious: hasPrevious, hasNext: hasNext)
            scrollView.transform = CGAffineTransform(translationX: offset, y: 0)
        case .ended:
            let step = NavigationSwipeRules.step(
                travel: travel, velocity: Double(pan.velocity(in: self).x),
                width: Double(bounds.width), hasPrevious: hasPrevious, hasNext: hasNext)
            if step != 0 {
                isNavigating = false
                onEdgeTap?(step > 0 ? .next : .previous)
                return
            }
            fallthrough
        case .cancelled, .failed:
            isNavigating = false
            UIView.animate(
                withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0, options: [.curveEaseOut]
            ) {
                self.scrollView.transform = .identity
            }
        default:
            break
        }
    }

    // MARK: - Taps

    /// VoiceOver activation reads the preview; chrome has its own explicit custom action.
    override func accessibilityActivate() -> Bool { true }

    @objc private func toggleChromeFromAccessibility() -> Bool {
        guard scrollView.zoomScale <= DetailFitScale.tolerance else { return false }
        onEdgeTap?(.centre)
        return true
    }

    @objc private func handleChromeTap() {
        guard !UIAccessibility.isVoiceOverRunning,
            DetailZoom.edgeZone(for: centreChromeTap.location(in: self), in: bounds.size) == .centre
        else { return }
        onEdgeTap?(.centre)
    }

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
    ///
    /// The geometry is ``DetailZoom``'s, so a double-tap, a synchronized zoom and a resize all
    /// place the viewport the same way (PRD P0-04; PRD In-group culling, synchronized zoom).
    private func zoom(to scale: CGFloat, around anchor: DetailZoomAnchor) {
        guard bounds.width > 0, bounds.height > 0, shownPixels.width > 0, shownPixels.height > 0
        else { return }
        let target = min(max(scale, 1), max(scrollView.maximumZoomScale, scale))
        scrollView.maximumZoomScale = max(scrollView.maximumZoomScale, target)
        let contentSize = CGSize(
            width: bounds.width * target, height: bounds.height * target)
        let point = DetailZoom.contentPoint(
            for: anchor, scale: target, imagePixels: shownPixels, viewSize: bounds.size)
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

    /// The largest zoom: enough to reach native 100%, and at least the inspection scale.
    ///
    /// The photo's full-resolution size sets it rather than the shown preview, so a pinch can
    /// reach native 100% while the preview is still on screen (PRD P0-04; G1 "Preview, detail
    /// (I2)").
    private func updateMaximumZoom() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = DetailZoom.maximumScale(
            nativePixels: fullResolutionPixels, shownPixels: shownPixels, viewSize: bounds.size,
            screenScale: traitCollection.displayScale)
        scrollView.maximumZoomScale = max(scale, scrollView.zoomScale)
    }
}
