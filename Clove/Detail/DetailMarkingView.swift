import CloveCore
import CloveImaging
import SwiftUI

/// How a preview's zoom behaves when the screen shows another photo (PRD P0-04; PRD In-group
/// culling, synchronized zoom).
///
/// Group review always keeps scale and position for comparing the same crop. Regular detail
/// optionally keeps the zoom level, without sharing position between unrelated photos.
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

    /// Group zoom and pan are always synced, as specified by the handoff.
    static let group = DetailZoomPolicy(keepsScale: true, keepsPosition: true)
}

/// What the marking view asks its screen to do beyond drawing it (PRD P0-04, P0-06; PRD P0-12).
///
/// The view owns the pixels, the zoom and the marking inputs; the screen owns the order the
/// photos are in, which is the grid's order and filter in detail and the group's member order in
/// the group view (PRD P0-03; PRD In-group culling). These three calls are that boundary.
@MainActor
struct DetailMarkingActions {
    /// Applies one resolved mark change to the photo it belongs to (PRD P0-08).
    let apply: (MarkChange, GridPhoto) -> Void

    /// Starts the auto-advance one written mark asks for, resolved in the screen's own order
    /// (PRD Auto-advance; PRD In-group culling).
    let marked: (MarkKind, GridPhoto) -> Void

    /// Moves the given number of photos in the screen's order, for an edge tap and for a
    /// keyboard result (PRD P0-04; PRD In-group culling).
    let step: (Int) -> Void

    /// A marking swipe began: drop whatever the last mark was about to do (PRD Auto-advance).
    let markingSwipeBegan: () -> Void

    /// Filmstrip navigation keeps the screen's existing auto-advance cancellation.
    var openPhoto: (PhotoIdentity) -> Void = { _ in }
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
/// The selected display mode controls fit and zoom together. A held screen RAW
/// appears immediately; otherwise the camera preview fills the screen-render wait.
/// Camera mode keeps its preview at fit and decodes its full camera image for zoom.
/// Every quality replacement preserves zoom and position.
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
/// Detail and group review share the same presentation; the group supplies its own header and pill.
struct DetailMarkingView: View {
    /// The scene's browsing state, which carries the folder's save state and the retry calls
    /// (PRD P0-08).
    let browsing: BrowsingModel

    /// The photo on screen, with its marks (PRD P0-05).
    let photo: GridPhoto

    /// C12's current settings: the double-tap behaviour, the enabled ratings and the labels the
    /// HUD offers (PRD Gesture-related settings).
    let settings: AppSettings

    /// The pixels to show, normally the open folder's source from the browsing model.
    let images: any DetailImageSource
    var displayMode: PhotoDisplayMode = .rawFirst

    /// What the next photo keeps of this one's zoom (PRD P0-04; PRD In-group culling).
    let zoomPolicy: DetailZoomPolicy

    /// The photos this screen can step through, in its own order, so the neighbours' previews
    /// are prefetched (G1 "Scheduling and cache").
    let order: [GridPhoto]

    /// Where an edge tap and a mark go, in the screen's own order (PRD P0-04; PRD P0-12).
    let actions: DetailMarkingActions

    /// C5's undo through the one model call U8 adds; the button stays disabled until then.
    var undo: () -> Void = {}

    /// Group review supplies only its header, filter choice and finishing pill.
    var groupReview: GroupReviewChrome?

    @Environment(\.displayScale) private var displayScale
    @Environment(\.cloveTheme) private var theme
    @State private var hidesChrome = false
    @State private var windowID = UUID()
    @State private var currentWindow: DetailPhotoWindow?
    @State private var previousPosition: Int?
    @State private var isLoadingFit = false
    @State private var showsInformation = false
    @State private var showsZoomChip = false
    @State private var controlsHeight: CGFloat = 0

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

    /// The position the previous photo showed, waiting for the new pixels (PRD In-group culling,
    /// synchronized zoom). A regular detail view keeps the level without this.
    @State private var keptZoom: DetailZoomSnapshot?

    /// The scale the previous photo showed, so the next photo opens at the same native-relative
    /// zoom (PRD P0-04; PRD In-group culling, synchronized zoom).
    @State private var keptScale: CGFloat?

    /// The previous photo's native 100% scale, when its size was known: the ratio between the
    /// two photos' native scales is what a pinched zoom converts by (PRD P0-04).
    @State private var keptNativeScale: CGFloat?

