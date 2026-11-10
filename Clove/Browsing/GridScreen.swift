import CloveCore
import SwiftUI

/// The grid: the open folder's photos in the state's order and filter (PRD Grid, P0-03).
///
/// A `UICollectionView` draws the cells, their overlays, the similar-group outlines and counts,
/// and the collapsed covers, while the browsing state keeps the filter and the order per scene
/// (PRD P0-03, P0-11, P0-14). The filter and order menus change the state through
/// ``BrowsingModel`` only, so a fold, a resize or a relaunch restores them.
///
/// A long press starts multi-select on a cell, a tap toggles a cell while the selection is
/// non-empty, and the batch bar applies a rating, a label or Reject to the selected photos
/// (PRD P0-09). The selection itself lives in ``BrowsingState/selection``, so folding, resizing or
/// relaunching keeps it with the rest of the scene (PRD P0-14).
///
/// Design placeholder: system menus, symbols and colours stand in for the visual design's
/// controls and overlays.
struct GridScreen: View {
    /// The scene's browsing state and the operations this screen performs on it.
    let browsing: BrowsingModel

    /// The app-wide settings, read live so a change on the settings screen shows here at once
    /// (PRD Grid, Similar groups).
    @Environment(SettingsStore.self) private var store

    /// The thumbnails the cells draw (PRD P0-03).
    ///
    /// The browsing model supplies the open folder's source, so opening another folder brings a
    /// source bound to that folder and no screen reaches into the folder library itself. A caller
    /// can pass its own for a preview.
    let thumbnails: any GridThumbnailSource

    /// Uses the supplied thumbnail source, or the browsing model's source for the open folder.
    init(browsing: BrowsingModel, thumbnails: (any GridThumbnailSource)? = nil) {
        self.browsing = browsing
        self.thumbnails = thumbnails ?? browsing.thumbnails
    }

    var body: some View {
        let photos = browsing.photos
        let cells = GridDisplay(
            photos: photos, groups: browsing.groups,
            groupsEnabled: store.settings.similarGroupsEnabled,
            display: store.settings.gridGroupDisplay
        ).cells
        VStack(spacing: 0) {
            controls
            Divider()
            if cells.isEmpty {
                emptyState
            } else {
                GridCollectionView(
                    items: cells,
                    currentPhoto: browsing.state.currentPhoto,
                    groups: browsing.groups,
                    shownPhotos: Set(photos.map(\.id)),
                    selection: browsing.state.selection,
                    thumbnails: thumbnails,
                    openPhoto: { browsing.openPhoto($0) },
                    openGroup: openGroup,
                    beginSelection: { browsing.beginSelection(of: $0) },
                    toggleSelection: { browsing.toggleSelection(of: $0) })
            }
        }
        .safeAreaInset(edge: .bottom) {
            if browsing.isSelecting {
                GridBatchBar(browsing: browsing, cells: cells)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.grid")
    }

    /// The filter and the order, read from and written to the browsing state (PRD P0-03).
    ///
    /// The grouping menu holds PRD P0-11's Run again and hides with the similar-groups setting,
    /// because turning grouping off hides every grouping entry point (PRD Similar groups rules).
    /// Design placeholder: the visual design replaces the menu, its label and its symbol.
    private var controls: some View {
        HStack(spacing: 16) {
            Menu {
                Button("All") { browsing.setFilter(.all) }
                    .accessibilityIdentifier("clove.grid.filter.all")
                Button("Unmarked") { browsing.setFilter(.unmarked) }
                    .accessibilityIdentifier("clove.grid.filter.unmarked")
                Button("Rejected") { browsing.setFilter(.rejected) }
                    .accessibilityIdentifier("clove.grid.filter.rejected")
                ForEach(1...5, id: \.self) { stars in
                    if let rating = Rating(rawValue: stars) {
                        Button("\(stars) stars or more") {
                            browsing.setFilter(.ratedAtLeast(rating))
                        }
                        .accessibilityIdentifier("clove.grid.filter.stars\(stars)")
                    }
                }
            } label: {
                Label(filterName, systemImage: "line.3.horizontal.decrease")
            }
            .accessibilityIdentifier("clove.grid.filter")

            Spacer()

            Menu {
                Button("Capture time") { browsing.setOrder(.captureTime) }
                    .accessibilityIdentifier("clove.grid.order.captureTime")
                Button("File name") { browsing.setOrder(.fileName) }
                    .accessibilityIdentifier("clove.grid.order.fileName")
            } label: {
                Label(orderName, systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("clove.grid.order")

            if store.settings.similarGroupsEnabled {
                Menu {
                    Button("Run again") { Task { await browsing.runGroupingAgain() } }
                        .accessibilityIdentifier("clove.grid.grouping.runAgain")
                } label: {
                    Label("Similar groups", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("clove.grid.grouping")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// What the grid shows when it has no cell to draw (PRD P0-01, P0-03).
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No photos", systemImage: "photo.on.rectangle")
        } description: {
            Text(
                browsing.hasFolderContents
                    ? "No photos match this filter." : "Open a folder to see its photos.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("clove.grid.empty")
    }

    /// Opens one similar group's view from its count tag or its cover (PRD Grid, P0-11).
    private func openGroup(_ id: GroupID) {
        guard let group = browsing.groups.first(where: { $0.id == id }) else { return }
        browsing.openGroup(group)
    }

    /// The current filter's name, so the grid shows the filter it is applying (PRD P0-03).
    private var filterName: String {
        switch browsing.state.filter {
        case .all:
            "All"
        case .unmarked:
            "Unmarked"
        case .rejected:
            "Rejected"
        case .ratedAtLeast(let rating):
            "\(rating.rawValue)+ stars"
        }
    }

    /// The current order's name (PRD P0-03).
    private var orderName: String {
        browsing.state.order == .captureTime ? "Capture time" : "File name"
    }
}
