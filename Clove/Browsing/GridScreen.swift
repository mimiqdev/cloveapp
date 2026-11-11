import CloveCore
import SwiftUI

/// The handoff's iPhone grid: compact navigation, stacked groups and a floating batch capsule.
/// Marks and navigation still go through BrowsingModel; this view owns only presentation.
struct GridScreen: View {
    let browsing: BrowsingModel
    let thumbnails: any GridThumbnailSource

    @Environment(SettingsStore.self) private var store
    @State private var moveSheet: MoveSheetRoute?
    @State private var isPickingEmptyFolder = false
    @State private var showsFilters = false
    @State private var selectsEmpty = false

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

    private var cells: [GridCellItem] {
        GridDisplay(
            photos: browsing.photos, groups: browsing.groups,
            groupsEnabled: store.settings.similarGroupsEnabled && browsing.readingProgress == nil,
            display: store.settings.gridGroupDisplay
        ).cells
    }

    var body: some View {
        VStack(spacing: 0) {
            header
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
                    openPhoto: { browsing.openPhoto($0) }, openGroup: openGroup,
                    beginSelection: { browsing.beginSelection(of: $0) },
                    toggleSelection: { browsing.toggleSelection(of: $0) }
                )
                .opacity(browsing.folderLocationLoss == nil ? 1 : 0.35)
            }
        }
        .background(Color.clove.bg.canvas)
        .overlay(alignment: .bottomTrailing) {
            if store.settings.moveRejectsEnabled, browsing.rejectedPhotoCount > 0,
                !browsing.isFolderOpening, !browsing.isMovingRejects, !isSelecting
            {
                MoveRejectsButton(identifier: "clove.grid.moveRejects") {
                    moveSheet = .flow(MoveRejectsFlow(browsing: browsing))
                }
                .padding(16)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting {
                GridBatchBar(browsing: browsing, cells: cells)
                    .disabled(!browsing.canMark)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if browsing.isSaveFailureToastVisible {
                Toast(
                    message: BrowsingModel.saveFailureToastMessage,
                    identifier: "clove.save.toast"
                )
                .padding(.horizontal)
                .padding(.bottom, 12)
            } else if let completed = browsing.lastRejectMove, browsing.isRejectMoveToastVisible {
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
        .accessibilityIdentifier("clove.grid")
    }

    private var header: some View {
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
            if isSelecting {
                Menu {
                    Button("Select all") { browsing.selectAllVisible(cells) }
                        .accessibilityIdentifier("clove.grid.batch.selectAll")
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Color.clove.text.primary)
                        .frame(width: 44, height: 44)
                        .cloveGlass(in: Circle())
                }
                .accessibilityLabel("Selection options")
                .accessibilityIdentifier("clove.grid.selectionOptions")
                Button("Done") {
                    browsing.clearSelection()
                    selectsEmpty = false
                }
                .foregroundStyle(Color.clove.accent)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .cloveGlass(in: Capsule())
                .accessibilityIdentifier("clove.grid.batch.done")
            } else {
                GlassIconButton(
                    label: "Filter", symbol: "line.3.horizontal.decrease", isActive: hasFilter,
                    identifier: "clove.grid.filter"
                ) { showsFilters.toggle() }
                .popover(isPresented: $showsFilters, arrowEdge: .top) {
                    filterMenu.presentationCompactAdaptation(.popover)
                }
                moreMenu
            }
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
            Button("Select") { selectsEmpty = true }
                .accessibilityIdentifier("clove.grid.select")
            if store.settings.similarGroupsEnabled {
                Button("Find similar shots again") { Task { await browsing.runGroupingAgain() } }
                    .accessibilityIdentifier("clove.grid.grouping.runAgain")
            }
            Section {
                Button("Settings") { browsing.showSettings() }
                    .accessibilityIdentifier("clove.nav.settings")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .foregroundStyle(Color.clove.text.primary)
                .frame(width: 44, height: 44)
                .cloveGlass(in: Circle())
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
                StarRow(rating: minimumRating, identifier: "clove.grid.filter.stars") { rating in
                    browsing.setFilter(rating == .unrated ? .all : .ratedAtLeast(rating))
                    showsFilters = false
                }
                .scaleEffect(0.75, anchor: .trailing)
                .frame(width: 126)
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
                Text(browsing.allPlacedPhotos.filter { filter.matches($0.marks) }.count.formatted())
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
        if let label = browsing.labelFilter { return "\(label.rawValue) · \(count)" }
        switch browsing.state.filter {
        case .all: return "\(count) photos"
        case .unmarked: return "Unmarked · \(count)"
        case .rejected: return "Rejected · \(count)"
        case .ratedAtLeast(let rating): return "Rating ≥ \(rating.starCount ?? 0) · \(count)"
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
        if let first = group.members.first(where: { browsing.shownMarks(for: $0).isUnmarked })
            ?? group.members.first
        {
            browsing.openPhoto(first)
        }
    }
}