    /// The handle that reads the shown zoom from the preview (PRD In-group culling).
    @State private var probe = DetailZoomProbe()

    /// The debounced render request a pinch may need (G1 "Scheduling and cache").
    @State private var upgradeTask: Task<Void, Never>?

    /// The rating or Reject badge the marking swipe draws near the finger (PRD P0-06).
    @State private var swipeFeedback = DetailSwipeFeedback()

    var body: some View {
        detailLayout
            .task(id: DetailDisplayOrder(photo: photo.id, order: order.map(\.id))) {
                await loadPreview(for: photo)
            }
            .onDisappear {
                upgradeTask?.cancel()
                shown = nil
                currentWindow = nil
                Task { await images.leave(window: windowID) }
            }
    }

    private var chromeIsVisible: Bool { !hidesChrome && scale <= DetailFitScale.tolerance }

    private var displayMarks: PhotoMarks { photo.marks }

    private var detailLayout: some View {
        VStack(spacing: 0) {
            BrowsingHeader(
                title: groupReview.map { "Group · \($0.group.members.count.formatted()) photos" }
                    ?? photo.fileName,
                titleIdentifier: groupReview == nil ? "clove.detail.fileName" : "clove.group.title",
                back: { browsing.back() }
            ) {
                HStack(spacing: 0) {
                    Text(
                        groupReview.map { "\($0.undecided.formatted()) undecided" }
                            ?? detailSubtitle
                    )
                    .accessibilityIdentifier(
                        groupReview == nil ? "clove.detail.zoom" : "clove.group.undecided")
                    if scale <= DetailFitScale.tolerance {
                        SaveStatusIndicator(
                            browsing: browsing, identifierPrefix: "clove.detail.saveState",
                            photo: groupReview == nil ? photo.id : nil)
                    }
                }
            } tools: {
                if chromeIsVisible {
                    if let groupReview {
                        groupMenu(groupReview)
                    } else {
                        GlassIconButton(
                            label: "Info", symbol: "info.circle", identifier: "clove.detail.info"
                        ) { showsInformation = true }
                    }
                    GlassIconButton(
                        label: "Undo", symbol: "arrow.uturn.backward",
                        identifier: "clove.detail.undo",
                        action: undo
                    ).disabled(true)
                }
            }
            FolderSaveBanner(
                browsing: browsing, identifierPrefix: "clove.detail.saveStatus.failure")
            previewArea
                .overlay(alignment: .bottom) {
                    if chromeIsVisible {
                        VStack(spacing: 8) {
                            DetailFilmstrip(
                                photos: order, current: photo.id, thumbnails: browsing.thumbnails,
                                open: actions.openPhoto,
                                failedPhotos: groupReview == nil
                                    ? []
                                    : Set(
                                        browsing.unsavedChanges.filter { $0.state.failure != nil }
                                            .map(\.photo)),
                                groups: groupReview == nil ? browsing.groups : [])
                            if let action = groupReview?.action {
                                action.disabled(!browsing.canMark)
                                    .padding(.vertical, 6)
                            }
                            DetailMarkCapsule(
                                marks: displayMarks, settings: settings,
                                previewRating: swipeFeedback.rating,
                                rate: { rate($0) }, label: { choose($0) },
                                toggleReject: { toggleReject() }
                            )
                            .disabled(!browsing.canMark)
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 8)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            controlsHeight = $0
                        }
                        .transition(.opacity)
                    } else if showsZoomChip && scale > DetailFitScale.tolerance {
                        Text(zoomName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.clove.text.primary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .cloveGlass(in: Capsule())
                            .padding(.bottom, 12)
                    }
                }
        }
        .background(Color.clove.bg.stage)
        .animation(.easeInOut(duration: 0.2), value: chromeIsVisible)
        .task(id: scale > DetailFitScale.tolerance) {
            showsZoomChip = scale > DetailFitScale.tolerance
            guard showsZoomChip else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            showsZoomChip = false
        }
        .sheet(isPresented: $showsInformation) {
            PhotoInformationSheet(browsing: browsing, photo: photo)
        }
    }

