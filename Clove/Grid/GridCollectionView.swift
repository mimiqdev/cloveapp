import CloveCore
import SwiftUI
import UIKit

/// The grid's collection view, wrapped for SwiftUI (PRD Grid, P0-03, P0-11).
///
/// A compositional layout draws three columns at compact width and five at regular width, taken
/// from the width the view is handed and never from a device check (PRD Grid). A diffable data
/// source tracks each cell by its stable ``GridCellItem/ID``, so a scan batch, a filter or a
/// group refinement moves cells rather than rebuilding the grid.
///
/// Each update holds the anchor cell's place on screen through ``GridAnchorRule``: the current
/// photo when the grid shows it, else the top visible cell. PRD Grid's similar-group display and
/// PRD P0-11 both require that arriving photos and refining groups never move the photo the
/// user is looking at.
///
/// A tap opens detail without delay, because the grid adds no double-tap recognizer (PRD Grid,
/// P0-03). A long press starts multi-select on the pressed cell, and while the selection is
/// non-empty a tap toggles a cell instead of opening it (PRD P0-09).
struct GridCollectionView: UIViewRepresentable {
    /// The cells to show, in grid order (PRD P0-03, P0-11).
    let items: [GridCellItem]

    /// The photo the browsing state is on, which the update holds in place (PRD Grid, P0-14).
    let currentPhoto: PhotoIdentity?

    /// The groups the cells were built from, so the update resolves the current photo to the
    /// cell that draws it, including a collapsed group's cover (PRD P0-11).
    let groups: [BrowsingGroup]

    /// The filtered photos the cells were built from (PRD P0-03).
    ///
    /// It decides whether the current photo is shown at all: a cover stands for its whole
    /// group, but a photo the filter hides must not claim that cover as its place.
    let shownPhotos: Set<PhotoIdentity>

    /// The photos multi-select has selected (PRD P0-09).
    ///
    /// An empty selection means the grid is not in multi-select, so a tap opens detail or a
    /// group as before. A non-empty one makes every tap a selection toggle.
    let selection: Set<PhotoIdentity>

    /// The thumbnails and companion badges the cells draw (PRD Grid, P0-03).
    let thumbnails: any GridThumbnailSource

    var failedPhotos: Set<PhotoIdentity> = []
    var isSelectingEmpty = false

    /// Opens one photo's detail (PRD Grid, P0-03). A single tap never waits for a second one.
    let openPhoto: (PhotoIdentity) -> Void

    /// Opens one similar group's view (PRD Grid, P0-11).
    let openGroup: (GroupID) -> Void

    /// Starts multi-select on one cell's photos after a long press (PRD P0-09).
    let beginSelection: (GridCellItem) -> Void

    /// Adds one cell's photos to the selection or removes them (PRD P0-09).
    let toggleSelection: (GridCellItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            thumbnails: thumbnails, openPhoto: openPhoto, openGroup: openGroup,
            beginSelection: beginSelection, toggleSelection: toggleSelection,
            selection: selection)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let collectionView = UICollectionView(
            frame: .zero, collectionViewLayout: Self.makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = context.coordinator
        collectionView.prefetchDataSource = context.coordinator
        context.coordinator.attach(to: collectionView)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.thumbnails = thumbnails
        context.coordinator.openPhoto = openPhoto
        context.coordinator.openGroup = openGroup
        context.coordinator.beginSelection = beginSelection
        context.coordinator.toggleSelection = toggleSelection
        context.coordinator.apply(
            items: items, groups: groups, shownPhotos: shownPhotos,
            currentPhoto: currentPhoto, selection: selection,
            sizeClass: context.environment.horizontalSizeClass,
            theme: context.environment.cloveTheme, failedPhotos: failedPhotos,
            isSelectingEmpty: isSelectingEmpty)
    }

    /// Three columns at compact width, five at regular width, from a square-ish cell (PRD Grid).
    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let columns = environment.traitCollection.horizontalSizeClass == .regular ? 5 : 3
            let spacing: CGFloat = 2
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1 / CGFloat(columns)),
                    heightDimension: .fractionalHeight(1)))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .fractionalWidth(1 / CGFloat(columns))),
                repeatingSubitem: item, count: columns)
            group.interItemSpacing = .fixed(spacing)
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: spacing, leading: spacing, bottom: spacing, trailing: spacing)
            section.interGroupSpacing = spacing
            return section
        }
    }
}

