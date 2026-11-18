import CloveCore
import SwiftUI
import UIKit

/// UIKit owns the drag session, including cancellation outside the grid. Its interactive
/// movement gives the lifted tile, insertion slot and edge scrolling their system behavior.
struct RenameOrderGrid: UIViewRepresentable {
    let flow: BatchRenameFlow
    let order: [GridPhoto]
    let open: (GridPhoto) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(flow: flow, open: open) }

    func makeUIView(context: Context) -> UICollectionView {
        context.coordinator.theme = context.environment.cloveTheme
        context.coordinator.appLanguage = context.environment.appLanguage
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let columns = environment.traitCollection.horizontalSizeClass == .regular ? 6 : 3
            let side =
                (environment.container.effectiveContentSize.width - CGFloat(columns - 1) * 2)
                / CGFloat(columns)
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1 / CGFloat(columns)),
                    heightDimension: .fractionalHeight(1)))
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
        view.register(RenameOrderTileCell.self, forCellWithReuseIdentifier: "photo")
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
        context.coordinator.appLanguage = context.environment.appLanguage
        if !context.coordinator.isDragging { view.reloadData() }
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        let flow: BatchRenameFlow
        var open: (GridPhoto) -> Void
        var theme: CloveTheme?
        var appLanguage: ResolvedAppLanguage = .english
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
                    .environment(\.appLanguage, appLanguage)
                    .environment(\.locale, appLanguage.locale)
                    .id(photo.id)
            }.margins(.all, 0)

            let tileAccessibility = cell.contentView
            tileAccessibility.isAccessibilityElement = true
            tileAccessibility.accessibilityLabel = photo.fileName
            tileAccessibility.accessibilityValue = AppLocalization.format(
                "Position %lld of %lld", language: appLanguage,
                Int64(position + 1), Int64(flow.order.count))
            tileAccessibility.accessibilityIdentifier = "clove.rename.tile.\(photo.id.stem)"
            tileAccessibility.accessibilityTraits = .button
            tileAccessibility.accessibilityCustomActions = [
                action(
                    AppLocalization.string("Move earlier", language: appLanguage),
                    photo: photo.id, position: position - 1),
                action(
                    AppLocalization.string("Move later", language: appLanguage),
                    photo: photo.id, position: position + 1),
                action(
                    AppLocalization.string("Move to start", language: appLanguage),
                    photo: photo.id, position: 0),
                action(
                    AppLocalization.string("Move to end", language: appLanguage),
                    photo: photo.id, position: flow.order.count - 1),
                UIAccessibilityCustomAction(
                    name: AppLocalization.string("Remove from batch", language: appLanguage)
                ) { [weak self] _ in
                    guard let self else { return false }
                    self.flow.remove(photo.id)
                    self.collection?.reloadData()
                    return true
                },
            ]

            if let tileCell = cell as? RenameOrderTileCell {
                tileCell.isAccessibilityElement = false
                tileCell.removeButton.accessibilityLabel = AppLocalization.string(
                    "Remove from batch", language: appLanguage)
                tileCell.removeButton.accessibilityValue = photo.fileName
                tileCell.removeButton.accessibilityIdentifier =
                    "clove.rename.remove.\(photo.id.stem)"
                tileCell.onRemove = { [weak self] in
                    guard let self else { return }
                    self.flow.remove(photo.id)
                    self.collection?.reloadData()
                }
                tileCell.accessibilityElements = [tileCell.contentView, tileCell.removeButton]
            }
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

@MainActor
private final class RenameOrderTileCell: UICollectionViewCell {
    let removeButton = UIButton(type: .custom)
    var onRemove: (() -> Void)?

    private let badgeView = UIView()
    private let badgeIcon = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        removeButton.frame = CGRect(x: bounds.width - 44, y: 0, width: 44, height: 44)
        removeButton.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        removeButton.addTarget(self, action: #selector(handleRemove), for: .touchUpInside)

        badgeView.frame = CGRect(x: 14, y: 6, width: 24, height: 24)
        badgeView.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        badgeView.layer.cornerRadius = 12
        badgeView.layer.cornerCurve = .continuous
        badgeView.isUserInteractionEnabled = false

        let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        badgeIcon.image = UIImage(systemName: "xmark", withConfiguration: config)
        badgeIcon.tintColor = .white
        badgeIcon.contentMode = .center
        badgeIcon.frame = badgeView.bounds
        badgeIcon.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        badgeView.addSubview(badgeIcon)

        removeButton.addSubview(badgeView)
        addSubview(removeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        removeButton.frame = CGRect(x: bounds.width - 44, y: 0, width: 44, height: 44)
        bringSubviewToFront(removeButton)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onRemove = nil
    }

    @objc private func handleRemove() {
        onRemove?()
    }
}