    private func groupMenu(_ chrome: GroupReviewChrome) -> some View {
        Menu {
            Toggle("Undecided only", isOn: chrome.undecidedOnly)
                .accessibilityIdentifier("clove.group.undecidedOnly")
            Button("Find similar shots again") { Task { await browsing.runGroupingAgain() } }
                .accessibilityIdentifier("clove.group.runAgain")
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .foregroundStyle(Color.clove.text.primary)
                .frame(width: 44, height: 44)
                .cloveGlass(in: Circle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("clove.group.more")
    }

    private var detailSubtitle: String {
        var parts: [String] = []
        if let index = order.firstIndex(where: { $0.id == photo.id }) {
            parts.append("\((index + 1).formatted()) / \(order.count.formatted())")
        }
        if scale > DetailFitScale.tolerance {
            parts.append(zoomName)
        } else {
            let companions = browsing.thumbnails.companions(for: photo.id)
            if companions.hasJPEG { parts.append("+ JPG") }
            if companions.hasHEIF { parts.append("+ HIF") }
        }
        return parts.joined(separator: " · ")
    }

    /// The zoomable preview and the states that must not look like a loaded image.
    private var previewArea: some View {
        DetailZoomView(
            image: shown?.image,
            fullResolutionPixels: shown?.fullResolutionPixels,
            command: command,
            doubleTapZoomEnabled: settings.doubleTap == .zoom,
            rules: rules,
            feedback: swipeFeedback,
            onZoomChange: { zoomChanged($0) },
            onEdgeTap: { navigate($0) },
            onDoubleTap: { doubleTap(at: $0) },
            onMarkingSwipe: { applyMarkingSwipe($0) },
            onSwipeBegin: { actions.markingSwipeBegan() },
            hasPrevious: navigationAvailability.previous,
            hasNext: navigationAvailability.next,
            probe: probe
        )
        .opacity(
            displayMarks.isRejected ? theme.tokens.rejectedOpacity : 1
        )
        .overlay {
            DetailSwipeFeedbackBadge(
                feedback: swipeFeedback, enabledRatings: settings.enabledRatings,
                bottomInset: controlsHeight)
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            guard size != viewSize else { return }
            viewSize = size
        }
        .overlay { previewState }
        .overlay(alignment: .topLeading) { limitationNote }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clove.bg.stage)
    }

    /// The loading, unavailable or failed state while no pixels are on screen (PRD Scan scope).
    @ViewBuilder private var previewState: some View {
        if shown == nil {
            switch phase {
            case .loading:
                ProgressView("Loading preview…")
                    .tint(theme.tokens.primaryText.color)
                    .foregroundStyle(Color.clove.text.primary)
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
        isLoadingFit = true
        if !zoomPolicy.keepsScale {
            keptZoom = nil
            keptScale = nil
            keptNativeScale = nil
        } else if let shown {
            // A preview that has not arrived yet leaves `shown` nil, so this branch is skipped:
            // the zoom read before an earlier tap in a run of quick taps stays pending for the
            // photo that finally loads (PRD In-group culling, synchronized zoom).
            let snapshot = probe.container?.zoomSnapshot
            keptScale = snapshot?.scale
            keptNativeScale = snapshot != nil ? nativeFullResolutionScale(for: shown) : nil
            keptZoom = zoomPolicy.keepsPosition ? snapshot : nil
            // A view at fit keeps no zoom, so nothing carries into the next photo. That includes a
            // 100% that is still waiting for the render's size: it belongs to the photo that was
            // tapped, not to the one an edge tap moves to (#111).
            if snapshot == nil { zoomMode = .fit }
        }
        if !zoomPolicy.keepsScale {
            zoomMode = .fit
            setZoom(.fit)
        }
        shown = nil
        phase = .loading
        limitation = nil
        previewOnly = false
        // Wait for the display, not just layout: the first render must use the
        // same physical screen edge as later photos and their held-render keys.
        for _ in 0..<120 {
            guard !Task.isCancelled else { return }
            if viewSize != .zero, probe.container?.window?.windowScene != nil { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
        guard !Task.isCancelled, let screen = probe.container?.window?.windowScene?.screen else {
            return
        }
        let screenPixels = Int(max(screen.nativeBounds.width, screen.nativeBounds.height))
        let window = photoWindow(for: photo, screenPixels: screenPixels)
        currentWindow = window
        previousPosition = window.current.position
        await images.prepare(window)
        let request = window.request(for: window.current)
        var attempts = 0
        while true {
            let outcome = await images.image(for: photo.id, request: request)
            if Task.isCancelled { return }
            switch outcome {
            case .image(let image):
                show(image)
                await renderFitAndPrefetch(window)
                return
            case .unavailable(let failure):
                phase = .unavailable(failure)
                await renderFitAndPrefetch(window)
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
    /// offset across a quality change, and the 100% target already came from the photo's native
    /// size: the render sharpens the picture instead of zooming a second time (PRD P0-04; G1
    /// "Preview, detail (I2)").
    ///
    /// The next photo is where the zoom is converted to the new photo's native size, so 100% stays
    /// 100% and a pinched fraction of native stays that fraction (PRD In-group culling,
    /// synchronized zoom; PRD P0-12). A group also keeps the position, and asks for the pixels
    /// its retained zoom needs, as before; a regular detail view keeps the level only and starts
    /// no render of its own.
    ///
    /// A 100% zoom is recomputed once when pixels land with a size other than the one it was
    /// computed with: a RAW render is the photo's own pixels, so it corrects a preview-sized or
    /// missing size at the same image point, and a size that was right leaves the zoom alone
    /// (PRD P0-04; G1 "Preview, detail (I2)"). If the render that would have brought the size
    /// failed, the arriving preview carries the last pixels this photo will give, so the zoom
    /// falls back to the inspection scale instead of staying at fit (#111).
    private func show(_ image: DetailImage) {
        shown = image
        limitation = image.limitation
        phase = .shown
        if image.limitation != nil {
            previewOnly = true
        }
        if let keptScale {
            let previousNativeScale = keptNativeScale
            let anchor = keptZoom?.anchor ?? .centre
            self.keptScale = nil
            self.keptNativeScale = nil
            self.keptZoom = nil
            let opening = openingScale(
                keptScale, previousNativeScale: previousNativeScale, for: image)
            if case .fullResolution(let chosen, _) = zoomMode {
                // The opening scale was converted to this photo's 100%, so a later render corrects
                // against this photo's size rather than the previous one's.
                zoomMode = .fullResolution(anchor: chosen, size: image.fullResolutionPixels)
            }
            setZoom(.scale(opening, anchor: anchor.unitPoint))
            // A group's retained zoom may need more pixels than the preview holds (G1 "Preview,
            // detail (I2)"); a regular detail view keeps its level without starting a render, as
            // before.
            if zoomPolicy.keepsPosition && !isLoadingFit { upgradeIfNeeded() }
        } else if case .fullResolution(let chosen, let targetSize) = zoomMode, viewSize.width > 0 {
            if let pixels = image.fullResolutionPixels {
                if let target = DetailZoom.retargetedFullResolutionScale(
                    from: targetSize, to: pixels, viewSize: viewSize, screenScale: displayScale)
                {
                    // The render is native by definition, so its size is the 100% a preview could
                    // not report; the unit image point under the viewport stays where the user put
                    // it.
                    zoomMode = .fullResolution(anchor: chosen, size: pixels)
                    let anchor = probe.container?.zoomSnapshot?.anchor ?? chosen
                    setZoom(.scale(target, anchor: anchor.unitPoint))
                }
            } else if previewOnly,
                let target = DetailZoom.fullResolutionTarget(
                    nativePixels: nil, shownPixels: pixelSize(image), viewSize: viewSize,
                    screenScale: displayScale, previewIsAll: true)
            {
                // The render that was going to supply the size failed, so the preview is all this
                // photo will give: the tap still inspects it rather than leaving the view at fit
                // (#111).
                setZoom(.scale(target, anchor: chosen.unitPoint))
            }
        }
    }

    /// The scale the next photo opens with (PRD P0-04; PRD In-group culling, synchronized zoom).
    ///
    /// 100% stays 100% of the new photo's own native size, and a pinched scale converts by the
    /// ratio of the two photos' native 100% scales, so the same fraction of the sensor stays on
    /// screen. When either native size is unknown, the earlier scale stays, which is the
    /// behaviour before native sizes were read.
    private func openingScale(
        _ keptScale: CGFloat, previousNativeScale: CGFloat?, for image: DetailImage
    ) -> CGFloat {
        guard viewSize.width > 0, let nativeScale = nativeFullResolutionScale(for: image)
        else { return keptScale }
        if case .fullResolution = zoomMode { return nativeScale }
        guard let previousNativeScale else { return keptScale }
        return DetailZoom.convertedScale(
            keptScale, fromNativeScale: previousNativeScale, toNativeScale: nativeScale)
    }

    /// The scroll-view scale at which this photo shows one native image pixel per screen pixel,
    /// or nil while its 100% is a RAW's and that size is unknown (PRD P0-04; G1 "Preview,
    /// detail (I2)").
    private func nativeFullResolutionScale(for image: DetailImage) -> CGFloat? {
        guard let pixels = image.fullResolutionPixels else { return nil }
        return DetailZoom.fullResolutionTarget(
            nativePixels: pixels, shownPixels: pixels, viewSize: viewSize,
            screenScale: displayScale)
    }

    private func photoWindow(for photo: GridPhoto, screenPixels: Int) -> DetailPhotoWindow {
        let index = order.firstIndex(where: { $0.id == photo.id }) ?? 0
        let direction: Int
        if let currentWindow, currentWindow.current.photo == photo.id {
            direction = currentWindow.direction
        } else {
            direction = previousPosition.map { index < $0 ? -1 : 1 } ?? 1
        }
        let neighbours = [index - 1, index + 1].compactMap { position -> DetailNeighbour? in
            guard order.indices.contains(position) else { return nil }
            return DetailNeighbour(photo: order[position].id, position: position)
        }
        return DetailPhotoWindow(
            id: windowID,
            current: DetailNeighbour(photo: photo.id, position: index), neighbours: neighbours,
            direction: direction,
            mode: currentWindow.flatMap { $0.current.photo == photo.id ? $0.mode : nil }
                ?? displayMode,
            screenPixels: screenPixels)
    }

    /// The preview stays on screen throughout the RAW fit upgrade, with no cue
    /// or status word. One-ahead work starts only after the current render shows.
    private func renderFitAndPrefetch(_ window: DetailPhotoWindow) async {
        let outcome = await images.image(
            for: window.current.photo,
            request: window.request(for: window.current, need: .screenRender))
        guard !Task.isCancelled else { return }
        if case .image(let image) = outcome, shown?.isBestAvailable != true {
            show(image)
        }
        isLoadingFit = false
        if zoomPolicy.keepsPosition { upgradeIfNeeded() }
        guard let shown, shown.limitation == nil else { return }
        let renderAhead =
            shown.quality == .screenRAW || shown.quality == .nativeRAW || !shown.hasRAW
        await images.prefetch(window, renderAhead: renderAhead)
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
        guard value > DetailFitScale.tolerance, !previewOnly, let shown else { return }
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
    ///
    /// The target is the photo's native 100%, computed from the size that arrived with the first
    /// preview, so the embedded preview is drawn enlarged and the RAW render later replaces it at
    /// the same scale: one zoom, not two (G1 "Preview, detail (I2)"). An image with no larger size
    /// known, such as a HIF that is never fully decoded, keeps the shown bitmap's own 100%.
    ///
    /// A RAW whose size is still unknown has no target, and its preview's pixels are not 100%: the
    /// view stays where it is, starts the native render, and zooms when that render's own size
    /// arrives (#111). A waiting cue would be a UI addition, so the smaller change is to leave the
    /// picture still until the pixels land. Once the render has failed there is nothing left to
    /// wait for, so the tap inspects the preview at ``DetailZoom/inspectionScale`` instead of
    /// doing nothing for good.
    private func doubleTap(at anchor: UnitPoint) {
        guard settings.doubleTap == .zoom else { return }
        let chosen = DetailZoomAnchor(x: anchor.x, y: anchor.y)
        guard scale <= DetailFitScale.tolerance else {
            zoomMode = .fit
            setZoom(.fit)
            return
        }
        guard let shown else { return }
        zoomMode = .fullResolution(anchor: chosen, size: shown.fullResolutionPixels)
        if let target = DetailZoom.fullResolutionTarget(
            nativePixels: shown.fullResolutionPixels, shownPixels: pixelSize(shown),
            viewSize: viewSize, screenScale: displayScale, previewIsAll: previewOnly)
        {
            setZoom(.scale(target, anchor: anchor))
        }
        upgradeTask?.cancel()
        // A photo whose render failed has no better pixels to ask for: the tap above already
        // inspected the preview (PRD P0-04).
        guard !previewOnly else { return }
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
        guard scale > DetailFitScale.tolerance, !previewOnly, let shown else { return }
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
        guard let window = currentWindow else { return }
        let request = DetailPixelRequest(
            displayPixels: requestPixels(scale: scale), need: need,
            mode: window.mode, screenPixels: window.screenPixels, position: window.current.position)
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

    /// The same neighbours edge taps use, including a decided current photo hidden by the
    /// group's Undecided only filter.
    var navigationAvailability: (previous: Bool, next: Bool) {
        if let groupReview {
            let navigation = GroupPhotoNavigation(
                group: groupReview.group, undecidedOnly: groupReview.undecidedOnly.wrappedValue)
            let marks = Dictionary(
                uniqueKeysWithValues: browsing.groupPhotos.map { ($0.id, $0.marks) })
            return (
                navigation.previousPhoto(before: photo.id, marks: marks) != nil,
                navigation.nextPhoto(after: photo.id, marks: marks) != nil
            )
        }
        guard let index = order.firstIndex(where: { $0.id == photo.id }) else {
            return (false, false)
        }
        return (index > 0, index + 1 < order.count)
    }

    /// Shows the previous or next photo in the screen's own order (PRD P0-04).
    private func navigate(_ zone: DetailEdgeZone) {
        if zone == .centre {
            guard scale <= DetailFitScale.tolerance else { return }
            hidesChrome.toggle()
            return
        }
        actions.step(zone == .previous ? -1 : 1)
    }

    // MARK: - Marking

    /// One rating tap, resolved by C13's rating-bar rule (PRD Marking rules).
    private func rate(_ rating: Rating) {
        apply(rules.result(forRating: rating, marks: browsing.shownMarks(for: photo.id)))
    }

    /// One label choice, resolved by C13's label rule (PRD Marking rules).
    private func choose(_ label: ColourLabel) {
        apply(rules.result(forLabel: label, marks: browsing.shownMarks(for: photo.id)))
    }

    /// Toggles Reject, which is the rating −1 (PRD Marking rules).
    private func toggleReject() {
        // The HUD's Reject is a toggle, while the `↓` key only turns Reject on. C13 owns both
        // directions and the mark kind auto-advance reads (PRD Marking rules, PRD Auto-advance).
        apply(rules.result(forRejectToggle: browsing.shownMarks(for: photo.id)))
    }

    /// Resolves one finished marking swipe through C13's gesture rules (PRD P0-06).
    ///
    /// The preview only begins a marking swipe at fit, and a one-finger drag cannot change the
    /// zoom, so the release is never the zoomed case those rules also guard against.
    func applyMarkingSwipe(_ end: DetailMarkingSwipeEnd) {
        guard browsing.canMark else { return }
        switch end {
        case .rating(let travel):
            apply(
                rules.result(
                    forSwipeUpTravel: travel, marks: browsing.shownMarks(for: photo.id),
                    isZoomed: false))
        case .reject(let travel):
            apply(
                rules.result(
                    forSwipeDownTravel: travel, marks: browsing.shownMarks(for: photo.id),
                    isZoomed: false))
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
            guard browsing.canMark else { return }
            // Plan navigation from the current order before a mark removes this photo from
            // a live filter. Both calls are synchronous; the mark still shows in this input turn.
            actions.marked(kind, photo)
            actions.apply(change, photo)
        case .previousPhoto:
            actions.step(-1)
        case .nextPhoto:
            actions.step(1)
        case .undo, .noChange:
            // C5's undo reaches the screen through U8; a no-change result does nothing.
            break
        }
    }

    /// C13's rules for this screen's settings.
    private var rules: MarkingInputRules {
        var inputSettings = settings
        inputSettings.gesturesEnabled = settings.gesturesEnabled && browsing.canMark
        return MarkingInputRules(settings: inputSettings)
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

    /// Fit, this photo's own native 100%, or the percentage the user pinched (PRD P0-04).
    ///
    /// The 100% reading comes from the shown scale and the photo's native size rather than from
    /// how the zoom got there: a group keeps its zoom level across photos of different native
    /// sizes, and only the photo whose own 100% is on screen may read 100% (PRD In-group culling,
    /// synchronized zoom).
    private var zoomName: String {
        if scale <= DetailFitScale.tolerance { return "Fit" }
        if let shown, viewSize.width > 0, let pixels = shown.fullResolutionPixels,
            DetailZoom.isFullResolution(
                scale: scale, nativePixels: pixels, viewSize: viewSize,
                screenScale: displayScale)
        {
            return "100%"
        }
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

/// Filtering a group can change neighbours without changing its current photo.
private struct DetailDisplayOrder: Hashable {
    let photo: PhotoIdentity
    let order: [PhotoIdentity]
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
    /// 100%, centred on the image point the user tapped, computed from this photo's size or from
    /// none while its RAW's is unknown (PRD P0-04; G1 "Preview, detail (I2)").
    case fullResolution(anchor: DetailZoomAnchor, size: CGSize?)
    /// A scale the user pinched.
    case manual
}
