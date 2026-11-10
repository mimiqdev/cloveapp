import CloveCore
import CloveImaging
import SwiftUI

/// One photo's detail: a full-width preview, edge navigation and the filmstrip, with the
/// marking HUD above them (PRD P0-04, PRD Detail and marking).
///
/// The screen keeps no browsing state of its own. The current photo, the grid's order and
/// filter, and the marks all come from ``BrowsingModel``; the pixels come from the open folder's
/// ``DetailImageSource``; and the zoom geometry is ``DetailZoom``'s. The screen asks for the
/// embedded preview first and only then, for a pinch that needs more pixels or a double-tap to
/// 100%, asks I2 for a render (G1 "Preview, detail (I2)"). A quality change replaces the pixels
/// in place, so it never resets the zoom or the position and never leaves a blank image
/// presented as loaded (PRD Scan scope).
///
/// The edge zones are ``DetailEdgeZone``'s: the outer 18% of the preview's width on each side
/// navigates, with single taps only, so a tap there never waits for a double tap. The middle
/// keeps the double-tap action (PRD Detail and marking).
///
/// Settings come from the app-wide ``SettingsStore`` in the environment, so a change on the
/// settings screen applies the next time this screen draws; the screen reads no storage itself
/// (PRD Gesture-related settings).
///
/// Every marking input — the swipe gesture, the HUD's rating bar, a label and the Reject toggle —
/// resolves through C13's ``MarkingInputRules`` and then one mark path, which writes through
/// ``BrowsingModel/apply(_:to:)`` and starts the auto-advance the mark asks for (PRD P0-06,
/// PRD Auto-advance). P2's keyboard can call that same path.
///
/// Design placeholder: the HUD, filmstrip, preview and the swipe's badge use system components
/// until the visual design lands. The save-state words are U1's summary, which U7 replaces; the
/// Undo button is disabled until U8 supplies the one model call it should invoke.
struct DetailScreen: View {
    /// The scene's browsing state and the operations this screen performs on it.
    let browsing: BrowsingModel

    /// The pixels to show, normally the open folder's source from the browsing model.
    private let images: any DetailImageSource

    @Environment(\.displayScale) private var displayScale

    /// The app-wide settings, read live so a change on the settings screen applies the next time
    /// this screen draws (PRD Gesture-related settings).
    @Environment(SettingsStore.self) private var store

    /// The pixels on screen, or nil while the first preview loads (PRD P0-04).
    @State private var shown: DetailImage?

    /// The first-preview state, so a failure is a visible state and not a blank image.
    @State private var phase: DetailPreviewPhase = .loading

    /// The shortfall the shown pixels carry, if any (G1 "Preview, detail (I2)").
    @State private var limitation: DetailLimitation?

    /// Whether the pixels are the best this photo can give, so no render is asked for again.
    @State private var previewOnly = false

    /// The preview's size in points, from the layout, for the zoom and pixel-demand math.
    @State private var viewSize: CGSize = .zero

    /// The scroll view's current scale, reported as the user pinches (PRD P0-04).
    @State private var scale: CGFloat = 1

    /// Whether the view is at fit, at 100% around a tap, or at a scale the user pinched.
    @State private var zoomMode: DetailZoomMode = .fit

    /// The scale the last command asked for, so a user pinch is told apart from that command.
    @State private var commandedScale: CGFloat = 1

    /// The zoom the preview should apply, or nil to leave the user's pinch alone.
    @State private var command: DetailZoomCommand?

    /// The command's identity, so repeated SwiftUI updates never re-apply a zoom.
    @State private var nextCommandID = 0

    /// The debounced render request a pinch may need (G1 "Scheduling and cache").
    @State private var upgradeTask: Task<Void, Never>?

    /// The rating or Reject badge the marking swipe draws near the finger (PRD P0-06).
    @State private var swipeFeedback = DetailSwipeFeedback()

    /// The auto-advance a mark started, waiting out its pause (PRD Auto-advance).
    @State private var autoAdvance = MarkAutoAdvance()

    /// C12's current settings: the double-tap behaviour, keep-zoom, the enabled ratings and the
    /// labels the HUD offers.
    private var settings: AppSettings { store.settings }

