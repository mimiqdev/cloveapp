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
/// P0-03). Long-press is left alone for multi-select (PRD P0-09, U4).
struct GridCollectionView: UIViewRepresentable {
    /// The cells to show, in grid order (PRD P0-03, P0-11).
    let items: [GridCellItem]

    /// The photo the browsing state is on, which the update holds in place (PRD Grid, P0-14).
    let currentPhoto: PhotoIdentity?

    /// The groups the cells were built from, so the update resolves the current photo to the
    /// cell that draws it, including a collapsed group's cover (PRD P0-11).
    let groups: [BrowsingGroup]

    /// The thumbnails and companion badges the cells draw (PRD Grid, P0-03).
    let thumbnails: any GridThumbnailSource

    /// Opens one photo's detail (PRD Grid, P0-03). A single tap never waits for a second one.
    let openPhoto: (PhotoIdentity) -> Void

    /// Opens one similar group's view (PRD Grid, P0-11).
    let openGroup: (GroupID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(thumbnails: thumbnails, openPhoto: openPhoto, openGroup: openGroup)
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
        context.coordinator.apply(
            items: items, groups: groups, currentPhoto: currentPhoto,
            sizeClass: context.environment.horizontalSizeClass)
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

        private var items: [GridCellItem] = []
        private var groups: [BrowsingGroup] = []
        private var itemsByID: [GridCellItem.ID: GridCellItem] = [:]
        private struct PrefetchRequest {
            let token: UUID
            let task: Task<Void, Never>
        }

        private var dataSource: UICollectionViewDiffableDataSource<Int, GridCellItem.ID>?
        private weak var collectionView: UICollectionView?
        private var prefetchRequests: [GridCellItem.ID: PrefetchRequest] = [:]
        private var lastSizeClass: UserInterfaceSizeClass?

        init(
            thumbnails: any GridThumbnailSource,
            openPhoto: @escaping (PhotoIdentity) -> Void,
            openGroup: @escaping (GroupID) -> Void
        ) {
            self.thumbnails = thumbnails
            self.openPhoto = openPhoto
            self.openGroup = openGroup
        }

        /// Registers the cell and builds the diffable data source (PRD P0-03, P0-11).
        func attach(to collectionView: UICollectionView) {
            self.collectionView = collectionView
            let registration = UICollectionView.CellRegistration<GridPhotoCell, GridCellItem.ID> {
                [weak self] cell, _, id in
                guard let self, let item = self.itemsByID[id] else { return }
                cell.configure(with: item, thumbnails: self.thumbnails) { [weak self] group in
                    self?.openGroup(group)
                }
            }
            dataSource = UICollectionViewDiffableDataSource<Int, GridCellItem.ID>(
                collectionView: collectionView
            ) { view, indexPath, id in
                view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
            }
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
            currentPhoto: PhotoIdentity?, sizeClass: UserInterfaceSizeClass?
        ) {
            guard let collectionView, let dataSource else { return }
            if sizeClass != lastSizeClass {
                lastSizeClass = sizeClass
                collectionView.collectionViewLayout.invalidateLayout()
            }
            guard newItems != items else {
                groups = newGroups
                return
            }

            let previousIDs = items.map(\.id)
            let previousByID = itemsByID
            let held = hold(currentPhoto: currentPhoto, groups: groups)
            items = newItems
            groups = newGroups
            itemsByID = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })

            var snapshot = NSDiffableDataSourceSnapshot<Int, GridCellItem.ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(newItems.map(\.id), toSection: 0)
            let changed: [GridCellItem.ID] = newItems.compactMap { item in
                guard let old = previousByID[item.id], old != item else { return nil }
                return item.id
            }
            if !changed.isEmpty { snapshot.reconfigureItems(changed) }
            dataSource.apply(snapshot, animatingDifferences: false)

            guard let held else { return }
            // The current photo may now be drawn by a different cell, such as a cover keyed by
            // a refined group; hold that cell where the photo's old cell was.
            if held.isCurrentPhoto, let currentPhoto,
                let cell = GridCellItem.cell(
                    for: currentPhoto, in: newItems, groups: newGroups),
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

        /// One cell tapped: the collapsed cover opens its group, any other cell opens detail.
        func collectionView(
            _ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath
        ) {
            collectionView.deselectItem(at: indexPath, animated: false)
            guard let item = item(at: indexPath) else { return }
            if let group = item.group, group.isCover {
                openGroup(group.id)
            } else {
                openPhoto(item.photo.id)
            }
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
        private func hold(currentPhoto: PhotoIdentity?, groups: [BrowsingGroup]) -> HeldPlace? {
            guard let collectionView, !items.isEmpty else { return nil }
            if let currentPhoto,
                let cell = GridCellItem.cell(for: currentPhoto, in: items, groups: groups),
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
