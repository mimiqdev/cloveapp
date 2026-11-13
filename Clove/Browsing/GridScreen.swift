import CloveCore
import SwiftUI

/// The handoff's iPhone grid: compact navigation, stacked groups and a floating batch capsule.
/// Marks and navigation still go through BrowsingModel; this view owns only presentation.
struct GridScreen: View {
    let browsing: BrowsingModel
    let thumbnails: any GridThumbnailSource

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(SettingsStore.self) private var store
    @State private var moveSheet: MoveSheetRoute?
    @State private var renameFlow: BatchRenameFlow?
    @State private var showsRenameDetails = false
    @State private var isPickingEmptyFolder = false
    @State private var showsFilters = false
    @State private var selectsEmpty = false
    @State private var split = DuoSplit.focus
    @Environment(\.isDuoExpanded) private var isDuoExpanded
    @Environment(\.isDuoCover) private var isDuoCover
    @Environment(\.usesSystemBrowsingToolbar) private var usesSystemToolbar

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

    init(browsing: BrowsingModel, thumbnails: (any GridThumbnailSource)? = nil) {
        self.browsing = browsing
        self.thumbnails = thumbnails ?? browsing.thumbnails
    }

    private var isSelecting: Bool { selectsEmpty || browsing.isSelecting }
    private var isRegular: Bool { horizontalSizeClass == .regular && !isDuoExpanded }
    private var usesDock: Bool { isDuoExpanded || isDuoCover }
    private var showsMoveRejects: Bool {
        store.settings.moveRejectsEnabled && browsing.rejectedPhotoCount > 0
            && !browsing.isFolderOpening && !browsing.isMovingRejects && !isSelecting
    }

    private var cells: [GridCellItem] {
        GridDisplay(
            photos: browsing.photos, groups: browsing.groups,
            groupsEnabled: store.settings.similarGroupsEnabled && browsing.readingProgress == nil,
            display: store.settings.gridGroupDisplay
        ).cells
    }

