import CloveCore
import CloveImaging
import SwiftUI

/// How a preview's zoom behaves when the screen shows another photo (PRD P0-04; PRD In-group
/// culling, synchronized zoom).
///
/// PRD Gesture-related settings keeps zoom while navigating on by default in groups and off in
/// regular detail, and PRD In-group culling adds the position: in a group the next photo opens on
/// the same spot of the image, so comparing two frames of a burst is one step (PRD P0-12). A
/// regular detail view keeps the zoom level only, because its photos need no shared position.
struct DetailZoomPolicy: Hashable {
    /// Whether the next photo keeps the zoom level (PRD Gesture-related settings).
    var keepsScale: Bool

    /// Whether the next photo keeps the position in unit image coordinates (PRD In-group
    /// culling, synchronized zoom).
    var keepsPosition: Bool

    /// The zoom a regular detail view keeps while navigating (C12's setting).
    static func detail(_ settings: AppSettings) -> DetailZoomPolicy {
        DetailZoomPolicy(keepsScale: settings.keepZoom.inDetail, keepsPosition: false)
    }

    /// The zoom a group view keeps while navigating its group; on by default (PRD In-group
    /// culling, synchronized zoom).
    static func group(_ settings: AppSettings) -> DetailZoomPolicy {
        DetailZoomPolicy(
            keepsScale: settings.keepZoom.inGroups, keepsPosition: settings.keepZoom.inGroups)
    }
}

/// What the marking view asks its screen to do beyond drawing it (PRD P0-04, P0-06; PRD P0-12).
///
/// The view owns the pixels, the zoom and the marking inputs; the screen owns the order the
/// photos are in, which is the grid's order and filter in detail and the group's member order in
/// the group view (PRD P0-03; PRD In-group culling). These three calls are that boundary.
@MainActor
struct DetailMarkingActions {
    /// Applies one resolved mark change to the photo it belongs to (PRD P0-08).
    let apply: (MarkChange, GridPhoto) async -> Void

    /// Starts the auto-advance one written mark asks for, resolved in the screen's own order
    /// (PRD Auto-advance; PRD In-group culling).
    let marked: (MarkKind, GridPhoto) -> Void

    /// Moves the given number of photos in the screen's order, for an edge tap and for a
    /// keyboard result (PRD P0-04; PRD In-group culling).
    let step: (Int) -> Void

    /// A marking swipe began: drop whatever the last mark was about to do (PRD Auto-advance).
    let markingSwipeBegan: () -> Void
}

/// One photo's preview and marking controls: the HUD, the zoomable preview with its edge taps
/// and marking swipes, and the states that must not look like a loaded image (PRD P0-04, P0-06).
///
/// The detail screen and the group view draw this same view, so a mark's path is one path: every
/// input — the swipe gesture, the HUD's rating bar, a label and the Reject toggle — resolves
/// through C13's ``MarkingInputRules`` and then asks the screen to write it and to start its
/// auto-advance (PRD In-group culling, P0-06, PRD Auto-advance). The screen supplies the order an
/// edge tap moves through, and the zoom the next photo opens with, through
/// ``DetailMarkingActions`` and ``DetailZoomPolicy``.
///
/// The screen asks for the embedded preview first and only then, for a pinch that needs more
/// pixels or a double-tap to 100%, asks I2 for a render (G1 "Preview, detail (I2)"). A quality
/// change replaces the pixels in place, so it never resets the zoom or the position and never
/// leaves a blank image presented as loaded (PRD Scan scope).
///
/// The edge zones are ``DetailEdgeZone``'s: the outer 18% of the preview's width on each side
/// navigates, with single taps only, so a tap there never waits for a double tap. The middle
/// keeps the double-tap action (PRD Detail and marking).
///
/// The folder's save state and the current photo's failure belong to this same block (PRD P0-08):
/// the folder's one indicator sits under the HUD, and a change that did not confirm brings the
/// PRD's single-photo copy with its Retry and Cancel. Both screens therefore report and retry a
/// save state in one place, and the group view's photos are marked and recovered exactly like a
/// single photo's.
///
/// Design placeholder: the HUD, the preview, the save-state row and the swipe's badge use system
/// components until the visual design lands.
struct DetailMarkingView: View {
    /// The scene's browsing state, which carries the folder's save state and the retry calls
    /// (PRD P0-08).
    let browsing: BrowsingModel

