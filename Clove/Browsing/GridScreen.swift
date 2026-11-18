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
    @State private var showsRenameDetails = false
    @State private var isPickingEmptyFolder = false
    @State private var showsFilters = false
    @State private var isFilterAnchorReady = false
    @State private var selectsEmpty = false
    @State private var isLandscapeContainer = false
    @State private var containerWidth: CGFloat = 0
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
    private var usesHorizontalBatchBar: Bool {
        isOrdinaryPhoneLandscape || isRegular || containerWidth >= 500
    }
    private var usesDock: Bool { isDuoExpanded || isDuoCover }
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
        if browsing.completedRename != nil, browsing.isRenameToastVisible {
            return "rename-\(browsing.renameToastAttempt)"
        }
        if browsing.lastRejectMove != nil, browsing.isRejectMoveToastVisible {
            return "rejectMove-\(browsing.rejectMoveToastAttempt)"
        }
        return nil
    }

    private var gridProgressLine: (progress: Double?, tone: ProgressLine.Tone) {
        if let progress = browsing.readingProgress {
            let value = progress.total > 0 ? Double(progress.read) / Double(progress.total) : 0
            return (value, .reading)
        }
        if browsing.isFindingSimilarShots, store.settings.similarGroupsEnabled {
            return (1, .grouping)
        }
        return (nil, .reading)
    }

    private var cells: [GridCellItem] { gridDisplay.cells }

    /// How the grid joins the folder and its groups.
    private var gridDisplay: GridDisplay {
        GridDisplay(
            photos: browsing.photos, groups: browsing.groups,
            groupsEnabled: store.settings.similarGroupsEnabled && browsing.readingProgress == nil)
    }

    var body: some View {
        surface
            .background(Color.clove.bg.canvas)
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: { size in
                isLandscapeContainer = size.width > size.height && size.width > 0
                containerWidth = size.width
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
                if isSelecting {
                    let renameButton = GridBatchRenameButton(
                        disabled: browsing.batchTargets.isEmpty || !browsing.canMark
                    ) {
                        renameFlow = BatchRenameFlow(browsing: browsing)
                    }
                    let batchBar = GridBatchBar(browsing: browsing, cells: cells) {
                        selectsEmpty = true
                    }
                    .disabled(!browsing.canMark)
                    Group {
                        if usesHorizontalBatchBar {
                            HStack(spacing: 8) {
                                batchBar
                                renameButton
                            }
                        } else {
                            VStack(spacing: 8) {
                                renameButton
                                batchBar
                            }
                        }
                    }
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
            .sheet(item: $moveSheet) { route in
                switch route {
                case .flow(let flow): MoveRejectsSheet(flow: flow)
                case .details(let completed):
                    MoveRejectsDetailsSheet(browsing: browsing, completed: completed)
                }
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
                            canUndo: browsing.canUndoMark, showsBack: !isRegular,
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
                                                Int64(browsing.state.selection.count))
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
                                    Text(subtitle)
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
                    keepSelectingWhenEmpty: { selectsEmpty = true }
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
                                Int64(browsing.state.selection.count))
                            : browsing.localizedFilterTitle(language: language)
                    )
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier(
                        isSelecting ? "clove.grid.batch.count" : "clove.grid.title")
                    HStack(spacing: 0) {
                        Text(subtitle).lineLimit(1)
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
                    "%lld selected", language: language, Int64(browsing.state.selection.count))
                : browsing.localizedFolderTitle(language: language),
            titleIdentifier: isSelecting ? "clove.grid.batch.count" : "clove.grid.title",
            usesInlineFlow: isOrdinaryPhoneLandscape,
            height: isOrdinaryPhoneLandscape ? 54 : 64,
            back: { browsing.back() }
        ) {
            HStack(spacing: 0) {
                Text(subtitle).lineLimit(1)
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
        let batchSelection = BatchSelection(
            groups: browsing.groups, selection: browsing.state.selection)
        if !batchSelection.showsAllSelected(cells) {
            Button(AppLocalization.string("Select all", language: language)) {
                browsing.selectAllVisible(cells)
            }
            .accessibilityIdentifier("clove.grid.batch.selectAll")
        }
        if !browsing.state.selection.isEmpty {
            Button(AppLocalization.string("Deselect all", language: language)) {
                selectsEmpty = true
                browsing.deselectAllVisible(cells)
            }
            .accessibilityIdentifier("clove.grid.batch.deselectAll")
        }
    }

    @ViewBuilder private var headerTools: some View {
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
            Button {
                browsing.clearSelection()
                selectsEmpty = false
            } label: {
                Text(AppLocalization.string("Done", language: language))
            }
            .accessibilityLabel(AppLocalization.string("Done", language: language))
            .foregroundStyle(Color.clove.accent)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .cloveGlass(in: Capsule())
            .accessibilityIdentifier("clove.grid.batch.done")
        } else {
            if isRegular {
                if showsMoveRejects {
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
            } else {
                filterButton
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
            isFilterAnchorReady = true
        }
        .onDisappear {
            isFilterAnchorReady = false
            showsFilters = false
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

    private var hasFilter: Bool { browsing.state.filter != .all || browsing.labelFilter != nil }

    private var subtitle: String {
        if isSelecting { return browsing.localizedFolderTitle(language: language) }
        if let progress = browsing.readingProgress {
            return progress.total == 0
                ? AppLocalization.string("Reading photos…", language: language)
                : AppLocalization.format(
                    "%lld of %lld", language: language, Int64(progress.read),
                    Int64(progress.total))
        }
        if browsing.isFindingSimilarShots, store.settings.similarGroupsEnabled {
            return AppLocalization.string("Finding similar shots…", language: language)
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("clove.grid.empty")
        }
    }

    /// Opens one collapsed group in Group Focus on its Representative Photo.
    private func openGroup(_ id: GroupID) {
        browsing.openGroup(id)
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
            hasBatchTargets: !browsing.batchTargets.isEmpty,
            hasMoveSheet: moveSheet != nil,
            hasRenameFlow: renameFlow != nil,
            showsFilters: showsFilters,
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            isLandscapeContainer: isLandscapeContainer)
    }
}

private struct GridBatchRenameButton: View {
    let disabled: Bool
    let action: () -> Void
    @Environment(\.tapPickerController) private var tapPicker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language

    var body: some View {
        let obscured = tapPicker?.isPresented == true
        Button(action: action) {
            Text(AppLocalization.string("Rename…", language: language))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.clove.accent)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .cloveGlass(in: Capsule())
        }
        .buttonStyle(.cloveGlassPress)
        .disabled(disabled)
        .opacity(obscured ? 0 : 1)
        .animation(CloveMotion.micro(reduceMotion: reduceMotion), value: obscured)
        .allowsHitTesting(!obscured)
        .accessibilityHidden(obscured)
        .accessibilityIdentifier("clove.grid.batch.rename")
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
    let hasBatchTargets: Bool
    let hasMoveSheet: Bool
    let hasRenameFlow: Bool
    let showsFilters: Bool
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?
    let isLandscapeContainer: Bool
}
