import CloveCore
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

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

/// The detail preview: a scroll view with pinch zoom, pan, double-tap zoom everywhere, uniform
/// single-tap chrome toggle at fit and zoom, and fit-only swipes for navigation and marking (PRD
/// P0-04, PRD Gestures and keyboard, PRD Detail gestures).
///
/// The scroll view is the system zoom container the plan names: pinch and one-finger pan are its
/// own, the image is drawn aspect-fit in it, and the minimum scale of 1 is the fit view. Single
/// taps anywhere on the preview wait for the double-tap recognizer to fail so toggling chrome
/// cannot interrupt a focus check, and toggle chrome at both fit and zoomed scales (#273).
///
/// Double taps anywhere on the preview toggle between 100% and fit (owner decision, 2026-11-14,
/// #252). At fit, the container's one-finger pan locks its initial dominant axis: horizontal drags
/// navigate, and vertical drags use the unchanged marking rules. While zoomed, only the scroll
/// view pans, and pinch and double tap retain their existing recognizers.
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

    /// Whether double-tap zoom does anything (C12's `doubleTap` setting).
    let doubleTapZoomEnabled: Bool

    /// The current settings and initial axis split for marking.
    let rules: MarkingInputRules

    /// Captured once by the session as the relative slider's starting value.
    let currentRating: Rating

    /// The live rating or Reject indicator (PRD P0-06).
    let feedback: DetailSwipeFeedback

    /// Reports every scale the scroll view shows, for the screen's pixel-demand decision.
    let onZoomChange: (CGFloat) -> Void

    /// Toggles chrome when single-tapping anywhere on the preview.
    var onChromeToggle: () -> Void = {}

    /// Reports a completed horizontal navigation swipe (`-1` previous, `1` next).
    let onStep: (Int) -> Void

    /// Reports a double tap anywhere on the preview, with the tapped point in unit image
    /// coordinates.
    let onDoubleTap: (UnitPoint) -> Void

    /// Reports the preview value once per release; cancellation reports nothing.
    let onMarkingSwipe: (Rating) -> Void

    /// Reports a two-finger zoomed marking swipe once per release; falls back to `onMarkingSwipe`.
    var onTwoFingerMarkingSwipe: ((Rating) -> Void)?

    /// Cancels pending auto-advance when navigation or marking starts.
    let onSwipeBegin: () -> Void

    let hasPrevious: Bool
    let hasNext: Bool

    /// A handle the screen reads the shown zoom from, or nil when it needs none
    /// (PRD In-group culling, synchronized zoom).
    var probe: DetailZoomProbe?

    /// Advisory analysis rectangles in the same displayed-image space as the preview.
    var focusRegions: [DetailFocusRegion] = []
    var inspectedFocusRegionID: String?
    var focusRegionColours = DetailFocusRegionColours(
        normal: .white, contrastEdge: UIColor.black.withAlphaComponent(0.45),
        selected: .systemBrown, unavailable: UIColor.white.withAlphaComponent(0.58))
    var onFocusRegionTap: (DetailFocusRegion) -> Void = { _ in }
    var previewAccessibilityLabel = "Detail preview"

    func makeUIView(context: Context) -> DetailZoomContainerView {
        let view = DetailZoomContainerView()
        probe?.container = view
        view.focusRegionColours = focusRegionColours
        view.onFocusRegionTap = onFocusRegionTap
        view.setPreviewAccessibilityLabel(previewAccessibilityLabel)
        view.onZoomChange = onZoomChange
        view.onChromeToggle = onChromeToggle
        view.onStep = onStep
        view.onDoubleTap = onDoubleTap
        view.onMarkingSwipe = onMarkingSwipe
        view.onTwoFingerMarkingSwipe = onTwoFingerMarkingSwipe
        view.onSwipeBegin = onSwipeBegin
        view.hasPrevious = hasPrevious
        view.hasNext = hasNext
        view.feedback = feedback
        view.rules = rules
        view.currentRating = currentRating
        return view
    }

    func updateUIView(_ view: DetailZoomContainerView, context: Context) {
        view.focusRegionColours = focusRegionColours
        view.onFocusRegionTap = onFocusRegionTap
        view.setPreviewAccessibilityLabel(previewAccessibilityLabel)
        view.onZoomChange = onZoomChange
        view.onChromeToggle = onChromeToggle
        view.onStep = onStep
        view.onDoubleTap = onDoubleTap
        view.onMarkingSwipe = onMarkingSwipe
        view.onTwoFingerMarkingSwipe = onTwoFingerMarkingSwipe
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
        view.setFocusRegions(focusRegions, inspectedRegionID: inspectedFocusRegionID)
        if let command { view.apply(command) }
    }
}