extension GridCollectionView {
    /// Keeps the collection view's cells, tapping and thumbnail requests in step with SwiftUI.
    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate,
        UICollectionViewDataSourcePrefetching
    {
        var thumbnails: any GridThumbnailSource
        var openPhoto: (PhotoIdentity) -> Void
        var openGroup: (GroupID) -> Void
        var beginSelection: (GridCellItem) -> Void
        var toggleSelection: (GridCellItem) -> Void

        private var items: [GridCellItem] = []
        private var groups: [BrowsingGroup] = []
        private var shownPhotos: Set<PhotoIdentity> = []
        private var selection: Set<PhotoIdentity>
        private var itemsByID: [GridCellItem.ID: GridCellItem] = [:]
        private struct PrefetchRequest {
            let token: UUID
            let task: Task<Void, Never>
        }

        private var dataSource: UICollectionViewDiffableDataSource<Int, GridCellItem.ID>?
        private weak var collectionView: UICollectionView?
        private var prefetchRequests: [GridCellItem.ID: PrefetchRequest] = [:]
        private var lastSizeClass: UserInterfaceSizeClass?
        private var theme = CloveTheme.light
        private var failedPhotos: Set<PhotoIdentity> = []
        private var isSelectingEmpty = false

        init(
            thumbnails: any GridThumbnailSource,
            openPhoto: @escaping (PhotoIdentity) -> Void,
            openGroup: @escaping (GroupID) -> Void,
            beginSelection: @escaping (GridCellItem) -> Void,
            toggleSelection: @escaping (GridCellItem) -> Void,
            selection: Set<PhotoIdentity>
        ) {
            self.thumbnails = thumbnails
            self.openPhoto = openPhoto
            self.openGroup = openGroup
            self.beginSelection = beginSelection
            self.toggleSelection = toggleSelection
            self.selection = selection
        }

        /// Registers the cell and builds the diffable data source (PRD P0-03, P0-11).
        func attach(to collectionView: UICollectionView) {
            self.collectionView = collectionView
            let registration = UICollectionView.CellRegistration<GridPhotoCell, GridCellItem.ID> {
                [weak self] cell, _, id in
                guard let self, let item = self.itemsByID[id] else { return }
                cell.configure(
                    with: item, isSelected: self.showsSelected(item),
                    isSelecting: self.isSelecting, thumbnails: self.thumbnails,
                    theme: self.theme, hasFailed: self.failedPhotos.contains(item.photo.id)
                ) { [weak self] group in
                    self?.openGroup(group)
                }
            }
            dataSource = UICollectionViewDiffableDataSource<Int, GridCellItem.ID>(
                collectionView: collectionView
            ) { view, indexPath, id in
                view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
            }
            // A long press starts multi-select (PRD P0-09). It lives on the collection view, so
            // a cell needs no recognizer of its own and a reused cell keeps nothing.
            collectionView.addGestureRecognizer(
                UILongPressGestureRecognizer(
                    target: self, action: #selector(handleLongPress(_:))))
        }

        /// Applies the cells SwiftUI handed over, holding the anchor cell's place (PRD P0-11).
        ///
        /// The anchor is measured before the snapshot changes: the cell that draws the current
        /// photo when the grid shows one, else the top visible cell. ``GridAnchorRule`` answers
        /// which cell takes that place afterwards, including when a filter or a group
        /// refinement removed the anchor, and the view scrolls that cell back to the same
        /// distance from the top. A refinement that moves the photo into a group with a new key
        /// still holds the photo, because both sides resolve the photo to its cell before the
        /// old place is measured and after the new cells arrive (PRD Grid, P0-11).
        func apply(
            items newItems: [GridCellItem], groups newGroups: [BrowsingGroup],
            shownPhotos newShownPhotos: Set<PhotoIdentity>, currentPhoto: PhotoIdentity?,
            selection newSelection: Set<PhotoIdentity>, sizeClass: UserInterfaceSizeClass?,
            theme newTheme: CloveTheme, failedPhotos newFailures: Set<PhotoIdentity>,
            isSelectingEmpty newSelectingEmpty: Bool
        ) {
            guard let collectionView, let dataSource else { return }
            let styleChanged =
                theme != newTheme || failedPhotos != newFailures
                || isSelectingEmpty != newSelectingEmpty
            theme = newTheme
            failedPhotos = newFailures
            isSelectingEmpty = newSelectingEmpty
            if sizeClass != lastSizeClass {
                lastSizeClass = sizeClass
                collectionView.collectionViewLayout.invalidateLayout()
            }
            let before = BatchSelection(groups: groups, selection: selection)
            let after = BatchSelection(groups: newGroups, selection: newSelection)
            guard newItems != items else {
                groups = newGroups
                shownPhotos = newShownPhotos
                selection = newSelection
                let restyled = items.compactMap { item in
                    !styleChanged && before.showsSelected(item) == after.showsSelected(item)
                        ? nil : item.id
                }
                guard !restyled.isEmpty else { return }
                // Only the cells whose selection changed are redrawn, so a toggle never
                // re-decodes a thumbnail (PRD P0-09, P0-03).
                var snapshot = dataSource.snapshot()
                snapshot.reconfigureItems(restyled)
                dataSource.apply(snapshot, animatingDifferences: false)
                return
            }

            let previousIDs = items.map(\.id)
            let previousByID = itemsByID
            let held = hold(
                currentPhoto: currentPhoto, groups: groups, shownPhotos: shownPhotos)
            items = newItems
            groups = newGroups
            shownPhotos = newShownPhotos
            selection = newSelection
            itemsByID = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })

            var snapshot = NSDiffableDataSourceSnapshot<Int, GridCellItem.ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(newItems.map(\.id), toSection: 0)
            let changed: [GridCellItem.ID] = newItems.compactMap { item in
                guard let old = previousByID[item.id] else { return nil }
                if old != item || styleChanged { return item.id }
                return before.showsSelected(old) != after.showsSelected(item) ? item.id : nil
            }
            if !changed.isEmpty { snapshot.reconfigureItems(changed) }
            dataSource.apply(snapshot, animatingDifferences: false)

            guard let held else { return }
            // The current photo may now be drawn by a different cell, such as a cover keyed by
            // a refined group; hold that cell where the photo's old cell was.
            if held.isCurrentPhoto, let currentPhoto,
                let cell = GridCellItem.cell(
                    for: currentPhoto, in: newItems, groups: newGroups,
                    shown: newShownPhotos),
                let index = newItems.firstIndex(where: { $0.id == cell })
            {
                restore(index: index, offset: held.offset)
                return
            }
            guard
                let index = GridAnchorRule.newIndex(
                    of: held.item, previous: previousIDs, in: newItems.map(\.id))
            else { return }
            restore(index: index, offset: held.offset)
        }

        /// One cell tapped: multi-select toggles it, a collapsed cover opens its group, and any
        /// other cell opens detail (PRD P0-09, PRD Grid).
        func collectionView(
            _ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath
        ) {
            collectionView.deselectItem(at: indexPath, animated: false)
            guard let item = item(at: indexPath) else { return }
            if isSelecting {
                toggleSelection(item)
            } else if let group = item.group, group.isCover {
                openGroup(group.id)
            } else {
                openPhoto(item.photo.id)
            }
        }

        /// A long press starts multi-select on the pressed cell's photos (PRD P0-09).
        ///
        /// The selection changes on `.began`, so the cell is selected while the finger is still
        /// down and the bar appears at once. A cell the collection view cannot resolve under the
        /// finger, such as the space between rows, starts nothing.
        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let collectionView,
                let indexPath = collectionView.indexPathForItem(
                    at: recognizer.location(in: collectionView)),
                let item = item(at: indexPath)
            else { return }
            beginSelection(item)
        }

