import CloveCore
import CloveImaging
import SwiftUI
import os

/// What the marking view asks its screen to do beyond drawing it (PRD P0-04, P0-06; PRD P0-12).
///
/// The view owns the pixels, the zoom and the marking inputs; the screen owns the grid's order
/// and filter, the marking actions and the auto-advance (PRD P0-03; PRD In-group culling).
/// These calls form that boundary.
@MainActor
struct DetailMarkingActions {
    /// Applies one resolved mark change to the photo it belongs to (PRD P0-08).
    let apply: (MarkChange, GridPhoto) -> Void

    /// Starts the auto-advance one written mark asks for, resolved in the screen's own order
    /// (PRD Auto-advance; PRD In-group culling).
    let marked: (MarkKind, MarkChange, GridPhoto) -> Void

    /// Moves the given number of photos in the screen's order, for a horizontal swipe and for a
    /// keyboard result (PRD P0-04; PRD In-group culling).
    let step: (Int) -> Void

    /// A marking swipe began: drop whatever the last mark was about to do (PRD Auto-advance).
    let markingSwipeBegan: () -> Void

    /// Filmstrip navigation keeps the screen's existing auto-advance cancellation.
    var openPhoto: (PhotoIdentity) -> Void = { _ in }
    var selectGroupPhoto: (PhotoIdentity) -> Void = { _ in }
    var expandGroup: (GroupID) -> Void = { _ in }
    var collapseGroup: () -> Void = {}
    /// Submits the visible group's finishing action and starts its auto-advance.
    var finishGroup: (GroupFinishingPlan) -> Void = { _ in }
}

/// One photo's preview and marking controls: the HUD, the zoomable preview with its chrome taps,
/// navigation swipes, and marking swipes, and the states that must not look like a loaded image
/// (PRD P0-04, P0-06).
///
/// Every input — the swipe gesture, the HUD's rating bar, a label, the Reject toggle and the
/// hardware keys — resolves through C13's ``MarkingInputRules`` and then asks the screen to write
/// it and start its auto-advance (PRD In-group culling, P0-06, PRD Auto-advance). The screen
/// supplies the active level's order using ``DetailMarkingActions``. Navigating within Group Focus
/// preserves zoom and position; Timeline navigation or returning to Timeline onto another photo
/// resets to fit (#302, #304).
///
/// The selected display mode controls fit and zoom together. A held screen RAW
/// appears immediately; otherwise the camera preview fills the screen-render wait.
/// Camera mode keeps its preview at fit and decodes its full camera image for zoom.
/// Every quality replacement preserves zoom and position.
///
/// Navigation is gesture-only: horizontal swipes move between photos at fit and in the default
/// zoomed mode. Single taps anywhere on the preview toggle chrome at both fit and zoomed scales
/// (waiting for the double-tap window), and double taps anywhere zoom to 100% or return to fit
/// (PRD Detail and marking, #252, #273). Chrome stays steady across fit and zoom, so entering 100%
/// never hides the marking controls (#302).
///
/// Folder access problems appear in the header's indicator and banner (PRD P0-08). A change
/// that did not confirm brings the shared failure toast, and the files supply the marks again.
/// The stage pill (`Expand N photos` in Timeline or `Reject N unmarked` in Group Focus) sits centred
/// above the filmstrip (or at the bottom of the stage in Photo Preview). It is drawn by the floating
/// chrome, never by the filmstrip, so its availability and the fit–zoom transitions never change the
/// stage's height or the fitted photo's anchor (#305).
struct DetailMarkingView: View {
    /// The scene's browsing state and ordered marking actions
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

    /// Two-level Timeline model for this Detail session (#304).
    let timeline: DetailTimeline

    /// Non-nil while Detail is in Group Focus on an active multi-photo group.
    let expandedGroup: ActiveBrowsingGroup?

    /// The photos this screen can step through in its active level, so the neighbours' previews
    /// are prefetched (G1 "Scheduling and cache").
    let order: [GridPhoto]