/// The scroll view and its one image view, plus the chrome tap, double-tap zoom, and the marking
/// and navigation pan.
@MainActor
final class DetailZoomContainerView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let imageView = DetailZoomImageView()
    private let previewAccessibilityView = UIView()
    private var focusRegionControls: [DetailFocusRegionControl] = []
    private var focusRegions: [DetailFocusRegion] = []
    private var inspectedFocusRegionID: String?
    private var renderedFocusRegionColours: DetailFocusRegionColours?
    private let doubleTap = UITapGestureRecognizer()
    private let chromeTap = UITapGestureRecognizer()
    private let markingPan = DetailSingleFingerPanGestureRecognizer()
    private let twoFingerMarkingSwipe = TwoFingerMarkingSwipeGestureRecognizer()
    private let haptics = MarkingSwipeHaptics()
    private var isNavigating = false

    /// One preview session for either direction, discarded on cancel.
    private var markingSession: MarkingSwipeSession?
    private weak var activeMarkingRecognizer: UIGestureRecognizer?
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
    var onFocusRegionTap: ((DetailFocusRegion) -> Void)?
    var focusRegionColours = DetailFocusRegionColours(
        normal: .white, contrastEdge: UIColor.black.withAlphaComponent(0.45),
        selected: .systemBrown, unavailable: UIColor.white.withAlphaComponent(0.58))
    var onChromeToggle: (() -> Void)?
    var onStep: ((Int) -> Void)?
    var onDoubleTap: ((UnitPoint) -> Void)?
    var onMarkingSwipe: ((Rating) -> Void)?
    var onTwoFingerMarkingSwipe: ((Rating) -> Void)?
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
        // The pane boundary is a hard edge: no drag, zoom or transition may draw photo
        // pixels over the neighbouring grid or divider (#199).
        clipsToBounds = true
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        addSubview(scrollView)
        previewAccessibilityView.isUserInteractionEnabled = false
        addSubview(previewAccessibilityView)

        doubleTap.delegate = self
        chromeTap.delegate = self
        doubleTap.numberOfTapsRequired = 2
        doubleTap.addTarget(self, action: #selector(handleDoubleTap))
        scrollView.addGestureRecognizer(doubleTap)
        chromeTap.addTarget(self, action: #selector(handleChromeTap))
        chromeTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(chromeTap)

        // Both marking gestures live on the container outside the scroll view. While zoomed,
        // `twoFingerMarkingSwipe` runs in the default two-finger mode and `markingPan` runs when
        // switched to single-finger axis-lock.
        markingPan.maximumNumberOfTouches = 1
        markingPan.delegate = self
        markingPan.addTarget(self, action: #selector(handleMarkingPan))
        addGestureRecognizer(markingPan)

        twoFingerMarkingSwipe.delegate = self
        twoFingerMarkingSwipe.addTarget(self, action: #selector(handleTwoFingerMarkingSwipe))
        addGestureRecognizer(twoFingerMarkingSwipe)

        // The preview and its region buttons are sibling accessibility elements. Making the
        // container itself the element would hide every region from VoiceOver.
        isAccessibilityElement = false
        previewAccessibilityView.isAccessibilityElement = true
        previewAccessibilityView.accessibilityIdentifier = "clove.detail.preview"
        previewAccessibilityView.accessibilityLabel = "Detail preview"
        previewAccessibilityView.accessibilityTraits = .image
        previewAccessibilityView.accessibilityValue = "Loading"
        previewAccessibilityView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "Show or hide controls", target: self,
                selector: #selector(toggleChromeFromAccessibility))
        ]
        accessibilityElements = [previewAccessibilityView]
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

    /// Whether a single tap can show or hide chrome (active at both fit and zoomed scales, #273).
    var chromeTapIsEnabled: Bool { chromeTap.isEnabled }
    var markingPanIsEnabled: Bool { markingPan.isEnabled }
    var twoFingerMarkingSwipeIsEnabled: Bool { twoFingerMarkingSwipe.isEnabled }
    var isZoomed: Bool { scrollView.zoomScale > DetailFitScale.tolerance }
    var twoFingerSwipeRecognizer: TwoFingerMarkingSwipeGestureRecognizer { twoFingerMarkingSwipe }

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
        shownPixels = pixels.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        self.fullResolutionPixels = fullResolution
        updateMaximumZoom()
        updatePreviewAccessibility()
        layoutFocusRegions()
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

    /// Enables or disables the double-tap zoom gesture (C12's `doubleTap` setting).
    func setDoubleTapEnabled(_ isEnabled: Bool) {
        doubleTap.isEnabled = isEnabled
    }

    /// Switches fit-only navigation off while zoomed, where a one-finger drag pans the image (or
    /// starts a zoomed rating swipe per settings), while chrome tap stays active at both fit and
    /// zoomed scales (#273).
    ///
    /// The scroll view's own pan stays enabled throughout: at fit there is nothing to scroll, so
    /// the two pans cannot compete, and simultaneous recognition below means neither cancels the
    /// other. Turning the scroll view's pan off at fit would also cost U5's pinch, which needs it
    /// for two-finger panning as it zooms.
    private func updateGestureAvailability() {
        let isZoomed = scrollView.zoomScale > DetailFitScale.tolerance
        chromeTap.isEnabled = true
        guard isZoomed else {
            markingPan.isEnabled = true
            twoFingerMarkingSwipe.isEnabled = false
            return
        }
        guard rules.settings.gesturesEnabled else {
            markingPan.isEnabled = false
            twoFingerMarkingSwipe.isEnabled = false
            return
        }
        switch rules.settings.zoomedRatingSwipe {
        case .twoFinger:
            markingPan.isEnabled = false
            twoFingerMarkingSwipe.isEnabled = true
        case .singleFingerAxisLock:
            markingPan.isEnabled = true
            twoFingerMarkingSwipe.isEnabled = false
        }
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
        layoutFocusRegions()
        // A programmatic zoom is the same handoff as a pinch, whether or not the delegate fires.
        updateGestureAvailability()
        updatePreviewAccessibility()
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
        previewAccessibilityView.frame = bounds
        scrollView.contentSize = bounds.size
        updateMaximumZoom()
        if previous != .zero, previousScale > 1 {
            zoom(to: previousScale, around: .centre)
        }
        layoutFocusRegions()
        isApplyingCommand = false
        updateGestureAvailability()
        updatePreviewAccessibility()
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // The zoom level decides whether a one-finger drag pans or marks, so the split follows
        // every pinch, including one the screen did not ask for (PRD Detail gestures).
        layoutFocusRegions()
        updateGestureAvailability()
        updatePreviewAccessibility()
        guard !isApplyingCommand else { return }
        onZoomChange?(scrollView.zoomScale)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isApplyingCommand, isZoomed else { return }
        updatePreviewAccessibility()
    }

    // MARK: - Marking swipe

    /// UIPan translation starts at recognition, losing more distance on a fast swipe. Capture
    /// touch-down so the continuous ladder always measures the full travel from the same origin.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool
    {
        if recognizer === markingPan { markingTouchStart = touch.location(in: self) }
        var touched = touch.view
        while let view = touched {
            if view is DetailFocusRegionControl {
                // A region owns a single tap, not a drag: the shared pan still resolves
                // vertical marking and horizontal navigation from its existing rules. Only
                // double-tap-to-fit and marking swipes may start over a region.
                return recognizer === markingPan
                    || recognizer === twoFingerMarkingSwipe
                    || (recognizer === doubleTap
                        && scrollView.zoomScale > DetailFitScale.tolerance)
            }
            touched = view.superview
        }
        return true
    }

    /// Locks the dominant axis once. Later samples cannot switch between navigation and marking.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        let isZoomed = scrollView.zoomScale > DetailFitScale.tolerance
        if recognizer === twoFingerMarkingSwipe {
            return isZoomed
                && rules.settings.gesturesEnabled
                && rules.settings.zoomedRatingSwipe == .twoFinger
        }
        guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
        // `UIPanGestureRecognizer.translation(in:)` starts at recognition after pan hysteresis
        // settles, which can be `(0, 0)` when a slow drag lands right on the threshold. Measure
        // initial travel from `markingTouchStart` when real touches are attached (falling back to
        // `translation` when zero or in synthetic pan tests without touches) so the axis check sees
        // the true finger displacement from touch-down.
        let translation: CGPoint
        if pan.numberOfTouches > 0 {
            let location = pan.location(in: self)
            let delta = CGPoint(
                x: location.x - markingTouchStart.x, y: location.y - markingTouchStart.y)
            translation = (delta.x != 0 || delta.y != 0) ? delta : pan.translation(in: self)
        } else {
            translation = pan.translation(in: self)
        }
        if isZoomed {
            guard rules.settings.gesturesEnabled,
                rules.settings.zoomedRatingSwipe == .singleFingerAxisLock
            else { return false }
            isNavigating = false
            return rules.beginsSwipe(
                horizontalTravel: Double(translation.x),
                verticalTravel: -Double(translation.y),
                isZoomed: true)
        }
        isNavigating =
            NavigationSwipeRules.axis(
                horizontal: Double(translation.x), vertical: Double(translation.y)) == .horizontal
        if isNavigating { return true }
        return rules.beginsSwipe(
            horizontalTravel: Double(translation.x),
            verticalTravel: -Double(translation.y),
            isZoomed: false)
    }

    /// Requires zoomed marking gestures to resolve before scroll-view pan/pinch begin so a rating
    /// swipe never pans or pinches, while a failed candidate yields immediately to pan/pinch.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard scrollView.zoomScale > DetailFitScale.tolerance, rules.settings.gesturesEnabled
        else { return false }
        switch rules.settings.zoomedRatingSwipe {
        case .twoFinger:
            return gestureRecognizer === twoFingerMarkingSwipe
                && (otherGestureRecognizer === scrollView.pinchGestureRecognizer
                    || otherGestureRecognizer === scrollView.panGestureRecognizer)
        case .singleFingerAxisLock:
            return gestureRecognizer === markingPan
                && otherGestureRecognizer === scrollView.panGestureRecognizer
        }
    }

    /// Lets the fit pan read drags alongside scrolling and yield to pinch.
    /// While zoomed, marking and scrolling/pinching are mutually exclusive.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        guard scrollView.zoomScale <= DetailFitScale.tolerance else { return false }
        return gestureRecognizer === markingPan
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
        handleMarkingState(
            pan.state, recognizer: pan, startLocation: markingTouchStart, travel: travel
        ) { [weak self] rating in
            self?.onMarkingSwipe?(rating)
        }
    }

    /// Handles a zoomed two-finger vertical drag through the same rating ladder.
    @objc func handleTwoFingerMarkingSwipe(_ swipe: TwoFingerMarkingSwipeGestureRecognizer) {
        handleMarkingState(
            swipe.state, recognizer: swipe, startLocation: swipe.startCentroid,
            travel: swipe.verticalTravel
        ) { [weak self] rating in
            guard let self else { return }
            if let onTwoFingerMarkingSwipe {
                onTwoFingerMarkingSwipe(rating)
            } else {
                onMarkingSwipe?(rating)
            }
        }
    }

    private func handleMarkingState(
        _ state: UIGestureRecognizer.State,
        recognizer: UIGestureRecognizer,
        startLocation: CGPoint,
        travel: Double,
        commit: (Rating) -> Void
    ) {
        switch state {
        case .began:
            beginMarkingSwipe(at: startLocation, recognizer: recognizer)
            updateMarkingSwipe(travel: travel)
        case .changed:
            updateMarkingSwipe(travel: travel)
        case .ended:
            updateMarkingSwipe(travel: travel, releasing: true)
            let rating = markingSession?.rating
            clearMarkingSwipe()
            if let rating { commit(rating) }
        case .cancelled, .failed:
            // A system cancel writes nothing and leaves the marks as they were (PRD P0-06).
            clearMarkingSwipe()
        default:
            break
        }
    }

    private func beginMarkingSwipe(at startLocation: CGPoint, recognizer: UIGestureRecognizer) {
        onSwipeBegin?()
        haptics.prepare()
        activeMarkingRecognizer = recognizer
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
            self.updateMarkingSwipe(travel: self.activeMarkingTravel)
        }
    }

    private var activeMarkingTravel: Double {
        if activeMarkingRecognizer === twoFingerMarkingSwipe {
            return twoFingerMarkingSwipe.verticalTravel
        }
        return Double(markingTouchStart.y - markingPan.location(in: self).y)
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
        activeMarkingRecognizer = nil
        markingSession = nil
        feedback?.clear()
    }

    // MARK: - Navigation swipe

    private func handleNavigationPan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            onSwipeBegin?()
        case .changed:
            break
        case .ended:
            let step = NavigationSwipeRules.step(
                travel: Double(pan.translation(in: self).x),
                velocity: Double(pan.velocity(in: self).x),
                width: Double(bounds.width), hasPrevious: hasPrevious, hasNext: hasNext)
            isNavigating = false
            if step != 0 {
                onStep?(step)
            }
        case .cancelled, .failed:
            isNavigating = false
        default:
            break
        }
    }

    // MARK: - Taps

    /// VoiceOver activation reads the preview; chrome has its own explicit custom action.
    override func accessibilityActivate() -> Bool { true }

    @objc private func toggleChromeFromAccessibility() -> Bool {
        onChromeToggle?()
        return true
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

/// Focus-region placement is an extension so the zoom container's gesture implementation stays
/// small. `private` access remains file-scoped across this extension.
@MainActor
extension DetailZoomContainerView {
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        if markingPan.state == .began || markingPan.state == .changed {
            markingPan.isEnabled = false
        }
        if twoFingerMarkingSwipe.state == .began || twoFingerMarkingSwipe.state == .changed {
            twoFingerMarkingSwipe.isEnabled = false
        }
        updateGestureAvailability()
    }

    @objc private func handleChromeTap() {
        guard !UIAccessibility.isVoiceOverRunning else { return }
        onChromeToggle?()
    }

    @objc private func handleDoubleTap() {
        let location = doubleTap.location(in: self)
        onDoubleTap?(imageAnchor(of: location))
    }

    func setPreviewAccessibilityLabel(_ label: String) {
        previewAccessibilityView.accessibilityLabel = label
    }

    func setFocusRegions(_ regions: [DetailFocusRegion], inspectedRegionID: String? = nil) {
        let inspectedChanged = inspectedFocusRegionID != inspectedRegionID
        if regions == focusRegions && renderedFocusRegionColours == focusRegionColours {
            if inspectedChanged {
                inspectedFocusRegionID = inspectedRegionID
                layoutFocusRegions()
            }
            return
        }
        focusRegions = regions
        inspectedFocusRegionID = inspectedRegionID
        renderedFocusRegionColours = focusRegionColours
        for control in focusRegionControls { control.removeFromSuperview() }
        focusRegionControls = regions.map { region in
            let control = DetailFocusRegionControl(
                region: region, colours: focusRegionColours)
            control.addTarget(
                self, action: #selector(handleFocusRegionTap(_:)), for: .touchUpInside)
            imageView.addSubview(control)
            return control
        }
        accessibilityElements = [previewAccessibilityView] + focusRegionControls
        layoutFocusRegions()
    }

    @objc private func handleFocusRegionTap(_ control: DetailFocusRegionControl) {
        guard control.region.isActionable else { return }
        onFocusRegionTap?(control.region)
    }

    private func layoutFocusRegions() {
        let fitted = DetailZoom.fittedSize(
            imagePixels: shownPixels, viewSize: imageView.bounds.size)
        let fittedRect = CGRect(
            x: (imageView.bounds.width - fitted.width) / 2,
            y: (imageView.bounds.height - fitted.height) / 2,
            width: fitted.width, height: fitted.height)
        let zoomScale = scrollView.zoomScale
        for control in focusRegionControls {
            control.place(
                actualRect: control.region.rect(in: fittedRect),
                zoomScale: zoomScale,
                isSelected: control.region.id == inspectedFocusRegionID)
        }
    }

    private func updatePreviewAccessibility() {
        let newValue: String
        if imageView.image == nil {
            newValue = "Loading"
        } else if let snapshot = zoomSnapshot {
            let percentX = Int((snapshot.anchor.x * 100).rounded())
            let percentY = Int((snapshot.anchor.y * 100).rounded())
            newValue = "Loaded, centred at \(percentX)%, \(percentY)% of the photo"
        } else {
            newValue = "Loaded"
        }
        if previewAccessibilityView.accessibilityValue != newValue {
            previewAccessibilityView.accessibilityValue = newValue
        }
    }
}

/// Keeps region controls as direct subviews of the `UIImageView` while resolving touches among
/// overlapping 44 pt expanded targets deterministically.
@MainActor
private final class DetailZoomImageView: UIImageView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let controls = subviews.compactMap { $0 as? DetailFocusRegionControl }.filter { control in
            !control.isHidden && control.alpha > 0.01 && control.isUserInteractionEnabled
                && control.point(inside: control.convert(point, from: self), with: event)
        }
        guard !controls.isEmpty else { return super.hitTest(point, with: event) }
        let actionable = controls.filter { $0.region.isActionable }
        let candidates = actionable.isEmpty ? controls : actionable
        return candidates.min { lhs, rhs in
            Self.controlPrecedes(lhs, rhs, at: point)
        }
    }

    private static func controlPrecedes(
        _ lhs: DetailFocusRegionControl, _ rhs: DetailFocusRegionControl, at point: CGPoint
    ) -> Bool {
        let lhsInVisual = lhs.visualFrameInSuperview.contains(point)
        let rhsInVisual = rhs.visualFrameInSuperview.contains(point)
        if lhsInVisual != rhsInVisual { return lhsInVisual }

        let lhsDistance = hypot(point.x - lhs.center.x, point.y - lhs.center.y)
        let rhsDistance = hypot(point.x - rhs.center.x, point.y - rhs.center.y)
        if abs(lhsDistance - rhsDistance) > 0.5 { return lhsDistance < rhsDistance }

        let lhsPriority = kindPriority(lhs.region.kind)
        let rhsPriority = kindPriority(rhs.region.kind)
        if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }

        return lhs.region.id < rhs.region.id
    }

    private static func kindPriority(_ kind: DetailFocusRegionKind) -> Int {
        switch kind {
        case .autofocus: 0
        case .eye: 1
        case .face: 2
        }
    }
}