    /// The photo on screen, with its marks (PRD P0-05).
    let photo: GridPhoto

    /// C12's current settings: the double-tap behaviour, the enabled ratings and the labels the
    /// HUD offers (PRD Gesture-related settings).
    let settings: AppSettings

    /// The save-state words for this photo, which U7 replaces with its own copy (PRD P0-08).
    let saveState: String

    /// The pixels to show, normally the open folder's source from the browsing model.
    let images: any DetailImageSource

    /// What the next photo keeps of this one's zoom (PRD P0-04; PRD In-group culling).
    let zoomPolicy: DetailZoomPolicy

    /// The photos this screen can step through, in its own order, so the neighbours' previews
    /// are prefetched (G1 "Scheduling and cache").
    let order: [GridPhoto]

    /// Where an edge tap and a mark go, in the screen's own order (PRD P0-04; PRD P0-12).
    let actions: DetailMarkingActions

    @Environment(\.displayScale) private var displayScale

    /// The pixels on screen, or nil while the first preview loads (PRD P0-04).
    @State private var shown: DetailImage?

    /// The first-preview state, so a failure is a visible state and not a blank image.
    @State private var phase: DetailMarkingPreviewPhase = .loading

    /// The shortfall the shown pixels carry, if any (G1 "Preview, detail (I2)").
    @State private var limitation: DetailLimitation?

    /// Whether the pixels are the best this photo can give, so no render is asked for again.
    @State private var previewOnly = false

    /// The preview's size in points, from the layout, for the zoom and pixel-demand math.
    @State private var viewSize: CGSize = .zero

    /// The scroll view's current scale, reported as the user pinches (PRD P0-04).
    @State private var scale: CGFloat = 1

    /// Whether the view is at fit, at 100% around a tap, or at a scale the user pinched.
    @State private var zoomMode: DetailMarkingZoomMode = .fit

    /// The scale the last command asked for, so a user pinch is told apart from that command.
    @State private var commandedScale: CGFloat = 1

    /// The zoom the preview should apply, or nil to leave the user's pinch alone.
    @State private var command: DetailZoomCommand?

    /// The command's identity, so repeated SwiftUI updates never re-apply a zoom.
    @State private var nextCommandID = 0

    /// The zoom the previous photo showed, waiting for the new pixels (PRD In-group culling,
    /// synchronized zoom).
    @State private var keptZoom: DetailZoomSnapshot?

    /// The handle that reads the shown zoom from the preview (PRD In-group culling).
    @State private var probe = DetailZoomProbe()

    /// The debounced render request a pinch may need (G1 "Scheduling and cache").
    @State private var upgradeTask: Task<Void, Never>?

    /// The rating or Reject badge the marking swipe draws near the finger (PRD P0-06).
    @State private var swipeFeedback = DetailSwipeFeedback()

    /// The failed changes whose explanation the user dismissed, so Cancel hides the row without
    /// pretending the change was saved (PRD Failure and recovery, row 1).
    @State private var dismissedFailures: Set<MarkChangeID> = []

    /// Whether the system folder picker is presented for a read-only failure's Open action
    /// (PRD P0-01).
    @State private var isPickingFolder = false

