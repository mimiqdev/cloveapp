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
    var undo: (() -> Void)? = nil
    var backToGrid: (() -> Void)? = nil
    var photoTapped: () -> Void = {}
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
    var allReviewedToast: DetailAllReviewedToast? = nil
    var undoToast: DetailUndoToast? = nil
    var compareRotateToastID: UUID? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.cloveUserInterfaceIdiom) private var overrideUserInterfaceIdiom
    @Environment(\.cloveTheme) private var theme
    @Environment(\.usesSystemBrowsingToolbar) private var usesSystemToolbar
    @Environment(\.usesVerticalBrowsingToolbar) private var usesVerticalToolbar
    @Environment(\.isDuoExpanded) private var isDuoExpanded
    @Environment(\.isDuoCover) private var isDuoCover
    @Environment(\.hasFoldRegion) private var hasFoldRegion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cloveReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }
    @Environment(\.appLanguage) private var language
    @Environment(SettingsStore.self) private var settingsStore: SettingsStore?
    @State private var hidesChrome = false
    @State private var widePresentation: DetailPresentation
    @State private var containerSize: CGSize = .zero
    @State private var pendingRestoredZoom: DetailZoomSnapshot?
    @State private var windowID = UUID()
    @State private var currentWindow: DetailPhotoWindow?
    @State private var loadedOrder: DetailDisplayOrder?
    @State private var previousPosition: Int?
    @State private var previousPhoto: PhotoIdentity?
    @State private var keepsPosition = false
    @State private var isLoadingFit = false
    private enum DetailSheetRoute: Identifiable, Equatable {
        case information
        case metadataFilters

        var id: String {
            switch self {
            case .information: "information"
            case .metadataFilters: "metadataFilters"
            }
        }
    }

    @State private var activeSheet: DetailSheetRoute?
    @State private var emptyFromFilterSelection = false
    private var showsInformation: Bool { activeSheet == .information }
    @State private var showsZoomChip = false
    @State private var controlsHeight: CGFloat = 0

    /// The floating pill's height in a pane whose chrome is a dock outside the stage: the marking
    /// swipe's star bar must stay above the pill there too (#305).
    @State private var duoPillHeight: CGFloat = 0
    @State private var tapPickerDismissToken = 0
    @State private var gridPickerDismissToken = 0
    @State private var focusRegionState = DetailFocusRegionState()
    @State private var focusAnalysisID = UUID()
    @State private var inspectedFocusRegionID: String?
    @State private var focusTracking = DetailFocusTrackingState()

    /// Detail pixels on screen; the grid thumbnail stands in until these arrive.
    @State private var shown: DetailImage?
    @State private var shownPhoto: PhotoIdentity?

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
    @State private var activeUpgradePhotoID: PhotoIdentity?
    @State private var activeUpgradeNeed: DetailPixelRequest.Need?
    @State private var activeUpgradeToken: UUID?

    /// 250 ms delay-gated 100% RAW progressive decode readout state.
    @State private var progressiveDecode = RawProgressiveDecodeController()

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
        initialPresentation: DetailPresentation = .photoPreview,
        allReviewedToast: DetailAllReviewedToast? = nil,
        undoToast: DetailUndoToast? = nil,
        compareRotateToastID: UUID? = nil
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
                groupsEnabled: settings.similarGroupsEnabled && !browsing.isScanning)
        self.expandedGroup = expandedGroup
        self.order = order
        self.actions = actions
        self.duo = duo
        self.presentation = presentation
        self.allReviewedToast = allReviewedToast
        self.undoToast = undoToast
        self.compareRotateToastID = compareRotateToastID
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
                cancelUpgradeTask()
                inspectedFocusRegionID = nil
                pendingRestoredZoom = nil
                focusAnalysisID = UUID()
                focusRegionState = DetailFocusRegionState()
                focusTracking.cancelPendingRecenter()
            }
            .onChange(of: browsing.folderLocationLoss != nil) { _, isLost in
                guard isShowingProgressiveZoomState else { return }
                if isLost {
                    DetailProgressiveDecodeSupport.syncAtFullResolution(
                        controller: progressiveDecode,
                        photoID: photo.id,
                        fileName: photo.fileName,
                        photoSet: browsing.scannedSet(for: photo.id)?.photoSet,
                        displayMode: currentWindow?.mode ?? displayMode,
                        shown: shown,
                        isPreviewOnly: previewOnly,
                        isLocationLost: true,
                        startingUpgrade: false)
                } else if progressiveDecode.phase == .previewOnly, !previewOnly {
                    progressiveDecode.reset()
                    upgradeIfNeeded()
                }
            }
            .onChange(of: expandedGroup?.id) { oldGroup, newGroup in
                if oldGroup != nil, newGroup == nil {
                    focusTracking.reset()
                }
            }
            .onChange(of: browsing.state.folder) { _, _ in
                focusTracking.reset()
                inspectedFocusRegionID = nil
                emptyFromFilterSelection = false
                activeSheet = nil
            }
            .onChange(of: detailFilterSelectionKey) { _, _ in
                handleDetailFilterSelectionChange()
            }
            .onChange(of: tapPickerDismissTrigger) { _, _ in
                gridPickerDismissToken += 1
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
                cancelUpgradeTask()
                shown = nil
                shownPhoto = nil
                phase = .placeholder(nil)
                focusTracking.reset()
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
        let duoHasFocusOverlay = duo != nil && isDuoExpanded && showsFilmstrip
        let floatingPillVisible: Bool =
            if duoHasFocusOverlay {
                chromeIsVisible || hasTransientToast
            } else if duo != nil && !isDuoExpanded {
                hasTransientToast || (chromeIsVisible && stagePill != nil)
            } else {
                false
            }
        let floatingPillHeight: CGFloat =
            if duoHasFocusOverlay {
                max(
                    DetailInspectionPill.size.height,
                    (!hasTransientToast && stagePill != nil) ? duoPillHeight : 0)
            } else {
                duoPillHeight
            }
        return Self.swipeFeedbackReservation(
            floatingPillInStage: duo != nil,
            pillVisible: floatingPillVisible,
            pillHeight: floatingPillHeight,
            pillGap: 12,
            measuredBand: isOrdinaryPhoneLandscape ? 0 : controlsHeight)
    }

    private var visibleAllReviewedToast: DetailAllReviewedToast? {
        browsing.failureToastMessage == nil ? allReviewedToast : nil
    }

    private var visibleUndoToast: DetailUndoToast? {
        guard browsing.failureToastMessage == nil, allReviewedToast == nil else { return nil }
        return undoToast
    }

    private var visibleCompareRotateToastID: UUID? {
        guard browsing.failureToastMessage == nil, allReviewedToast == nil, undoToast == nil else {
            return nil
        }
        return compareRotateToastID
    }

    private var hasTransientToast: Bool {
        visibleAllReviewedToast != nil || visibleUndoToast != nil
            || visibleCompareRotateToastID != nil
    }

    private var transientToastIdentity: String? {
        visibleAllReviewedToast?.id.uuidString
            ?? visibleUndoToast?.id.uuidString
            ?? visibleCompareRotateToastID?.uuidString
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

    private var userInterfaceIdiom: UIUserInterfaceIdiom {
        overrideUserInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom
    }

    private var isOrdinaryPhone: Bool {
        userInterfaceIdiom == .phone && !isDuoExpanded && !isDuoCover && !hasFoldRegion
    }

    private var isLandscapeContainer: Bool {
        containerSize.width > containerSize.height && containerSize.width > 0
    }

    private var isOrdinaryPhoneLandscape: Bool {
        isOrdinaryPhone && (verticalSizeClass == .compact || isLandscapeContainer)
    }

    private var isWidePadLayout: Bool {
        !isOrdinaryPhone && horizontalSizeClass == .regular && duo == nil
    }

    private var detailBackTitle: String? {
        Self.resolvedBackTitle(
            isWidePadLayout: isWidePadLayout,
            isDuoExpanded: isDuoExpanded,
            filterTitle: browsing.localizedFilterTitle(language: language))
    }

    static func resolvedBackTitle(
        isWidePadLayout: Bool,
        isDuoExpanded: Bool,
        filterTitle: String
    ) -> String? {
        isWidePadLayout && !isDuoExpanded ? filterTitle : nil
    }

    private var usesDuoViewportOverlay: Bool {
        isDuoCover || (isDuoExpanded && (usesVerticalToolbar || !hasFoldRegion))
    }

    private var presentationPolicy: DetailPresentationPolicy {
        DetailPresentationPolicy(
            isRegularWidth: horizontalSizeClass == .regular,
            isPhone: userInterfaceIdiom == .phone,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover,
            hasFoldRegion: hasFoldRegion,
            availableWidth: Double(containerSize.width),
            availableHeight: Double(containerSize.height))
    }

    private var compareLayoutPolicy: CompareLayoutPolicy {
        CompareLayoutPolicy(
            availableWidth: Double(containerSize.width),
            availableHeight: Double(containerSize.height),
            isRegularWidth: horizontalSizeClass == .regular,
            isCompactHeight: verticalSizeClass == .compact,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover)
    }

    private var usesInspectionPill: Bool {
        userInterfaceIdiom == .pad || isDuoExpanded
    }

    private var usesUnifiedStageBackground: Bool {
        userInterfaceIdiom == .pad || isDuoExpanded || isDuoCover
    }

    private var canEnterCompare: Bool {
        compareLayoutPolicy.supportsCompare
            && browsing.canEnterCompareFromDetail(timeline: timeline)
    }

    private var inspectionPill: some View {
        DetailInspectionPill(
            isFocusRegionsOn: browsing.showsFocusRegions,
            canCompare: canEnterCompare,
            showsCompare: !isDuoExpanded || compareLayoutPolicy.supportsCompare,
            onToggleFocus: {
                browsing.showsFocusRegions.toggle()
            },
            onCompare: {
                dismissGestureGuide()
                tapPickerDismissToken += 1
                actions.markingSwipeBegan()
                browsing.enterCompareFromDetail(timeline: timeline)
            }
        )
    }

    private var compareToolbarButton: some View {
        Button(
            AppLocalization.string("Compare", language: language),
            systemImage: "rectangle.split.2x1"
        ) {
            dismissGestureGuide()
            tapPickerDismissToken += 1
            actions.markingSwipeBegan()
            browsing.enterCompareFromDetail(timeline: timeline)
        }
        .accessibilityIdentifier("clove.detail.compare")
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
        .background {
            Rectangle()
                .fill(Color.clove.bg.stage)
                .ignoresSafeArea(edges: usesUnifiedStageBackground ? .all : [])
        }
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
        .sheet(item: $activeSheet) { route in
            switch route {
            case .information:
                PhotoInformationSheet(
                    browsing: browsing,
                    photo: photo,
                    groupMemberCount: activePhotoGroupCount)
            case .metadataFilters:
                MetadataFilterSheet(browsing: browsing)
            }
        }
    }

    private var activePhotoGroupCount: Int? {
        Self.groupMemberCount(
            for: photo.id,
            timeline: timeline,
            expandedGroup: expandedGroup)
    }

    static func groupMemberCount(
        for photoID: PhotoIdentity,
        timeline: DetailTimeline,
        expandedGroup: ActiveBrowsingGroup?
    ) -> Int? {
        let group =
            if let expandedGroup,
                expandedGroup.visibleMembers.contains(where: { $0.id == photoID })
            {
                expandedGroup
            } else {
                timeline.activeGroup(containing: photoID)
            }
        guard let count = group?.visibleMembers.count, count >= 2 else { return nil }
        return count
    }

    @available(iOS 27.1, *)
    private var nativeStandardLayout: some View {
        standardLayout
            .toolbar {
                BrowsingToolbar(
                    back: { browsing.back() }, undo: undo, canUndo: browsing.canUndoMark,
                    showsUndo: false,
                    backTitle: detailBackTitle,
                    showsNavigationTools: !emptyFromFilterSelection,
                    showsTools: chromeIsVisible,
                    showsBottom: false
                ) {
                    if !emptyFromFilterSelection {
                        if presentationPolicy.supportsPhotoPreview {
                            photoGridToggle
                        }
                        if !usesInspectionPill {
                            focusRegionsToggle
                        }
                    }
                } tools: {
                    if chromeIsVisible {
                        if !emptyFromFilterSelection {
                            if isOrdinaryPhoneLandscape, let pill = makeStagePill(compact: true) {
                                Button(pill.title, action: pill.action)
                                    .tint(
                                        pill.tone == .destructive
                                            ? Color.clove.reject : Color.clove.text.primary
                                    )
                                    .accessibilityIdentifier(pill.identifier)
                            }
                            if !usesInspectionPill, canEnterCompare {
                                compareToolbarButton
                            }
                        }
                        detailFilterButton
                    }
                } marks: {
                    Optional<ToolbarItem<Void, EmptyView>>.none
                } bottom: {
                    EmptyView()
                }
                if !emptyFromFilterSelection {
                    ToolbarItem(placement: .principal) { detailToolbarTitle }
                        .axisBehavior(.horizontalOnly)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(
                usesUnifiedStageBackground ? .hidden : .automatic,
                for: .navigationBar
            )
            .toolbarVisibility(
                isOrdinaryPhoneLandscape && !chromeIsVisible ? .hidden : .visible,
                for: .navigationBar)
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
                size: isWidePadLayout ? .pad : .phone,
                identifier: "clove.detail.gridToggle"
            ) {
                togglePresentation()
            }
            .help(actionTitle)
        }
    }

    @ViewBuilder
    private var focusRegionsToggle: some View {
        let focusLabel = AppLocalization.string("Focus regions", language: language)
        let focusValue = AppLocalization.string(
            browsing.showsFocusRegions ? "On" : "Off", language: language)
        if usesSystemToolbar {
            Button {
                browsing.showsFocusRegions.toggle()
            } label: {
                Image(systemName: "dot.viewfinder")
                    .foregroundStyle(
                        browsing.showsFocusRegions ? Color.clove.accent : Color.clove.text.primary)
            }
            .tint(browsing.showsFocusRegions ? Color.clove.accent : Color.clove.text.primary)
            .help(focusLabel)
            .accessibilityLabel(focusLabel)
            .accessibilityValue(focusValue)
            .accessibilityAddTraits(browsing.showsFocusRegions ? .isSelected : [])
            .accessibilityIdentifier("clove.detail.focusToggle")
        } else {
            GlassIconButton(
                label: focusLabel,
                symbol: "dot.viewfinder",
                isActive: browsing.showsFocusRegions,
                size: isWidePadLayout ? .pad : .phone,
                identifier: "clove.detail.focusToggle"
            ) {
                browsing.showsFocusRegions.toggle()
            }
            .help(focusLabel)
            .reportHeaderControlFrame("clove.detail.focusToggle")
        }
    }

    private var infoButtonAccessibilityLabel: String {
        AppLocalization.format(
            "%@, %@", language: language, photo.fileName,
            AppLocalization.string("Info", language: language))
    }

    private var detailFilterButton: some View {
        PhotoFilterButton(
            browsing: browsing,
            controlSize: isWidePadLayout ? .pad : .phone,
            identifierPrefix: "clove.detail.filter",
            onMoreFilters: canPresentMetadataFilters ? { activeSheet = .metadataFilters } : nil
        )
    }

    private var detailToolbarTitle: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(photo.fileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.clove.text.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("clove.detail.fileName")
                    .reportHeaderControlFrame("clove.detail.fileName")
                Image(systemName: "info.circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.clove.text.secondary)
                    .layoutPriority(1)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                detailZoomReadout
                InlineFolderPreparationBar(
                    browsing: browsing,
                    identifier: "clove.detail.preparation.progress")
                SaveStatusIndicator(
                    browsing: browsing, identifierPrefix: "clove.detail.saveState")
            }
            .font(.caption)
            .foregroundStyle(Color.clove.text.secondary)
        }
        .padding(.horizontal, 6)
        .frame(minWidth: 44, minHeight: 44)
        .allowsHitTesting(false)
        .background {
            Button {
                activeSheet = .information
            } label: {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(infoButtonAccessibilityLabel)
            .accessibilityIdentifier("clove.detail.info")
            .reportHeaderControlFrame("clove.detail.info")
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func expandedLayout(_ duo: DuoDetailLayout) -> some View {
        if #available(iOS 27.1, *) {
            Group {
                if emptyFromFilterSelection {
                    filteredEmptyStage
                } else if duo.showsGrid && showsPhotoGrid {
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
                    back: { browsing.back() }, undo: undo, canUndo: browsing.canUndoMark,
                    showsUndo: false,
                    showsNavigationTools: false,
                    showsStandaloneDockTool: !emptyFromFilterSelection
                        && ((duo.showsGrid && presentationPolicy.supportsPhotoPreview)
                            || isDuoCover),
                    showsTools: true,
                    showsBottom: false
                ) {
                    EmptyView()
                } standaloneDockTool: {
                    if !emptyFromFilterSelection {
                        if duo.showsGrid && presentationPolicy.supportsPhotoPreview {
                            photoGridToggle
                        } else if isDuoCover {
                            focusRegionsToggle
                        }
                    }
                } tools: {
                    detailFilterButton
                    if !isDuoExpanded, !isDuoCover, !emptyFromFilterSelection {
                        focusRegionsToggle
                        if !usesInspectionPill, canEnterCompare {
                            compareToolbarButton
                        }
                    }
                } marks: {
                    Optional<ToolbarItem<Void, EmptyView>>.none
                } bottom: {
                    EmptyView()
                }
                if !emptyFromFilterSelection && !usesDuoViewportOverlay {
                    ToolbarItem(placement: .principal) { detailToolbarTitle }
                        .axisBehavior(.horizontalOnly)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(
                usesUnifiedStageBackground ? .hidden : .automatic,
                for: .navigationBar
            )
            .toolbarVerticalBehavior(.automatic)
            .toolbarVerticalCompressionBehavior(.prefersToolbarItems)
        }
    }

    @ViewBuilder
    @available(iOS 27.1, *)
    private func duoPhotoPane(showsFilmstrip: Bool) -> some View {
        let activeStagePill = chromeIsVisible ? stagePill : nil
        VStack(spacing: 0) {
            previewArea
                .overlay(alignment: .bottom) {
                    // The finishing pill and Focus/Compare capsule float above the dock without
                    // changing its height so showing or hiding them never resizes the photo stage
                    // (#305, #463).
                    if showsFilmstrip {
                        if isDuoExpanded {
                            if chromeIsVisible {
                                DetailPhotoPreviewBandLayout(
                                    leadingInset: 16,
                                    trailingInset: 16,
                                    pillGap: 12
                                ) {
                                    inspectionPill
                                        .layoutValue(
                                            key: DetailBottomBandRoleKey.self, value: .leadingPill)
                                    if hasTransientToast {
                                        activeTransientToastView
                                            .layoutValue(
                                                key: DetailBottomBandRoleKey.self,
                                                value: .centerPill
                                            )
                                            .transition(
                                                CloveMotion.slideTransition(
                                                    edge: .bottom, offset: 12,
                                                    reduceMotion: reduceMotion))
                                    } else if let activeStagePill {
                                        activeStagePill
                                            .onGeometryChange(for: CGFloat.self) {
                                                $0.size.height
                                            } action: {
                                                duoPillHeight = $0
                                            }
                                            .layoutValue(
                                                key: DetailBottomBandRoleKey.self,
                                                value: .centerPill
                                            )
                                            .transition(
                                                .asymmetric(
                                                    insertion: CloveMotion.slideTransition(
                                                        edge: .bottom, offset: 8,
                                                        reduceMotion: reduceMotion),
                                                    removal: .identity))
                                    }
                                }
                                .padding(.bottom, 12)
                                .transition(.opacity)
                            } else if hasTransientToast {
                                activeTransientToastView
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 12)
                                    .transition(
                                        CloveMotion.slideTransition(
                                            edge: .bottom, offset: 12,
                                            reduceMotion: reduceMotion))
                            }
                        } else if hasTransientToast {
                            activeTransientToastView
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                                .transition(
                                    CloveMotion.slideTransition(
                                        edge: .bottom, offset: 12,
                                        reduceMotion: reduceMotion))
                        } else if let activeStagePill {
                            activeStagePill
                                .onGeometryChange(for: CGFloat.self) {
                                    $0.size.height
                                } action: {
                                    duoPillHeight = $0
                                }
                                .padding(.bottom, 12)
                                .transition(
                                    .asymmetric(
                                        insertion: CloveMotion.slideTransition(
                                            edge: .bottom, offset: 8, reduceMotion: reduceMotion),
                                        removal: .identity))
                        }
                    } else if hasTransientToast {
                        activeTransientToastView
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .transition(
                                CloveMotion.slideTransition(
                                    edge: .bottom, offset: 12, reduceMotion: reduceMotion))
                    }
                }
                .animation(
                    hasTransientToast
                        || (showsFilmstrip && activeStagePill != nil)
                        ? CloveMotion.chrome(reduceMotion: reduceMotion) : nil,
                    value: transientToastIdentity
                        ?? (showsFilmstrip ? activeStagePill?.identifier : nil)
                )
                .onChange(
                    of: !hasTransientToast && activeStagePill != nil && showsFilmstrip
                ) { _, isVisible in
                    if !isVisible {
                        duoPillHeight = 0
                    }
                }
            // The failure toast sits above the filmstrip, clear of the capsule row
            // (handoff screens.md §03, components.md Toast).
            if let message = browsing.failureToastMessage {
                Toast(
                    message: AppLocalization.string(message, language: language),
                    identifier: "clove.save.toast"
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(
                    CloveMotion.slideTransition(
                        edge: .bottom, offset: 12, reduceMotion: reduceMotion))
            }
            // The marking toolbar gets its own reserved area inside the shared bottom control
            // band, never over the image and never in the system side toolbar (#200, #227, #469).
            // In Expanded Focus View, it sits beside the filmstrip at 16 pt trailing inset (same
            // anchor as Photo Preview); in Duo Cover Focus View, the background-free two-level
            // filmstrip sits above the centered MarkingToolbar, matching iPhone Detail's bottom
            // stack. In 30/70 Photo Preview, [ Focus | Compare ], Stage Pill, and MarkingToolbar
            // align on one single bottom row inside the 70% photo pane (#463).
            if chromeIsVisible && (showsFilmstrip || isDuoExpanded) {
                if showsFilmstrip {
                    if isDuoExpanded {
                        let markingLeadingGap: CGFloat = 6
                        let markingTrailingInset: CGFloat = 16
                        HStack(alignment: .center, spacing: 0) {
                            DetailFilmstrip(
                                timeline: timeline,
                                expandedGroup: expandedGroup,
                                current: photo.id,
                                thumbnails: browsing.thumbnails,
                                gridPickerDismissToken: gridPickerDismissToken,
                                openPhoto: openFilmstripPhoto,
                                selectGroupPhoto: selectFilmstripGroupPhoto,
                                expandGroup: expandFilmstripGroup,
                                collapseGroup: collapseFilmstripGroup
                            )
                            .frame(maxWidth: .infinity)
                            duoMarkingToolbar
                                .padding(.leading, markingLeadingGap)
                                .padding(.trailing, markingTrailingInset)
                                .layoutPriority(1)
                        }
                        .frame(height: DetailFilmstrip.Metrics.standard.bandHeight)
                    } else {
                        VStack(spacing: 8) {
                            DetailFilmstrip(
                                timeline: timeline,
                                expandedGroup: expandedGroup,
                                current: photo.id,
                                thumbnails: browsing.thumbnails,
                                gridPickerDismissToken: gridPickerDismissToken,
                                openPhoto: openFilmstripPhoto,
                                selectGroupPhoto: selectFilmstripGroupPhoto,
                                expandGroup: expandFilmstripGroup,
                                collapseGroup: collapseFilmstripGroup)
                            duoMarkingToolbar
                                .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 8)
                    }
                } else {
                    DetailPhotoPreviewBandLayout(
                        leadingInset: 16,
                        trailingInset: 16,
                        pillGap: 12
                    ) {
                        inspectionPill
                            .layoutValue(key: DetailBottomBandRoleKey.self, value: .leadingPill)
                        if !hasTransientToast, let activeStagePill {
                            activeStagePill
                                .id(activeStagePill.identity)
                                .layoutValue(key: DetailBottomBandRoleKey.self, value: .centerPill)
                                .transition(.identity)
                                .transaction { transaction in
                                    transaction.animation = nil
                                    transaction.disablesAnimations = true
                                }
                        }
                        duoMarkingToolbar
                            .layoutValue(key: DetailBottomBandRoleKey.self, value: .toolbar)
                    }
                    .frame(height: DetailFilmstrip.Metrics.standard.bandHeight)
                    .frame(maxWidth: .infinity)
                    .reportTapPickerFrame("clove.detail.bottomBand")
                }
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
                label: displayMarks.label.colour,
                isRejected: displayMarks.isRejected,
                enabledRatings: settings.enabledRatings,
                labels: [nil] + settings.availableLabels.map { Optional($0) },
                identifier: "clove.duo.capsule", labelPickerIdentifier: "clove.duo.labels",
                photoID: photo.id,
                onRate: { rate($0) }, onReject: { toggleReject() },
                onLabel: { choose($0.map { ColourLabel(colour: $0) } ?? .clear) },
                onBegin: beginToolbarMarking
            )
            .disabled(!browsing.canMark)
            .accessibilityValue(MarkSummary.text(for: displayMarks, language: language))
            .transition(.opacity)
        }
    }

    private var standardLayout: some View {
        VStack(spacing: 0) {
            if !usesSystemToolbar && (!isOrdinaryPhoneLandscape || chromeIsVisible) {
                BrowsingHeader(
                    title: emptyFromFilterSelection ? "" : photo.fileName,
                    titleIdentifier: "clove.detail.fileName",
                    backTitle: detailBackTitle,
                    usesInlineFlow: isOrdinaryPhoneLandscape,
                    height: isOrdinaryPhoneLandscape ? 44 : 64,
                    background: usesUnifiedStageBackground
                        ? Color.clove.bg.stage : Color.clove.bg.canvas,
                    titleTrailingSymbol: emptyFromFilterSelection ? nil : "info.circle",
                    titleActionIdentifier: emptyFromFilterSelection ? nil : "clove.detail.info",
                    titleActionLabel: emptyFromFilterSelection ? nil : infoButtonAccessibilityLabel,
                    titleAction: emptyFromFilterSelection ? nil : { activeSheet = .information },
                    back: { browsing.back() }
                ) {
                    if !emptyFromFilterSelection {
                        HStack(spacing: 6) {
                            detailZoomReadout
                            InlineFolderPreparationBar(
                                browsing: browsing,
                                identifier: "clove.detail.preparation.progress")
                            SaveStatusIndicator(
                                browsing: browsing, identifierPrefix: "clove.detail.saveState")
                        }
                    }
                } leadingTools: {
                    if !emptyFromFilterSelection {
                        if presentationPolicy.supportsPhotoPreview {
                            photoGridToggle
                        }
                        if !usesInspectionPill {
                            focusRegionsToggle
                        }
                    }
                } tools: {
                    if chromeIsVisible {
                        if !emptyFromFilterSelection {
                            if isOrdinaryPhoneLandscape, let pill = makeStagePill(compact: true) {
                                pill
                                    .fixedSize()
                                    .reportHeaderControlFrame(pill.identifier)
                            }
                            if !usesInspectionPill, canEnterCompare {
                                GlassIconButton(
                                    label: AppLocalization.string("Compare", language: language),
                                    symbol: "rectangle.split.2x1",
                                    size: isWidePadLayout ? .pad : .phone,
                                    identifier: "clove.detail.compare"
                                ) {
                                    dismissGestureGuide()
                                    tapPickerDismissToken += 1
                                    actions.markingSwipeBegan()
                                    browsing.enterCompareFromDetail(timeline: timeline)
                                }
                                .reportHeaderControlFrame("clove.detail.compare")
                            }
                        }
                        detailFilterButton
                            .reportHeaderControlFrame("clove.detail.filter")
                    }
                }
            }
            Group {
                if emptyFromFilterSelection {
                    filteredEmptyStage
                } else if #available(iOS 27.1, *), hasFoldRegion, showsPhotoGrid {
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
    }

    private var filteredEmptyStage: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.clove.text.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(AppLocalization.string("No photos", language: language))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.clove.text.primary)
                Text(AppLocalization.string("No photos match this filter.", language: language))
                    .font(.subheadline)
                    .foregroundStyle(Color.clove.text.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("clove.detail.empty")
            if browsing.hasActiveFilter {
                Button(AppLocalization.string("Clear filters", language: language)) {
                    browsing.clearAllFilters()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.clove.accent)
                .accessibilityIdentifier("clove.detail.empty.clearFilters")
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clove.bg.stage)
    }

    private var standardDetailStage: some View {
        photoStage
            .tapPickerContainer(
                dismissWhen: tapPickerDismissTrigger,
                margin: isWidePadLayout ? 16 : 12,
                gap: isWidePadLayout ? 12 : 10)
    }

    private var splitGridPane: some View {
        SplitFolderGridPane(
            browsing: browsing,
            thumbnails: browsing.thumbnails,
            similarGroupsEnabled: settings.similarGroupsEnabled,
            openPhoto: openFilmstripPhoto,
            selectGroupPhoto: selectFilmstripGroupPhoto,
            openGroup: expandFilmstripGroup,
            collapseGroup: collapseFilmstripGroup)
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
        if case .fullResolution(_, let size) = zoomMode, !focusTracking.isTracking {
            zoomMode = .fullResolution(anchor: snapshot.anchor, size: size)
        }
        pendingRestoredZoom = snapshot
    }

    private var photoStage: some View {
        VStack(spacing: 0) {
            previewArea
                .overlay(alignment: .bottom) {
                    if isOrdinaryPhoneLandscape {
                        landscapeStageFeedbackOverlay
                    } else {
                        standardStageOverlayChrome
                    }
                }
            if isWidePadLayout && chromeIsVisible {
                iPadBottomControlBand
                    .transition(.opacity)
            } else if isOrdinaryPhoneLandscape && showsFilmstrip && chromeIsVisible {
                landscapeBottomReviewRow
            }
        }
    }

    private var iPadBottomToolbar: some View {
        MarkingToolbar(
            rating: swipeFeedback.rating
                ?? (displayMarks.isRejected ? .unrated : displayMarks.rating),
            label: displayMarks.label.colour,
            isRejected: displayMarks.isRejected,
            enabledRatings: settings.enabledRatings,
            labels: [nil] + settings.availableLabels.map { Optional($0) },
            identifier: "clove.detail.capsule",
            labelPickerIdentifier: "clove.detail.labels",
            photoID: photo.id,
            onRate: { rate($0) },
            onReject: { toggleReject() },
            onLabel: { choose($0.map { ColourLabel(colour: $0) } ?? .clear) },
            onBegin: beginToolbarMarking
        )
        .disabled(!browsing.canMark)
        .opacity(browsing.canMark ? 1 : 0.32)
        .accessibilityValue(MarkSummary.text(for: displayMarks, language: language))
    }

    @ViewBuilder private var iPadBottomControlBand: some View {
        if showsFilmstrip {
            HStack(alignment: .bottom, spacing: 24) {
                DetailFilmstrip(
                    timeline: timeline,
                    expandedGroup: expandedGroup,
                    current: photo.id,
                    thumbnails: browsing.thumbnails,
                    gridPickerDismissToken: gridPickerDismissToken,
                    openPhoto: openFilmstripPhoto,
                    selectGroupPhoto: selectFilmstripGroupPhoto,
                    expandGroup: expandFilmstripGroup,
                    collapseGroup: collapseFilmstripGroup
                )
                .frame(maxWidth: .infinity)
                .padding(.bottom, 1)

                iPadBottomToolbar
                    .padding(.trailing, 24)
                    .padding(.bottom, 10)
                    .layoutPriority(1)
            }
            .frame(height: 78, alignment: .bottom)
            .background(Color.clove.bg.stage)
            .reportTapPickerFrame("clove.detail.bottomBand")
        } else {
            DetailPhotoPreviewBandLayout(
                leadingInset: 16,
                trailingInset: 24,
                pillGap: 12
            ) {
                inspectionPill
                    .layoutValue(key: DetailBottomBandRoleKey.self, value: .leadingPill)
                if !hasTransientToast, let stagePill {
                    stagePill
                        .layoutValue(key: DetailBottomBandRoleKey.self, value: .centerPill)
                        .transition(
                            .asymmetric(
                                insertion: CloveMotion.slideTransition(
                                    edge: .bottom, offset: 8, reduceMotion: reduceMotion),
                                removal: .identity))
                }
                iPadBottomToolbar
                    .layoutValue(key: DetailBottomBandRoleKey.self, value: .toolbar)
            }
            .animation(
                !hasTransientToast && stagePill != nil
                    ? CloveMotion.chrome(reduceMotion: reduceMotion) : nil,
                value: !hasTransientToast ? stagePill?.identifier : nil
            )
            .padding(.bottom, 10)
            .frame(height: 84, alignment: .bottom)
            .frame(maxWidth: .infinity)
            .background(Color.clove.bg.stage)
            .reportTapPickerFrame("clove.detail.bottomBand")
        }
    }

    private var landscapeStageFeedbackOverlay: some View {
        VStack(spacing: 8) {
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
                } else if hasTransientToast {
                    activeTransientToastView
                        .padding(.horizontal, 16)
                        .padding(.bottom, (showsFilmstrip && chromeIsVisible) ? 4 : 0)
                        .transition(
                            CloveMotion.slideTransition(
                                edge: .bottom, offset: 12, reduceMotion: reduceMotion))
                }
            }
            .animation(
                CloveMotion.chrome(reduceMotion: reduceMotion),
                value: browsing.failureToastMessage ?? transientToastIdentity
            )
            if showsZoomChip && scale > DetailFitScale.tolerance {
                Text(zoomName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.clove.text.primary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .cloveGlass(in: Capsule())
                    .transition(.opacity)
            }
        }
        .padding(.bottom, (showsFilmstrip && chromeIsVisible) ? 8 : 12)
        .transition(.opacity)
    }

    private var standardStageOverlayChrome: some View {
        let hasWidePadOverlayItems =
            browsing.failureToastMessage != nil
            || hasTransientToast
            || (showsZoomChip && scale > DetailFitScale.tolerance)
            || (showsFilmstrip && chromeIsVisible)
        return VStack(spacing: 8) {
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
                    .padding(
                        .bottom,
                        (isWidePadLayout || (showsFilmstrip && chromeIsVisible)
                            || hasTransientToast)
                            ? 0 : 12
                    )
                    .transition(.opacity)
            }
            if isWidePadLayout {
                if showsFilmstrip && chromeIsVisible {
                    DetailPhotoPreviewBandLayout(
                        leadingInset: 16,
                        trailingInset: 16,
                        pillGap: 12
                    ) {
                        inspectionPill
                            .layoutValue(key: DetailBottomBandRoleKey.self, value: .leadingPill)
                        if hasTransientToast {
                            activeTransientToastView
                                .layoutValue(
                                    key: DetailBottomBandRoleKey.self, value: .centerPill
                                )
                                .transition(
                                    CloveMotion.slideTransition(
                                        edge: .bottom, offset: 12, reduceMotion: reduceMotion))
                        } else if let stagePill {
                            stagePill
                                .layoutValue(
                                    key: DetailBottomBandRoleKey.self, value: .centerPill
                                )
                                .transition(
                                    .asymmetric(
                                        insertion: CloveMotion.slideTransition(
                                            edge: .bottom, offset: 8,
                                            reduceMotion: reduceMotion),
                                        removal: .identity))
                        }
                    }
                    .animation(
                        hasTransientToast || stagePill != nil
                            ? CloveMotion.chrome(reduceMotion: reduceMotion) : nil,
                        value: transientToastIdentity ?? stagePill?.identifier
                    )
                } else {
                    Group {
                        if hasTransientToast {
                            activeTransientToastView
                                .padding(.horizontal, 16)
                                .transition(
                                    CloveMotion.slideTransition(
                                        edge: .bottom, offset: 12, reduceMotion: reduceMotion))
                        }
                    }
                    .animation(
                        CloveMotion.chrome(reduceMotion: reduceMotion),
                        value: transientToastIdentity
                    )
                }
            } else if showsFilmstrip && chromeIsVisible {
                // The pill or transient toast rides the floating chrome band above the strip.
                // The band is an overlay, so its height never moves the stage (#305).
                VStack(spacing: 8) {
                    if usesInspectionPill {
                        DetailPhotoPreviewBandLayout(
                            leadingInset: 16,
                            trailingInset: 16,
                            pillGap: 12
                        ) {
                            inspectionPill
                                .layoutValue(
                                    key: DetailBottomBandRoleKey.self, value: .leadingPill)
                            if hasTransientToast {
                                activeTransientToastView
                                    .layoutValue(
                                        key: DetailBottomBandRoleKey.self, value: .centerPill
                                    )
                                    .transition(
                                        CloveMotion.slideTransition(
                                            edge: .bottom, offset: 12,
                                            reduceMotion: reduceMotion))
                            } else if let stagePill {
                                stagePill
                                    .layoutValue(
                                        key: DetailBottomBandRoleKey.self, value: .centerPill
                                    )
                                    .transition(
                                        .asymmetric(
                                            insertion: CloveMotion.slideTransition(
                                                edge: .bottom, offset: 8,
                                                reduceMotion: reduceMotion),
                                            removal: .identity))
                            }
                        }
                        .animation(
                            hasTransientToast || stagePill != nil
                                ? CloveMotion.chrome(reduceMotion: reduceMotion) : nil,
                            value: transientToastIdentity ?? stagePill?.identifier
                        )
                        .padding(.bottom, 4)
                    } else {
                        Group {
                            if hasTransientToast {
                                activeTransientToastView
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 4)
                                    .transition(
                                        CloveMotion.slideTransition(
                                            edge: .bottom, offset: 12,
                                            reduceMotion: reduceMotion))
                            } else if let stagePill {
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
                            hasTransientToast || stagePill != nil
                                ? CloveMotion.chrome(reduceMotion: reduceMotion) : nil,
                            value: transientToastIdentity ?? stagePill?.identifier
                        )
                    }
                    DetailFilmstrip(
                        timeline: timeline,
                        expandedGroup: expandedGroup,
                        current: photo.id,
                        thumbnails: browsing.thumbnails,
                        gridPickerDismissToken: gridPickerDismissToken,
                        openPhoto: openFilmstripPhoto,
                        selectGroupPhoto: selectFilmstripGroupPhoto,
                        expandGroup: expandFilmstripGroup,
                        collapseGroup: collapseFilmstripGroup)
                    MarkingToolbar(
                        rating: swipeFeedback.rating
                            ?? (displayMarks.isRejected
                                ? .unrated : displayMarks.rating),
                        label: displayMarks.label.colour,
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
                        onBegin: beginToolbarMarking
                    )
                    .disabled(!browsing.canMark)
                    .accessibilityValue(
                        MarkSummary.text(for: displayMarks, language: language)
                    )
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            } else {
                Group {
                    if hasTransientToast {
                        activeTransientToastView
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .transition(
                                CloveMotion.slideTransition(
                                    edge: .bottom, offset: 12, reduceMotion: reduceMotion))
                    } else if !showsFilmstrip && chromeIsVisible, let stagePill {
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
                    hasTransientToast || (!showsFilmstrip && chromeIsVisible && stagePill != nil)
                        ? CloveMotion.chrome(reduceMotion: reduceMotion) : nil,
                    value: transientToastIdentity
                        ?? ((!showsFilmstrip && chromeIsVisible) ? stagePill?.identifier : nil)
                )
            }
        }
        .padding(.bottom, (isWidePadLayout && hasWidePadOverlayItems) ? 12 : 0)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            controlsHeight = $0
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var activeTransientToastView: some View {
        if let visibleAllReviewedToast {
            detailAllReviewedToastView(visibleAllReviewedToast)
        } else if let visibleUndoToast {
            detailUndoToastView(visibleUndoToast)
        } else if visibleCompareRotateToastID != nil {
            compareRotateToastView
        }
    }

    private func detailAllReviewedToastView(_ toast: DetailAllReviewedToast) -> some View {
        Toast(
            message: toast.localizedMessage(language: language),
            leadingSymbol: "checkmark",
            actionTitle: toast.localizedActionTitle(language: language),
            identifier: "clove.detail.allReviewedToast",
            actionIdentifierSuffix: "backToGrid",
            onAction: backToGrid
        )
        .reportTapPickerFrame("clove.detail.allReviewedToast")
    }

    private func detailUndoToastView(_ toast: DetailUndoToast) -> some View {
        Toast(
            message: toast.localizedMessage(language: language),
            actionTitle: AppLocalization.string("Undo", language: language),
            identifier: "clove.detail.undoToast",
            onAction: undo
        )
        .reportTapPickerFrame("clove.detail.undoToast")
    }

    private var compareRotateToastView: some View {
        HStack(spacing: 0) {
            Text(AppLocalization.string("Rotate to landscape to compare", language: language))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.clove.text.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .reportTapPickerFrame("clove.detail.compareRotateToast")
        .cloveGlass(in: Capsule())
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clove.detail.compareRotateToast")
    }

    private var landscapeBottomReviewRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            DetailFilmstrip(
                timeline: timeline,
                expandedGroup: expandedGroup,
                current: photo.id,
                thumbnails: browsing.thumbnails,
                metrics: .compact,
                gridPickerDismissToken: gridPickerDismissToken,
                openPhoto: openFilmstripPhoto,
                selectGroupPhoto: selectFilmstripGroupPhoto,
                expandGroup: expandFilmstripGroup,
                collapseGroup: collapseFilmstripGroup
            )
            .frame(maxWidth: .infinity)

            MarkingToolbar(
                rating: swipeFeedback.rating
                    ?? (displayMarks.isRejected ? .unrated : displayMarks.rating),
                label: displayMarks.label.colour,
                isRejected: displayMarks.isRejected,
                enabledRatings: settings.enabledRatings,
                labels: [nil] + settings.availableLabels.map { Optional($0) },
                identifier: "clove.detail.capsule",
                labelPickerIdentifier: "clove.detail.labels",
                photoID: photo.id,
                onRate: { rate($0) },
                onReject: { toggleReject() },
                onLabel: { choose($0.map { ColourLabel(colour: $0) } ?? .clear) },
                onBegin: beginToolbarMarking
            )
            .disabled(!browsing.canMark)
            .accessibilityValue(MarkSummary.text(for: displayMarks, language: language))
            .padding(.bottom, 2)
            .layoutPriority(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.bottom, 4)
        .background(Color.clove.bg.stage)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail.landscapeBottomRow")
        .reportTapPickerFrame("clove.detail.landscapeBottomRow")
    }

    private var stagePill: PillAction? {
        makeStagePill(compact: false)
    }

    private func makeStagePill(compact: Bool) -> PillAction? {
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
                tone: .destructive,
                compact: compact
            ) {
                dismissGestureGuide()
                actions.finishGroup(plan)
            }
        }
        if let group = currentTimelineGroup {
            return PillAction(
                title: AppLocalization.format(
                    "Expand %lld photos", language: language, Int64(group.visibleMembers.count)),
                identifier: "clove.detail.expandGroup",
                tone: .neutral,
                compact: compact
            ) { expandFilmstripGroup(group.id) }
        }
        return nil
    }

    private var detailSubtitlePrefix: String? {
        Self.headerSubtitlePrefix(
            photoID: photo.id,
            timeline: timeline,
            expandedGroup: expandedGroup,
            language: language)
    }

    static func headerSubtitlePrefix(
        photoID: PhotoIdentity,
        timeline: DetailTimeline,
        expandedGroup: ActiveBrowsingGroup?,
        language: ResolvedAppLanguage
    ) -> String? {
        if let expandedGroup,
            let index = expandedGroup.visibleMembers.firstIndex(where: { $0.id == photoID })
        {
            let pos = AppLocalization.format(
                "%lld / %lld", language: language, Int64(index + 1),
                Int64(expandedGroup.visibleMembers.count))
            return AppLocalization.format("Group · %@", language: language, pos)
        }
        if let index = timeline.slotIndex(containing: photoID) {
            return AppLocalization.format(
                "%lld / %lld", language: language, Int64(index + 1),
                Int64(timeline.slots.count))
        }
        return nil
    }

    private var isFullResolutionUpgradeInFlight: Bool {
        upgradeTask != nil && activeUpgradePhotoID == photo.id
            && activeUpgradeNeed == .fullResolution
    }

    private var isShowingProgressiveZoomState: Bool {
        DetailProgressiveDecodeSupport.showsProgressiveState(
            scale: scale,
            zoomModeIsFullResolution: isAtFullResolution,
            fullResolutionPixels: shown?.fullResolutionPixels,
            viewSize: viewSize,
            screenScale: displayScale,
            isFullResolutionUpgradeInFlight: isFullResolutionUpgradeInFlight,
            phase: progressiveDecode.phase)
    }

    private var effectiveDetailZoomText: String? {
        DetailProgressiveDecodeSupport.zoomLabelText(
            scale: scale,
            scaledZoomText: zoomName,
            fitText: nil,
            zoomModeIsFullResolution: isAtFullResolution,
            isFullResolutionUpgradeInFlight: isFullResolutionUpgradeInFlight,
            phase: progressiveDecode.phase,
            language: language)
    }

    private var detailZoomReadout: some View {
        DetailProgressiveDecodeReadout(
            photoID: photo.id,
            prefixText: detailSubtitlePrefix,
            zoomText: effectiveDetailZoomText,
            showsProgressiveState: isShowingProgressiveZoomState,
            phase: progressiveDecode.phase,
            language: language,
            tone: .header,
            lineLimit: 1,
            identifier: "clove.detail.zoom",
            reportHeaderFrame: true
        )
    }

    private var detailSubtitle: String {
        var parts: [String] = []
        if let detailSubtitlePrefix {
            parts.append(detailSubtitlePrefix)
        }
        if scale > DetailFitScale.tolerance {
            parts.append(zoomName)
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
            onViewportChanged: { viewportChanged($0) },
            onChromeToggle: { toggleChrome() },
            onStep: {
                dismissGestureGuide()
                actions.step($0)
            },
            onDoubleTap: { doubleTap(at: $0) },
            onMarkingSwipe: { applyMarkingSwipe($0, touchCount: 1) },
            onTwoFingerMarkingSwipe: { applyMarkingSwipe($0, touchCount: 2) },
            onSwipeBegin: { beginMarkingGesture() },
            allowsMarking: browsing.canMark,
            hasPrevious: navigationAvailability.previous,
            hasNext: navigationAvailability.next,
            probe: probe,
            focusRegions: (shown == nil || shownPhoto != photo.id)
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
        .opacity(browsing.folderLocationLoss == nil ? 1 : 0.35)
        .animation(
            CloveMotion.chrome(reduceMotion: reduceMotion),
            value: browsing.folderLocationLoss == nil
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
        .overlay { gestureGuideOverlay }
        .overlay(alignment: .top) {
            FolderSaveBanner(
                browsing: browsing,
                identifierPrefix: "clove.detail.saveStatus.failure"
            )
            .padding(.top, usesDuoViewportOverlay ? 56 : 0)
        }
        .animation(CloveMotion.chrome(reduceMotion: reduceMotion), value: showsGestureGuide)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clove.bg.stage)
    }

    private var showsGestureGuide: Bool {
        settingsStore?.hasSeenGestureGuide == false
    }

    @ViewBuilder private var gestureGuideOverlay: some View {
        if showsGestureGuide {
            ZStack {
                Color.black.opacity(0.28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissGestureGuide()
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { _ in
                                dismissGestureGuide()
                            }
                    )
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(
                        AppLocalization.string("Dismiss gesture guide", language: language))

                DetailGestureGuideCard {
                    dismissGestureGuide()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, max(12, swipeFeedbackReservation))
            }
            .transition(.opacity)
        }
    }

    private func dismissGestureGuide() {
        guard let settingsStore, !settingsStore.hasSeenGestureGuide else { return }
        withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
            settingsStore.markGestureGuideSeen()
        }
    }

    private func openFilmstripPhoto(_ photo: PhotoIdentity) {
        dismissGestureGuide()
        actions.openPhoto(photo)
    }

    private func selectFilmstripGroupPhoto(_ photo: PhotoIdentity) {
        dismissGestureGuide()
        actions.selectGroupPhoto(photo)
    }

    private func expandFilmstripGroup(_ groupID: GroupID) {
        dismissGestureGuide()
        actions.expandGroup(groupID)
    }

    private func collapseFilmstripGroup() {
        dismissGestureGuide()
        actions.collapseGroup()
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
                    .reportHeaderControlFrame("clove.detail.unavailable")
            case .deferred:
                Text(AppLocalization.string("The preview did not load.", language: language))
                    .foregroundStyle(.secondary)
                    .padding()
                    .accessibilityIdentifier("clove.detail.unavailable")
                    .reportHeaderControlFrame("clove.detail.unavailable")
            case .shown:
                EmptyView()
            }
        }
    }

    /// Compact passive face/AF result indicators and any preview-only limitation note stacked cleanly
    /// in the viewport's upper-leading corner inside its safe area. On expanded Duo Landscape and
    /// Duo Cover, the upper-leading viewport corner also pins the passive photo identity badge
    /// beside the floating save/access indicator so the photo stage reclaims the former top header
    /// height.
    @ViewBuilder private var topLeadingStageOverlays: some View {
        let isShowingCurrentPhoto = shown != nil && shownPhoto == photo.id
        let indicators = focusRegionState.resultIndicators(
            visible: isShowingCurrentPhoto && chromeIsVisible && browsing.showsFocusRegions)
        let showsLimitation = limitation != nil && isShowingCurrentPhoto
        if usesDuoViewportOverlay {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    if chromeIsVisible {
                        DetailPhotoCornerOverlay(
                            fileName: photo.fileName,
                            positionText: cornerPositionText,
                            isGroupFocus: isCornerGroupFocus,
                            zoomText: effectiveDetailZoomText,
                            language: language,
                            browsing: browsing,
                            photoID: photo.id,
                            showsProgressiveState: isShowingProgressiveZoomState,
                            progressiveDecodePhase: progressiveDecode.phase,
                            onInfoTap: { activeSheet = .information }
                        )
                        .layoutPriority(0)
                        .transition(.opacity)
                    }
                    SaveStatusIndicator(
                        browsing: browsing,
                        identifierPrefix: "clove.detail.saveState",
                        usesFloatingBackdrop: true
                    )
                    .layoutPriority(2)
                }
                if !indicators.isEmpty {
                    DetailFocusResultIndicatorsView(
                        indicators: indicators,
                        usesPhotoBacking: DetailFocusResultIndicators.coversPhotoPixels(
                            indicators: indicators,
                            scale: scale,
                            imagePixels: shown.map { pixelSize($0) },
                            viewSize: viewSize,
                            origin: CGPoint(x: 16, y: 62)),
                        language: language)
                }
                limitationNote
            }
            .padding(.top, 12)
            .padding(.leading, 16)
            .padding(.trailing, 46)
        } else if !indicators.isEmpty || showsLimitation {
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

    private var isCornerGroupFocus: Bool {
        Self.cornerPositionDescriptor(
            photo: photo, timeline: timeline, expandedGroup: expandedGroup, language: language
        ).isGroupFocus
    }

    private var cornerPositionText: String? {
        Self.cornerPositionDescriptor(
            photo: photo, timeline: timeline, expandedGroup: expandedGroup, language: language
        ).positionText
    }

    static func cornerPositionDescriptor(
        photo: GridPhoto,
        timeline: DetailTimeline,
        expandedGroup: ActiveBrowsingGroup?,
        language: ResolvedAppLanguage
    ) -> (positionText: String?, isGroupFocus: Bool) {
        if let expandedGroup,
            let index = expandedGroup.visibleMembers.firstIndex(where: { $0.id == photo.id })
        {
            return (
                AppLocalization.format(
                    "%lld / %lld", language: language, Int64(index + 1),
                    Int64(expandedGroup.visibleMembers.count)),
                true
            )
        }
        if let index = timeline.slotIndex(containing: photo.id) {
            return (
                AppLocalization.format(
                    "%lld / %lld", language: language, Int64(index + 1),
                    Int64(timeline.slots.count)),
                false
            )
        }
        return (nil, false)
    }

    /// The "preview only" note a failed render or a capped source must show (PRD P0-04).
    @ViewBuilder private var limitationNote: some View {
        if let limitation, shown != nil, shownPhoto == photo.id {
            Text(limitationText(limitation))
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .allowsHitTesting(false)
                .accessibilityIdentifier("clove.detail.limitation")
                .reportHeaderControlFrame("clove.detail.limitation")
        }
    }

    // MARK: - Focus regions

    private func loadFocusRegions(for photo: GridPhoto) async {
        let analysisID = UUID()
        focusAnalysisID = analysisID
        guard browsing.showsFocusRegions else {
            focusRegionState = DetailFocusRegionState()
            applyAsyncRecenterIfNeeded(for: photo.id, isFinalResult: true)
            return
        }
        focusRegionState.begin(for: photo.id)
        guard let source = images as? DetailRegionSharpnessSource else {
            focusRegionState.finish(nil, for: photo.id)
            applyAsyncRecenterIfNeeded(for: photo.id, isFinalResult: true)
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
                guard focusRegionState.photo == photo.id, focusRegionState.isAnalyzing else {
                    return
                }
                focusRegionState.receiveAutofocus(result, for: photo.id)
                applyAsyncRecenterIfNeeded(for: photo.id, isFinalResult: false)
            }
        }
        guard !Task.isCancelled, focusAnalysisID == analysisID else { return }
        focusRegionState.finish(analysis, for: photo.id)
        applyAsyncRecenterIfNeeded(for: photo.id, isFinalResult: true)
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
                if snapshot == nil {
                    zoomMode = .fit
                    focusTracking.reset()
                } else {
                    let referenceAnchor: DetailZoomAnchor? =
                        if case .fullResolution(let chosen, _) = zoomMode {
                            chosen
                        } else {
                            snapshot?.anchor
                        }
                    focusTracking.preparePhotoTransition(
                        to: photo.id,
                        keepsPosition: true,
                        hasZoomedState: isAtFullResolution,
                        referenceAnchor: referenceAnchor)
                }
            } else {
                let referenceAnchor: DetailZoomAnchor? =
                    if case .fullResolution(let chosen, _) = zoomMode {
                        chosen
                    } else {
                        keptZoom?.anchor
                    }
                focusTracking.preparePhotoTransition(
                    to: photo.id,
                    keepsPosition: true,
                    hasZoomedState: keptScale != nil && isAtFullResolution,
                    referenceAnchor: referenceAnchor)
            }
        } else {
            keptZoom = nil
            keptScale = nil
            keptNativeScale = nil
            zoomMode = .fit
            focusTracking.reset()
            setZoom(.fit)
        }
        cancelUpgradeTask()
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
                guard await showPlaceholderWhileLoading(for: photo.id) else { return }
                window = candidateWindow
                currentWindow = window
                previousPosition = window.current.position
                await images.prepare(window)
                guard !Task.isCancelled else { return }
            }
        } else {
            guard await showPlaceholderWhileLoading(for: photo.id) else { return }
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

    private func showPlaceholderWhileLoading(for photoID: PhotoIdentity) async -> Bool {
        let retainedPixels = shown?.image ?? placeholder
        shown = nil
        shownPhoto = nil
        if case .image(let cachedThumbnail) = browsing.thumbnails.cachedThumbnail(for: photoID) {
            phase = .placeholder(cachedThumbnail)
            return true
        }
        phase = .placeholder(retainedPixels)
        let thumbnail = await images.placeholder(
            for: photoID, gridThumbnails: browsing.thumbnails)
        guard !Task.isCancelled else { return false }
        if let thumbnail {
            phase = .placeholder(thumbnail)
        }
        return true
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
        shownPhoto = photo.id
        limitation = image.limitation
        phase = .shown
        if image.limitation != nil {
            previewOnly = true
        }
        if image.limitation == nil, image.quality == .nativeRAW || image.isBestAvailable {
            progressiveDecode.completeIfTracking(photoID: photo.id)
        } else if image.limitation != nil, isShowingProgressiveZoomState {
            DetailProgressiveDecodeSupport.syncAtFullResolution(
                controller: progressiveDecode,
                photoID: photo.id,
                fileName: photo.fileName,
                photoSet: browsing.scannedSet(for: photo.id)?.photoSet,
                displayMode: currentWindow?.mode ?? displayMode,
                shown: image,
                isPreviewOnly: true,
                isLocationLost: browsing.folderLocationLoss != nil,
                startingUpgrade: false)
        }
        if let keptScale {
            let previousNativeScale = keptNativeScale
            let fallbackAnchor = keptZoom?.anchor ?? .centre
            self.keptScale = nil
            self.keptNativeScale = nil
            self.keptZoom = nil
            let opening = openingScale(
                keptScale, previousNativeScale: previousNativeScale, for: image)
            let openingAnchor: DetailZoomAnchor
            switch focusTracking.resolveOpening(
                for: photo.id,
                fallbackAnchor: fallbackAnchor,
                focusRegions: focusRegionState,
                showsFocusRegions: browsing.showsFocusRegions)
            {
            case .focusRegion(let targetRegion):
                openingAnchor = DetailZoomAnchor(
                    x: targetRegion.centre.x, y: targetRegion.centre.y)
                inspectedFocusRegionID = targetRegion.id
            case .keepAnchor(let anchor):
                openingAnchor = anchor
                inspectedFocusRegionID = nil
            }
            if case .fullResolution = zoomMode {
                // The opening scale was converted to this photo's 100%, so a later render corrects
                // against this photo's size rather than the previous one's.
                zoomMode = .fullResolution(
                    anchor: openingAnchor, size: image.fullResolutionPixels)
            }
            setZoom(.scale(opening, anchor: openingAnchor.unitPoint))
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
                    let anchor =
                        focusTracking.isTracking
                        ? chosen : (probe.container?.zoomSnapshot?.anchor ?? chosen)
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
        if value > DetailFitScale.tolerance {
            dismissGestureGuide()
        }
        scale = value
        if abs(value - commandedScale) > 0.01 {
            zoomMode = .manual
            focusTracking.reset()
        }
        if value <= DetailFitScale.tolerance {
            inspectedFocusRegionID = nil
            focusTracking.reset()
            if !isAtFullResolution {
                cancelUpgradeTask()
            }
            return
        }
        if !DetailProgressiveDecodeSupport.shouldRetainProgressiveDecodeAboveFit(
            scale: value,
            zoomModeIsFullResolution: isAtFullResolution,
            fullResolutionPixels: shown?.fullResolutionPixels,
            viewSize: viewSize,
            screenScale: displayScale,
            isFullResolutionUpgradeInFlight: isFullResolutionUpgradeInFlight)
            && progressiveDecode.phase != .idle
        {
            progressiveDecode.reset()
        }
        if previewOnly || browsing.folderLocationLoss != nil {
            if isScaleAtFullResolution {
                DetailProgressiveDecodeSupport.syncAtFullResolution(
                    controller: progressiveDecode,
                    photoID: photo.id,
                    fileName: photo.fileName,
                    photoSet: browsing.scannedSet(for: photo.id)?.photoSet,
                    displayMode: currentWindow?.mode ?? displayMode,
                    shown: shown,
                    isPreviewOnly: previewOnly,
                    isLocationLost: browsing.folderLocationLoss != nil,
                    startingUpgrade: false)
            }
            return
        }
        guard let shown, shownPhoto == photo.id else { return }
        guard requestPixels(scale: scale) > max(shown.width, shown.height) else { return }
        let need: DetailPixelRequest.Need = isScaleAtFullResolution ? .fullResolution : .morePixels
        if upgradeTask != nil, activeUpgradePhotoID == photo.id,
            activeUpgradeNeed == .fullResolution, need == .fullResolution
        {
            return
        }
        startUpgradeTask(need: need, debounce: .milliseconds(220))
    }

    private func viewportChanged(_ snapshot: DetailZoomSnapshot?) {
        guard focusTracking.isTracking || focusTracking.pendingRecenter != nil else { return }
        guard let snapshot, snapshot.scale > DetailFitScale.tolerance else { return }
        guard case .fullResolution(let targetAnchor, let size) = zoomMode else { return }
        let imagePixels = shown.map { pixelSize($0) }
        guard
            DetailFocusTrackingState.didManuallyPan(
                snapshot: snapshot,
                fromTargetAnchor: targetAnchor,
                imagePixels: imagePixels,
                viewSize: viewSize)
        else { return }
        focusTracking.reset()
        inspectedFocusRegionID = nil
        probe.container?.cancelPendingScaleZoom()
        zoomMode = .fullResolution(anchor: snapshot.anchor, size: size)
    }

    private func applyAsyncRecenterIfNeeded(for photoID: PhotoIdentity, isFinalResult: Bool) {
        guard photo.id == photoID else { return }
        let result = focusTracking.resolveAsyncRecenter(
            for: photoID,
            isFinalResult: isFinalResult,
            focusRegions: focusRegionState,
            showsFocusRegions: browsing.showsFocusRegions,
            isShowingPhoto: shown != nil && shownPhoto == photoID,
            isZoomedFullResolution: isAtFullResolution && scale > DetailFitScale.tolerance)
        switch result {
        case .recenter(let targetRegion):
            recenterZoomToFocusRegion(targetRegion)
        case .clearInspectionKeepAnchor:
            inspectedFocusRegionID = nil
        case .ignore:
            break
        }
    }

    private func recenterZoomToFocusRegion(_ region: DetailFocusRegion) {
        guard let shown else { return }
        let chosen = DetailZoomAnchor(x: region.centre.x, y: region.centre.y)
        zoomMode = .fullResolution(anchor: chosen, size: shown.fullResolutionPixels)
        inspectedFocusRegionID = region.id
        let targetScale: CGFloat
        if let pixels = shown.fullResolutionPixels,
            let resolved = DetailZoom.fullResolutionTarget(
                nativePixels: pixels, shownPixels: pixelSize(shown),
                viewSize: viewSize, screenScale: displayScale, previewIsAll: previewOnly)
        {
            targetScale = resolved
        } else {
            targetScale = scale
        }
        setZoom(.scale(targetScale, anchor: region.centre))
    }

    /// Whether the current zoom is the explicit 100%, which keeps asking for native pixels.
    private var isAtFullResolution: Bool {
        if case .fullResolution = zoomMode { return true }
        return false
    }

    /// Whether either the explicit zoom mode or a pinch scale is at or above native 100%.
    private var isScaleAtFullResolution: Bool {
        DetailProgressiveDecodeSupport.isAtOrAboveFullResolution(
            scale: scale,
            zoomModeIsFullResolution: isAtFullResolution,
            fullResolutionPixels: shown?.fullResolutionPixels,
            viewSize: viewSize,
            screenScale: displayScale)
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
    private func doubleTap(at tap: DetailDoubleTapLocation) {
        dismissGestureGuide()
        guard settings.doubleTap != .off else { return }
        guard scale <= DetailFitScale.tolerance && !isAtFullResolution else {
            inspectedFocusRegionID = nil
            focusTracking.reset()
            cancelUpgradeTask()
            zoomMode = .fit
            setZoom(.fit)
            return
        }
        guard shown != nil, shownPhoto == photo.id else { return }
        if settings.doubleTap == .zoomToFocus,
            let targetRegion = focusRegionState.preferredDoubleTapRegion(
                at: tap.proximityAnchor,
                visible: browsing.showsFocusRegions,
                inspectedRegionID: inspectedFocusRegionID)
        {
            inspectedFocusRegionID = targetRegion.id
            focusTracking.beginTracking()
            inspectFullResolution(at: targetRegion.centre)
        } else {
            inspectedFocusRegionID = nil
            focusTracking.reset()
            inspectFullResolution(at: tap.zoomAnchor)
        }
    }

    /// A valid analysis region always enters the existing 100% inspection, independently of the
    /// double-tap setting. It neither resolves a marking input nor calls a navigation action.
    private func focusRegionTapped(_ region: DetailFocusRegion) {
        dismissGestureGuide()
        guard region.isActionable, shown != nil, shownPhoto == photo.id else { return }
        inspectedFocusRegionID = region.id
        focusTracking.beginTracking()
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
        if previewOnly || browsing.folderLocationLoss != nil {
            cancelUpgradeTask()
            DetailProgressiveDecodeSupport.syncAtFullResolution(
                controller: progressiveDecode,
                photoID: photo.id,
                fileName: photo.fileName,
                photoSet: browsing.scannedSet(for: photo.id)?.photoSet,
                displayMode: currentWindow?.mode ?? displayMode,
                shown: shown,
                isPreviewOnly: previewOnly,
                isLocationLost: browsing.folderLocationLoss != nil,
                startingUpgrade: false)
            return
        }
        // Keep an already-running native decode intact when jumping between focus points on the same photo.
        if upgradeTask != nil, activeUpgradePhotoID == photo.id,
            activeUpgradeNeed == .fullResolution
        {
            return
        }
        startUpgradeTask(need: .fullResolution)
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
        let anchor =
            focusTracking.isTracking ? chosen : (probe.container?.zoomSnapshot?.anchor ?? chosen)
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
        guard isAtFullResolution || scale > DetailFitScale.tolerance else {
            cancelUpgradeTask()
            return
        }
        if !DetailProgressiveDecodeSupport.shouldRetainProgressiveDecodeAboveFit(
            scale: scale,
            zoomModeIsFullResolution: isAtFullResolution,
            fullResolutionPixels: shown?.fullResolutionPixels,
            viewSize: viewSize,
            screenScale: displayScale,
            isFullResolutionUpgradeInFlight: isFullResolutionUpgradeInFlight)
            && progressiveDecode.phase != .idle
        {
            progressiveDecode.reset()
        }
        if (previewOnly || browsing.folderLocationLoss != nil), isScaleAtFullResolution {
            DetailProgressiveDecodeSupport.syncAtFullResolution(
                controller: progressiveDecode,
                photoID: photo.id,
                fileName: photo.fileName,
                photoSet: browsing.scannedSet(for: photo.id)?.photoSet,
                displayMode: currentWindow?.mode ?? displayMode,
                shown: shown,
                isPreviewOnly: previewOnly,
                isLocationLost: browsing.folderLocationLoss != nil,
                startingUpgrade: false)
            return
        }
        guard !previewOnly, browsing.folderLocationLoss == nil, let shown, shownPhoto == photo.id
        else { return }
        let needsUpgrade =
            (isAtFullResolution && shown.fullResolutionPixels == nil)
            ? !shown.isBestAvailable
            : (requestPixels(scale: scale) > max(shown.width, shown.height))
        guard needsUpgrade else { return }
        let need: DetailPixelRequest.Need = isScaleAtFullResolution ? .fullResolution : .morePixels
        if upgradeTask != nil, activeUpgradePhotoID == photo.id,
            activeUpgradeNeed == .fullResolution,
            need == .fullResolution
        {
            return
        }
        startUpgradeTask(need: need)
    }

    private func startUpgradeTask(need: DetailPixelRequest.Need, debounce: Duration? = nil) {
        let targetPhotoID = photo.id
        let taskToken = UUID()
        upgradeTask?.cancel()
        activeUpgradePhotoID = targetPhotoID
        activeUpgradeNeed = need
        activeUpgradeToken = taskToken
        upgradeTask = Task {
            defer {
                if activeUpgradeToken == taskToken {
                    upgradeTask = nil
                    activeUpgradePhotoID = nil
                    activeUpgradeNeed = nil
                    activeUpgradeToken = nil
                }
            }
            if let debounce {
                try? await Task.sleep(for: debounce)
                guard !Task.isCancelled else { return }
            }
            await upgrade(for: targetPhotoID, need: need)
        }
    }

    private func cancelUpgradeTask() {
        upgradeTask?.cancel()
        upgradeTask = nil
        activeUpgradePhotoID = nil
        activeUpgradeNeed = nil
        activeUpgradeToken = nil
        progressiveDecode.reset()
    }

    /// Asks I2 for the pixels a pinch or a double tap needs, keeping the preview meanwhile.
    ///
    /// A failed RAW render returns the preview with a limitation, which turns ``previewOnly`` on
    /// so the same failing render is never requested again for this photo (PRD P0-04).
    private func upgrade(for targetPhotoID: PhotoIdentity, need: DetailPixelRequest.Need) async {
        guard !previewOnly, photo.id == targetPhotoID else { return }
        guard let window = currentWindow else { return }
        let scannedSet = browsing.scannedSet(for: targetPhotoID)
        let decodeToken: RawProgressiveDecodeToken? =
            need == .fullResolution
            ? DetailProgressiveDecodeSupport.syncAtFullResolution(
                controller: progressiveDecode,
                photoID: targetPhotoID,
                fileName: photo.fileName,
                photoSet: scannedSet?.photoSet,
                displayMode: window.mode,
                shown: shown,
                isPreviewOnly: previewOnly,
                isLocationLost: browsing.folderLocationLoss != nil,
                startingUpgrade: true)
            : nil

        let request = DetailPixelRequest(
            displayPixels: requestPixels(scale: scale), need: need,
            mode: window.mode, screenPixels: window.screenPixels)
        let outcome = await images.image(for: targetPhotoID, request: request)
        guard !Task.isCancelled else {
            if let decodeToken { progressiveDecode.cancel(token: decodeToken) }
            return
        }
        guard photo.id == targetPhotoID else { return }
        if case .image(let image) = outcome {
            show(image)
        }
        if need == .fullResolution {
            DetailProgressiveDecodeSupport.settle(
                controller: progressiveDecode,
                token: decodeToken,
                outcome: outcome,
                photoID: targetPhotoID,
                fileName: photo.fileName,
                photoSet: scannedSet?.photoSet,
                isLocationLost: browsing.folderLocationLoss != nil)
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
        dismissGestureGuide()
        actions.photoTapped()
        hidesChrome.toggle()
    }

    private func backToGrid() {
        dismissGestureGuide()
        actions.markingSwipeBegan()
        if let customBackToGrid = actions.backToGrid {
            customBackToGrid()
        } else {
            browsing.back()
        }
    }

    // MARK: - Marking

    /// One hardware key from the PRD keyboard table, resolved by C13's key rule (PRD P0-06).
    ///
    /// The key reads the marks the capsule acts on, so a disabled level or a key that
    /// would change nothing is the same no-input the rules already report for them.
    func markKey(_ key: MarkingKey) {
        tapPickerDismissToken += 1
        apply(
            rules.result(
                for: key, marks: browsing.shownMarks(for: photo.id),
                allowsMarking: browsing.canMark))
    }

    private func beginToolbarMarking() {
        dismissGestureGuide()
        actions.markingSwipeBegan()
    }

    private func beginMarkingGesture() {
        dismissGestureGuide()
        tapPickerDismissToken += 1
        actions.markingSwipeBegan()
    }

    /// Undoes the last mark from the Detail Undo toast or `⌘Z` (PRD Undo row).
    private func undo() {
        guard browsing.canUndoMark else { return }
        beginMarkingGesture()
        if let customUndo = actions.undo {
            customUndo()
        } else {
            browsing.undoLastMark()
        }
    }

    /// One rating tap, resolved by C13's rating-bar rule (PRD Marking rules).
    func rate(_ rating: Rating) {
        let marks = browsing.shownMarks(for: photo.id)
        apply(
            rules.result(
                forRating: rating, marks: marks, allowsMarking: browsing.canMark))
    }

    /// One label choice, resolved by C13's label rule (PRD Marking rules).
    func choose(_ label: ColourLabel) {
        apply(
            rules.result(
                forLabel: label, marks: browsing.shownMarks(for: photo.id),
                allowsMarking: browsing.canMark))
    }

    /// Toggles Reject, which is the rating −1 (PRD Marking rules).
    func toggleReject() {
        // The HUD's Reject is a toggle, while the `↓` key only turns Reject on. C13 owns both
        // directions and the mark kind auto-advance reads (PRD Marking rules, PRD Auto-advance).
        apply(
            rules.result(
                forRejectToggle: browsing.shownMarks(for: photo.id),
                allowsMarking: browsing.canMark))
    }

    /// Resolves one finished marking swipe through C13's gesture rules (PRD P0-06).
    func applyMarkingSwipe(_ rating: Rating, touchCount: Int = 1) {
        guard browsing.canMark else { return }
        let isZoomed = (probe.container?.isZoomed ?? false) || scale > DetailFitScale.tolerance
        apply(
            rules.result(
                forSwipeRating: rating, marks: browsing.shownMarks(for: photo.id),
                isZoomed: isZoomed, touchCount: touchCount, allowsMarking: browsing.canMark))
    }

    /// Applies one resolved marking input and asks the screen to start the advance it asks for
    /// (PRD Auto-advance).
    ///
    /// The gesture, the HUD bar, a label, the Reject toggle and the keyboard all come through
    /// here, so the mark path is one function. A result that changes nothing writes nothing and
    /// advances nothing (PRD P0-06 acceptance).
    private func apply(_ result: MarkingResult) {
        Self.apply(
            result,
            currentTimelineGroup: currentTimelineGroup,
            expandedGroup: expandedGroup,
            photo: photo,
            canMark: browsing.canMark,
            actions: actions,
            undo: undo,
            dismissGestureGuide: dismissGestureGuide)
    }

    /// Dispatches one resolved marking result using explicit dependencies so callers and tests can
    /// exercise the exact expand-before-plan-and-apply ordering outside a mounted view hierarchy.
    @MainActor
    static func apply(
        _ result: MarkingResult,
        currentTimelineGroup: ActiveBrowsingGroup?,
        expandedGroup: ActiveBrowsingGroup?,
        photo: GridPhoto,
        canMark: Bool,
        actions: DetailMarkingActions,
        undo: () -> Void,
        dismissGestureGuide: () -> Void = {}
    ) {
        dismissGestureGuide()
        switch result {
        case .mark(let change, let kind):
            guard canMark else { return }
            if let group = currentTimelineGroup {
                actions.expandGroup(group.id)
            }
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

    private var detailFilterSelectionKey: DetailFilterSelectionKey {
        DetailFilterSelectionKey(
            filter: browsing.state.filter,
            labelFilter: browsing.labelFilter,
            metadataFilter: browsing.metadataFilter)
    }

    private var canPresentMetadataFilters: Bool {
        Self.allowsMetadataFilters(isComparing: browsing.compareSession != nil)
    }

    static func allowsMetadataFilters(isComparing: Bool) -> Bool {
        !isComparing
    }

    private func handleDetailFilterSelectionChange() {
        guard browsing.compareSession == nil else { return }
        if browsing.photos.isEmpty {
            if browsing.hasActiveFilter && !browsing.allPlacedPhotos.isEmpty {
                actions.markingSwipeBegan()
                emptyFromFilterSelection = true
            } else {
                emptyFromFilterSelection = false
            }
            return
        }
        emptyFromFilterSelection = false
        guard !browsing.photos.contains(where: { $0.id == photo.id }) else { return }
        let refreshedTimeline = DetailTimeline(
            photos: browsing.photos,
            groups: browsing.groups,
            groupsEnabled: settings.similarGroupsEnabled && !browsing.isScanning)
        if let target = refreshedTimeline.slots.first?.stagePhoto.id ?? browsing.photos.first?.id {
            actions.openPhoto(target)
        }
    }

    private var tapPickerDismissTrigger: DetailTapPickerDismissTrigger {
        DetailTapPickerDismissTrigger(
            photoID: photo.id,
            canMark: browsing.canMark,
            chromeIsVisible: chromeIsVisible,
            showsInformation: showsInformation,
            showsPhotoGrid: showsPhotoGrid,
            expandedGroupID: expandedGroup?.id,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover,
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            isLandscapeContainer: isLandscapeContainer,
            dismissToken: tapPickerDismissToken)
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
    let showsPhotoGrid: Bool
    let expandedGroupID: GroupID?
    let isDuoExpanded: Bool
    let isDuoCover: Bool
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?
    let isLandscapeContainer: Bool
    let dismissToken: Int
}

private struct DetailFilterSelectionKey: Equatable {
    let filter: PhotoFilter
    let labelFilter: LabelColour?
    let metadataFilter: PhotoMetadataFilter
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
                    .reportHeaderControlFrame("clove.detail.rejectGlyph")
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

struct DetailHeaderFileNameParts: Equatable, Sendable {
    let stem: String
    let extensionSuffix: String

    init(_ fileName: String) {
        if let dotIndex = fileName.lastIndex(of: "."),
            dotIndex > fileName.startIndex
        {
            let suffix = String(fileName[dotIndex...])
            let extensionLength = suffix.count - 1
            if extensionLength >= 1 && extensionLength <= 8 {
                self.stem = String(fileName[..<dotIndex])
                self.extensionSuffix = suffix
                return
            }
        }
        self.stem = fileName
        self.extensionSuffix = ""
    }
}

/// Tappable two-line photo identity badge pinned to the upper-leading corner of the photo viewport
/// on expanded Duo Landscape and Duo Cover.
struct DetailPhotoCornerOverlay: View {
    let fileName: String
    let positionText: String?
    let isGroupFocus: Bool
    let zoomText: String?
    let language: ResolvedAppLanguage
    var browsing: BrowsingModel? = nil
    var photoID: PhotoIdentity? = nil
    var showsProgressiveState: Bool = false
    var progressiveDecodePhase: RawProgressiveDecodePhase = .idle
    var onInfoTap: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var fileNameSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var metadataSize: CGFloat = 11

    static func metadataStrings(
        positionText: String?,
        isGroupFocus: Bool,
        zoomText: String?,
        showsProgressiveState: Bool = false,
        progressiveDecodePhase: RawProgressiveDecodePhase = .idle,
        language: ResolvedAppLanguage
    ) -> (visible: String?, accessible: String) {
        let accessiblePosition = positionText.map { pos in
            isGroupFocus
                ? AppLocalization.format("Group · %@", language: language, pos)
                : pos
        }
        let presentation = DetailZoomReadoutPresentation(
            prefixText: positionText,
            accessiblePrefixText: accessiblePosition,
            zoomText: zoomText,
            showsProgressiveState: showsProgressiveState,
            phase: progressiveDecodePhase,
            language: language
        )
        return (presentation.combinedVisibleText, presentation.accessibilityLabel)
    }

    private var showsInlinePreparation: Bool {
        guard let browsing else { return false }
        return FolderPreparationAccessibility.isActive(
            for: browsing.preparationStatus,
            isGroupingInProgress: browsing.isGroupingInProgress)
    }

    var body: some View {
        let parts = DetailHeaderFileNameParts(fileName)
        let effectivePhase: RawProgressiveDecodePhase =
            (zoomText != nil && showsProgressiveState) ? progressiveDecodePhase : .idle
        let hasMetadataReadout = positionText != nil || zoomText != nil
        let resolvedPhotoID =
            photoID
            ?? PhotoIdentity(
                folderID: FolderIdentity(rawValue: "corner-overlay"),
                relativeFolderPath: "",
                stem: fileName
            )
        let accessiblePosition = positionText.map { pos in
            isGroupFocus
                ? AppLocalization.format("Group · %@", language: language, pos)
                : pos
        }

        let scrim = VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                HStack(spacing: 0) {
                    Text(parts.stem)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(0)
                    if !parts.extensionSuffix.isEmpty {
                        Text(parts.extensionSuffix)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                            .reportHeaderControlFrame("clove.detail.fileName.extension")
                    }
                }
                .font(.system(size: fileNameSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel(fileName)
                .accessibilityIdentifier("clove.detail.fileName")
                .reportHeaderControlFrame("clove.detail.fileName")

                Image(systemName: "info.circle")
                    .font(.system(size: max(fileNameSize - 1, 10), weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .layoutPriority(1)
                    .accessibilityHidden(true)
            }

            if hasMetadataReadout || showsInlinePreparation {
                HStack(alignment: .center, spacing: 6) {
                    if hasMetadataReadout {
                        DetailProgressiveDecodeReadout(
                            photoID: resolvedPhotoID,
                            prefixText: positionText,
                            accessiblePrefixText: accessiblePosition,
                            zoomText: zoomText,
                            showsProgressiveState: showsProgressiveState,
                            phase: effectivePhase,
                            language: language,
                            tone: .darkScrim,
                            font: .system(size: metadataSize),
                            leadingIcon: isGroupFocus ? "square.stack" : nil,
                            iconSize: metadataSize,
                            lineLimit: dynamicTypeSize.isAccessibilitySize ? 2 : 1,
                            identifier: "clove.detail.zoom",
                            reportHeaderFrame: true
                        )
                    }
                    if let browsing {
                        InlineFolderPreparationBar(
                            browsing: browsing,
                            identifier: "clove.detail.preparation.progress",
                            usesDarkScrim: true,
                            width: 32,
                            height: 3)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Color.black.opacity(0.62),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .reportHeaderControlFrame("clove.detail.photoCornerOverlay")

        if let onInfoTap {
            let infoLabel = AppLocalization.format(
                "%@, %@", language: language, fileName,
                AppLocalization.string("Info", language: language))
            scrim
                .allowsHitTesting(false)
                .frame(minWidth: 44, minHeight: 44, alignment: .topLeading)
                .background {
                    Button(action: onInfoTap) {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(infoLabel)
                    .accessibilityIdentifier("clove.detail.info")
                    .reportHeaderControlFrame("clove.detail.info")
                }
                .accessibilityElement(children: .contain)
        } else {
            scrim
                .allowsHitTesting(false)
        }
    }
}