/// Fails immediately if a second touch lands while `.possible`, preventing a zoomed pinch from
/// stalling on single-finger axis-lock failure resolution.
@MainActor
final class DetailSingleFingerPanGestureRecognizer: UIPanGestureRecognizer {
    private var activeTouchIDs: Set<ObjectIdentifier> = []
    private(set) var didFailForMultiTouch = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .began || state == .changed {
            for touch in touches { ignore(touch, for: event) }
            return
        }
        for touch in touches { activeTouchIDs.insert(ObjectIdentifier(touch)) }
        super.touchesBegan(touches, with: event)
        if activeTouchIDs.count > 1 {
            didFailForMultiTouch = true
            if state == .possible {
                state = .failed
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { activeTouchIDs.remove(ObjectIdentifier(touch)) }
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { activeTouchIDs.remove(ObjectIdentifier(touch)) }
        super.touchesCancelled(touches, with: event)
    }

    override func reset() {
        activeTouchIDs.removeAll()
        didFailForMultiTouch = false
        super.reset()
    }
}

/// Recognizes a parallel two-finger vertical drag while zoomed and immediately fails pinches,
/// horizontal two-finger drags, and single-finger drags.
@MainActor
final class TwoFingerMarkingSwipeGestureRecognizer: UIGestureRecognizer {
    private var orderedTouchIDs: [ObjectIdentifier] = []
    private var startPoints: [ObjectIdentifier: CGPoint] = [:]
    private var currentPoints: [ObjectIdentifier: CGPoint] = [:]
    private(set) var startCentroid: CGPoint = .zero
    private(set) var currentCentroid: CGPoint = .zero
    private(set) var didFailInCurrentSequence = false

