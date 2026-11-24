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
    @State private var moveSheet: MoveSheetRoute?
    @State private var renameFlow: BatchRenameFlow?
    @State private var showsKeywordsSheet = false
    @State private var showsRenameDetails = false
    @State private var pendingPhotosConfirmationPlan: PhotosSavePlan?
    @State private var showsNoEligiblePhotosAlert = false
    @State private var isPickingEmptyFolder = false
    @State private var showsFilters = false
    @State private var showsMetadataFilters = false
    @State private var filterAnchorAttachments = 0
    @State private var selectsEmpty = false
    @State private var areGroupsUnfolded: Bool
    private var isFilterAnchorReady: Bool { filterAnchorAttachments > 0 }
    @State private var isLandscapeContainer = false
    @State private var containerSize: CGSize = .zero
    @State private var presentation = DetailPresentation.photoPreview
    /// Whether this session opened a photo, so the Duo's grid reopens at the photo on screen
    /// after Back instead of the folder's first row (#225). A launch that restores a photo keeps
    /// the grid where it opens today.
    @State private var hasOpenedPhoto = false
    @Environment(\.isDuoExpanded) private var isDuoExpanded
    @Environment(\.isDuoCover) private var isDuoCover
    @Environment(\.usesSystemBrowsingToolbar) private var usesSystemToolbar
    @Environment(\.usesVerticalBrowsingToolbar) private var usesVerticalToolbar
    @Environment(\.hasFoldRegion) private var hasFoldRegion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var filterPopoverTrigger: Int = 0

    private enum MoveSheetRoute: Identifiable {
        case flow(MoveRejectsFlow)
        case details(CompletedRejectMove)

        var id: String {
            switch self {
            case .flow(let flow): "flow-\(flow.id)"
            case .details(let completed): "details-\(completed.id)"
            }
        }
    }

    init(
        browsing: BrowsingModel,
        thumbnails: (any GridThumbnailSource)? = nil,
        filterPopoverTrigger: Int = 0,
        initialPresentation: DetailPresentation = .photoPreview
    ) {
        self.browsing = browsing
        self.thumbnails = thumbnails ?? browsing.thumbnails
        self.filterPopoverTrigger = filterPopoverTrigger
        _presentation = State(initialValue: initialPresentation)
        _areGroupsUnfolded = State(initialValue: browsing.isSelecting)
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
        if let progress = browsing.readingProgress {
            let value = progress.total > 0 ? Double(progress.read) / Double(progress.total) : 0
            return (value, .reading)
        }
        if browsing.isFindingSimilarShots, similarGroupsEnabled,
            browsing.preparationStatus.waitingReason == nil
        {
            return (1, .grouping)
        }
        return (nil, .reading)
    }

    private var cells: [GridCellItem] { gridDisplay.cells }

    /// How the grid joins the folder and its groups.
    private var gridDisplay: GridDisplay {
        GridDisplay(
            photos: browsing.photos, groups: browsing.groups,
            groupsEnabled: store.settings.similarGroupsEnabled && browsing.readingProgress == nil,
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
            .onChange(of: browsing.state.folder) { _, _ in
                selectsEmpty = false
                areGroupsUnfolded = browsing.isSelecting
                pendingPhotosConfirmationPlan = nil
                showsNoEligiblePhotosAlert = false
                showsMetadataFilters = false
            }
            .onChange(of: browsing.folderLocationLoss != nil) { _, isLost in
                if isLost {
                    pendingPhotosConfirmationPlan = nil
                    showsNoEligiblePhotosAlert = false
                }
            }
            .onChange(of: browsing.state.route) { _, route in
                if route == .detail { hasOpenedPhoto = true }
                if route != .detail {
                    presentation = .photoPreview
                }
            }
            .onChange(of: filterPopoverTrigger) { _, _ in
                if isFilterAnchorReady, scenePhase == .active {
                    showsFilters = true
                }
            }
            .onChange(of: filterDismissTrigger) { _, _ in
                showsFilters = false
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    showsFilters = false
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isRegular, !usesDock, showsMoveRejects {
                    MoveRejectsButton(identifier: "clove.grid.moveRejects") {
                        moveSheet = .flow(MoveRejectsFlow(browsing: browsing))
                    }
                    .padding(16)
                    .transition(
                        .asymmetric(
                            insertion: CloveMotion.scaleOpacityTransition(
                                scale: 0.9, anchor: .bottomTrailing, reduceMotion: reduceMotion),
                            removal: .identity))
                }
            }
            .animation(
                (!isRegular && !usesDock && showsMoveRejects)
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
                        onKeywords: { showsKeywordsSheet = true },
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
                    || browsing.readingProgress != nil
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
                    BatchRenameToast(completed: completed) { showsRenameDetails = true }
                        .padding(.horizontal).padding(.bottom, 12)
                        .transition(
                            CloveMotion.slideTransition(
                                edge: .bottom, offset: 12, reduceMotion: reduceMotion))
                } else if let completed = browsing.lastRejectMove, browsing.isRejectMoveToastVisible
                {
                    MoveRejectsToast(browsing: browsing, completed: completed) {
                        moveSheet = .details(completed)
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
            .sheet(isPresented: $showsRenameDetails) {
                if let completed = browsing.completedRename {
                    BatchRenameDetailsSheet(completed: completed)
                }
            }
            .sheet(isPresented: $showsKeywordsSheet) {
                BatchKeywordsSheet(browsing: browsing)
            }
            .sheet(isPresented: $showsMetadataFilters) {
                MetadataFilterSheet(browsing: browsing)
            }
            .sheet(item: $moveSheet) { route in
                switch route {
                case .flow(let flow): MoveRejectsSheet(flow: flow)
                case .details(let completed):
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
                usesDock && browsing.state.route == .detail ? "clove.detail" : "clove.grid")
    }

    @ViewBuilder private var surface: some View {
        if usesSystemToolbar, #available(iOS 27.1, *) {
            if usesDock && browsing.state.route == .detail {
                DetailScreen(
                    browsing: browsing,
                    duo: DuoDetailLayout(
                        presentation: $presentation, filter: AnyView(filterButton),
                        more: AnyView(moreMenu), bottom: AnyView(dockBottom),
                        showsGrid: isDuoExpanded))
            } else {
                grid
                    .toolbar {
                        BrowsingToolbar(
                            back: { browsing.back() }, undo: { browsing.undoLastMark() },
                            canUndo: browsing.canUndoMark,
                            showsBack: !isRegular && (usesDock || !isSelecting),
                            showsUndo: usesDock
                        ) {
                            headerTools
                        } marks: {
                            Optional<ToolbarItem<Void, EmptyView>>.none
                        } bottom: {
                            if usesDock { dockBottom }
                        }
                        ToolbarItem(placement: .principal) {
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
                                            .minimumScaleFactor(0.85)
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
                        .axisBehavior(.horizontalOnly)
                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarVerticalBehavior(.automatic)
                    .toolbarVerticalCompressionBehavior(.prefersToolbarItems)
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            if !usesSystemToolbar { header }
            ProgressLine(progress: gridProgressLine.progress, tone: gridProgressLine.tone)
            FolderSaveBanner(browsing: browsing, identifierPrefix: "clove.grid.saveState.failure")
            if !browsing.metadataFilter.isEmpty {
                ActiveMetadataFilterBar(
                    browsing: browsing,
                    onEdit: isRegular ? nil : { showsMetadataFilters = true })
            }
            if cells.isEmpty && !browsing.isFolderOpening {
                emptyState
            } else {
                GridCollectionView(
                    sections: gridDisplay.sections, currentPhoto: browsing.state.currentPhoto,
                    groups: browsing.groups, shownPhotos: Set(browsing.photos.map(\.id)),
                    selection: browsing.state.selection,
                    thumbnails: thumbnails,
                    isSelectingEmpty: selectsEmpty,
                    placeholderCount: browsing.readingProgress.map {
                        $0.total == 0 ? 9 : max($0.total - $0.read, 0)
                    } ?? 0,
                    columnCount: isDuoExpanded ? 6 : nil,
                    highlightsCurrentPhoto: false,
                    followsCurrentPhoto: isDuoExpanded && hasOpenedPhoto,
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
        .background(Color.clove.bg.canvas)
        .ignoresSafeArea(.container, edges: usesDock ? .bottom : [])
    }

    private var dockBottom: some View {
        Group {
            if showsMoveRejects {
                Button(
                    AppLocalization.string("Move rejects", language: language),
                    systemImage: "tray.and.arrow.down"
                ) {
                    moveSheet = .flow(MoveRejectsFlow(browsing: browsing))
                }
                .accessibilityIdentifier("clove.grid.moveRejects")
            }
        }
    }

    @ViewBuilder private var header: some View {
        if isRegular {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(
                        isSelecting
                            ? AppLocalization.format(
                                "%lld selected", language: language,
                                Int64(browsing.batchTargets.count))
                            : browsing.localizedFilterTitle(language: language)
                    )
                    .font(.subheadline.weight(.semibold))
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
                                .minimumScaleFactor(0.85)
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
            height: isOrdinaryPhoneLandscape ? 54 : 64,
            back: { browsing.back() }
        ) {
            HStack(spacing: 0) {
                if let hiddenSelectedSubtitle {
                    Text(hiddenSelectedSubtitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
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
        } tools: {
            headerTools
        }
    }

    @ViewBuilder private var selectionOptionsMenuItems: some View {
        if !browsing.showsAllVisibleSelected {
            Button(AppLocalization.string("Select all", language: language)) {
                completeGroupUnfoldImmediately()
                browsing.selectAllVisible()
            }
            .accessibilityIdentifier("clove.grid.batch.selectAll")
        }
        if !browsing.batchTargets.isEmpty {
            Button(AppLocalization.string("Deselect all", language: language)) {
                selectsEmpty = true
                browsing.deselectAllVisible()
            }
            .accessibilityIdentifier("clove.grid.batch.deselectAll")
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
            Menu {
                selectionOptionsMenuItems
            } label: {
                Label(
                    AppLocalization.string("Selection options", language: language),
                    systemImage: "ellipsis")
            }
            .accessibilityIdentifier("clove.grid.selectionOptions")
            Button(
                AppLocalization.string("Done", language: language),
                systemImage: "checkmark"
            ) {
                browsing.clearSelection()
                selectsEmpty = false
            }
            .accessibilityIdentifier("clove.grid.batch.done")
        } else if isSelecting {
            Menu {
                selectionOptionsMenuItems
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color.clove.text.primary)
                    .frame(width: isRegular ? 40 : 44, height: isRegular ? 40 : 44)
                    .cloveGlass(in: Circle())
            }
            .accessibilityLabel(AppLocalization.string("Selection options", language: language))
            .accessibilityIdentifier("clove.grid.selectionOptions")
            .reportHeaderControlFrame("clove.grid.selectionOptions")
            Button {
                browsing.clearSelection()
                selectsEmpty = false
            } label: {
                Text(AppLocalization.string("Done", language: language))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(Color.clove.accent)
                    .padding(.horizontal, isRegular ? 16 : 14)
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
                    dockBottom
                } else {
                    GlassIconButton(
                        label: AppLocalization.string("Move rejects", language: language),
                        symbol: "tray.and.arrow.down", size: .pad,
                        identifier: "clove.grid.moveRejects"
                    ) {
                        moveSheet = .flow(MoveRejectsFlow(browsing: browsing))
                    }
                }
            }
            moreMenu
        }
    }

    private var filterButton: some View {
        Group {
            if usesSystemToolbar {
                Button(
                    AppLocalization.string("Filter", language: language),
                    systemImage: "line.3.horizontal.decrease"
                ) {
                    showsFilters.toggle()
                }
                .tint(hasFilter ? Color.clove.accent : Color.clove.text.primary)
                .accessibilityIdentifier("clove.grid.filter")
            } else {
                GlassIconButton(
                    label: AppLocalization.string("Filter", language: language),
                    symbol: "line.3.horizontal.decrease", isActive: hasFilter,
                    size: isRegular ? .pad : .phone, identifier: "clove.grid.filter"
                ) { showsFilters.toggle() }
            }
        }
        .popover(
            isPresented: Binding(
                get: { showsFilters && isFilterAnchorReady && scenePhase == .active },
                set: { showsFilters = $0 })
        ) {
            filterMenu.presentationCompactAdaptation(.popover)
        }
        .onAppear {
            filterAnchorAttachments += 1
        }
        .onDisappear {
            filterAnchorAttachments = max(0, filterAnchorAttachments - 1)
            if filterAnchorAttachments == 0 {
                showsFilters = false
            }
        }
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

    private var filterMenu: some View {
        VStack(spacing: 0) {
            filterRow(
                AppLocalization.string("All", language: language), filter: .all, identifier: "all")
            filterRow(
                AppLocalization.string("Unmarked", language: language), filter: .unmarked,
                identifier: "unmarked")
            filterRow(
                AppLocalization.string("Rejected", language: language), filter: .rejected,
                identifier: "rejected")
            Divider().overlay(Color.clove.separator)
            HStack {
                Text(AppLocalization.string("Rating ≥", language: language))
                Spacer()
                FilterStarRow(rating: minimumRating, identifier: "clove.grid.filter.stars") {
                    rating in
                    browsing.setFilter(rating == .unrated ? .all : .ratedAtLeast(rating))
                    showsFilters = false
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            HStack(spacing: 12) {
                Text(AppLocalization.string("Label", language: language))
                Spacer()
                ForEach(LabelColour.allCases.filter { !$0.isExtended }, id: \.self) { label in
                    Button {
                        browsing.setLabelFilter(label)
                        showsFilters = false
                    } label: {
                        Circle().fill(Color.clove.label.colour(for: label))
                            .frame(width: 16, height: 16)
                            .frame(height: 32)
                    }
                    .accessibilityLabel(
                        AppLocalization.format(
                            "Label, %@", language: language,
                            AppLocalization.colourName(label, language: language))
                    )
                    .accessibilityIdentifier(
                        "clove.grid.filter.label.\(label.rawValue.lowercased())")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            if browsing.metadataFilterOptions.hasAnyDimension || !browsing.metadataFilter.isEmpty {
                Divider().overlay(Color.clove.separator)
                Button {
                    showsFilters = false
                    showsMetadataFilters = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 16)
                            .foregroundStyle(
                                browsing.metadataFilter.isEmpty
                                    ? Color.clove.text.secondary : Color.clove.accent)
                        Text(AppLocalization.string("More filters", language: language))
                        Spacer()
                        if !browsing.metadataFilter.isEmpty {
                            Text(
                                browsing.metadataFilter.activeCount.formatted(
                                    .number.locale(language.locale))
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.clove.accent, in: Capsule())
                            .accessibilityIdentifier("clove.grid.filter.more.badge")
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.clove.text.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clove.grid.filter.more")
            }
        }
        .font(.subheadline)
        .foregroundStyle(Color.clove.text.primary)
        .frame(width: 280)
        .background(Color.clove.surface.sheet)
    }

    private func filterRow(_ name: String, filter: PhotoFilter, identifier: String) -> some View {
        Button {
            browsing.setFilter(filter)
            showsFilters = false
        } label: {
            HStack {
                Image(systemName: "checkmark")
                    .opacity(browsing.state.filter == filter && browsing.labelFilter == nil ? 1 : 0)
                    .frame(width: 16)
                Text(name)
                Spacer()
                Text(
                    browsing.allPlacedPhotos.filter {
                        filter.matches($0.marks, relativeFolderPath: $0.id.relativeFolderPath)
                    }.count.formatted(.number.locale(language.locale))
                )
                .foregroundStyle(Color.clove.text.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("clove.grid.filter.\(identifier)")
    }

    private var minimumRating: Rating {
        if case .ratedAtLeast(let rating) = browsing.state.filter { return rating }
        return .unrated
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
        if let progress = browsing.readingProgress {
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
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            isLandscapeContainer: isLandscapeContainer)
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
            hasMoveSheet: moveSheet != nil,
            hasRenameFlow: renameFlow != nil,
            hasKeywordsSheet: showsKeywordsSheet,
            hasMetadataFiltersSheet: showsMetadataFilters,
            hasPendingPhotosAlert: pendingPhotosConfirmationPlan != nil
                || showsNoEligiblePhotosAlert,
            showsFilters: showsFilters,
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            isLandscapeContainer: isLandscapeContainer)
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
