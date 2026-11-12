import CloveCore
import SwiftUI
import UIKit

/// UIKit owns the drag session, including cancellation outside the grid. Its interactive
/// movement gives the lifted tile, insertion slot and edge scrolling their system behavior.
struct RenameOrderGrid: UIViewRepresentable {
    let flow: BatchRenameFlow
    let open: (GridPhoto) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(flow: flow, open: open) }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let columns = environment.traitCollection.horizontalSizeClass == .regular ? 6 : 3
            let side =
                (environment.container.effectiveContentSize.width - CGFloat(columns - 1) * 2)
                / CGFloat(columns)
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .absolute(side)),
                repeatingSubitem: item, count: columns)
            group.interItemSpacing = .fixed(2)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 2
            return section
        }
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "photo")
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        let press = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.reorder(_:)))
        view.addGestureRecognizer(press)
        context.coordinator.collection = view
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        context.coordinator.open = open
        context.coordinator.theme = context.environment.cloveTheme
        if !context.coordinator.isDragging { view.reloadData() }
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        let flow: BatchRenameFlow
        var open: (GridPhoto) -> Void
        var theme: CloveTheme?
        weak var collection: UICollectionView?
        private(set) var isDragging = false
        private var draggingPhoto: PhotoIdentity?
        private var targetPosition: Int?

        init(flow: BatchRenameFlow, open: @escaping (GridPhoto) -> Void) {
            self.flow = flow
            self.open = open
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
            -> Int
        {
            flow.order.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
            -> UICollectionViewCell
        {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: "photo", for: indexPath)
            let photo = flow.order[indexPath.item]
            configure(cell, photo: photo, position: indexPath.item)
            return cell
        }

        private func configure(_ cell: UICollectionViewCell, photo: GridPhoto, position: Int) {
            cell.contentConfiguration = UIHostingConfiguration {
                MoveRejectsThumbnail(photo: photo.id, source: flow.browsing.thumbnails)
                    .overlay(alignment: .topLeading) {
                        Text("\(position + 1)").font(.caption.bold()).foregroundStyle(.white)
                            .frame(minWidth: 26, minHeight: 26)
                            .background(Color.clove.accent, in: Circle()).padding(6)
                    }
                    .environment(\.cloveTheme, theme ?? .light)
                    .id(photo.id)
            }.margins(.all, 0)
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = photo.fileName
            cell.accessibilityValue = "Position \(position + 1) of \(flow.order.count)"
            cell.accessibilityIdentifier = "clove.rename.tile.\(photo.id.stem)"
            cell.accessibilityTraits = .button
            cell.accessibilityCustomActions = [
                action("Move earlier", photo: photo.id, position: position - 1),
                action("Move later", photo: photo.id, position: position + 1),
                action("Move to start", photo: photo.id, position: 0),
                action("Move to end", photo: photo.id, position: flow.order.count - 1),
            ]
        }

        private func action(_ name: String, photo: PhotoIdentity, position: Int)
            -> UIAccessibilityCustomAction
        {
            UIAccessibilityCustomAction(name: name) { [weak self] _ in
                guard let self else { return false }
                self.flow.move(photo, to: position)
                self.collection?.reloadData()
                return true
            }
        }

        func collectionView(
            _ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath
        ) {
            open(flow.order[indexPath.item])
        }

        func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath)
            -> Bool
        { true }

        func collectionView(
            _ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath,
            to destinationIndexPath: IndexPath
        ) {
            flow.move(flow.order[sourceIndexPath.item].id, to: destinationIndexPath.item)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
            toProposedIndexPath proposedIndexPath: IndexPath
        ) -> IndexPath {
            targetPosition = proposedIndexPath.item
            renumberPreview()
            return proposedIndexPath
        }

        private func renumberPreview() {
            guard let collection, let draggingPhoto, let targetPosition,
                let original = flow.order.firstIndex(where: { $0.id == draggingPhoto })
            else { return }
            var proposed = flow.order
            proposed.insert(proposed.remove(at: original), at: targetPosition)
            for cell in collection.visibleCells {
                guard let path = collection.indexPath(for: cell) else { continue }
                let photo = flow.order[path.item]
                if let position = proposed.firstIndex(where: { $0.id == photo.id }) {
                    configure(cell, photo: photo, position: position)
                }
            }
        }

        @objc func reorder(_ gesture: UILongPressGestureRecognizer) {
            guard let collection else { return }
            let point = gesture.location(in: collection)
            switch gesture.state {
            case .began:
                guard let path = collection.indexPathForItem(at: point) else { return }
                draggingPhoto = flow.order[path.item].id
                targetPosition = path.item
                isDragging = collection.beginInteractiveMovementForItem(at: path)
            case .changed:
                if isDragging { collection.updateInteractiveMovementTargetPosition(point) }
            case .ended:
                if isDragging { collection.endInteractiveMovement() }
                finishDrag()
            case .cancelled, .failed:
                if isDragging { collection.cancelInteractiveMovement() }
                finishDrag()
            default: break
            }
        }

        private func finishDrag() {
            isDragging = false
            draggingPhoto = nil
            targetPosition = nil
            collection?.reloadData()
        }
    }
}