    /// Where navigation and marks go, in the screen's own order (PRD P0-04; PRD P0-12).
    let actions: DetailMarkingActions
    var duo: DuoDetailLayout?
    var presentation: Binding<DetailPresentation>? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.cloveTheme) private var theme
    @Environment(\.usesSystemBrowsingToolbar) private var usesSystemToolbar
    @Environment(\.usesVerticalBrowsingToolbar) private var usesVerticalToolbar
    @Environment(\.isDuoExpanded) private var isDuoExpanded
    @Environment(\.isDuoCover) private var isDuoCover
    @Environment(\.hasFoldRegion) private var hasFoldRegion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language
    @State private var hidesChrome = false
    @State private var widePresentation: DetailPresentation
    @State private var expandPillNudgeCount = 0
    @State private var containerSize: CGSize = .zero
    @State private var pendingRestoredZoom: DetailZoomSnapshot?
    @State private var windowID = UUID()
    @State private var currentWindow: DetailPhotoWindow?
    @State private var loadedOrder: DetailDisplayOrder?
    @State private var previousPosition: Int?
    @State private var previousPhoto: PhotoIdentity?
    @State private var keepsPosition = false
    @State private var isLoadingFit = false
    @State private var showsInformation = false
    @State private var showsToolbarStars = false
    @State private var toolbarDragRating: Rating?
    @State private var showsZoomChip = false
    @State private var controlsHeight: CGFloat = 0

    /// The floating pill's height in a pane whose chrome is a dock outside the stage: the marking
    /// swipe's star bar must stay above the pill there too (#305).
    @State private var duoPillHeight: CGFloat = 0
    @State private var tapPickerDismissToken = 0
    @State private var focusRegionState = DetailFocusRegionState()
    @State private var focusAnalysisID = UUID()
    @State private var inspectedFocusRegionID: String?

    /// Detail pixels on screen; the grid thumbnail stands in until these arrive.
    @State private var shown: DetailImage?

    /// The first-preview state, so a failure is a visible state and not a blank image.
    @State private var phase: DetailMarkingPreviewPhase = .placeholder(nil)

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
    /// synchronized zoom). Only a group keeps it; every other photo change returns to fit (#302).
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

    /// Whether the view holds the keyboard focus its hardware keys arrive through (PRD P0-06).
    @FocusState private var hasKeyFocus: Bool

    init(
        browsing: BrowsingModel,
        photo: GridPhoto,
        settings: AppSettings,
        images: any DetailImageSource,
        displayMode: PhotoDisplayMode = .rawFirst,
        timeline: DetailTimeline? = nil,
        expandedGroup: ActiveBrowsingGroup? = nil,
        order: [GridPhoto],
        actions: DetailMarkingActions,
        duo: DuoDetailLayout? = nil,
        presentation: Binding<DetailPresentation>? = nil,
        initialPresentation: DetailPresentation = .photoPreview
    ) {
        self.browsing = browsing
        self.photo = photo
        self.settings = settings
        self.images = images
        self.displayMode = displayMode
        self.timeline =
            timeline
            ?? DetailTimeline(
                photos: browsing.photos, groups: browsing.groups,
                groupsEnabled: settings.similarGroupsEnabled && browsing.readingProgress == nil)
        self.expandedGroup = expandedGroup
        self.order = order
        self.actions = actions
        self.duo = duo
        self.presentation = presentation
        _widePresentation = State(initialValue: initialPresentation)
    }

    var body: some View {
        detailLayout
            .focusable()
            .focusEffectDisabled()
            .focused($hasKeyFocus)
            .onKeyPress { press in
                guard let key = MarkingKey(press) else { return .ignored }
                markKey(key)
                return .handled
            }
            .onAppear { hasKeyFocus = true }
            .onChange(of: photo.id) { _, _ in
                showsToolbarStars = false
                toolbarDragRating = nil
                inspectedFocusRegionID = nil
                pendingRestoredZoom = nil
                focusAnalysisID = UUID()
                focusRegionState = DetailFocusRegionState()
            }
            .onChange(of: duoPopoverDismissTrigger) { _, _ in
                showsToolbarStars = false
                toolbarDragRating = nil
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    showsToolbarStars = false
                    toolbarDragRating = nil
                }
            }
            .task(id: photo.id) {
                await loadPreview(for: photo)
            }
            .task(id: DetailDisplayOrder(photo: photo.id, order: order.map(\.id))) {
                await refreshPrefetchForOrderChange(for: photo)
            }
            .task(
                id: DetailFocusTrigger(
                    photo: photo.id, showsFocusRegions: browsing.showsFocusRegions)
            ) {
                await loadFocusRegions(for: photo)
            }
            .onDisappear {
                showsToolbarStars = false
                toolbarDragRating = nil
                upgradeTask?.cancel()
                shown = nil
                currentWindow = nil
                Task { await images.leave(window: windowID) }
            }
    }

    /// Chrome is one visibility across fit and zoom: only the single-tap toggle changes it (#302).
    private var chromeIsVisible: Bool { !hidesChrome }

    /// How much of the stage's bottom the marking swipe's star bar must stay clear of.
    ///
    /// The standard layout's chrome floats inside the stage and measures itself. The Duo pane's
    /// chrome is a dock below the stage, so only its floating pill sits over the stage's bottom
    /// edge; reserving that band keeps a low central swipe's star bar above the pill without
    /// shrinking the photo (#305).
    private var swipeFeedbackReservation: CGFloat {
        Self.swipeFeedbackReservation(
            floatingPillInStage: duo != nil,
            pillVisible: chromeIsVisible && stagePill != nil,
            pillHeight: duoPillHeight,
            pillGap: showsFilmstrip ? 6 : 12,
            measuredBand: controlsHeight)
    }

    /// The stage-bottom band a marking swipe's star bar must stay clear of (#305).
    ///
    /// The standard layout's chrome floats inside the stage, so the band measures itself. The Duo
    /// pane's chrome is a dock below the stage, so there the only thing over the stage's bottom edge
    /// is the floating pill: without reserving it the bar was free to end 8 pt above the stage's
    /// edge and sit on the pill.
    static func swipeFeedbackReservation(
        floatingPillInStage: Bool, pillVisible: Bool, pillHeight: CGFloat, pillGap: CGFloat,
        measuredBand: CGFloat
    ) -> CGFloat {
        guard floatingPillInStage else { return measuredBand }
        guard pillVisible else { return 0 }
        return pillHeight + pillGap
    }

    private var displayMarks: PhotoMarks { photo.marks }

    private var currentTimelineGroup: ActiveBrowsingGroup? {
        expandedGroup == nil ? timeline.activeGroup(containing: photo.id) : nil
    }

    private var isReadOnlyCollapsedGroup: Bool {
        currentTimelineGroup != nil
    }

    private var allowsMarkingInput: Bool {
        browsing.canMark && !isReadOnlyCollapsedGroup
    }

    private var usesRail: Bool { horizontalSizeClass == .regular && duo == nil }

    private var showsExpandedPhotoHeader: Bool {
        isDuoExpanded && (usesVerticalToolbar || !hasFoldRegion)
    }

    private var presentationPolicy: DetailPresentationPolicy {
        DetailPresentationPolicy(
            isRegularWidth: horizontalSizeClass == .regular,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover,
            hasFoldRegion: hasFoldRegion,
            availableWidth: Double(containerSize.width),
            availableHeight: Double(containerSize.height))
    }

    private var presentationBinding: Binding<DetailPresentation> {
        presentation ?? duo?.presentation ?? $widePresentation
    }

    private var effectivePresentation: DetailPresentation {
        presentationPolicy.effectivePresentation(for: presentationBinding.wrappedValue)
    }

    private var showsPhotoGrid: Bool {
        effectivePresentation.showsPhotoGrid
    }

    private var showsFilmstrip: Bool {
        !showsPhotoGrid
    }

    private var detailLayout: some View {
        Group {
            if let duo {
                expandedLayout(duo)
            } else if usesSystemToolbar, #available(iOS 27.1, *) {
                nativeStandardLayout
            } else {
                standardLayout
            }
        }
        .background(Color.clove.bg.stage)
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: { size in
            if containerSize != size {
                containerSize = size
            }
        }
        .animation(CloveMotion.chrome(reduceMotion: reduceMotion), value: chromeIsVisible)
        .task(id: scale > DetailFitScale.tolerance) {
            let zoomed = scale > DetailFitScale.tolerance
            withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
                showsZoomChip = zoomed
            }
            guard zoomed else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
                showsZoomChip = false
            }
        }
        .sheet(isPresented: $showsInformation) {
            PhotoInformationSheet(browsing: browsing, photo: photo)
        }
    }

    @available(iOS 27.1, *)
    private var nativeStandardLayout: some View {
        standardLayout
            .toolbar {
                BrowsingToolbar(
                    back: { browsing.back() }, undo: undo, canUndo: browsing.canUndoMark,
                    showsUndo: chromeIsVisible
                ) {
                    if presentationPolicy.supportsPhotoPreview {
                        photoGridToggle
                    }
                    focusRegionsToggle
                } tools: {
                    if chromeIsVisible {
                        Button(
                            AppLocalization.string("Info", language: language),
                            systemImage: "info.circle"
                        ) { showsInformation = true }
                        .accessibilityIdentifier("clove.detail.info")
                    }
                } marks: {
                    Optional<ToolbarItem<Void, EmptyView>>.none
                } bottom: {
                    EmptyView()
                }
                ToolbarItem(placement: .principal) { detailToolbarTitle }
                    .axisBehavior(.horizontalOnly)
            }
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var photoGridToggle: some View {
        let gridShown = showsPhotoGrid
        let actionTitle = AppLocalization.string(
            gridShown ? "Hide photo grid" : "Show photo grid", language: language)
        let stateValue = AppLocalization.string(
            gridShown ? "Photo Preview" : "Focus View", language: language)
        if usesSystemToolbar {
            Button {
                togglePresentation()
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(gridShown ? Color.clove.accent : Color.clove.text.primary)
            }
            .tint(gridShown ? Color.clove.accent : Color.clove.text.primary)
            .help(actionTitle)
            .accessibilityLabel(actionTitle)
            .accessibilityValue(stateValue)
            .accessibilityAddTraits(gridShown ? .isSelected : [])
            .accessibilityIdentifier("clove.detail.gridToggle")
        } else {
            GlassIconButton(
                label: actionTitle,
                symbol: "sidebar.left",
                isActive: gridShown,
                activeAccessibilityValue: stateValue,
                size: usesRail ? .pad : .phone,
                identifier: "clove.detail.gridToggle"
            ) {
                togglePresentation()
            }
            .help(actionTitle)
        }
    }

    private var focusRegionsToggle: some View {
        focusRegionsButton(inStageHeader: false)
    }

    @ViewBuilder
    private func focusRegionsButton(inStageHeader: Bool) -> some View {
        let focusLabel = AppLocalization.string("Focus regions", language: language)
        let focusValue = AppLocalization.string(
            browsing.showsFocusRegions ? "On" : "Off", language: language)
        if inStageHeader {
            Group {
                if #available(iOS 26.0, *) {
                    Button {
                        browsing.showsFocusRegions.toggle()
                    } label: {
                        Image(systemName: "viewfinder")
                            .font(.body)
                            .foregroundStyle(
                                browsing.showsFocusRegions
                                    ? Color.clove.accent : Color.clove.text.primary
                            )
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Circle())
                    .tint(
                        browsing.showsFocusRegions ? Color.clove.accent : Color.clove.text.primary
                    )
                    .accessibilityLabel(focusLabel)
                    .accessibilityValue(focusValue)
                    .accessibilityAddTraits(browsing.showsFocusRegions ? .isSelected : [])
                    .accessibilityIdentifier("clove.detail.focusToggle")
                } else {
                    GlassIconButton(
                        label: focusLabel,
                        symbol: "viewfinder",
                        isActive: browsing.showsFocusRegions,
                        size: .pad,
                        identifier: "clove.detail.focusToggle"
                    ) {
                        browsing.showsFocusRegions.toggle()
                    }
                }
            }
            .reportHeaderControlFrame("clove.detail.focusToggle")
        } else if usesSystemToolbar {
            Button {
                browsing.showsFocusRegions.toggle()
            } label: {
                Image(systemName: "viewfinder")
                    .foregroundStyle(
                        browsing.showsFocusRegions ? Color.clove.accent : Color.clove.text.primary)
            }
            .tint(browsing.showsFocusRegions ? Color.clove.accent : Color.clove.text.primary)
            .accessibilityLabel(focusLabel)
            .accessibilityValue(focusValue)
            .accessibilityAddTraits(browsing.showsFocusRegions ? .isSelected : [])
            .accessibilityIdentifier("clove.detail.focusToggle")
        } else {
            GlassIconButton(
                label: focusLabel,
                symbol: "viewfinder",
                isActive: browsing.showsFocusRegions,
                size: usesRail ? .pad : .phone,
                identifier: "clove.detail.focusToggle"
            ) {
                browsing.showsFocusRegions.toggle()
            }
        }
    }

    private var detailToolbarTitle: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(photo.fileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.clove.text.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("clove.detail.fileName")
                    .reportHeaderControlFrame("clove.detail.fileName")
                FolderPreparationIndicator(
                    browsing: browsing,
                    identifierPrefix: "clove.detail.preparation"
                )
                .layoutPriority(1)
            }
            HStack(spacing: 0) {
                Text(detailSubtitle)
                    .lineLimit(1)
                    .accessibilityIdentifier("clove.detail.zoom")
                SaveStatusIndicator(
                    browsing: browsing, identifierPrefix: "clove.detail.saveState")
            }
            .font(.caption)
            .foregroundStyle(Color.clove.text.secondary)
        }
    }

    @available(iOS 27.1, *)
    private var duoPhotoHeader: some View {
        HStack(spacing: 8) {
            focusRegionsButton(inStageHeader: true)
            Spacer(minLength: 0)
            detailToolbarTitle
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.clove.bg.stage)
    }

    @ViewBuilder private func expandedLayout(_ duo: DuoDetailLayout) -> some View {
        if #available(iOS 27.1, *) {
            Group {
                if duo.showsGrid && showsPhotoGrid {
                    PhotoArrangement(
                        grid: AnyView(splitGridPane),
                        presentation: duo.presentation,
                        back: { browsing.back() }
                    ) {
                        duoPhotoPane(showsFilmstrip: false)
                    }
                } else {
                    duoPhotoPane(showsFilmstrip: true)
                }
            }
            .toolbar {
                BrowsingToolbar(
                    back: { browsing.back() }, undo: undo, canUndo: browsing.canUndoMark
                ) {
                    if isDuoExpanded && !showsExpandedPhotoHeader {
                        focusRegionsToggle
                    }
                } tools: {
                    if duo.showsGrid {
                        duo.filter
                        duo.more
                        if presentationPolicy.supportsPhotoPreview {
                            photoGridToggle
                        }
                    }
                    if !isDuoExpanded {
                        focusRegionsToggle
                    }
                    Button(
                        AppLocalization.string("Info", language: language),
                        systemImage: "info.circle"
                    ) { showsInformation = true }
                    .accessibilityIdentifier("clove.detail.info")
                } marks: {
                    // Expanded Duo marks live in the capsule row beneath the photo, so
                    // system status activity cannot push them into overflow (#200). The
                    // cover keeps the compact dock controls.
                    if isDuoExpanded {
                        Optional<ToolbarItem<Void, EmptyView>>.none
                    } else {
                        DuoMarkControls(
                            photoID: photo.id, marks: displayMarks, settings: settings,
                            previewRating: swipeFeedback.rating, canMark: allowsMarkingInput,
                            showsStars: $showsToolbarStars, dragRating: $toolbarDragRating,
                            rate: { rate($0, togglesCurrent: false) }, label: { choose($0) },
                            toggleReject: { toggleReject() },
                            markingBegan: beginMarkingGesture)
                    }
                } bottom: {
                    if duo.showsGrid {
                        duo.bottom
                    }
                }
                if !showsExpandedPhotoHeader && (!duo.showsGrid || !showsPhotoGrid) {
                    ToolbarItem(placement: .principal) { detailToolbarTitle }
                        .axisBehavior(.horizontalOnly)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVerticalBehavior(.automatic)
            .toolbarVerticalCompressionBehavior(.prefersToolbarItems)
            .background {
                if !isDuoExpanded {
                    ToolbarRatingGesture(
                        rating: displayMarks.rating, enabledRatings: settings.enabledRatings,
                        canMark: allowsMarkingInput, began: beginMarkingGesture,
                        preview: {
                            toolbarDragRating = $0
                            showsToolbarStars = true
                        },
                        commit: {
                            rate($0, togglesCurrent: false)
                            toolbarDragRating = nil
                            showsToolbarStars = false
                        },
                        cancel: {
                            toolbarDragRating = nil
                            showsToolbarStars = false
                        })
                }
            }
        }
    }

    @available(iOS 27.1, *)
    private func duoPhotoPane(showsFilmstrip: Bool) -> some View {
        VStack(spacing: 0) {
            if showsExpandedPhotoHeader {
                duoPhotoHeader
            }
            FolderSaveBanner(
                browsing: browsing, identifierPrefix: "clove.detail.saveStatus.failure")
            previewArea
                .overlay(alignment: .bottom) {
                    // The finishing pill floats over the stage's bottom edge, above the dock. It
                    // is not part of the dock's height, so showing or hiding it never resizes
                    // the photo stage (#305).
                    if chromeIsVisible, let stagePill {
                        stagePill
                            .onGeometryChange(for: CGFloat.self) {
                                $0.size.height
                            } action: {
                                duoPillHeight = $0
                            }
                            .padding(.bottom, showsFilmstrip ? 6 : 12)
                            .transition(
                                .asymmetric(
                                    insertion: CloveMotion.slideTransition(
                                        edge: .bottom, offset: 8, reduceMotion: reduceMotion),
                                    removal: .identity))
                    }
                }
                .animation(
                    chromeIsVisible && stagePill != nil
                        ? CloveMotion.chrome(reduceMotion: reduceMotion) : nil,
                    value: stagePill?.identifier)
            // The failure toast sits above the filmstrip, clear of the capsule row
            // (handoff screens.md §03, components.md Toast).
            if let message = browsing.failureToastMessage {
                Toast(
                    message: AppLocalization.string(message, language: language),
                    identifier: "clove.save.toast"
                )
                .padding(.horizontal, 16)
                .transition(
                    CloveMotion.slideTransition(
                        edge: .bottom, offset: 12, reduceMotion: reduceMotion))
            }
            // The marking toolbar gets its own reserved bottom-right area beside the narrowed
            // filmstrip, never over the image and never in the system side toolbar (#200, #227).
            // The toolbar sibling is the one reservation: the strip's viewport narrows by its
            // width, and the strip's content fills that viewport up to the toolbar (#237).
            // The two regions share the photo stage's background, so no contrasting sidebar slab
            // divides them.
            if showsFilmstrip && chromeIsVisible {
                HStack(alignment: .bottom, spacing: 0) {
                    DetailFilmstrip(
                        timeline: timeline,
                        expandedGroup: expandedGroup,
                        current: photo.id,
                        thumbnails: browsing.thumbnails,
                        openPhoto: actions.openPhoto,
                        selectGroupPhoto: actions.selectGroupPhoto,
                        expandGroup: actions.expandGroup,
                        collapseGroup: actions.collapseGroup)
                    if isDuoExpanded {
                        duoMarkingToolbar
                    }
                }
            } else if isDuoExpanded && chromeIsVisible {
                duoMarkingToolbar
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .animation(
            CloveMotion.chrome(reduceMotion: reduceMotion),
            value: browsing.failureToastMessage
        )
        .contentMargins(for: .container, edges: .horizontal)
        .tapPickerContainer(dismissWhen: tapPickerDismissTrigger)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(showsFilmstrip ? "clove.duo.focus" : "clove.duo.photoPreview")
        .reportTapPickerFrame(showsFilmstrip ? "clove.duo.focus" : "clove.duo.photoPreview")
    }

    /// The shared marking family in the reserved bottom-right marking area beside the filmstrip
    /// (#227). It never overlaps the filmstrip or the fitted photo.
    @ViewBuilder private var duoMarkingToolbar: some View {
        if chromeIsVisible {
            MarkingToolbar(
                rating: swipeFeedback.rating
                    ?? (displayMarks.isRejected ? .unrated : displayMarks.rating),
                label: displayMarks.isRejected ? nil : displayMarks.label.colour,
                isRejected: displayMarks.isRejected,
                enabledRatings: settings.enabledRatings,
                labels: [nil] + settings.availableLabels.map { Optional($0) },
                identifier: "clove.duo.capsule", labelPickerIdentifier: "clove.duo.labels",
                photoID: photo.id,
                onRate: { rate($0) }, onReject: { toggleReject() },
                onLabel: { choose($0.map { ColourLabel(colour: $0) } ?? .clear) },
                onBegin: actions.markingSwipeBegan
            )
            .disabled(!allowsMarkingInput)
            .accessibilityValue(MarkSummary.text(for: displayMarks, language: language))
            .transition(.opacity)
        }
    }

    private var standardLayout: some View {
        VStack(spacing: 0) {
            if !usesSystemToolbar {
                BrowsingHeader(
                    title: photo.fileName,
                    titleIdentifier: "clove.detail.fileName",
                    backTitle: horizontalSizeClass == .regular
                        ? browsing.localizedFilterTitle(language: language) : nil,
                    back: { browsing.back() }
                ) {
                    HStack(spacing: 0) {
                        Text(detailSubtitle)
                            .accessibilityIdentifier("clove.detail.zoom")
                        SaveStatusIndicator(
                            browsing: browsing, identifierPrefix: "clove.detail.saveState")
                    }
                } titleAccessory: {
                    FolderPreparationIndicator(
                        browsing: browsing,
                        identifierPrefix: "clove.detail.preparation")
                } leadingTools: {
                    if presentationPolicy.supportsPhotoPreview {
                        photoGridToggle
                    }
                    focusRegionsToggle
                } tools: {
                    if chromeIsVisible {
                        GlassIconButton(
                            label: AppLocalization.string("Info", language: language),
                            symbol: "info.circle", size: usesRail ? .pad : .phone,
                            identifier: "clove.detail.info"
                        ) { showsInformation = true }
                        GlassIconButton(
                            label: AppLocalization.string("Undo", language: language),
                            symbol: "arrow.uturn.backward",
                            size: usesRail ? .pad : .phone,
                            identifier: "clove.detail.undo",
                            action: undo
                        ).disabled(!browsing.canUndoMark)
                    }
                }
            }
            FolderSaveBanner(
                browsing: browsing, identifierPrefix: "clove.detail.saveStatus.failure")
            Group {
                if #available(iOS 27.1, *), hasFoldRegion, showsPhotoGrid {
                    PhotoArrangement(
                        grid: AnyView(splitGridPane),
                        presentation: presentationBinding,
                        back: { browsing.back() }
                    ) {
                        standardDetailStage
                    }
                } else {
                    SplitPhotoView(
                        showsGrid: showsPhotoGrid,
                        presentation: presentationBinding,
                        back: { browsing.back() }
                    ) {
                        splitGridPane
                    } secondary: {
                        standardDetailStage
                    }
                }
            }
        }
        .tapPickerContainer(dismissWhen: tapPickerDismissTrigger)
    }

    private var standardDetailStage: some View {
        HStack(spacing: 0) {
            photoStage
            if usesRail {
                DetailMarkRail(
                    marks: displayMarks, settings: settings,
                    previewRating: swipeFeedback.rating,
                    photoID: photo.id,
                    rate: { rate($0, togglesCurrent: false) }, label: { choose($0) },
                    toggleReject: { toggleReject() }, markingBegan: beginMarkingGesture
                )
                .disabled(!allowsMarkingInput)
            }
        }
    }

    private var splitGridPane: some View {
        SplitFolderGridPane(
            browsing: browsing,
            thumbnails: browsing.thumbnails,
            similarGroupsEnabled: settings.similarGroupsEnabled,
            openPhoto: actions.openPhoto,
            selectGroupPhoto: actions.selectGroupPhoto,
            openGroup: actions.expandGroup,
            collapseGroup: actions.collapseGroup)
    }

    private func togglePresentation() {
        captureZoomForPresentationTransition()
        presentationBinding.wrappedValue = presentationBinding.wrappedValue.toggled
    }

    private func captureZoomForPresentationTransition() {
        guard scale > DetailFitScale.tolerance,
            let snapshot = probe.container?.zoomSnapshot
        else {
            pendingRestoredZoom = nil
            return
        }
        if case .fullResolution(_, let size) = zoomMode {
            zoomMode = .fullResolution(anchor: snapshot.anchor, size: size)
        }
        pendingRestoredZoom = snapshot
    }

    private var photoStage: some View {
        previewArea
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    // The save/read failure toast sits above the filmstrip so it never
                    // covers the mark capsule (handoff screens.md §03, components.md Toast).
                    // It is transient feedback, not chrome, and remains visible at 100% zoom.
                    Group {
                        if let message = browsing.failureToastMessage {
                            Toast(
                                message: AppLocalization.string(message, language: language),
                                identifier: "clove.save.toast"
                            )
                            .padding(.horizontal, 16)
                            .transition(
                                CloveMotion.slideTransition(
                                    edge: .bottom, offset: 12, reduceMotion: reduceMotion))
                        }
                    }
                    .animation(
                        CloveMotion.chrome(reduceMotion: reduceMotion),
                        value: browsing.failureToastMessage
                    )
                    if showsZoomChip && scale > DetailFitScale.tolerance {
                        Text(zoomName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.clove.text.primary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .cloveGlass(in: Capsule())
                            .padding(.bottom, (showsFilmstrip && chromeIsVisible) ? 0 : 12)
                            .transition(.opacity)
                    }
                    if showsFilmstrip && chromeIsVisible {
                        // The pill rides the floating chrome band above the strip. The band is an
                        // overlay, so its height never moves the stage (handoff components.md,
                        // Pill action; #305).
                        VStack(spacing: 8) {
                            Group {
                                if let stagePill {
                                    stagePill
                                        .transition(
                                            .asymmetric(
                                                insertion: CloveMotion.slideTransition(
                                                    edge: .bottom, offset: 8,
                                                    reduceMotion: reduceMotion
                                                ),
                                                removal: .identity))
                                }
                            }
                            .animation(
                                stagePill != nil
                                    ? CloveMotion.chrome(reduceMotion: reduceMotion) : nil,
                                value: stagePill?.identifier
                            )
                            DetailFilmstrip(
                                timeline: timeline,
                                expandedGroup: expandedGroup,
                                current: photo.id,
                                thumbnails: browsing.thumbnails,
                                openPhoto: actions.openPhoto,
                                selectGroupPhoto: actions.selectGroupPhoto,
                                expandGroup: actions.expandGroup,
                                collapseGroup: actions.collapseGroup)
                            if chromeIsVisible && !usesRail {
                                MarkingToolbar(
                                    rating: swipeFeedback.rating
                                        ?? (displayMarks.isRejected
                                            ? .unrated : displayMarks.rating),
                                    label: displayMarks.isRejected
                                        ? nil : displayMarks.label.colour,
                                    isRejected: displayMarks.isRejected,
                                    enabledRatings: settings.enabledRatings,
                                    labels: [nil] + settings.availableLabels.map { Optional($0) },
                                    identifier: "clove.detail.capsule",
                                    labelPickerIdentifier: "clove.detail.labels",
                                    photoID: photo.id,
                                    onRate: { rate($0) }, onReject: { toggleReject() },
                                    onLabel: {
                                        choose($0.map { ColourLabel(colour: $0) } ?? .clear)
                                    },
                                    onBegin: actions.markingSwipeBegan
                                )
                                .disabled(!allowsMarkingInput)
                                .accessibilityValue(
                                    MarkSummary.text(for: displayMarks, language: language)
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.bottom, 8)
                    } else if !showsFilmstrip && chromeIsVisible {
                        Group {
                            if let stagePill {
                                stagePill
                                    .padding(.bottom, 12)
                                    .transition(
                                        .asymmetric(
                                            insertion: CloveMotion.slideTransition(
                                                edge: .bottom, offset: 8,
                                                reduceMotion: reduceMotion),
                                            removal: .identity))
                            }
                        }
                        .animation(
                            stagePill != nil
                                ? CloveMotion.chrome(reduceMotion: reduceMotion) : nil,
                            value: stagePill?.identifier
                        )
                    }
                }
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    controlsHeight = $0
                }
                .transition(.opacity)
            }
    }

    private var stagePill: PillAction? {
        if let expandedGroup {
            guard browsing.canMark else { return nil }
            let plan = GroupFinishingPlan(
                group: expandedGroup,
                action: .rejectUnmarked,
                currentPhoto: photo.id)
            guard plan.availability.isAvailable, !plan.isEmpty else { return nil }
            return PillAction(
                title: AppLocalization.format(
                    "Reject %lld unmarked", language: language, Int64(plan.rejects.count)),
                identifier: "clove.detail.rejectUnmarked",
                tone: .destructive
            ) { actions.finishGroup(plan) }
        }
        if let group = currentTimelineGroup {
            return PillAction(
                title: AppLocalization.format(
                    "Expand %lld photos", language: language, Int64(group.visibleMembers.count)),
                identifier: "clove.detail.expandGroup",
                tone: .neutral,
                nudgeTrigger: expandPillNudgeCount
            ) { actions.expandGroup(group.id) }
        }
        return nil
    }

    private var detailSubtitle: String {
        var parts: [String] = []
        if let expandedGroup,
            let index = expandedGroup.visibleMembers.firstIndex(where: { $0.id == photo.id })
        {
            let pos = AppLocalization.format(
                "%lld / %lld", language: language, Int64(index + 1),
                Int64(expandedGroup.visibleMembers.count))
            parts.append(AppLocalization.format("Group · %@", language: language, pos))
        } else if let index = timeline.slotIndex(containing: photo.id) {
            parts.append(
                AppLocalization.format(
                    "%lld / %lld", language: language, Int64(index + 1),
                    Int64(timeline.slots.count)))
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
            image: shown?.image ?? placeholder,
            fullResolutionPixels: shown?.fullResolutionPixels,
            command: command,
            doubleTapZoomEnabled: settings.doubleTap != .off,
            rules: rules,
            currentRating: browsing.shownMarks(for: photo.id).rating,
            feedback: swipeFeedback,
            onZoomChange: { zoomChanged($0) },
            onChromeToggle: { toggleChrome() },
            onStep: { actions.step($0) },
            onDoubleTap: { doubleTap(at: $0) },
            onMarkingSwipe: { applyMarkingSwipe($0, touchCount: 1) },
            onTwoFingerMarkingSwipe: { applyMarkingSwipe($0, touchCount: 2) },
            onSwipeBegin: { beginMarkingGesture() },
            allowsMarking: allowsMarkingInput,
            onReadOnlyMarkingDrag: isReadOnlyCollapsedGroup ? { expandPillNudgeCount += 1 } : nil,
            hasPrevious: navigationAvailability.previous,
            hasNext: navigationAvailability.next,
            probe: probe,
            focusRegions: shown == nil
                ? []
                : focusRegionState.regions(
                    visible: browsing.showsFocusRegions,
                    inspectedRegionID: inspectedFocusRegionID),
            inspectedFocusRegionID: inspectedFocusRegionID,
            focusRegionColours: DetailFocusRegionColours(
                normal: UIColor(theme.tokens.focusOutline.color),
                contrastEdge: UIColor(theme.tokens.focusEdge.color),
                selected: UIColor(theme.tokens.accent.color),
                unavailable: UIColor(theme.tokens.focusOutline.color.opacity(0.58))),
            onFocusRegionTap: { focusRegionTapped($0) },
            previewAccessibilityLabel: displayMarks.isRejected
                ? AppLocalization.format("%@, Rejected", language: language, photo.fileName)
                : photo.fileName
        )
        .overlay {
            DetailSwipeFeedbackBadge(
                feedback: swipeFeedback, enabledRatings: settings.enabledRatings,
                controlsHeight: swipeFeedbackReservation, chromeIsVisible: chromeIsVisible)
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            guard size != viewSize else { return }
            viewSize = size
            if let restored = pendingRestoredZoom {
                pendingRestoredZoom = nil
                if case .fullResolution = zoomMode {
                    retargetFullResolution(for: size, force: true)
                } else if isDuoExpanded {
                    setZoom(.scale(restored.scale, anchor: restored.anchor.unitPoint))
                }
            } else {
                retargetFullResolution(for: size)
            }
        }
        .overlay { previewState }
        .overlay(alignment: .topLeading) { topLeadingStageOverlays }
        .overlay(alignment: .topTrailing) {
            DetailRejectGlyphOverlay(photoID: photo.id, isRejected: displayMarks.isRejected)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clove.bg.stage)
    }

    private var placeholder: CGImage? {
        if case .placeholder(let pixels) = phase { return pixels }
        return nil
    }

    /// Loading shows pixels alone; unavailable and failed answers keep their explicit copy.
    @ViewBuilder private var previewState: some View {
        if shown == nil {
            switch phase {
            case .placeholder:
                EmptyView()
            case .unavailable(let failure):
                Text(unavailableText(failure))
                    .foregroundStyle(.secondary)
                    .padding()
                    .accessibilityIdentifier("clove.detail.unavailable")
            case .deferred:
                Text(AppLocalization.string("The preview did not load.", language: language))
                    .foregroundStyle(.secondary)
                    .padding()
                    .accessibilityIdentifier("clove.detail.unavailable")
            case .shown:
                EmptyView()
            }
        }
    }

    /// Compact passive face/AF result indicators and any preview-only limitation note stacked cleanly
    /// in the viewport's upper-leading corner inside its safe area.
    @ViewBuilder private var topLeadingStageOverlays: some View {
        let indicators = focusRegionState.resultIndicators(
            visible: shown != nil && chromeIsVisible && browsing.showsFocusRegions)
        let showsLimitation = limitation != nil && shown != nil
        if !indicators.isEmpty || showsLimitation {
            VStack(alignment: .leading, spacing: 6) {
                if !indicators.isEmpty {
                    DetailFocusResultIndicatorsView(
                        indicators: indicators,
                        usesPhotoBacking: DetailFocusResultIndicators.coversPhotoPixels(
                            indicators: indicators,
                            scale: scale,
                            imagePixels: shown.map { pixelSize($0) },
                            viewSize: viewSize),
                        language: language)
                }
                limitationNote
            }
            .padding(.top, 8)
            .padding(.leading, 12)
            .allowsHitTesting(false)
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
                .accessibilityIdentifier("clove.detail.limitation")
        }
    }

    // MARK: - Focus regions

    private func loadFocusRegions(for photo: GridPhoto) async {
        let analysisID = UUID()
        focusAnalysisID = analysisID
        guard browsing.showsFocusRegions else {
            focusRegionState = DetailFocusRegionState()
            return
        }
        focusRegionState.begin(for: photo.id)
        guard let source = images as? DetailRegionSharpnessSource else {
            focusRegionState.finish(nil, for: photo.id)
            return
        }
        let group =
            timeline.activeGroup(containing: photo.id)?.visibleMembers.map(\.id).filter {
                $0 != photo.id
            } ?? []
        let position = order.firstIndex(where: { $0.id == photo.id }) ?? 0
        let nearby = [position - 1, position + 1].compactMap { index in
            order.indices.contains(index) ? order[index].id : nil
        }
        let analysis = await source.analyzeRegions(
            for: photo.id, group: group, nearby: nearby
        ) { result in
            Task { @MainActor in
                guard focusAnalysisID == analysisID else { return }
                focusRegionState.receiveAutofocus(result, for: photo.id)
            }
        }
        guard !Task.isCancelled, focusAnalysisID == analysisID else { return }
        focusRegionState.finish(analysis, for: photo.id)
    }

    // MARK: - Pixels

    /// Asks for the photo's preview and keeps the crop only within Group Focus (PRD P0-04, #304).
    ///
    /// Between members of the expanded group, the new photo opens at the previous photo's crop;
    /// every Timeline step or collapse onto another photo returns to fit (#302, #304). A deferred
    /// answer is retried a bounded number of times because the pipeline may have been busy with the
    /// photo that was on screen a moment ago; a refused or unreadable file is final and shown as
    /// its own state. The neighbours' previews are prefetched after the photo's own pixels are on
    /// screen, so a swipe to them is cheap (G1 scheduling row).
    private func loadPreview(for photo: GridPhoto) async {
        let arrivalID = PerformanceSignpost.detailArrival.makeSignpostID()
        var screenArrivalInterval: OSSignpostIntervalState? = PerformanceSignpost.detailArrival
            .beginInterval("DetailArrivalToScreen", id: arrivalID)
        defer {
            if let screenArrivalInterval {
                PerformanceSignpost.detailArrival.endInterval(
                    "DetailArrivalToScreen", screenArrivalInterval)
            }
        }
        var previewArrivalInterval: OSSignpostIntervalState? = PerformanceSignpost.detailArrival
            .beginInterval("DetailArrivalToPreview", id: arrivalID)
        defer {
            if let previewArrivalInterval {
                PerformanceSignpost.detailArrival.endInterval(
                    "DetailArrivalToPreview", previewArrivalInterval)
            }
        }

        upgradeTask?.cancel()
        isLoadingFit = true
        loadedOrder = DetailDisplayOrder(photo: photo.id, order: order.map(\.id))
        keepsPosition =
            previousPhoto.map { previous in
                previous != photo.id
                    && (expandedGroup?.visibleMembers.contains(where: { $0.id == previous })
                        ?? false)
                    && (expandedGroup?.visibleMembers.contains(where: { $0.id == photo.id })
                        ?? false)
            } ?? false
        previousPhoto = photo.id
        // Only members within Group Focus share a crop; every other photo change returns to fit
        // (#302, #304). A retained zoom across unrelated photos would open on an arbitrary region
        // before the next photo's focus analysis lands.
        if keepsPosition {
            if let shown {
                // A preview that has not arrived yet leaves `shown` nil, so this branch is skipped:
                // the zoom read before an earlier step in a run of quick steps stays pending for
                // the photo that finally loads (PRD In-group culling, synchronized zoom).
                let snapshot = probe.container?.zoomSnapshot
                keptScale = snapshot?.scale
                keptNativeScale = snapshot != nil ? nativeFullResolutionScale(for: shown) : nil
                keptZoom = snapshot
                // A view at fit keeps no zoom, so nothing carries into the next photo. That
                // includes a 100% that is still waiting for the render's size: it belongs to the
                // photo that was tapped, not to the one a swipe moves to (#111).
                if snapshot == nil { zoomMode = .fit }
            }
        } else {
            keptZoom = nil
            keptScale = nil
            keptNativeScale = nil
            zoomMode = .fit
            setZoom(.fit)
        }
        limitation = nil
        previewOnly = false

        var previewPrefetchTask: Task<Void, Never>?
        defer { previewPrefetchTask?.cancel() }

        let window: DetailPhotoWindow
        var presentedWarm = false
        if viewSize != .zero, let screen = probe.container?.window?.windowScene?.screen {
            // Keep the full-screen native long edge across Duo split toggles: reducing to a 70%
            // split edge saves only ~6% on screen RAW render time while forcing ~280 ms re-renders
            // whenever split presets change.
            let screenPixels = Int(max(screen.nativeBounds.width, screen.nativeBounds.height))
            let candidateWindow = photoWindow(for: photo, screenPixels: screenPixels)
            if let warm = images.warmImage(for: photo.id, request: candidateWindow.request()) {
                window = candidateWindow
                currentWindow = window
                previousPosition = window.current.position
                show(warm)
                presentedWarm = true
                if let interval = previewArrivalInterval {
                    previewArrivalInterval = nil
                    PerformanceSignpost.detailArrival.endInterval(
                        "DetailArrivalToPreview", interval)
                }
                await images.prepare(window)
                guard !Task.isCancelled else { return }
                previewPrefetchTask = Task { await images.prefetchPreviews(window) }
            } else {
                shown = nil
                phase = .placeholder(nil)
                let thumbnail = await images.placeholder(
                    for: photo.id, gridThumbnails: browsing.thumbnails)
                guard !Task.isCancelled else { return }
                phase = .placeholder(thumbnail)
                window = candidateWindow
                currentWindow = window
                previousPosition = window.current.position
                await images.prepare(window)
                guard !Task.isCancelled else { return }
            }
        } else {
            shown = nil
            phase = .placeholder(nil)
            let thumbnail = await images.placeholder(
                for: photo.id, gridThumbnails: browsing.thumbnails)
            guard !Task.isCancelled else { return }
            phase = .placeholder(thumbnail)
            // Wait for the display, not just layout: the first render must use the
            // same physical screen edge as later photos and their held-render keys.
            for _ in 0..<120 {
                guard !Task.isCancelled else { return }
                if viewSize != .zero, probe.container?.window?.windowScene != nil { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled, let screen = probe.container?.window?.windowScene?.screen
            else {
                return
            }
            let screenPixels = Int(max(screen.nativeBounds.width, screen.nativeBounds.height))
            window = photoWindow(for: photo, screenPixels: screenPixels)
            currentWindow = window
            previousPosition = window.current.position
            await images.prepare(window)
            guard !Task.isCancelled else { return }
        }

        let request = window.request()
        var attempts = 0
        while true {
            let outcome = await images.image(for: photo.id, request: request)
            if Task.isCancelled { return }
            switch outcome {
            case .image(let image):
                if !presentedWarm
                    || image.image !== shown?.image
                    || image.quality != shown?.quality
                    || image.source != shown?.source
                    || image.fullResolutionSize != shown?.fullResolutionSize
                {
                    show(image)
                }
                if let interval = previewArrivalInterval {
                    previewArrivalInterval = nil
                    PerformanceSignpost.detailArrival.endInterval(
                        "DetailArrivalToPreview", interval)
                }
                if previewPrefetchTask == nil {
                    previewPrefetchTask = Task { await images.prefetchPreviews(window) }
                }
                await renderFitAndPrefetch(window) {
                    if let interval = screenArrivalInterval {
                        screenArrivalInterval = nil
                        PerformanceSignpost.detailArrival.endInterval(
                            "DetailArrivalToScreen", interval)
                    }
                }
                return
            case .unavailable(let failure):
                phase = .unavailable(failure)
                if let interval = previewArrivalInterval {
                    previewArrivalInterval = nil
                    PerformanceSignpost.detailArrival.endInterval(
                        "DetailArrivalToPreview", interval)
                }
                if previewPrefetchTask == nil {
                    previewPrefetchTask = Task { await images.prefetchPreviews(window) }
                }
                await renderFitAndPrefetch(window) {
                    if let interval = screenArrivalInterval {
                        screenArrivalInterval = nil
                        PerformanceSignpost.detailArrival.endInterval(
                            "DetailArrivalToScreen", interval)
                    }
                }
                return
            case .deferred:
                attempts += 1
                guard attempts < 3 else {
                    if !presentedWarm { phase = .deferred }
                    return
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    /// Updates `DetailPhotoWindow` prefetch neighbours when the active level or filter order
    /// changes without changing `photo.id` (e.g. expanding/collapsing on the representative photo),
    /// keeping the shown pixels and zoom untouched (issue #304, decision 3).
    private func refreshPrefetchForOrderChange(for photo: GridPhoto) async {
        let targetOrder = DetailDisplayOrder(photo: photo.id, order: order.map(\.id))
        guard loadedOrder?.photo == photo.id, loadedOrder != targetOrder else { return }
        for _ in 0..<120 {
            guard !Task.isCancelled else { return }
            if currentWindow?.current.photo == photo.id,
                viewSize != .zero,
                probe.container?.window?.windowScene != nil
            {
                break
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
        guard !Task.isCancelled,
            currentWindow?.current.photo == photo.id,
            viewSize != .zero,
            let screen = probe.container?.window?.windowScene?.screen
        else {
            return
        }
        loadedOrder = targetOrder
        let screenPixels = Int(max(screen.nativeBounds.width, screen.nativeBounds.height))
        let window = photoWindow(for: photo, screenPixels: screenPixels)
        currentWindow = window
        previousPosition = window.current.position
        await images.prepare(window)
        guard !Task.isCancelled else { return }
        await images.prefetchPreviews(window)
        guard !Task.isCancelled, !isLoadingFit, let shown, shown.limitation == nil else { return }
        let renderAhead =
            shown.quality == .screenRAW || shown.quality == .nativeRAW || !shown.hasRAW
        await images.prefetch(window, renderAhead: renderAhead)
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
    /// synchronized zoom; PRD P0-12). A group also keeps the position, and asks for the pixels its
    /// retained zoom needs; a photo outside the group opens at fit instead (#302).
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
            // The group's retained zoom may need more pixels than the preview holds (G1 "Preview,
            // detail (I2)").
            if keepsPosition && !isLoadingFit { upgradeIfNeeded() }
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
        let previewNeighbours = [
            index + direction,
            index - direction,
            index + 2 * direction,
            index - 2 * direction,
        ].compactMap { position -> DetailNeighbour? in
            guard order.indices.contains(position) else { return nil }
            return DetailNeighbour(photo: order[position].id, position: position)
        }
        return DetailPhotoWindow(
            id: windowID,
            current: DetailNeighbour(photo: photo.id, position: index),
            neighbours: neighbours,
            previewNeighbours: previewNeighbours,
            direction: direction,
            mode: currentWindow.flatMap { $0.current.photo == photo.id ? $0.mode : nil }
                ?? displayMode,
            screenPixels: screenPixels)
    }

    /// The preview stays on screen throughout the RAW fit upgrade, with no cue
    /// or status word. One-ahead work starts only after the current render shows.
    private func renderFitAndPrefetch(
        _ window: DetailPhotoWindow, onScreenSettled: () -> Void = {}
    ) async {
        var renderInterval: OSSignpostIntervalState? = PerformanceSignpost.detailArrival
            .beginInterval(
                "DetailScreenRender", id: PerformanceSignpost.detailArrival.makeSignpostID())
        defer {
            if let renderInterval {
                PerformanceSignpost.detailArrival.endInterval("DetailScreenRender", renderInterval)
            }
        }
        let outcome = await images.image(
            for: window.current.photo,
            request: window.request(need: .screenRender))
        guard !Task.isCancelled else { return }
        if case .image(let image) = outcome, shown?.isBestAvailable != true {
            show(image)
        }
        if let interval = renderInterval {
            renderInterval = nil
            PerformanceSignpost.detailArrival.endInterval("DetailScreenRender", interval)
        }
        onScreenSettled()
        isLoadingFit = false
        if keepsPosition { upgradeIfNeeded() }
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
        if value <= DetailFitScale.tolerance {
            inspectedFocusRegionID = nil
        }
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

    /// The double-tap action chosen in Settings, or back to fit (PRD P0-04, PRD Gesture-related
    /// settings).
    ///
    /// `Zoom to focus` (the default) centres 100% on the most relevant presented focus region and
    /// `Zoom to tap point` always centres on the tapped image point, even while focus regions are
    /// presented (#302). `Off` leaves double taps to the scroll view.
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
        guard settings.doubleTap != .off else { return }
        guard scale <= DetailFitScale.tolerance else {
            inspectedFocusRegionID = nil
            zoomMode = .fit
            setZoom(.fit)
            return
        }
        guard shown != nil else { return }
        if settings.doubleTap == .zoomToFocus,
            let targetRegion = focusRegionState.preferredDoubleTapRegion(
                at: anchor,
                visible: browsing.showsFocusRegions,
                inspectedRegionID: inspectedFocusRegionID)
        {
            inspectedFocusRegionID = targetRegion.id
            inspectFullResolution(at: targetRegion.centre)
        } else {
            inspectedFocusRegionID = nil
            inspectFullResolution(at: anchor)
        }
    }

    /// A valid analysis region always enters the existing 100% inspection, independently of the
    /// double-tap setting. It neither resolves a marking input nor calls a navigation action.
    private func focusRegionTapped(_ region: DetailFocusRegion) {
        guard region.isActionable else { return }
        inspectedFocusRegionID = region.id
        inspectFullResolution(at: region.centre)
    }

    private func inspectFullResolution(at anchor: UnitPoint) {
        guard let shown else { return }
        let chosen = DetailZoomAnchor(x: anchor.x, y: anchor.y)
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

    private func retargetFullResolution(for size: CGSize, force: Bool = false) {
        guard size.width > 0, size.height > 0,
            case .fullResolution(let chosen, _) = zoomMode,
            scale > DetailFitScale.tolerance,
            let shown,
            let target = DetailZoom.fullResolutionTarget(
                nativePixels: shown.fullResolutionPixels, shownPixels: pixelSize(shown),
                viewSize: size, screenScale: displayScale, previewIsAll: previewOnly),
            target > DetailFitScale.tolerance,
            force || abs(target - scale) > 0.005
        else { return }
        let anchor = probe.container?.zoomSnapshot?.anchor ?? chosen
        zoomMode = .fullResolution(anchor: anchor, size: shown.fullResolutionPixels)
        setZoom(.scale(target, anchor: anchor.unitPoint))
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
            mode: window.mode, screenPixels: window.screenPixels)
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

    /// The neighbours horizontal swipes and keyboard shortcuts use in the active Detail level.
    var navigationAvailability: (previous: Bool, next: Bool) {
        if let expandedGroup {
            guard let index = expandedGroup.visibleMembers.firstIndex(where: { $0.id == photo.id })
            else {
                return (false, false)
            }
            return (index > 0, index + 1 < expandedGroup.visibleMembers.count)
        }
        guard let index = timeline.slotIndex(containing: photo.id) else {
            return (false, false)
        }
        return (index > 0, index + 1 < timeline.slots.count)
    }

    /// Toggles chrome visibility when single-tapping anywhere on the preview, at both fit and
    /// zoomed scales (PRD P0-04, #252, #273).
    private func toggleChrome() {
        hidesChrome.toggle()
    }

    // MARK: - Marking

    /// One hardware key from the PRD keyboard table, resolved by C13's key rule (PRD P0-06).
    ///
    /// The key reads the marks the rail and the capsule act on, so a disabled level or a key that
    /// would change nothing is the same no-input the rules already report for them.
    private func markKey(_ key: MarkingKey) {
        tapPickerDismissToken += 1
        apply(
            rules.result(
                for: key, marks: browsing.shownMarks(for: photo.id),
                allowsMarking: allowsMarkingInput))
    }

    private func beginMarkingGesture() {
        tapPickerDismissToken += 1
        actions.markingSwipeBegan()
    }

    /// Undoes the last mark from the top bar, Duo dock or `⌘Z` (PRD Undo row).
    private func undo() {
        beginMarkingGesture()
        browsing.undoLastMark()
    }

    /// One rating tap, resolved by C13's rating-bar rule (PRD Marking rules).
    private func rate(_ rating: Rating, togglesCurrent: Bool = true) {
        let marks = browsing.shownMarks(for: photo.id)
        // The rail resolves tap-to-clear itself and a drag commits its final value directly.
        apply(
            togglesCurrent
                ? rules.result(
                    forRating: rating, marks: marks, allowsMarking: allowsMarkingInput)
                : rules.result(
                    for: .rating(rating), marks: marks, allowsMarking: allowsMarkingInput))
    }

    /// One label choice, resolved by C13's label rule (PRD Marking rules).
    private func choose(_ label: ColourLabel) {
        apply(
            rules.result(
                forLabel: label, marks: browsing.shownMarks(for: photo.id),
                allowsMarking: allowsMarkingInput))
    }

    /// Toggles Reject, which is the rating −1 (PRD Marking rules).
    private func toggleReject() {
        // The HUD's Reject is a toggle, while the `↓` key only turns Reject on. C13 owns both
        // directions and the mark kind auto-advance reads (PRD Marking rules, PRD Auto-advance).
        apply(
            rules.result(
                forRejectToggle: browsing.shownMarks(for: photo.id),
                allowsMarking: allowsMarkingInput))
    }

    /// Resolves one finished marking swipe through C13's gesture rules (PRD P0-06).
    func applyMarkingSwipe(_ rating: Rating, touchCount: Int = 1) {
        guard allowsMarkingInput else { return }
        let isZoomed = (probe.container?.isZoomed ?? false) || scale > DetailFitScale.tolerance
        apply(
            rules.result(
                forSwipeRating: rating, marks: browsing.shownMarks(for: photo.id),
                isZoomed: isZoomed, touchCount: touchCount, allowsMarking: allowsMarkingInput))
    }

    /// Applies one resolved marking input and asks the screen to start the advance it asks for
    /// (PRD Auto-advance).
    ///
    /// The gesture, the HUD bar, a label, the Reject toggle and the keyboard all come through
    /// here, so the mark path is one function. A result that changes nothing writes nothing and
    /// advances nothing (PRD P0-06 acceptance).
    private func apply(_ result: MarkingResult) {
        switch result {
        case .mark(let change, let kind):
            guard allowsMarkingInput else { return }
            // Plan navigation from the current order before a mark removes this photo from
            // a live filter. Both calls are synchronous; the mark still shows in this input turn.
            actions.marked(kind, change, photo)
            actions.apply(change, photo)
        case .previousPhoto:
            actions.step(-1)
        case .nextPhoto:
            actions.step(1)
        case .undo:
            undo()
        case .toggleGroupFocus:
            if expandedGroup != nil {
                actions.collapseGroup()
            } else if let group = currentTimelineGroup {
                actions.expandGroup(group.id)
            }
        case .collapseGroup:
            if expandedGroup != nil {
                actions.collapseGroup()
            }
        case .noChange:
            break
        }
    }

    /// C13's rules for this screen's settings.
    private var rules: MarkingInputRules {
        var inputSettings = settings
        inputSettings.gesturesEnabled = settings.gesturesEnabled && browsing.canMark
        return MarkingInputRules(settings: inputSettings)
    }

    private var tapPickerDismissTrigger: DetailTapPickerDismissTrigger {
        DetailTapPickerDismissTrigger(
            photoID: photo.id,
            canMark: browsing.canMark,
            chromeIsVisible: chromeIsVisible,
            showsInformation: showsInformation,
            dismissToken: tapPickerDismissToken)
    }

    private var duoPopoverDismissTrigger: DetailDuoPopoverDismissTrigger {
        DetailDuoPopoverDismissTrigger(
            route: browsing.state.route,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover,
            usesVerticalToolbar: usesVerticalToolbar,
            hasFoldRegion: hasFoldRegion,
            horizontalSizeClass: horizontalSizeClass,
            allowsMarkingInput: allowsMarkingInput,
            hasDuo: duo != nil)
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
        if scale <= DetailFitScale.tolerance {
            return AppLocalization.string("Fit", language: language)
        }
        if let shown, viewSize.width > 0, let pixels = shown.fullResolutionPixels,
            DetailZoom.isFullResolution(
                scale: scale, nativePixels: pixels, viewSize: viewSize,
                screenScale: displayScale)
        {
            return AppLocalization.format("%lld%%", language: language, Int64(100))
        }
        return AppLocalization.format(
            "%lld%%", language: language, Int64((scale * 100).rounded()))
    }

    // MARK: - Words

    /// Why no pixels could be shown (PRD Scan scope: never a blank image presented as loaded).
    private func unavailableText(_ failure: DetailFailure) -> String {
        switch failure {
        case .cannotOpen:
            AppLocalization.string("This file cannot be opened as an image.", language: language)
        case .noUsablePreview:
            AppLocalization.string("This file has no preview Clove can show.", language: language)
        case .sourceChanged:
            AppLocalization.string("The file changed while it was opening.", language: language)
        }
    }

    /// Why these pixels are the best available (PRD P0-04).
    private func limitationText(_ limitation: DetailLimitation) -> String {
        switch limitation {
        case .rawRenderFailed:
            AppLocalization.string("Preview only — the RAW render failed.", language: language)
        case .noHigherResolution:
            AppLocalization.string(
                "Preview only — full resolution is unavailable.", language: language)
        }
    }
}

private struct DetailTapPickerDismissTrigger: Equatable {
    let photoID: PhotoIdentity
    let canMark: Bool
    let chromeIsVisible: Bool
    let showsInformation: Bool
    let dismissToken: Int
}

private struct DetailDuoPopoverDismissTrigger: Equatable {
    let route: BrowserRoute
    let isDuoExpanded: Bool
    let isDuoCover: Bool
    let usesVerticalToolbar: Bool
    let hasFoldRegion: Bool
    let horizontalSizeClass: UserInterfaceSizeClass?
    let allowsMarkingInput: Bool
    let hasDuo: Bool
}

/// Filtering a group can change neighbours without changing its current photo.
private struct DetailDisplayOrder: Hashable {
    let photo: PhotoIdentity
    let order: [PhotoIdentity]
}

/// Focus region loading starts only for the active photo when the overlay is enabled.
private struct DetailFocusTrigger: Hashable {
    let photo: PhotoIdentity
    let showsFocusRegions: Bool
}

/// The first preview's state, so loading, failure and success never look alike (PRD P0-04).
private enum DetailMarkingPreviewPhase {
    case placeholder(CGImage?)
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

private struct DetailRejectGlyphOverlay: View {
    let photoID: PhotoIdentity
    let isRejected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settledPhotoID: PhotoIdentity?

    private var shouldAnimate: Bool {
        CloveMotion.shouldAnimateMarkChange(settledPhotoID: settledPhotoID, currentPhotoID: photoID)
    }

    var body: some View {
        Group {
            if isRejected {
                Image(systemName: "flag.slash.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.clove.reject, in: Circle())
                    .padding(8)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("clove.detail.rejectGlyph")
                    .accessibilityHidden(true)
                    .transition(
                        .asymmetric(
                            insertion: CloveMotion.scaleOpacityTransition(
                                scale: 0.85, anchor: .topTrailing, reduceMotion: reduceMotion),
                            removal: .identity))
            }
        }
        .animation(
            shouldAnimate && isRejected ? CloveMotion.micro(reduceMotion: reduceMotion) : nil,
            value: isRejected
        )
        .onAppear { settledPhotoID = photoID }
        .onChange(of: photoID) { _, newValue in
            settledPhotoID = newValue
        }
    }
}