    /// Creates the screen for one browsing model.
    ///
    /// `images` exists for previews and tests; the app uses the browsing model's source for the
    /// open folder. Settings come from the app-wide ``SettingsStore`` in the environment, so this
    /// screen reads no storage of its own and one source of settings serves every screen.
    init(browsing: BrowsingModel, images: (any DetailImageSource)? = nil) {
        self.browsing = browsing
        self.images = images ?? browsing.detailImages
    }

    var body: some View {
        Group {
            if let photo = browsing.currentPhoto {
                content(for: photo)
                    .task(id: photo.id) { await loadPreview(for: photo) }
            } else {
                ContentUnavailableView {
                    Label("No photo", systemImage: "photo")
                } description: {
                    Text("Choose a photo in the grid.")
                }
                .accessibilityIdentifier("clove.detail.noPhoto")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail")
        .onDisappear {
            // A render the user left behind must not keep reading the folder or write into a
            // screen that is gone; the neighbour prefetch is dropped too (G1 scheduling row).
            upgradeTask?.cancel()
            // Leaving detail drops a pending advance, so coming back never jumps photos
            // (PRD Auto-advance).
            autoAdvance.cancel()
            Task { await images.cancelPrefetch() }
        }
    }

    /// The HUD, the preview and the filmstrip, in the order PRD Detail and marking fixes.
    private func content(for photo: GridPhoto) -> some View {
        VStack(spacing: 0) {
            DetailMarkingHUD(
                photo: photo,
                settings: settings,
                saveState: SaveStateSummary.text(
                    for: browsing.latestChange(for: photo.id)?.state),
                zoomName: zoomName,
                rate: { rate($0, on: photo) },
                label: { choose($0, on: photo) },
                toggleReject: { toggleReject(on: photo) },
                undo: undo)
            Divider()
            previewArea(for: photo)
            Divider()
            DetailFilmstrip(
                photos: browsing.photos,
                current: photo.id,
                thumbnails: browsing.thumbnails,
                open: { openPhoto($0) })
        }
    }

    /// The zoomable preview and the states that must not look like a loaded image.
    private func previewArea(for photo: GridPhoto) -> some View {
        DetailZoomView(
            image: shown?.image,
            command: command,
            doubleTapZoomEnabled: settings.doubleTap == .zoom,
            rules: rules,
            feedback: swipeFeedback,
            onZoomChange: { zoomChanged($0, on: photo) },
            onEdgeTap: { navigate($0) },
            onDoubleTap: { doubleTap(at: $0, on: photo) },
            onMarkingSwipe: { applyMarkingSwipe($0, on: photo) },
            onMarkingSwipeBegin: { autoAdvance.cancel() }
        )
        .overlay { DetailSwipeFeedbackBadge(feedback: swipeFeedback) }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            guard size != viewSize else { return }
            viewSize = size
        }
        .overlay { previewState }
        .overlay(alignment: .topLeading) { limitationNote }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    /// The loading, unavailable or failed state while no pixels are on screen (PRD Scan scope).
    @ViewBuilder private var previewState: some View {
        if shown == nil {
            switch phase {
            case .loading:
                ProgressView("Loading preview…")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("clove.detail.loading")
            case .unavailable(let failure):
                Text(unavailableText(failure))
                    .foregroundStyle(.secondary)
                    .padding()
                    .accessibilityIdentifier("clove.detail.unavailable")
            case .deferred:
                Text("The preview did not load.")
                    .foregroundStyle(.secondary)
                    .padding()
                    .accessibilityIdentifier("clove.detail.unavailable")
            case .shown:
                EmptyView()
            }
        }
    }

    /// The "preview only" note a failed render or a capped source must show (PRD P0-04).
    @ViewBuilder private var limitationNote: some View {
        if let limitation, shown != nil {
            Text(limitationText(limitation))
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(12)
                .accessibilityIdentifier("clove.detail.limitation")
        }
    }

    // MARK: - Pixels

    /// Asks for the photo's preview and keeps the screen's zoom for that photo (PRD P0-04).
    ///
    /// A deferred answer is retried a bounded number of times because the pipeline may have been
    /// busy with the photo that was on screen a moment ago; a refused or unreadable file is
    /// final and shown as its own state. The neighbours' previews are prefetched after the
    /// photo's own pixels are on screen, so an edge tap to them is cheap (G1 scheduling row).
    private func loadPreview(for photo: GridPhoto) async {
        upgradeTask?.cancel()
        if !settings.keepZoom.inDetail {
            zoomMode = .fit
            setZoom(.fit)
        }
        shown = nil
        phase = .loading
        limitation = nil
        previewOnly = false
        await images.cancelPrefetch()
        // The first layout gives the view its size; a preview requested from a zero-sized view
        // would ask a JPEG only for a one-pixel raster.
        for _ in 0..<10 where viewSize == .zero {
            try? await Task.sleep(for: .milliseconds(16))
        }
        let request = DetailPixelRequest(displayPixels: requestPixels(scale: 1), need: .preview)
        var attempts = 0
        while true {
            let outcome = await images.image(for: photo.id, request: request)
            if Task.isCancelled { return }
            switch outcome {
            case .image(let image):
                show(image, for: photo)
                prefetchNeighbours(of: photo)
                return
            case .unavailable(let failure):
                phase = .unavailable(failure)
                return
            case .deferred:
                attempts += 1
                guard attempts < 3 else {
                    phase = .deferred
                    return
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    /// Shows pixels without touching the zoom, and keeps a 100% target on the new pixel size.
    ///
    /// A preview that is replaced by a RAW render is the same path, so the scroll view keeps its
    /// scale and offset across a quality change (PRD P0-04). A 100% target is the exception: its
    /// scale is one image pixel per screen pixel, so it follows the new bitmap's size.
    private func show(_ image: DetailImage, for photo: GridPhoto) {
        shown = image
        limitation = image.limitation
        phase = .shown
        if image.limitation != nil {
            previewOnly = true
        }
        guard case .fullResolution(let anchor) = zoomMode, viewSize.width > 0 else { return }
        let target = DetailZoom.fullResolutionScale(
            imagePixels: pixelSize(image), viewSize: viewSize, screenScale: displayScale)
        setZoom(.scale(target, anchor: anchor))
    }

    /// The neighbours' previews, so the next edge tap starts from a cache hit.
    private func prefetchNeighbours(of photo: GridPhoto) {
        let photos = browsing.photos
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        var neighbours: [PhotoIdentity] = []
        if index > 0 { neighbours.append(photos[index - 1].id) }
        if index + 1 < photos.count { neighbours.append(photos[index + 1].id) }
        guard !neighbours.isEmpty else { return }
        let pixels = requestPixels(scale: 1)
        Task { await images.prefetch(neighbours, displayPixels: pixels) }
    }

    // MARK: - Zoom

    /// Records a reported scale and asks for more pixels once the pinch settles (PRD P0-04).
    ///
    /// A scale that differs from the last command is the user's own pinch, so the mode becomes
    /// manual and a later double tap returns to fit. The render request is debounced: pinching
    /// back and forth must not queue one native render per frame, and I2 will drop any queued
    /// stale render anyway (G1 "Scheduling and cache").
    private func zoomChanged(_ value: CGFloat, on photo: GridPhoto) {
        scale = value
        if abs(value - commandedScale) > 0.01 {
            zoomMode = .manual
        }
        guard !previewOnly, let shown else { return }
        guard requestPixels(scale: scale) > max(shown.width, shown.height) else { return }
        upgradeTask?.cancel()
        upgradeTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await upgrade(
                for: photo,
                need: isAtFullResolution ? .fullResolution : .morePixels)
        }
    }

    /// Whether the current zoom is the explicit 100%, which keeps asking for native pixels.
    private var isAtFullResolution: Bool {
        if case .fullResolution = zoomMode { return true }
        return false
    }

    /// The double-tap action: 100% around the tapped point, or back to fit (PRD P0-04).
    private func doubleTap(at anchor: UnitPoint, on photo: GridPhoto) {
        guard settings.doubleTap == .zoom else { return }
        guard scale <= DetailFitScale.tolerance else {
            zoomMode = .fit
            setZoom(.fit)
            return
        }
        guard let shown else { return }
        let target = DetailZoom.fullResolutionScale(
            imagePixels: pixelSize(shown), viewSize: viewSize, screenScale: displayScale)
        zoomMode = .fullResolution(anchor: anchor)
        setZoom(.scale(target, anchor: anchor))
        upgradeTask?.cancel()
        upgradeTask = Task { await upgrade(for: photo, need: .fullResolution) }
    }

    /// Asks I2 for the pixels a pinch or a double tap needs, keeping the preview meanwhile.
    ///
    /// A failed RAW render returns the preview with a limitation, which turns ``previewOnly`` on
    /// so the same failing render is never requested again for this photo (PRD P0-04).
    private func upgrade(for photo: GridPhoto, need: DetailPixelRequest.Need) async {
        guard !previewOnly else { return }
        let request = DetailPixelRequest(displayPixels: requestPixels(scale: scale), need: need)
        let outcome = await images.image(for: photo.id, request: request)
        guard !Task.isCancelled else { return }
        switch outcome {
        case .image(let image):
            show(image, for: photo)
        case .unavailable, .deferred:
            break
        }
    }

    /// Sends one zoom request to the preview and records the scale it asked for.
    private func setZoom(_ kind: DetailZoomCommand.Kind) {
        nextCommandID += 1
        command = DetailZoomCommand(id: nextCommandID, kind: kind)
        switch kind {
        case .fit:
            commandedScale = 1
            scale = 1
        case .scale(let value, _):
            commandedScale = value
            scale = value
        }
    }

    // MARK: - Navigation

    /// Shows the previous or next photo in the grid's order and filter (PRD P0-04).
    private func navigate(_ zone: DetailEdgeZone) {
        guard zone != .centre else { return }
        showPhoto(offset: zone == .previous ? -1 : 1)
    }

    /// Opens another photo in the grid's current order and filter, without wrapping at the ends.
    private func showPhoto(offset: Int) {
        let photos = browsing.photos
        guard let current = browsing.state.currentPhoto,
            let index = photos.firstIndex(where: { $0.id == current })
        else { return }
        let target = index + offset
        guard photos.indices.contains(target) else { return }
        openPhoto(photos[target].id)
    }

    /// Shows one photo and drops an advance that was still waiting to move (PRD Auto-advance).
    private func openPhoto(_ photo: PhotoIdentity) {
        autoAdvance.cancel()
        browsing.openPhoto(photo)
    }

    // MARK: - Marking

    /// One rating tap, resolved by C13's rating-bar rule (PRD Marking rules).
    private func rate(_ rating: Rating, on photo: GridPhoto) {
        apply(rules.result(forRating: rating, marks: photo.marks), on: photo)
    }

    /// One label choice, resolved by C13's label rule (PRD Marking rules).
    private func choose(_ label: ColourLabel, on photo: GridPhoto) {
        apply(rules.result(forLabel: label, marks: photo.marks), on: photo)
    }

    /// Toggles Reject, which PRD Marking rules keeps independent of the rating.
    private func toggleReject(on photo: GridPhoto) {
        // The HUD's Reject is a toggle, while the `↓` key only turns Reject on, so the toggle
        // builds its own change and reports the same mark kind for auto-advance (PRD Marking
        // rules, PRD Auto-advance).
        apply(.mark(MarkChange(reject: !photo.marks.isRejected), .reject), on: photo)
    }

    /// Resolves one finished marking swipe through C13's gesture rules (PRD P0-06).
    ///
    /// The preview only begins a marking swipe at fit, and a one-finger drag cannot change the
    /// zoom, so the release is never the zoomed case those rules also guard against.
    private func applyMarkingSwipe(_ end: DetailMarkingSwipeEnd, on photo: GridPhoto) {
        switch end {
        case .rating(let travel):
            apply(
                rules.result(forSwipeUpTravel: travel, marks: photo.marks, isZoomed: false),
                on: photo)
        case .reject(let travel):
            apply(
                rules.result(forSwipeDownTravel: travel, marks: photo.marks, isZoomed: false),
                on: photo)
        }
    }

    /// Applies one resolved marking input and starts the auto-advance its mark asks for
    /// (PRD Auto-advance).
    ///
    /// The gesture, the HUD bar, a label and the Reject toggle all come through here, so the mark
    /// path is one function and P2's keyboard can call the same one. A result that changes nothing
    /// writes nothing and advances nothing (PRD P0-06 acceptance).
    private func apply(_ result: MarkingResult, on photo: GridPhoto) {
        switch result {
        case .mark(let change, let kind):
            // A new mark replaces whatever advance the last one was waiting to make.
            autoAdvance.cancel()
            Task { await browsing.apply(change, to: photo.id) }
            startAutoAdvance(after: kind, from: photo)
        case .previousPhoto:
            showPhoto(offset: -1)
        case .nextPhoto:
            showPhoto(offset: 1)
        case .undo, .noChange:
            // C5's undo reaches the screen through U8; a no-change result does nothing.
            break
        }
    }

    /// Starts the pause-then-advance one written mark asks for (PRD Auto-advance).
    ///
    /// C13 decides where to go from the grid's current order and filter, so a filtered grid only
    /// offers the photos it shows, and the plan carries the marked photo so undo can return there
    /// (PRD Undo row). Every plan is recorded, including the one that stays, so undo always reads
    /// the photo of the mark it undid. A group view answers with its own next undecided photo
    /// through the same rules; that hook is U9's.
    private func startAutoAdvance(after kind: MarkKind, from photo: GridPhoto) {
        let plan = rules.autoAdvancePlan(after: kind, from: photo.id, photos: browsing.photos)
        browsing.recordAutoAdvance(plan)
        autoAdvance.schedule(plan) { target in
            switch target {
            case .stay:
                break
            case .nextPhoto(let next), .nextUnmarkedPhoto(let next), .groupUndecidedPhoto(let next):
                browsing.openPhoto(next)
            }
        }
    }

    /// C5's undo, which U8 wires through the model's one undo call; the HUD disables it until then.
    private func undo() {}

    /// C13's rules for this screen's settings.
    private var rules: MarkingInputRules { MarkingInputRules(settings: settings) }

    // MARK: - Geometry

    /// The image's long edge in device pixels at a scale, which is what I2 compares with the
    /// preview's own size (G1 "Preview, detail (I2)").
    ///
    /// Before the first image arrives the preview's drawn size is unknown, so the view's long
    /// edge stands in; that only affects a JPEG's display raster, never a RAW render.
    private func requestPixels(scale requestedScale: CGFloat) -> Int {
        let longEdge: CGFloat
        if let shown {
            let fitted = DetailZoom.fittedSize(
                imagePixels: pixelSize(shown), viewSize: viewSize)
            longEdge = max(fitted.width, fitted.height)
        } else {
            longEdge = max(viewSize.width, viewSize.height)
        }
        return max(Int((longEdge * displayScale * requestedScale).rounded(.up)), 1)
    }

    /// A bitmap's size in pixels.
    private func pixelSize(_ image: DetailImage) -> CGSize {
        CGSize(width: image.width, height: image.height)
    }

    /// Fit, 100% or the percentage the user pinched.
    private var zoomName: String {
        if case .fullResolution = zoomMode { return "100%" }
        if scale <= DetailFitScale.tolerance { return "Fit" }
        return "\(Int((scale * 100).rounded()))%"
    }

    // MARK: - Words

    /// Why no pixels could be shown (PRD Scan scope: never a blank image presented as loaded).
    private func unavailableText(_ failure: DetailFailure) -> String {
        switch failure {
        case .cannotOpen:
            "This file cannot be opened as an image."
        case .noUsablePreview:
            "This file has no preview Clove can show."
        case .sourceChanged:
            "The file changed while it was opening."
        }
    }

    /// Why these pixels are the best available (PRD P0-04).
    private func limitationText(_ limitation: DetailLimitation) -> String {
        switch limitation {
        case .rawRenderFailed:
            "Preview only — the RAW render failed."
        case .noHigherResolution:
            "Preview only — full resolution is unavailable."
        }
    }
}

/// The first preview's state, so loading, failure and success never look alike (PRD P0-04).
private enum DetailPreviewPhase {
    case loading
    case shown
    case unavailable(DetailFailure)
    case deferred
}

/// How the preview's zoom got where it is, which decides what a double tap does next
/// (PRD P0-04).
private enum DetailZoomMode: Equatable {
    /// The whole image at the fit scale.
    case fit
    /// 100%, centred on the image point the user tapped.
    case fullResolution(anchor: UnitPoint)
    /// A scale the user pinched.
    case manual
}