    var verticalTravel: Double {
        Double(startCentroid.y - currentCentroid.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard state == .possible else {
            for touch in touches { ignore(touch, for: event) }
            return
        }
        if orderedTouchIDs.isEmpty {
            didFailInCurrentSequence = false
        }
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let point = touch.location(in: view)
            if !orderedTouchIDs.contains(id) {
                orderedTouchIDs.append(id)
            }
            startPoints[id] = point
            currentPoints[id] = point
        }
        if orderedTouchIDs.count > 2 {
            failSequence()
            return
        }
        if orderedTouchIDs.count == 2 {
            for id in orderedTouchIDs {
                if let current = currentPoints[id] {
                    startPoints[id] = current
                }
            }
            updateCentroids(resetStart: true)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard startPoints[id] != nil else { continue }
            currentPoints[id] = touch.location(in: view)
        }
        if orderedTouchIDs.count == 2 {
            updateCentroids(resetStart: false)
        }
        switch state {
        case .possible:
            if orderedTouchIDs.count == 1, let id = orderedTouchIDs.first,
                let start = startPoints[id], let current = currentPoints[id]
            {
                let distance = hypot(current.x - start.x, current.y - start.y)
                if distance >= ZoomedTwoFingerSwipeRules.decisionTravel {
                    failSequence()
                }
                return
            }
            guard orderedTouchIDs.count == 2 else { return }
            let id1 = orderedTouchIDs[0]
            let id2 = orderedTouchIDs[1]
            guard let start1 = startPoints[id1], let current1 = currentPoints[id1],
                let start2 = startPoints[id2], let current2 = currentPoints[id2]
            else { return }
            let first = ZoomedTwoFingerSwipeRules.TouchDelta(
                horizontal: Double(current1.x - start1.x),
                vertical: Double(start1.y - current1.y))
            let second = ZoomedTwoFingerSwipeRules.TouchDelta(
                horizontal: Double(current2.x - start2.x),
                vertical: Double(start2.y - current2.y))
            switch ZoomedTwoFingerSwipeRules.classify(first: first, second: second) {
            case .undecided:
                break
            case .pinchOrOther:
                failSequence()
            case .swipe:
                state = .began
            }
        case .began, .changed:
            state = .changed
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if startPoints[id] != nil {
                currentPoints[id] = touch.location(in: view)
            }
        }
        if orderedTouchIDs.count == 2 {
            updateCentroids(resetStart: false)
        }
        switch state {
        case .possible:
            failSequence()
        case .began, .changed:
            state = .ended
        default:
            break
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        switch state {
        case .possible:
            failSequence()
        case .began, .changed:
            state = .cancelled
        default:
            break
        }
    }

    override func reset() {
        orderedTouchIDs.removeAll()
        startPoints.removeAll()
        currentPoints.removeAll()
        startCentroid = .zero
        currentCentroid = .zero
        super.reset()
    }

    private func failSequence() {
        didFailInCurrentSequence = true
        state = .failed
    }

    private func updateCentroids(resetStart: Bool) {
        guard orderedTouchIDs.count == 2 else { return }
        let id1 = orderedTouchIDs[0]
        let id2 = orderedTouchIDs[1]
        if resetStart, let s1 = startPoints[id1], let s2 = startPoints[id2] {
            startCentroid = CGPoint(x: (s1.x + s2.x) / 2, y: (s1.y + s2.y) / 2)
        }
        if let c1 = currentPoints[id1], let c2 = currentPoints[id2] {
            currentCentroid = CGPoint(x: (c1.x + c2.x) / 2, y: (c1.y + c2.y) / 2)
        }
    }
}