        /// Requests the next screenful before the cells appear (PRD P0-03, G1 scheduling row).
        func collectionView(
            _ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]
        ) {
            for indexPath in indexPaths {
                guard let item = item(at: indexPath), prefetchRequests[item.id] == nil else {
                    continue
                }
                let token = UUID()
                let task = Task { [weak self] in
                    _ = await self?.thumbnails.thumbnail(for: item.photo.id, priority: .prefetch)
                    self?.finishPrefetch(item.id, token: token)
                }
                prefetchRequests[item.id] = PrefetchRequest(token: token, task: task)
            }
        }

        /// Cancels the requests the collection view no longer expects (PRD P0-03).
        func collectionView(
            _ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]
        ) {
            for indexPath in indexPaths {
                guard let item = item(at: indexPath) else { continue }
                cancelPrefetch(item.id)
            }
        }

        /// A cell about to show: its prefetch is no longer needed and it asks for its own pixels.
        func collectionView(
            _ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            guard let item = item(at: indexPath), let cell = cell as? GridPhotoCell else { return }
            cancelPrefetch(item.id)
            cell.resumeThumbnail(using: thumbnails)
        }

        /// A cell leaving the screen drops its pending request (PRD P0-03, G1 scheduling row).
        func collectionView(
            _ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            (cell as? GridPhotoCell)?.cancelThumbnailRequest()
        }

        /// Drops one prefetch, cancelling the request when it is still running.
        private func cancelPrefetch(_ id: GridCellItem.ID) {
            prefetchRequests.removeValue(forKey: id)?.task.cancel()
        }

        /// Clears a finished prefetch only when it is still the request stored for that cell.
        ///
        /// A cancelled request may finish after a replacement was installed, so the token keeps
        /// the old completion from erasing the new request's handle (G1 scheduling row).
        private func finishPrefetch(_ id: GridCellItem.ID, token: UUID) {
            guard prefetchRequests[id]?.token == token else { return }
            prefetchRequests[id] = nil
        }

        private func item(at indexPath: IndexPath) -> GridCellItem? {
            guard items.indices.contains(indexPath.item) else { return nil }
            return items[indexPath.item]
        }

        /// Whether the grid is in multi-select, which a non-empty selection means (PRD P0-09).
        private var isSelecting: Bool { isSelectingEmpty || !selection.isEmpty }

        /// Whether one cell draws as selected (PRD P0-09).
        private func showsSelected(_ item: GridCellItem) -> Bool {
            BatchSelection(groups: groups, selection: selection).showsSelected(item)
        }

        /// One cell's old place on screen, and whether the current photo chose it (PRD P0-11).
        private struct HeldPlace {
            let item: GridCellItem.ID
            let offset: CGFloat?
            let isCurrentPhoto: Bool
        }

        /// The anchor cell and its distance from the top of the visible area, before an update.
        ///
        /// The current photo wins when the old cells drew it, so a refinement holds the photo.
        /// Otherwise the top visible cell is the anchor, because no photo has a place to keep.
        private func hold(
            currentPhoto: PhotoIdentity?, groups: [BrowsingGroup],
            shownPhotos: Set<PhotoIdentity>
        ) -> HeldPlace? {
            guard let collectionView, !items.isEmpty else { return nil }
            if let currentPhoto,
                let cell = GridCellItem.cell(
                    for: currentPhoto, in: items, groups: groups, shown: shownPhotos),
                let offset = viewportOffset(of: cell)
            {
                return HeldPlace(item: cell, offset: offset, isCurrentPhoto: true)
            }
            guard let first = collectionView.indexPathsForVisibleItems.min(),
                items.indices.contains(first.item)
            else { return nil }
            let anchor = items[first.item].id
            return HeldPlace(
                item: anchor, offset: viewportOffset(of: anchor), isCurrentPhoto: false)
        }

        /// How far one cell sits below the visible area's top edge, negative when above it.
        private func viewportOffset(of id: GridCellItem.ID) -> CGFloat? {
            guard let collectionView, let index = items.firstIndex(where: { $0.id == id }),
                let attributes = collectionView.layoutAttributesForItem(
                    at: IndexPath(item: index, section: 0))
            else { return nil }
            return attributes.frame.minY - collectionView.contentOffset.y
        }

        /// Scrolls the held cell back to the distance from the top it had before the update.
        ///
        /// The offset is clamped to the scrollable range, so a photo near the folder's start or
        /// end keeps as much of its place as the grid can show.
        private func restore(index: Int, offset: CGFloat?) {
            guard let collectionView else { return }
            collectionView.layoutIfNeeded()
            guard
                let attributes = collectionView.layoutAttributesForItem(
                    at: IndexPath(item: index, section: 0))
            else { return }
            let insets = collectionView.adjustedContentInset
            let minimum = -insets.top
            let maximum = max(
                collectionView.contentSize.height + insets.bottom - collectionView.bounds.height,
                minimum)
            let y = min(max(attributes.frame.minY - (offset ?? 0), minimum), maximum)
            guard abs(y - collectionView.contentOffset.y) > 0.5 else { return }
            collectionView.setContentOffset(
                CGPoint(x: collectionView.contentOffset.x, y: y), animated: false)
        }
    }
}