    var body: some View {
        surface
            .background(Color.clove.bg.canvas)
            .onChange(of: browsing.state.route) { _, route in
                if route != .detail { split = .focus }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isRegular, !usesDock, showsMoveRejects {
                    MoveRejectsButton(identifier: "clove.grid.moveRejects") {
                        moveSheet = .flow(MoveRejectsFlow(browsing: browsing))
                    }
                    .padding(16)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting {
                    VStack(spacing: 8) {
                        GridBatchRenameButton(
                            disabled: browsing.batchTargets.isEmpty || !browsing.canMark
                        ) {
                            renameFlow = BatchRenameFlow(browsing: browsing)
                        }
                        GridBatchBar(browsing: browsing, cells: cells)
                            .disabled(!browsing.canMark)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .tapPickerContainer(dismissWhen: tapPickerDismissTrigger)
            .overlay(alignment: .bottom) {
                if !(usesDock && browsing.state.route == .detail),
                    let message = browsing.failureToastMessage
                {
                    Toast(message: message, identifier: "clove.save.toast")
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                } else if let completed = browsing.completedRename, browsing.isRenameToastVisible {
                    BatchRenameToast(completed: completed) { showsRenameDetails = true }
                        .padding(.horizontal).padding(.bottom, 12)
                } else if let completed = browsing.lastRejectMove, browsing.isRejectMoveToastVisible
                {
                    MoveRejectsToast(browsing: browsing, completed: completed) {
                        moveSheet = .details(completed)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
            .task(id: browsing.rejectMoveToastAttempt) {
                guard browsing.isRejectMoveToastVisible, !TestLibrary.keepsMoveToast else { return }
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                browsing.dismissRejectMoveToast()
            }
            .task(id: browsing.renameToastAttempt) {
                guard browsing.isRenameToastVisible, !TestLibrary.keepsMoveToast else { return }
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                browsing.dismissRenameToast()
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
                        split: $split, grid: AnyView(duoLeftPane), filter: AnyView(filterButton),
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
                                Text(
                                    isSelecting
                                        ? "\(browsing.state.selection.count.formatted()) selected"
                                        : (isRegular ? browsing.filterTitle : browsing.folderTitle)
                                )
                                .font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier(
                                    isSelecting ? "clove.grid.batch.count" : "clove.grid.title")
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

    /// The expanded Duo's left pane: while the photo on screen belongs to a group, its
    /// members fill the pane with the current one ringed, so the person can compare and
    /// pick members without closing the preview (#198). Anything else keeps the folder
    /// grid, and Back or navigating out of the group returns to it with its position.
    @ViewBuilder private var duoLeftPane: some View {
        let members = duoGroupMembers
        if members.isEmpty {
            grid
        } else {
            GridCollectionView(
                items: GridDisplay(photos: members, groups: [], groupsEnabled: false).cells,
                currentPhoto: browsing.state.currentPhoto,
                groups: [], shownPhotos: Set(members.map(\.id)),
                selection: [], thumbnails: thumbnails,
                columnCount: 2, highlightsCurrentPhoto: true,
                openPhoto: { browsing.openPhoto($0) },
                // Browsing only: selection and group stacks belong to the folder grid.
                openGroup: { _ in },
                beginSelection: { _ in }, toggleSelection: { _ in }
            )
            .background(Color.clove.bg.canvas)
            .ignoresSafeArea(.container, edges: .bottom)
            .accessibilityIdentifier("clove.duo.groupMembers")
        }
    }

    /// The shown members of the current photo's group, in the grid's order and filter.
    private var duoGroupMembers: [GridPhoto] {
        guard isDuoExpanded, browsing.state.route == .detail,
            let group = browsing.currentGroup
        else { return [] }
        let members = Set(group.members)
        return browsing.photos.filter { members.contains($0.id) }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            if !usesSystemToolbar { header }
            if let progress = browsing.readingProgress {
                ProgressLine(
                    progress: progress.total > 0
                        ? Double(progress.read) / Double(progress.total) : 0)
            } else if browsing.isFindingSimilarShots, store.settings.similarGroupsEnabled {
                ProgressLine(progress: 1, tone: .grouping)
            }
            FolderSaveBanner(browsing: browsing, identifierPrefix: "clove.grid.saveState.failure")
            if cells.isEmpty && !browsing.isFolderOpening {
                emptyState
            } else {
                GridCollectionView(
                    items: cells, currentPhoto: browsing.state.currentPhoto,
                    groups: browsing.groups, shownPhotos: Set(browsing.photos.map(\.id)),
                    selection: browsing.state.selection, thumbnails: thumbnails,
                    isSelectingEmpty: selectsEmpty,
                    placeholderCount: browsing.readingProgress.map {
                        $0.total == 0 ? 9 : max($0.total - $0.read, 0)
                    } ?? 0,
                    columnCount: isDuoExpanded ? (browsing.state.route == .detail ? 2 : 6) : nil,
                    openPhoto: { browsing.openPhoto($0) }, openGroup: openGroup,
                    beginSelection: { browsing.beginSelection(of: $0) },
                    toggleSelection: { browsing.toggleSelection(of: $0) }
                )
                .opacity(browsing.folderLocationLoss == nil ? 1 : 0.35)
            }
        }
        .background(Color.clove.bg.canvas)
        .ignoresSafeArea(.container, edges: usesDock ? .bottom : [])
    }

    private var dockBottom: some View {
        Group {
            if showsMoveRejects {
                Button("Move rejects", systemImage: "tray.and.arrow.down") {
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
                            ? "\(browsing.state.selection.count.formatted()) selected"
                            : browsing.filterTitle
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
                ? "\(browsing.state.selection.count.formatted()) selected" : browsing.folderTitle,
            titleIdentifier: isSelecting ? "clove.grid.batch.count" : "clove.grid.title",
            back: { browsing.back() }
        ) {
            HStack(spacing: 0) {
                Text(subtitle).lineLimit(1)
                SaveStatusIndicator(
                    browsing: browsing, identifierPrefix: "clove.grid.saveState")
            }
        } tools: {
            headerTools
        }
    }

    @ViewBuilder private var headerTools: some View {
        if isSelecting && usesSystemToolbar {
            Menu {
                Button("Select all") { browsing.selectAllVisible(cells) }
                    .accessibilityIdentifier("clove.grid.batch.selectAll")
            } label: {
                Label("Selection options", systemImage: "ellipsis")
            }
            .accessibilityIdentifier("clove.grid.selectionOptions")
            Button("Done", systemImage: "checkmark") {
                browsing.clearSelection()
                selectsEmpty = false
            }
            .accessibilityIdentifier("clove.grid.batch.done")
        } else if isSelecting {
            Menu {
                Button("Select all") { browsing.selectAllVisible(cells) }
                    .accessibilityIdentifier("clove.grid.batch.selectAll")
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color.clove.text.primary)
                    .frame(width: isRegular ? 40 : 44, height: isRegular ? 40 : 44)
                    .cloveGlass(in: Circle())
            }
            .accessibilityLabel("Selection options")
            .accessibilityIdentifier("clove.grid.selectionOptions")
            Button {
                browsing.clearSelection()
                selectsEmpty = false
            } label: {
                Text("Done")
            }
            .accessibilityLabel("Done")
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
                            label: "Move rejects", symbol: "tray.and.arrow.down", size: .pad,
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
                Button("Filter", systemImage: "line.3.horizontal.decrease") {
                    showsFilters.toggle()
                }
                .tint(hasFilter ? Color.clove.accent : Color.clove.text.primary)
                .accessibilityIdentifier("clove.grid.filter")
            } else {
                GlassIconButton(
                    label: "Filter", symbol: "line.3.horizontal.decrease", isActive: hasFilter,
                    size: isRegular ? .pad : .phone, identifier: "clove.grid.filter"
                ) { showsFilters.toggle() }
            }
        }
        .popover(isPresented: $showsFilters) {
            filterMenu.presentationCompactAdaptation(.popover)
        }
    }

    private var moreMenu: some View {
        Menu {
            Section("Sort by") {
                Button {
                    browsing.setOrder(.captureTime)
                } label: {
                    Label(
                        "Capture time",
                        systemImage: browsing.state.order == .captureTime ? "checkmark" : "")
                }
                .accessibilityIdentifier("clove.grid.order.captureTime")
                Button {
                    browsing.setOrder(.fileName)
                } label: {
                    Label(
                        "Filename",
                        systemImage: browsing.state.order == .fileName ? "checkmark" : "")
                }
                .accessibilityIdentifier("clove.grid.order.fileName")
            }
            Button("Select") {
                if usesDock && browsing.state.route == .detail { browsing.back() }
                selectsEmpty = true
            }
            .accessibilityIdentifier("clove.grid.select")
            if !isRegular, store.settings.similarGroupsEnabled {
                Button("Find similar shots again") { Task { await browsing.runGroupingAgain() } }
                    .accessibilityIdentifier("clove.grid.grouping.runAgain")
            }
            Section {
                Button("Settings") { browsing.showSettings() }
                    .accessibilityIdentifier("clove.nav.settings")
            }
        } label: {
            if usesSystemToolbar {
                Label("More", systemImage: "ellipsis")
            } else {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundStyle(Color.clove.text.primary)
                    .frame(width: isRegular ? 40 : 44, height: isRegular ? 40 : 44)
                    .cloveGlass(in: Circle())
            }
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("clove.grid.more")
    }

    private var filterMenu: some View {
        VStack(spacing: 0) {
            filterRow("All", filter: .all, identifier: "all")
            filterRow("Unmarked", filter: .unmarked, identifier: "unmarked")
            filterRow("Rejected", filter: .rejected, identifier: "rejected")
            Divider().overlay(Color.clove.separator)
            HStack {
                Text("Rating ≥")
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
                Text("Label")
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
                    .accessibilityLabel("Label, \(label.rawValue)")
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
                    }.count.formatted()
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
        if isSelecting { return browsing.folderTitle }
        if let progress = browsing.readingProgress {
            return progress.total == 0
                ? "Reading photos…"
                : "\(progress.read.formatted()) of \(progress.total.formatted())"
        }
        if browsing.isFindingSimilarShots, store.settings.similarGroupsEnabled {
            return "Finding similar shots…"
        }
        let count = browsing.photos.count.formatted()
        if isRegular { return "\(count) photos" }
        if let label = browsing.labelFilter { return "\(label.rawValue) · \(count)" }
        switch browsing.state.filter {
        case .all: return "\(count) photos"
        case .unmarked: return "Unmarked · \(count)"
        case .rejected: return "Rejected · \(count)"
        case .ratedAtLeast(let rating): return "Rating ≥ \(rating.starCount ?? 0) · \(count)"
        case .subfolder(let path): return "\(path) · \(count)"
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !browsing.hasFolderContents && !browsing.isFolderOpening {
            EntryEmptyState(isEmptyFolder: true) { isPickingEmptyFolder = true }
                .accessibilityIdentifier("clove.grid.empty")
        } else {
            ContentUnavailableView {
                Label("No photos", systemImage: "photo.on.rectangle")
            } description: {
                Text(browsing.isFolderOpening ? "Reading photos…" : "No photos match this filter.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("clove.grid.empty")
        }
    }

    private func openGroup(_ id: GroupID) {
        guard let group = browsing.groups.first(where: { $0.id == id }) else { return }
        let visible = group.visible(in: Set(browsing.photos.map(\.id)))
        if let first = visible.members.first(where: { browsing.shownMarks(for: $0).isUnmarked })
            ?? visible.members.first
        {
            browsing.openPhoto(first)
        }
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
            showsFilters: showsFilters)
    }
}

private struct GridBatchRenameButton: View {
    let disabled: Bool
    let action: () -> Void
    @Environment(\.tapPickerController) private var tapPicker

    var body: some View {
        let obscured = tapPicker?.isPresented == true
        Button(action: action) {
            Text("Rename…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.clove.accent)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .cloveGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(obscured ? 0 : 1)
        .allowsHitTesting(!obscured)
        .accessibilityHidden(obscured)
        .accessibilityIdentifier("clove.grid.batch.rename")
    }
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
}
