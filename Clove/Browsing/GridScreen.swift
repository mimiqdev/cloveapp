import CloveCore
import SwiftUI

/// The handoff's iPhone grid: compact navigation, stacked groups and a floating batch capsule.
/// Marks and navigation still go through BrowsingModel; this view owns only presentation.
struct GridScreen: View {
    let browsing: BrowsingModel
    let thumbnails: any GridThumbnailSource

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.cloveUserInterfaceIdiom) private var overrideUserInterfaceIdiom
    @Environment(SettingsStore.self) private var store
    @Environment(\.appLanguage) private var language
    @State private var activeSheet: GridSheetRoute?
    @State private var renameFlow: BatchRenameFlow?
    @State private var pendingPhotosConfirmationPlan: PhotosSavePlan?
    @State private var showsNoEligiblePhotosAlert = false
    @State private var isPickingEmptyFolder = false
    @State private var filterHandoff = GridFilterSheetHandoff()
    @State private var popoverHandoffTask: Task<Void, Never>?
    @State private var selectsEmpty = false
    @State private var areGroupsUnfolded: Bool
    @State private var isLandscapeContainer = false
    @State private var containerSize: CGSize = .zero
    @State private var presentation = DetailPresentation.focus
    /// Whether this session opened a photo (or has an active current photo), so returning to the
    /// grid from Detail brings the active photo into view across iPhone, iPad, and Duo when
    /// off-screen while preserving the scroll offset when it is already visible.
    @State private var hasOpenedPhoto: Bool
    @Environment(\.isDuoExpanded) private var isDuoExpanded
    @Environment(\.isDuoCover) private var isDuoCover
    @Environment(\.usesSystemBrowsingToolbar) private var usesSystemToolbar
    @Environment(\.usesVerticalBrowsingToolbar) private var usesVerticalToolbar
    @Environment(\.hasFoldRegion) private var hasFoldRegion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var filterPopoverTrigger: Int = 0

    private enum GridSheetRoute: Identifiable {
        case renameDetails
        case keywords
        case photosConfirmation(PhotosSaveSheetRequest)
        case metadataFilters
        case moveFlow(MoveRejectsFlow)
        case moveDetails(CompletedRejectMove)

        var id: String {
            switch self {
            case .renameDetails: "renameDetails"
            case .keywords: "keywords"
            case .photosConfirmation(let request): "photosConfirmation-\(request.id)"
            case .metadataFilters: "metadataFilters"
            case .moveFlow(let flow): "moveFlow-\(flow.id)"
            case .moveDetails(let completed): "moveDetails-\(completed.id)"
            }
        }

        var isMove: Bool {
            switch self {
            case .moveFlow, .moveDetails: true
            case .renameDetails, .keywords, .photosConfirmation, .metadataFilters: false
            }
        }

        var isKeywords: Bool {
            if case .keywords = self { return true }
            return false
        }

        var isMetadataFilters: Bool {
            if case .metadataFilters = self { return true }
            return false
        }

        var isPhotosConfirmation: Bool {
            if case .photosConfirmation = self { return true }
            return false
        }
    }

    init(
        browsing: BrowsingModel,
        thumbnails: (any GridThumbnailSource)? = nil,
        filterPopoverTrigger: Int = 0,
        initialPresentation: DetailPresentation = .focus
    ) {
        self.browsing = browsing
        self.thumbnails = thumbnails ?? browsing.thumbnails
        self.filterPopoverTrigger = filterPopoverTrigger
        _presentation = State(initialValue: initialPresentation)
        _areGroupsUnfolded = State(initialValue: browsing.isSelecting)
        _hasOpenedPhoto = State(
            initialValue: browsing.state.route == .detail || browsing.state.currentPhoto != nil)
    }

    private var userInterfaceIdiom: UIUserInterfaceIdiom {
        overrideUserInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom
    }
    private var isSelecting: Bool { selectsEmpty || browsing.isSelecting }
    private var isRegular: Bool {
        userInterfaceIdiom == .pad
            && horizontalSizeClass == .regular
            && !isDuoExpanded
    }
    private var isOrdinaryPhoneLandscape: Bool {
        userInterfaceIdiom == .phone
            && !isDuoExpanded
            && !isDuoCover
            && !hasFoldRegion
            && (verticalSizeClass == .compact || isLandscapeContainer)
    }
    private var usesDock: Bool { isDuoExpanded || isDuoCover }
    private var usesVerticalGridDock: Bool {
        isDuoCover || (isDuoExpanded && usesVerticalToolbar)
    }
    private var supportsCompare: Bool {
        CompareLayoutPolicy(
            availableWidth: Double(containerSize.width),
            availableHeight: Double(containerSize.height),
            isRegularWidth: horizontalSizeClass == .regular,
            isCompactHeight: verticalSizeClass == .compact,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover
        ).supportsCompare
    }
    private var showsMoveRejects: Bool {
        store.settings.moveRejectsEnabled && browsing.rejectedPhotoCount > 0
            && !browsing.isFolderOpening && !browsing.isMovingRejects && !isSelecting
    }

    private var activeToastKey: String? {
        if !(usesDock && browsing.state.route == .detail),
            browsing.failureToastMessage != nil
        {
            return "failure-\(browsing.failureToastBurst)"
        }
        if !(usesDock && browsing.state.route == .detail),
            let message = browsing.photosSaveToastMessage,
            browsing.isPhotosSaveToastVisible
        {
            return "photosSave-\(browsing.photosSaveToastAttempt)-\(message)"
        }
        if browsing.completedRename != nil, browsing.isRenameToastVisible {
            return "rename-\(browsing.renameToastAttempt)"
        }
        if browsing.lastRejectMove != nil, browsing.isRejectMoveToastVisible {
            return "rejectMove-\(browsing.rejectMoveToastAttempt)"
        }
        return nil
    }

    private var gridProgressLine: (progress: Double?, tone: ProgressLine.Tone) {
        Self.progressLineState(
            browsing: browsing, similarGroupsEnabled: store.settings.similarGroupsEnabled)
    }

    static func progressLineState(
        browsing: BrowsingModel, similarGroupsEnabled: Bool
    ) -> (progress: Double?, tone: ProgressLine.Tone) {
        if let progress = browsing.visibleReadingProgress {
            let value = progress.total > 0 ? Double(progress.read) / Double(progress.total) : 0
            return (value, .reading)
        }
        return (nil, .reading)
    }

    private var cells: [GridCellItem] { gridDisplay.cells }

    /// How the grid joins the folder and its groups.
    private var gridDisplay: GridDisplay {
        GridDisplay(
            photos: browsing.photos, groups: browsing.groups,
            groupsEnabled: store.settings.similarGroupsEnabled && !browsing.isScanning,
            expandGroupsInline: isSelecting && areGroupsUnfolded)
    }

    var body: some View {
        surface
            .background(Color.clove.bg.canvas)
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: { size in
                containerSize = size
                isLandscapeContainer = size.width > size.height && size.width > 0
            }
            .onAppear {
                if browsing.state.route == .detail || browsing.state.currentPhoto != nil {
                    hasOpenedPhoto = true
                }
            }
            .onChange(of: browsing.state.folder) { _, _ in
                hasOpenedPhoto =
                    browsing.state.route == .detail || browsing.state.currentPhoto != nil
                selectsEmpty = false
                areGroupsUnfolded = browsing.isSelecting
                pendingPhotosConfirmationPlan = nil
                showsNoEligiblePhotosAlert = false
                cancelPendingMetadataFiltersHandoff()
                filterHandoff.dismissFiltersAndCancelPending()
                if activeSheet?.isPhotosConfirmation == true
                    || activeSheet?.isMetadataFilters == true
                {
                    activeSheet = nil
                }
            }
            .onChange(of: browsing.folderLocationLoss != nil) { _, isLost in
                if isLost {
                    pendingPhotosConfirmationPlan = nil
                    if activeSheet?.isPhotosConfirmation == true {
                        activeSheet = nil
                    }
                    showsNoEligiblePhotosAlert = false
                }
            }
            .onChange(of: browsing.state.route) { _, route in
                if route == .detail { hasOpenedPhoto = true }
                if route != .detail {
                    presentation = .focus
                }
            }
            .onChange(of: filterDismissTrigger) { _, _ in
                cancelPendingMetadataFiltersHandoff()
                filterHandoff.dismissFiltersAndCancelPending()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    cancelPendingMetadataFiltersHandoff()
                    filterHandoff.dismissFiltersAndCancelPending()
                }
            }
            .onDisappear {
                cancelPendingMetadataFiltersHandoff()
                filterHandoff.dismissFiltersAndCancelPending()
            }
            .overlay(alignment: .bottomTrailing) {
                if !isRegular, !usesVerticalGridDock, showsMoveRejects {
                    MoveRejectsButton(identifier: "clove.grid.moveRejects") {
                        presentSheet(.moveFlow(MoveRejectsFlow(browsing: browsing)))
                    }
                    .reportHeaderControlFrame("clove.grid.moveRejects")
                    .padding(16)
                    .transition(
                        .asymmetric(
                            insertion: CloveMotion.scaleOpacityTransition(
                                scale: 0.9, anchor: .bottomTrailing, reduceMotion: reduceMotion),
                            removal: .identity))
                }
            }
            .animation(
                (!isRegular && !usesVerticalGridDock && showsMoveRejects)
                    ? CloveMotion.chrome(reduceMotion: reduceMotion) : nil,
                value: showsMoveRejects
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting && !(usesDock && browsing.state.route == .detail) {
                    GridBatchBar(
                        browsing: browsing,
                        cells: cells,
                        onSelectAll: completeGroupUnfoldImmediately,
                        onDeselectAll: { selectsEmpty = true },
                        onRename: { renameFlow = BatchRenameFlow(browsing: browsing) },
                        onKeywords: { presentSheet(.keywords) },
                        onSaveToPhotos: startSaveToPhotos,
                        showsCompare: browsing.batchTargets.count == 2 && supportsCompare,
                        onCompare: { browsing.enterCompareFromBatchSelection() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .transition(
                        .asymmetric(
                            insertion: CloveMotion.slideTransition(
                                edge: .bottom, offset: 14, reduceMotion: reduceMotion),
                            removal: .identity))
                }
            }
            .animation(
                isSelecting ? CloveMotion.chrome(reduceMotion: reduceMotion) : nil,
                value: isSelecting
            )
            .task(id: isSelecting) {
                guard isSelecting else {
                    areGroupsUnfolded = false
                    return
                }
                guard !areGroupsUnfolded else { return }
                if reduceMotion || !store.settings.similarGroupsEnabled
                    || browsing.isScanning
                {
                    areGroupsUnfolded = true
                    return
                }
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, isSelecting else { return }
                areGroupsUnfolded = true
            }
            .tapPickerContainer(dismissWhen: tapPickerDismissTrigger)
            .overlay(alignment: .bottom) {
                if !(usesDock && browsing.state.route == .detail),
                    let message = browsing.failureToastMessage
                {
                    Toast(
                        message: AppLocalization.string(message, language: language),
                        identifier: "clove.save.toast"
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .transition(
                        CloveMotion.slideTransition(
                            edge: .bottom, offset: 12, reduceMotion: reduceMotion))
                } else if !(usesDock && browsing.state.route == .detail),
                    let photosToast = browsing.photosSaveToastMessage,
                    browsing.isPhotosSaveToastVisible
                {
                    Toast(
                        message: photosToast.localizedText(language: language),
                        identifier: "clove.photos.toast"
                    )
                    .padding(.horizontal)
                    .padding(
                        .bottom,
                        (isSelecting && !(usesDock && browsing.state.route == .detail)) ? 76 : 12
                    )
                    .transition(
                        CloveMotion.slideTransition(
                            edge: .bottom, offset: 12, reduceMotion: reduceMotion))
                } else if let completed = browsing.completedRename, browsing.isRenameToastVisible {
                    BatchRenameToast(completed: completed) { presentSheet(.renameDetails) }
                        .padding(.horizontal).padding(.bottom, 12)
                        .transition(
                            CloveMotion.slideTransition(
                                edge: .bottom, offset: 12, reduceMotion: reduceMotion))
                } else if let completed = browsing.lastRejectMove, browsing.isRejectMoveToastVisible
                {
                    MoveRejectsToast(browsing: browsing, completed: completed) {
                        presentSheet(.moveDetails(completed))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .transition(
                        CloveMotion.slideTransition(
                            edge: .bottom, offset: 12, reduceMotion: reduceMotion))
                }
            }
            .animation(
                CloveMotion.chrome(reduceMotion: reduceMotion),
                value: activeToastKey
            )
            .task(id: browsing.photosSaveToastAttempt) {
                guard browsing.isPhotosSaveToastVisible, !TestLibrary.keepsMoveToast else {
                    return
                }
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
                    browsing.dismissPhotosSaveToast()
                }
            }
            .task(id: browsing.rejectMoveToastAttempt) {
                guard browsing.isRejectMoveToastVisible, !TestLibrary.keepsMoveToast else { return }
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
                    browsing.dismissRejectMoveToast()
                }
            }
            .task(id: browsing.renameToastAttempt) {
                guard browsing.isRenameToastVisible, !TestLibrary.keepsMoveToast else { return }
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
                    browsing.dismissRenameToast()
                }
            }
            .fullScreenCover(
                item: $renameFlow,
                onDismiss: {
                    if !browsing.isSelecting { selectsEmpty = false }
                }
            ) { flow in
                BatchRenameOrderScreen(flow: flow)
            }
            .sheet(item: $activeSheet) { route in
                switch route {
                case .renameDetails:
                    if let completed = browsing.completedRename {
                        BatchRenameDetailsSheet(completed: completed)
                    }
                case .keywords:
                    BatchKeywordsSheet(browsing: browsing)
                case .photosConfirmation(let request):
                    SaveToPhotosConfirmationSheet(
                        plan: request.plan,
                        hiddenSelectedCount: browsing.hiddenSelectedCount
                    ) {
                        Task {
                            await browsing.saveToPhotos(request.plan, language: language)
                        }
                    }
                case .metadataFilters:
                    MetadataFilterSheet(browsing: browsing)
                case .moveFlow(let flow):
                    MoveRejectsSheet(flow: flow)
                case .moveDetails(let completed):
                    MoveRejectsDetailsSheet(browsing: browsing, completed: completed)
                }
            }
            .alert(
                AppLocalization.format(
                    "Save %lld photos to Photos?", language: language,
                    Int64(pendingPhotosConfirmationPlan?.eligibleCount ?? 0)),
                isPresented: Binding(
                    get: { pendingPhotosConfirmationPlan != nil },
                    set: { isPresented in
                        if !isPresented { pendingPhotosConfirmationPlan = nil }
                    }),
                presenting: pendingPhotosConfirmationPlan
            ) { plan in
                Button(
                    AppLocalization.format(
                        "Save %lld", language: language, Int64(plan.eligibleCount))
                ) {
                    pendingPhotosConfirmationPlan = nil
                    Task {
                        await browsing.saveToPhotos(plan, language: language)
                    }
                }
                .accessibilityIdentifier("clove.photos.confirm.save")
                Button(AppLocalization.string("Cancel", language: language), role: .cancel) {
                    pendingPhotosConfirmationPlan = nil
                }
                .accessibilityIdentifier("clove.photos.confirm.cancel")
            } message: { plan in
                Text(
                    AppLocalization.format(
                        "%lld RAW-only photos have no JPEG or HEIF and will be skipped.",
                        language: language, Int64(plan.skippedRawCount)))
            }
            .alert(
                AppLocalization.string("No JPEG or HEIF to save", language: language),
                isPresented: $showsNoEligiblePhotosAlert
            ) {
                Button(AppLocalization.string("OK", language: language), role: .cancel) {}
                    .accessibilityIdentifier("clove.photos.noEligible.ok")
            } message: {
                Text(
                    verbatim: AppLocalization.string(
                        "Selected photos are RAW-only. Clove saves existing JPEG and HEIF files without re-encoding RAW.",
                        language: language))
            }
            .folderPicker(isPresented: $isPickingEmptyFolder) { url in
                await browsing.openPickedFolder(url)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(
                usesDock && browsing.state.route == .detail
                    ? (browsing.compareSession != nil ? "clove.compare" : "clove.detail")
                    : "clove.grid")
    }

    @ViewBuilder private var surface: some View {
        if usesSystemToolbar, #available(iOS 27.1, *) {
            if usesDock && browsing.state.route == .detail {
                DetailScreen(
                    browsing: browsing,
                    duo: DuoDetailLayout(
                        presentation: $presentation,
                        showsGrid: isDuoExpanded))
            } else {
                grid
                    .toolbar {
                        BrowsingToolbar(
                            back: { browsing.back() }, undo: { browsing.undoLastMark() },
                            canUndo: browsing.canUndoMark,
                            showsBack: !isRegular && (usesVerticalGridDock || !isSelecting),
                            showsUndo: isDuoExpanded && usesVerticalToolbar,
                            showsNavigationTools: isSelecting,
                            showsHorizontalLeadingTools: isSelecting,
                            showsStandaloneDockTool: isDuoCover && !isSelecting && showsMoveRejects,
                            showsHorizontalTools: isDuoCover,
                            showsTools: !isDuoCover,
                            showsBottom: usesVerticalGridDock
                        ) {
                            if isSelecting {
                                systemSelectAllButton
                            }
                        } horizontalLeadingTools: {
                            if isSelecting {
                                systemSelectAllButton
                            }
                        } standaloneDockTool: {
                            if isDuoCover && !isSelecting && showsMoveRejects {
                                moveRejectsToolbarButton
                            }
                        } horizontalTools: {
                            if isDuoCover {
                                coverHorizontalTools
                            }
                        } tools: {
                            if !isDuoCover {
                                headerTools
                            }
                        } marks: {
                            Optional<ToolbarItem<Void, EmptyView>>.none
                        } bottom: {
                            if isDuoCover {
                                filterButton
                            } else if isDuoExpanded && usesVerticalToolbar {
                                dockBottom
                            }
                        }
                        if Self.usesLeadingRegularHeader(
                            isRegular: isRegular, isSelecting: isSelecting)
                        {
                            ToolbarItem(placement: .topBarLeading) {
                                ToolbarTitleBoundingLayout(maxWidth: regularHeaderMaxTitleWidth) {
                                    regularGridHeaderTitle
                                }
                            }
                            .sharedBackgroundVisibility(.hidden)
                        } else {
                            ToolbarItem(placement: .principal) {
                                compactOrSelectingToolbarTitle
                            }
                            .axisBehavior(.horizontalOnly)
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarVerticalBehavior(.automatic)
                    .toolbarVerticalCompressionBehavior(.prefersToolbarItems)
                    .toolbarVisibility(.visible, for: .navigationBar)
            }
        } else {
            grid
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }

    static func usesLeadingRegularHeader(isRegular: Bool, isSelecting: Bool) -> Bool {
        isRegular && !isSelecting
    }

    private var regularHeaderMaxTitleWidth: CGFloat {
        containerSize.width > 0 ? max(containerSize.width - 180, 140) : 320
    }

    private var regularGridHeaderTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(browsing.localizedFilterTitle(language: language))
                .font(.title3.bold())
                .foregroundStyle(Color.clove.text.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityIdentifier("clove.grid.title")
            HStack(spacing: 0) {
                Text(subtitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("clove.grid.subtitle")
                SaveStatusIndicator(
                    browsing: browsing, identifierPrefix: "clove.grid.saveState"
                )
            }
            .font(.caption)
            .foregroundStyle(Color.clove.text.secondary)
        }
    }

    private var compactOrSelectingToolbarTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(
                    isSelecting
                        ? AppLocalization.format(
                            "%lld selected", language: language,
                            Int64(browsing.batchTargets.count))
                        : (isRegular
                            ? browsing.localizedFilterTitle(language: language)
                            : browsing.localizedFolderTitle(language: language))
                )
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .accessibilityIdentifier(
                    isSelecting ? "clove.grid.batch.count" : "clove.grid.title")
                if !isRegular && !isSelecting {
                    FolderPreparationIndicator(
                        browsing: browsing,
                        identifierPrefix: "clove.grid.preparation"
                    )
                    .layoutPriority(1)
                }
            }
            HStack(spacing: 0) {
                if let hiddenSelectedSubtitle {
                    Text(hiddenSelectedSubtitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier("clove.grid.batch.hiddenCount")
                        .reportHeaderControlFrame(
                            "clove.grid.batch.hiddenCount")
                } else {
                    Text(subtitle)
                        .lineLimit(1)
                        .accessibilityIdentifier("clove.grid.subtitle")
                }
                SaveStatusIndicator(
                    browsing: browsing, identifierPrefix: "clove.grid.saveState"
                )
            }
            .font(.caption)
        }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            if !usesSystemToolbar { header }
            ProgressLine(progress: gridProgressLine.progress, tone: gridProgressLine.tone)
            gridContent
                .overlay(alignment: .top) {
                    FolderSaveBanner(
                        browsing: browsing, identifierPrefix: "clove.grid.saveState.failure")
                }
        }
        .background(Color.clove.bg.canvas)
        .ignoresSafeArea(.container, edges: usesDock ? .bottom : [])
    }

    private var gridContent: some View {
        VStack(spacing: 0) {
            if !browsing.metadataFilter.isEmpty {
                ActiveMetadataFilterBar(
                    browsing: browsing,
                    onEdit: isRegular ? nil : { presentSheet(.metadataFilters) })
            }
            if cells.isEmpty && !browsing.isFolderOpening {
                emptyState
                    .opacity(browsing.folderLocationLoss == nil ? 1 : 0.35)
                    .animation(
                        CloveMotion.chrome(reduceMotion: reduceMotion),
                        value: browsing.folderLocationLoss == nil)
            } else {
                GridCollectionView(
                    sections: gridDisplay.sections, currentPhoto: browsing.state.currentPhoto,
                    groups: browsing.groups, shownPhotos: Set(browsing.photos.map(\.id)),
                    selection: browsing.state.selection,
                    thumbnails: thumbnails,
                    isSelectingEmpty: selectsEmpty,
                    placeholderCount: browsing.visibleReadingProgress.map {
                        $0.total == 0 ? 9 : max($0.total - $0.read, 0)
                    } ?? 0,
                    columnCount: isDuoExpanded ? 6 : nil,
                    highlightsCurrentPhoto: false,
                    followsCurrentPhoto: hasOpenedPhoto,
                    foldExpandedGroup: { _ in },
                    openPhoto: { browsing.openPhoto($0) }, openGroup: openGroup,
                    beginSelection: { browsing.beginSelection(of: $0) },
                    toggleSelection: { browsing.toggleSelection(of: $0) },
                    setSelection: { browsing.setSelection($0) },
                    keepSelectingWhenEmpty: { selectsEmpty = true },
                    areGroupsUnfolded: areGroupsUnfolded,
                    completeGroupUnfold: completeGroupUnfoldImmediately
                )
                .opacity(browsing.folderLocationLoss == nil ? 1 : 0.35)
                .animation(
                    CloveMotion.chrome(reduceMotion: reduceMotion),
                    value: browsing.folderLocationLoss == nil)
            }
        }
    }

    private var moveRejectsToolbarButton: some View {
        Button(
            AppLocalization.string("Move rejects", language: language),
            systemImage: "tray.and.arrow.down"
        ) {
            presentSheet(.moveFlow(MoveRejectsFlow(browsing: browsing)))
        }
        .accessibilityIdentifier("clove.grid.moveRejects")
    }

    private var dockBottom: some View {
        Group {
            if showsMoveRejects {
                moveRejectsToolbarButton
            }
        }
    }

    @ViewBuilder private var header: some View {
        if isRegular {
            HStack(spacing: 8) {
                if isSelecting {
                    selectAllButton
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(
                        isSelecting
                            ? AppLocalization.format(
                                "%lld selected", language: language,
                                Int64(browsing.batchTargets.count))
                            : browsing.localizedFilterTitle(language: language)
                    )
                    .font(isSelecting ? .subheadline.weight(.semibold) : .title3.bold())
                    .lineLimit(1)
                    .accessibilityIdentifier(
                        isSelecting ? "clove.grid.batch.count" : "clove.grid.title"
                    )
                    .reportHeaderControlFrame(
                        isSelecting ? "clove.grid.batch.count" : "clove.grid.title")
                    HStack(spacing: 0) {
                        if let hiddenSelectedSubtitle {
                            Text(hiddenSelectedSubtitle)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .accessibilityIdentifier("clove.grid.batch.hiddenCount")
                                .reportHeaderControlFrame("clove.grid.batch.hiddenCount")
                        } else {
                            Text(subtitle)
                                .lineLimit(1)
                                .accessibilityIdentifier("clove.grid.subtitle")
                        }
                        SaveStatusIndicator(
                            browsing: browsing, identifierPrefix: "clove.grid.saveState")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.clove.text.secondary)
                }
                Spacer(minLength: 0)
                headerTools
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .foregroundStyle(Color.clove.text.primary)
        } else {
            compactHeader
        }
    }

    private var compactHeader: some View {
        BrowsingHeader(
            title: isSelecting
                ? AppLocalization.format(
                    "%lld selected", language: language, Int64(browsing.batchTargets.count))
                : browsing.localizedFolderTitle(language: language),
            titleIdentifier: isSelecting ? "clove.grid.batch.count" : "clove.grid.title",
            showsBack: !isSelecting,
            usesInlineFlow: isOrdinaryPhoneLandscape || isSelecting,
            height: isOrdinaryPhoneLandscape ? 44 : 64,
            back: { browsing.back() }
        ) {
            HStack(spacing: 0) {
                if let hiddenSelectedSubtitle {
                    Text(hiddenSelectedSubtitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier("clove.grid.batch.hiddenCount")
                        .reportHeaderControlFrame("clove.grid.batch.hiddenCount")
                } else {
                    Text(subtitle)
                        .lineLimit(1)
                        .accessibilityIdentifier("clove.grid.subtitle")
                }
                SaveStatusIndicator(
                    browsing: browsing, identifierPrefix: "clove.grid.saveState")
            }
        } titleAccessory: {
            if !isSelecting {
                FolderPreparationIndicator(
                    browsing: browsing,
                    identifierPrefix: "clove.grid.preparation")
            }
        } leadingTools: {
            if isSelecting {
                selectAllButton
            } else if isDuoCover && showsMoveRejects {
                GlassIconButton(
                    label: AppLocalization.string("Move rejects", language: language),
                    symbol: "tray.and.arrow.down",
                    size: .phone,
                    identifier: "clove.grid.moveRejects"
                ) {
                    presentSheet(.moveFlow(MoveRejectsFlow(browsing: browsing)))
                }
            }
        } tools: {
            headerTools
        }
    }

    private var selectAllTitle: String {
        AppLocalization.string(
            browsing.showsAllVisibleSelected ? "Deselect All" : "Select All",
            language: language)
    }

    private func toggleSelectAllVisible() {
        if browsing.showsAllVisibleSelected {
            selectsEmpty = true
            browsing.deselectAllVisible()
        } else {
            completeGroupUnfoldImmediately()
            browsing.selectAllVisible()
        }
    }

    private var systemSelectAllButton: some View {
        Button(selectAllTitle) {
            toggleSelectAllVisible()
        }
        .disabled(browsing.photos.isEmpty)
        .accessibilityIdentifier("clove.grid.selectAll")
    }

    private var selectAllButton: some View {
        Button {
            toggleSelectAllVisible()
        } label: {
            Text(selectAllTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(
                    browsing.photos.isEmpty
                        ? Color.clove.text.secondary : Color.clove.text.primary
                )
                .opacity(browsing.photos.isEmpty ? 0.45 : 1)
                .padding(.horizontal, isRegular ? 14 : 12)
                .frame(height: isRegular ? 40 : 44)
                .cloveGlass(in: Capsule())
        }
        .buttonStyle(.cloveGlassPress)
        .disabled(browsing.photos.isEmpty)
        .accessibilityLabel(selectAllTitle)
        .accessibilityIdentifier("clove.grid.selectAll")
        .reportHeaderControlFrame("clove.grid.selectAll")
    }

    @ViewBuilder private var systemSelectionToolbarTools: some View {
        Button(
            AppLocalization.string("Done", language: language),
            systemImage: "checkmark"
        ) {
            browsing.clearSelection()
            selectsEmpty = false
        }
        .accessibilityIdentifier("clove.grid.batch.done")
    }

    @ViewBuilder private var coverHorizontalTools: some View {
        if isSelecting {
            systemSelectionToolbarTools
        } else {
            moreMenu
        }
    }

    @ViewBuilder private var headerTools: some View {
        if !isRegular {
            if usesSystemToolbar {
                filterButton
            } else {
                filterButton
                    .reportHeaderControlFrame("clove.grid.filter")
            }
        }
        if isSelecting && usesSystemToolbar {
            systemSelectionToolbarTools
        } else if isSelecting {
            Button {
                browsing.clearSelection()
                selectsEmpty = false
            } label: {
                Text(AppLocalization.string("Done", language: language))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(Color.clove.accent)
                    .padding(.horizontal, isRegular ? 16 : 12)
                    .frame(height: isRegular ? 40 : 44)
                    .cloveGlass(in: Capsule())
            }
            .buttonStyle(.cloveGlassPress)
            .accessibilityLabel(AppLocalization.string("Done", language: language))
            .accessibilityIdentifier("clove.grid.batch.done")
            .reportHeaderControlFrame("clove.grid.batch.done")
        } else {
            if isRegular, showsMoveRejects {
                if usesSystemToolbar {
                    moveRejectsToolbarButton
                } else {
                    GlassIconButton(
                        label: AppLocalization.string("Move rejects", language: language),
                        symbol: "tray.and.arrow.down", size: .pad,
                        identifier: "clove.grid.moveRejects"
                    ) {
                        presentSheet(.moveFlow(MoveRejectsFlow(browsing: browsing)))
                    }
                }
            }
            moreMenu
        }
    }

    private var filterButton: some View {
        PhotoFilterPopoverButton(
            browsing: browsing,
            controlSize: isRegular ? .pad : .phone,
            identifierPrefix: "clove.grid.filter",
            filterHandoff: $filterHandoff,
            canPresentMetadataFilters: canPresentMetadataFiltersFromPopover,
            popoverTrigger: filterPopoverTrigger,
            onCancelPendingMetadataFilters: cancelPendingMetadataFiltersHandoff,
            onCompleteMetadataFiltersHandoff: completeMetadataFiltersHandoffIfPending
        )
    }

    private var moreMenu: some View {
        Menu {
            Section(AppLocalization.string("Sort by", language: language)) {
                Button {
                    browsing.setOrder(.captureTime)
                } label: {
                    Label(
                        AppLocalization.string("Capture time", language: language),
                        systemImage: browsing.state.order == .captureTime ? "checkmark" : "")
                }
                .accessibilityIdentifier("clove.grid.order.captureTime")
                Button {
                    browsing.setOrder(.fileName)
                } label: {
                    Label(
                        AppLocalization.string("Filename", language: language),
                        systemImage: browsing.state.order == .fileName ? "checkmark" : "")
                }
                .accessibilityIdentifier("clove.grid.order.fileName")
            }
            Button(AppLocalization.string("Select", language: language)) {
                if usesDock && browsing.state.route == .detail { browsing.back() }
                selectsEmpty = true
            }
            .accessibilityIdentifier("clove.grid.select")
            if !isRegular, store.settings.similarGroupsEnabled {
                Button(AppLocalization.string("Find similar shots again", language: language)) {
                    Task { await browsing.runGroupingAgain() }
                }
                .accessibilityIdentifier("clove.grid.grouping.runAgain")
            }
            Section {
                Button(AppLocalization.string("Settings", language: language)) {
                    browsing.showSettings()
                }
                .accessibilityIdentifier("clove.nav.settings")
            }
        } label: {
            if usesSystemToolbar {
                Label(AppLocalization.string("More", language: language), systemImage: "ellipsis")
            } else {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundStyle(Color.clove.text.primary)
                    .frame(width: isRegular ? 40 : 44, height: isRegular ? 40 : 44)
                    .cloveGlass(in: Circle())
            }
        }
        .accessibilityLabel(AppLocalization.string("More", language: language))
        .accessibilityIdentifier("clove.grid.more")
    }

    private var hasFilter: Bool { browsing.hasActiveFilter }

    private static func metadataFilterSubtitlePart(
        for filter: PhotoMetadataFilter, language: ResolvedAppLanguage
    ) -> String? {
        guard !filter.isEmpty else { return nil }
        if filter.activeCount == 1 {
            if let camera = filter.camera { return camera }
            if let lens = filter.lens { return lens }
            if let bucket = filter.focalLength {
                return AppLocalization.focalLengthBucketTitle(bucket, language: language)
            }
            if let keyword = filter.keyword { return keyword }
        }
        return AppLocalization.format(
            "%lld filters", language: language, Int64(filter.activeCount))
    }

    private var hiddenSelectedSubtitle: String? {
        guard isSelecting, browsing.hiddenSelectedCount > 0 else { return nil }
        return AppLocalization.format(
            "%lld hidden by filter", language: language, Int64(browsing.hiddenSelectedCount))
    }

    private var subtitle: String {
        Self.subtitleText(
            browsing: browsing, isSelecting: isSelecting, isRegular: isRegular, language: language)
    }

    static func subtitleText(
        browsing: BrowsingModel,
        isSelecting: Bool,
        isRegular: Bool,
        language: ResolvedAppLanguage = .english
    ) -> String {
        if isSelecting { return browsing.localizedFolderTitle(language: language) }
        if let progress = browsing.visibleReadingProgress {
            return progress.total == 0
                ? AppLocalization.string("Reading photos…", language: language)
                : AppLocalization.format(
                    "%lld of %lld", language: language, Int64(progress.read),
                    Int64(progress.total))
        }
        let count = browsing.photos.count
        let countText = count.formatted(.number.locale(language.locale))
        if isRegular {
            return AppLocalization.format("%lld photos", language: language, Int64(count))
        }
        if let label = browsing.labelFilter {
            return AppLocalization.format(
                "%@ · %@", language: language,
                AppLocalization.colourName(label, language: language), countText)
        }
        switch browsing.state.filter {
        case .all:
            if let metadataPart = metadataFilterSubtitlePart(
                for: browsing.metadataFilter, language: language)
            {
                return AppLocalization.format(
                    "%@ · %@", language: language, metadataPart, countText)
            }
            return AppLocalization.format("%lld photos", language: language, Int64(count))
        case .unmarked:
            return AppLocalization.format(
                "%@ · %@", language: language,
                AppLocalization.string("Unmarked", language: language), countText)
        case .rejected:
            return AppLocalization.format(
                "%@ · %@", language: language,
                AppLocalization.string("Rejected", language: language), countText)
        case .ratedAtLeast(let rating):
            let stars = (rating.starCount ?? 0).formatted(.number.locale(language.locale))
            let filterLabel = "\(AppLocalization.string("Rating ≥", language: language)) \(stars)"
            return AppLocalization.format("%@ · %@", language: language, filterLabel, countText)
        case .subfolder(let path):
            return AppLocalization.format("%@ · %@", language: language, path, countText)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !browsing.hasFolderContents && !browsing.isFolderOpening {
            EntryEmptyState(isEmptyFolder: true) { isPickingEmptyFolder = true }
                .accessibilityIdentifier("clove.grid.empty")
        } else {
            ContentUnavailableView {
                Label(
                    AppLocalization.string("No photos", language: language),
                    systemImage: "photo.on.rectangle")
            } description: {
                Text(
                    AppLocalization.string(
                        browsing.isFolderOpening
                            ? "Reading photos…" : "No photos match this filter.",
                        language: language))
            } actions: {
                if !browsing.isFolderOpening && hasFilter {
                    Button(AppLocalization.string("Clear filters", language: language)) {
                        browsing.clearAllFilters()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.clove.accent)
                    .accessibilityIdentifier("clove.grid.empty.clearFilters")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("clove.grid.empty")
        }
    }

    private func completeGroupUnfoldImmediately() {
        guard isSelecting, !areGroupsUnfolded else { return }
        areGroupsUnfolded = true
    }

    /// Opens one collapsed group in Group Focus on its Representative Photo.
    private func openGroup(_ id: GroupID) {
        browsing.openGroup(id)
    }

    private func startSaveToPhotos() {
        guard browsing.canSaveToPhotos else { return }
        let plan = browsing.planSaveToPhotos()
        guard !plan.isEmpty else { return }
        if store.settings.confirmBatchActions {
            presentSheet(.photosConfirmation(PhotosSaveSheetRequest(plan: plan)))
            return
        }
        if plan.eligibleCount == 0 && plan.skippedRawCount > 0 {
            showsNoEligiblePhotosAlert = true
        } else if plan.skippedRawCount > 0 {
            pendingPhotosConfirmationPlan = plan
        } else if plan.eligibleCount > 0 {
            Task {
                await browsing.saveToPhotos(plan, language: language)
            }
        }
    }

    private var filterDismissTrigger: GridFilterDismissTrigger {
        GridFilterDismissTrigger(
            route: browsing.state.route,
            folder: browsing.state.folder,
            isRegular: isRegular,
            isSelecting: isSelecting,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover,
            usesVerticalToolbar: usesVerticalToolbar,
            hasFoldRegion: hasFoldRegion,
            isComparing: browsing.compareSession != nil,
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            isLandscapeContainer: isLandscapeContainer)
    }

    private var canPresentMetadataFiltersFromPopover: Bool {
        Self.allowsMetadataFiltersFromPopover(
            isRegular: isRegular, usesDock: usesDock, route: browsing.state.route)
    }

    static func allowsMetadataFiltersFromPopover(
        isRegular: Bool, usesDock: Bool, route: BrowserRoute
    ) -> Bool {
        (!isRegular || usesDock) && route == .grid
    }

    private func presentSheet(_ route: GridSheetRoute) {
        cancelPendingMetadataFiltersHandoff()
        filterHandoff.dismissFiltersAndCancelPending()
        activeSheet = route
    }

    private func cancelPendingMetadataFiltersHandoff() {
        popoverHandoffTask?.cancel()
        popoverHandoffTask = nil
        filterHandoff.cancelPendingMetadataFilters()
    }

    private func completeMetadataFiltersHandoffIfPending() {
        guard filterHandoff.pendingMetadataFiltersAfterPopover else { return }
        let expectedFolder = browsing.state.folder
        PhotoFilterPopoverButton.scheduleMetadataFiltersHandoff(
            handoffTask: &popoverHandoffTask,
            canPresent: { true },
            consume: {
                filterHandoff.consumePendingMetadataFiltersOnPopoverDisappear(
                    currentFolder: browsing.state.folder,
                    isSceneActive: scenePhase == .active,
                    canPresent: canPresentMetadataFiltersFromPopover
                        && browsing.state.folder == expectedFolder)
            },
            present: { activeSheet = .metadataFilters },
            clearTask: { popoverHandoffTask = nil })
    }

    private var tapPickerDismissTrigger: GridTapPickerDismissTrigger {
        GridTapPickerDismissTrigger(
            isSelecting: isSelecting,
            canMark: browsing.canMark,
            isInDetail: browsing.state.route == .detail,
            selection: browsing.state.selection,
            filter: browsing.state.filter,
            labelFilter: browsing.labelFilter,
            metadataFilter: browsing.metadataFilter,
            hasBatchTargets: !browsing.batchTargets.isEmpty,
            hasMoveSheet: activeSheet?.isMove == true,
            hasRenameFlow: renameFlow != nil,
            hasKeywordsSheet: activeSheet?.isKeywords == true,
            hasMetadataFiltersSheet: activeSheet?.isMetadataFilters == true,
            hasPendingPhotosAlert: pendingPhotosConfirmationPlan != nil
                || activeSheet?.isPhotosConfirmation == true
                || showsNoEligiblePhotosAlert,
            showsFilters: filterHandoff.showsFilters,
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            isLandscapeContainer: isLandscapeContainer)
    }
}

private struct ToolbarTitleBoundingLayout: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(.unspecified)
        let targetWidth = min(ideal.width, maxWidth)
        let fitted = child.sizeThatFits(
            ProposedViewSize(width: targetWidth, height: proposal.height))
        return CGSize(width: max(targetWidth, fitted.width), height: fitted.height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard let child = subviews.first else { return }
        child.place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

private struct GridFilterDismissTrigger: Equatable {
    let route: BrowserRoute
    let folder: FolderIdentity?
    let isRegular: Bool
    let isSelecting: Bool
    let isDuoExpanded: Bool
    let isDuoCover: Bool
    let usesVerticalToolbar: Bool
    let hasFoldRegion: Bool
    let isComparing: Bool
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?
    let isLandscapeContainer: Bool
}

private struct GridTapPickerDismissTrigger: Equatable {
    let isSelecting: Bool
    let canMark: Bool
    let isInDetail: Bool
    let selection: Set<PhotoIdentity>
    let filter: PhotoFilter
    let labelFilter: LabelColour?
    let metadataFilter: PhotoMetadataFilter
    let hasBatchTargets: Bool
    let hasMoveSheet: Bool
    let hasRenameFlow: Bool
    let hasKeywordsSheet: Bool
    let hasMetadataFiltersSheet: Bool
    let hasPendingPhotosAlert: Bool
    let showsFilters: Bool
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?
    let isLandscapeContainer: Bool
}