    var body: some View {
        VStack(spacing: 0) {
            DetailMarkingHUD(
                photo: photo,
                settings: settings,
                saveState: saveState,
                zoomName: zoomName,
                rate: { rate($0) },
                label: { choose($0) },
                toggleReject: { toggleReject() },
                canUndo: browsing.canUndo,
                undoFailure: browsing.lastUndoFailureSummary,
                undo: { browsing.undo() })
            // The open folder's own save state, then this photo's failure with the PRD's Retry
            // and Cancel (PRD P0-08). The folder's row carries a location loss; the photo's row
            // carries one write that did not confirm.
            SaveStatusIndicator(browsing: browsing, identifierPrefix: "clove.detail.saveStatus")
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            if let situation = failureSituation {
                SaveFailureBanner(
                    situation: situation, identifierPrefix: "clove.detail.saveFailure",
                    perform: perform
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
            Divider()
            previewArea
        }
        .folderPicker(isPresented: $isPickingFolder) { url in
            await browsing.openPickedFolder(url)
        }
        // The scene's undo manager reaches this model here, so ⌘Z and the three-finger gestures
        // undo the same history the HUD's button does (PRD P0-05).
        .undoHistory(browsing: browsing)
        .task(id: photo.id) { await loadPreview(for: photo) }
        .onDisappear {
            // A render the user left behind must not keep reading the folder or write into a
            // screen that is gone; the neighbour prefetch is dropped too (G1 scheduling row).
            upgradeTask?.cancel()
            Task { await images.cancelPrefetch() }
        }
    }

    /// The zoomable preview and the states that must not look like a loaded image.
    private var previewArea: some View {
        DetailZoomView(
            image: shown?.image,
            command: command,
            doubleTapZoomEnabled: settings.doubleTap == .zoom,
            rules: rules,
            feedback: swipeFeedback,
            onZoomChange: { zoomChanged($0) },
            onEdgeTap: { navigate($0) },
            onDoubleTap: { doubleTap(at: $0) },
            onMarkingSwipe: { applyMarkingSwipe($0) },
            onMarkingSwipeBegin: { actions.markingSwipeBegan() },
            probe: probe
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

    /// Asks for the photo's preview and keeps the zoom the screen's policy keeps (PRD P0-04).
    ///
    /// A group view reads the position the previous photo was on before the pixels are replaced,
    /// so the new photo opens on the same spot (PRD In-group culling, synchronized zoom). A
    /// deferred answer is retried a bounded number of times because the pipeline may have been
    /// busy with the photo that was on screen a moment ago; a refused or unreadable file is final
    /// and shown as its own state. The neighbours' previews are prefetched after the photo's own
    /// pixels are on screen, so an edge tap to them is cheap (G1 scheduling row).
    private func loadPreview(for photo: GridPhoto) async {
        upgradeTask?.cancel()
        if zoomPolicy.keepsPosition {
            // A preview that has not arrived yet leaves the container with no pixels, so its
            // snapshot is nil: the position read before an earlier tap in a run of quick taps
            // stays pending for the photo that finally loads (PRD In-group culling, synchronized
            // zoom).
            if shown != nil { keptZoom = probe.container?.zoomSnapshot }
        } else {
            keptZoom = nil
        }
        if !zoomPolicy.keepsScale {
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
                show(image)
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

    /// Shows pixels, keeping the zoom and the position the policy keeps.
    ///
    /// A preview replaced by a RAW render is the same path, so the scroll view keeps its scale and
    /// offset across a quality change (PRD P0-04). The next photo of a group is the exception the
    /// policy names: the position the previous photo was on is applied to the new pixels, so the
    /// same spot stays under the viewport (PRD In-group culling, synchronized zoom). A 100% target
    /// follows the new bitmap's size, because its scale is one image pixel per screen pixel.
    private func show(_ image: DetailImage) {
        shown = image
        limitation = image.limitation
        phase = .shown
        if image.limitation != nil {
            previewOnly = true
        }
        if let keptZoom {
            self.keptZoom = nil
            if case .fullResolution = zoomMode {
                zoomMode = .fullResolution(anchor: keptZoom.anchor)
            }
            setZoom(.scale(keptZoom.scale, anchor: keptZoom.anchor.unitPoint))
            // The retained zoom may need more pixels than a fit-sized preview holds, so the next
            // photo is not an enlarged embedded preview (G1 "Preview, detail (I2)").
            upgradeIfNeeded()
            return
        }
        guard case .fullResolution(let anchor) = zoomMode, viewSize.width > 0 else { return }
        let target = DetailZoom.fullResolutionScale(
            imagePixels: pixelSize(image), viewSize: viewSize, screenScale: displayScale)
        setZoom(.scale(target, anchor: anchor.unitPoint))
    }

    /// The neighbours' previews, so the next edge tap starts from a cache hit.
    private func prefetchNeighbours(of photo: GridPhoto) {
        let photos = order
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
    private func zoomChanged(_ value: CGFloat) {
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
            await upgrade(need: isAtFullResolution ? .fullResolution : .morePixels)
        }
    }

    /// Whether the current zoom is the explicit 100%, which keeps asking for native pixels.
    private var isAtFullResolution: Bool {
        if case .fullResolution = zoomMode { return true }
        return false
    }

    /// The double-tap action: 100% around the tapped point, or back to fit (PRD P0-04).
    private func doubleTap(at anchor: UnitPoint) {
        guard settings.doubleTap == .zoom else { return }
        guard scale <= DetailFitScale.tolerance else {
            zoomMode = .fit
            setZoom(.fit)
            return
        }
        guard let shown else { return }
        let target = DetailZoom.fullResolutionScale(
            imagePixels: pixelSize(shown), viewSize: viewSize, screenScale: displayScale)
        zoomMode = .fullResolution(anchor: DetailZoomAnchor(x: anchor.x, y: anchor.y))
        setZoom(.scale(target, anchor: anchor))
        upgradeTask?.cancel()
        upgradeTask = Task { await upgrade(need: .fullResolution) }
    }

    /// Asks I2 for the pixels the zoom on screen needs, if the shown pixels are too small.
    ///
    /// A pinch goes through the debounced request in ``zoomChanged(_:)``; this is the path a
    /// photo that opened at a retained zoom takes, where no pinch follows to ask for the pixels
    /// (PRD In-group culling, synchronized zoom; G1 "Preview, detail (I2)"). A source that has
    /// nothing better to give returns the preview with a limitation, which turns ``previewOnly``
    /// on, so the same request is never repeated for that photo (PRD P0-04).
    private func upgradeIfNeeded() {
        guard !previewOnly, let shown else { return }
        guard requestPixels(scale: scale) > max(shown.width, shown.height) else { return }
        upgradeTask?.cancel()
        upgradeTask = Task {
            await upgrade(need: isAtFullResolution ? .fullResolution : .morePixels)
        }
    }

    /// Asks I2 for the pixels a pinch or a double tap needs, keeping the preview meanwhile.
    ///
    /// A failed RAW render returns the preview with a limitation, which turns ``previewOnly`` on
    /// so the same failing render is never requested again for this photo (PRD P0-04).
    private func upgrade(need: DetailPixelRequest.Need) async {
        guard !previewOnly else { return }
        let request = DetailPixelRequest(displayPixels: requestPixels(scale: scale), need: need)
        let outcome = await images.image(for: photo.id, request: request)
        guard !Task.isCancelled else { return }
        switch outcome {
        case .image(let image):
            show(image)
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

    /// Shows the previous or next photo in the screen's own order (PRD P0-04).
    private func navigate(_ zone: DetailEdgeZone) {
        guard zone != .centre else { return }
        actions.step(zone == .previous ? -1 : 1)
    }

    // MARK: - Marking

    /// One rating tap, resolved by C13's rating-bar rule (PRD Marking rules).
    private func rate(_ rating: Rating) {
        apply(rules.result(forRating: rating, marks: photo.marks))
    }

    /// One label choice, resolved by C13's label rule (PRD Marking rules).
    private func choose(_ label: ColourLabel) {
        apply(rules.result(forLabel: label, marks: photo.marks))
    }

    /// Toggles Reject, which PRD Marking rules keeps independent of the rating.
    private func toggleReject() {
        // The HUD's Reject is a toggle, while the `↓` key only turns Reject on, so the toggle
        // builds its own change and reports the same mark kind for auto-advance (PRD Marking
        // rules, PRD Auto-advance).
        apply(.mark(MarkChange(reject: !photo.marks.isRejected), .reject))
    }

    /// Resolves one finished marking swipe through C13's gesture rules (PRD P0-06).
    ///
    /// The preview only begins a marking swipe at fit, and a one-finger drag cannot change the
    /// zoom, so the release is never the zoomed case those rules also guard against.
    private func applyMarkingSwipe(_ end: DetailMarkingSwipeEnd) {
        switch end {
        case .rating(let travel):
            apply(rules.result(forSwipeUpTravel: travel, marks: photo.marks, isZoomed: false))
        case .reject(let travel):
            apply(rules.result(forSwipeDownTravel: travel, marks: photo.marks, isZoomed: false))
        }
    }

    /// Applies one resolved marking input and asks the screen to start the advance it asks for
    /// (PRD Auto-advance).
    ///
    /// The gesture, the HUD bar, a label and the Reject toggle all come through here, so the mark
    /// path is one function and P2's keyboard can call the same one. A result that changes nothing
    /// writes nothing and advances nothing (PRD P0-06 acceptance).
    private func apply(_ result: MarkingResult) {
        switch result {
        case .mark(let change, let kind):
            Task { await actions.apply(change, photo) }
            actions.marked(kind, photo)
        case .previousPhoto:
            actions.step(-1)
        case .nextPhoto:
            actions.step(1)
        case .undo:
            // C13 reports the keyboard's ⌘Z as an undo request; it takes the same path as the
            // toolbar button and the system gestures (PRD P0-05).
            browsing.undo()
        case .noChange:
            break
        }
    }

    /// C13's rules for this screen's settings.
    private var rules: MarkingInputRules { MarkingInputRules(settings: settings) }

    // MARK: - Save state

    /// The situation to explain under the HUD for the current photo, or nil (PRD P0-08).
    ///
    /// A folder whose location was reported gone explains itself once, in the folder's row, so
    /// one photo's own failure row stays out of its way. The row is only for a change that did not
    /// confirm, and Cancel keeps it dismissed for that change rather than for the photo forever:
    /// a newer failure has a new identity and asks again (PRD How marks reach disk, rule 8).
    private var failureSituation: SaveSituation? {
        guard browsing.folderLocationLoss == nil else { return nil }
        guard let status = browsing.latestChange(for: photo.id), status.state.failure != nil,
            !dismissedFailures.contains(status.id)
        else { return nil }
        return SaveStatus.situation(for: status.state, folderLoss: nil)
    }

    /// Performs one action of the PRD's failure row (PRD Failure and recovery).
    private func perform(_ action: SaveAction) {
        switch action {
        case .retry, .freeSpaceAndRetry:
            Task { await browsing.retryLatestChange(for: photo.id) }
        case .cancel:
            if let status = browsing.latestChange(for: photo.id) {
                dismissedFailures.insert(status.id)
            }
        case .reopenFolder:
            Task { await browsing.reopenOpenFolder() }
        case .openFolder:
            isPickingFolder = true
        }
    }

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
private enum DetailMarkingPreviewPhase {
    case loading
    case shown
    case unavailable(DetailFailure)
    case deferred
}

/// How the preview's zoom got where it is, which decides what a double tap does next
/// (PRD P0-04).
private enum DetailMarkingZoomMode: Equatable {
    /// The whole image at the fit scale.
    case fit
    /// 100%, centred on the image point the user tapped.
    case fullResolution(anchor: DetailZoomAnchor)
    /// A scale the user pinched.
    case manual
}
