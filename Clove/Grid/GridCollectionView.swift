import CloveCore
import SwiftUI
import UIKit

/// The grid's collection view, wrapped for SwiftUI (PRD Grid, P0-03, P0-11).
///
/// A compositional layout draws three columns at compact width and adaptive columns at regular width, taken
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
///
/// The cells arrive as runs (``GridSection``). A run of the folder's own cells draws as it always
/// did; Group Focus replaces it with one group run, which draws a header with its fold control and
/// a shared surface behind the group's members (issue #304, #309).
struct GridCollectionView: UIViewRepresentable {
    /// The runs to show, in grid order (PRD P0-03, P0-11).
    let sections: [GridSection]

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

    var isSelectingEmpty = false
    var placeholderCount = 0
    /// Duo uses six columns in the grid and two beside a focused photo.
    var columnCount: Int?
    /// Whether the cell drawing the current photo carries the current-photo indicator. The split
    /// Photo Preview turns this on so the person can see which photo or collapsed stack is open.
    var highlightsCurrentPhoto = false

    /// Whether the grid keeps the photo on screen in view: the Duo's split pane follows the open
    /// member, and its grid opens where the person left off (#225).
    var followsCurrentPhoto = false

    /// Folds Group Focus back into the folder's Timeline run (issue #309).
    var foldExpandedGroup: (GroupID) -> Void = { _ in }

    /// Opens one photo's detail (PRD Grid, P0-03). A single tap never waits for a second one.
    let openPhoto: (PhotoIdentity) -> Void

    /// Opens one similar group's view (PRD Grid, P0-11).
    let openGroup: (GroupID) -> Void

    /// Starts multi-select on one cell's photos after a long press (PRD P0-09).
    let beginSelection: (GridCellItem) -> Void

    /// Adds one cell's photos to the selection or removes them (PRD P0-09).
    let toggleSelection: (GridCellItem) -> Void

    /// Replaces the current selection during drag-range selection.
    var setSelection: ((Set<PhotoIdentity>) -> Void)? = nil

    /// Keeps multi-select mode active if a drag-deselect clears the last selected item.
    var keepSelectingWhenEmpty: () -> Void = {}

    /// Whether similar groups are unfolded inline in select mode.
    var areGroupsUnfolded = false

    /// Completes the inline group unfold immediately when interaction begins before beat 2.
    var completeGroupUnfold: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            thumbnails: thumbnails, openPhoto: openPhoto, openGroup: openGroup,
            beginSelection: beginSelection, toggleSelection: toggleSelection,
            setSelection: setSelection, keepSelectingWhenEmpty: keepSelectingWhenEmpty,
            selection: selection, foldExpandedGroup: foldExpandedGroup,
            areGroupsUnfolded: areGroupsUnfolded,
            completeGroupUnfold: completeGroupUnfold)
    }

    static func dismantleUIView(_ uiView: UICollectionView, coordinator: Coordinator) {
        coordinator.stopDragSelection()
    }

    /// What the layout needs from one run: whether it draws a group header and surface
    /// (Group Focus).
    fileprivate struct SectionPlan: Equatable {
        let isGroup: Bool
    }

    func makeUIView(context: Context) -> UICollectionView {
        let coordinator = context.coordinator
        let layout = Self.makeLayout(
            placeholderCount: { [weak coordinator] in coordinator?.placeholderCount ?? 0 },
            columnCount: { [weak coordinator] in coordinator?.columnCount },
            sectionPlans: { [weak coordinator] in coordinator?.sectionPlans ?? [] })
        let collectionView = AnchoredGridCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = context.coordinator
        collectionView.prefetchDataSource = context.coordinator
        collectionView.onWidthWillChange = { [weak coordinator] newWidth in
            coordinator?.captureResizeAnchor(forNewWidth: newWidth)
        }
        collectionView.onDidLayoutForWidthChange = { [weak coordinator] in
            coordinator?.restoreResizeAnchorIfNeeded()
        }
        collectionView.onSettledLayout = { [weak coordinator] in
            coordinator?.updateSettledAnchor()
        }
        context.coordinator.attach(to: collectionView)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        if context.coordinator.placeholderCount != placeholderCount
            || context.coordinator.columnCount != columnCount
        {
            context.coordinator.placeholderCount = placeholderCount
            context.coordinator.columnCount = columnCount
            collectionView.collectionViewLayout.invalidateLayout()
        }
        context.coordinator.thumbnails = thumbnails
        context.coordinator.highlightsCurrentPhoto = highlightsCurrentPhoto
        context.coordinator.followsCurrentPhoto = followsCurrentPhoto
        context.coordinator.foldExpandedGroup = foldExpandedGroup
        context.coordinator.openPhoto = openPhoto
        context.coordinator.openGroup = openGroup
        context.coordinator.beginSelection = beginSelection
        context.coordinator.toggleSelection = toggleSelection
        context.coordinator.setSelection = setSelection
        context.coordinator.keepSelectingWhenEmpty = keepSelectingWhenEmpty
        context.coordinator.completeGroupUnfold = completeGroupUnfold
        context.coordinator.apply(
            sections: sections, groups: groups, shownPhotos: shownPhotos,
            currentPhoto: currentPhoto, selection: selection,
            sizeClass: context.environment.horizontalSizeClass,
            verticalSizeClass: context.environment.verticalSizeClass,
            theme: context.environment.cloveTheme,
            language: context.environment.appLanguage,
            isSelectingEmpty: isSelectingEmpty,
            areGroupsUnfolded: areGroupsUnfolded,
            reduceMotion: context.environment.accessibilityReduceMotion)
        for case let header as GridGroupHeader in collectionView.visibleSupplementaryViews(
            ofKind: GridGroupHeader.kind)
        where header.theme != context.environment.cloveTheme
            || header.language != context.environment.appLanguage
        {
            header.theme = context.environment.cloveTheme
            header.language = context.environment.appLanguage
            header.fold = foldExpandedGroup
        }
        for case let footer as GridPlaceholderFooter in collectionView.visibleSupplementaryViews(
            ofKind: UICollectionView.elementKindSectionFooter)
        {
            let safeWidth = collectionView.safeAreaLayoutGuide.layoutFrame.width
            let footerWidth = safeWidth > 0 ? safeWidth : collectionView.bounds.width
            let columns =
                columnCount
                ?? Self.columns(
                    width: footerWidth,
                    regular: context.environment.horizontalSizeClass == .regular,
                    compactHeight: context.environment.verticalSizeClass == .compact)
            footer.configure(
                count: placeholderCount, columns: columns, theme: context.environment.cloveTheme)
        }
    }

    /// About six square tiles beside the sidebar on an 11-inch iPad in landscape;
    /// compact-width or compact-height landscape widths (>= 500 pt) use a 120 pt minimum tile
    /// width so standard iPhone landscape usable widths (~740+ pt) yield 6 columns, while
    /// narrower compact widths (portrait phone, Duo cover, narrow splits) keep 3 columns.
    static func columns(
        width: CGFloat, regular: Bool, compactHeight: Bool = false
    ) -> Int {
        if regular && !compactHeight {
            return max(1, Int((width + 1.5) / (140 + 1.5)))
        }
        if width >= 500 {
            return max(4, Int((width + 1.5) / (120 + 1.5)))
        }
        return 3
    }

    /// Narrow compact widths keep three columns; iPhone landscape fits tiles at a minimum of
    /// 120 points, and regular-height regular widths fit tiles at a minimum of 140 points.
    ///
    /// A group run adds its header and its surface; a run of the folder's own cells keeps the
    /// layout the grid always had (owner decision, #225).
    private static func makeLayout(
        placeholderCount: @escaping () -> Int, columnCount: @escaping () -> Int?,
        sectionPlans: @escaping () -> [SectionPlan]
    )
        -> UICollectionViewCompositionalLayout
    {
        UICollectionViewCompositionalLayout { sectionIndex, environment in
            let plans = sectionPlans()
            let isGroup = plans.indices.contains(sectionIndex) && plans[sectionIndex].isGroup
            let columns =
                columnCount()
                ?? columns(
                    width: environment.container.effectiveContentSize.width,
                    regular: environment.traitCollection.horizontalSizeClass == .regular,
                    compactHeight: environment.traitCollection.verticalSizeClass == .compact)
            let spacing: CGFloat = 1.5
            let side =
                (environment.container.effectiveContentSize.width - CGFloat(columns - 1) * spacing)
                / CGFloat(columns)
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1 / CGFloat(columns)),
                    heightDimension: .fractionalHeight(1)))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(side)),
                repeatingSubitem: item, count: columns)
            group.interItemSpacing = .fixed(spacing)
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets =
                isGroup
                ? NSDirectionalEdgeInsets(
                    top: GridGroupRun.inset, leading: 0, bottom: GridGroupRun.inset,
                    trailing: 0)
                : NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: spacing, trailing: 0)
            section.interGroupSpacing = spacing
            if isGroup {
                section.boundarySupplementaryItems = [
                    NSCollectionLayoutBoundarySupplementaryItem(
                        layoutSize: NSCollectionLayoutSize(
                            widthDimension: .fractionalWidth(1),
                            heightDimension: .absolute(GridGroupRun.headerHeight)),
                        elementKind: GridGroupHeader.kind, alignment: .top)
                ]
            }
            let unread = placeholderCount()
            if unread > 0, sectionIndex == max(0, plans.count - 1) {
                let rows = ceil(Double(unread) / Double(columns))
                section.boundarySupplementaryItems.append(
                    NSCollectionLayoutBoundarySupplementaryItem(
                        layoutSize: NSCollectionLayoutSize(
                            widthDimension: .fractionalWidth(1),
                            heightDimension: .absolute(CGFloat(rows) * (side + spacing))),
                        elementKind: UICollectionView.elementKindSectionFooter, alignment: .bottom))
            }
            return section
        }
    }
}

@MainActor
private final class AnchoredGridCollectionView: UICollectionView {
    var onWidthWillChange: ((CGFloat) -> Void)?
    var onDidLayoutForWidthChange: (() -> Void)?
    var onSettledLayout: (() -> Void)?
    private(set) var laidOutWidth: CGFloat = 0
    private var pendingWidthChangeLayout = false

    var isResizingWidth: Bool {
        pendingWidthChangeLayout || (laidOutWidth > 0 && abs(bounds.width - laidOutWidth) > 0.5)
    }

    override var frame: CGRect {
        willSet {
            if super.frame.width > 0,
                abs(newValue.width - super.frame.width) > 0.5
            {
                onWidthWillChange?(newValue.width)
            }
        }
    }

    override var bounds: CGRect {
        willSet {
            if super.bounds.width > 0,
                abs(newValue.width - super.bounds.width) > 0.5
            {
                onWidthWillChange?(newValue.width)
            }
        }
    }

    override func layoutSubviews() {
        let widthChanged = abs(bounds.width - laidOutWidth) > 0.5
        if widthChanged {
            if laidOutWidth > 0 {
                pendingWidthChangeLayout = true
            }
            laidOutWidth = bounds.width
            collectionViewLayout.invalidateLayout()
        }
        super.layoutSubviews()
        if pendingWidthChangeLayout, bounds.width > 0, bounds.height > 0 {
            onDidLayoutForWidthChange?()
            pendingWidthChangeLayout = false
            onSettledLayout?()
        } else if bounds.width > 0, bounds.height > 0 {
            onSettledLayout?()
        }
    }
}

extension GridCollectionView {
    /// Keeps the collection view's cells, tapping and thumbnail requests in step with SwiftUI.
    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate,
        UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate
    {
        var thumbnails: any GridThumbnailSource
        var openPhoto: (PhotoIdentity) -> Void
        var openGroup: (GroupID) -> Void
        var beginSelection: (GridCellItem) -> Void
        var toggleSelection: (GridCellItem) -> Void
        var setSelection: ((Set<PhotoIdentity>) -> Void)?
        var keepSelectingWhenEmpty: () -> Void
        var foldExpandedGroup: (GroupID) -> Void
        var completeGroupUnfold: () -> Void
        var followsCurrentPhoto = false

        private var sections: [GridSection] = []
        private var items: [GridCellItem] = []
        private var groups: [BrowsingGroup] = []
        private var shownPhotos: Set<PhotoIdentity> = []
        private var selection: Set<PhotoIdentity>
        private var itemsByID: [GridCellItem.ID: GridCellItem] = [:]
        private var trayPositionsByID: [GridCellItem.ID: GridGroupTrayPosition] = [:]
        private var areGroupsUnfolded: Bool
        private var pendingLongPressAnchorPhoto: PhotoIdentity?
        private struct PrefetchRequest {
            let token: UUID
            let task: Task<Void, Never>
        }

        private struct DragSelectionState {
            let anchorPhotoID: PhotoIdentity
            var anchorIndex: Int
            let baseline: Set<PhotoIdentity>
            let selecting: Bool
            var lastCurrentIndex: Int
            var fingerViewportPoint: CGPoint
        }

        private var dataSource: UICollectionViewDiffableDataSource<GridSection.ID, GridCellItem.ID>?
        private weak var collectionView: UICollectionView?
        private var prefetchRequests: [GridCellItem.ID: PrefetchRequest] = [:]
        private var lastSizeClass: UserInterfaceSizeClass?
        private var lastVerticalSizeClass: UserInterfaceSizeClass?
        private var theme = CloveTheme.light
        private var language = ResolvedAppLanguage.english
        private var isSelectingEmpty = false
        fileprivate var sectionPlans: [GridCollectionView.SectionPlan] = []
        var placeholderCount = 0
        var columnCount: Int?
        var highlightsCurrentPhoto = false
        /// The current photo the cell registration reads when it configures a cell (#225).
        private var currentPhoto: PhotoIdentity?
        /// The current photo and highlight flag the visible cells were configured with,
        /// so moving to another member reconfigures exactly the two affected cells (#225).
        private var highlightedCellID: GridCellItem.ID?
        private var drawnCurrentPhoto: PhotoIdentity?
        private var drawnHighlight = false

        /// The folder's scroll offset when the grid entered Group Focus, so folding returns the
        /// person to the stack they left on (issue #309).
        private var folderOffsetBeforeGroupFocus: CGFloat?

        /// Scroll anchor held across width/column count changes on rotation, measured relative to
        /// the visible safe top (`adjustedContentInset.top`).
        private struct HeldResizeAnchor {
            let id: GridCellItem.ID
            let visibleTopOffset: CGFloat
        }

        private var pendingResizeAnchor: HeldResizeAnchor?
        private var settledResizeAnchor: HeldResizeAnchor?

        private var dragSelection: DragSelectionState?
        private var autoScrollLink: CADisplayLink?
        private var autoScrollTarget: DisplayLinkProxy?
        private var lastAutoScrollTimestamp: CFTimeInterval?
        private weak var longPressRecognizer: UILongPressGestureRecognizer?
        private weak var selectionPanRecognizer: UIPanGestureRecognizer?

        init(
            thumbnails: any GridThumbnailSource,
            openPhoto: @escaping (PhotoIdentity) -> Void,
            openGroup: @escaping (GroupID) -> Void,
            beginSelection: @escaping (GridCellItem) -> Void,
            toggleSelection: @escaping (GridCellItem) -> Void,
            setSelection: ((Set<PhotoIdentity>) -> Void)?,
            keepSelectingWhenEmpty: @escaping () -> Void,
            selection: Set<PhotoIdentity>,
            foldExpandedGroup: @escaping (GroupID) -> Void,
            areGroupsUnfolded: Bool,
            completeGroupUnfold: @escaping () -> Void
        ) {
            self.thumbnails = thumbnails
            self.openPhoto = openPhoto
            self.openGroup = openGroup
            self.beginSelection = beginSelection
            self.toggleSelection = toggleSelection
            self.setSelection = setSelection
            self.keepSelectingWhenEmpty = keepSelectingWhenEmpty
            self.selection = selection
            self.foldExpandedGroup = foldExpandedGroup
            self.areGroupsUnfolded = areGroupsUnfolded
            self.completeGroupUnfold = completeGroupUnfold
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateSettledAnchor()
        }

        func updateSettledAnchor() {
            guard let collectionView = collectionView as? AnchoredGridCollectionView,
                !collectionView.isResizingWidth,
                pendingResizeAnchor == nil,
                !items.isEmpty,
                collectionView.bounds.width > 0,
                collectionView.bounds.height > 0
            else { return }
            reconfigureTrayPositionsIfNeeded(in: collectionView)
            if let anchor = currentResizeAnchor(in: collectionView) {
                settledResizeAnchor = anchor
            }
        }

        func captureResizeAnchor(forNewWidth newWidth: CGFloat) {
            guard pendingResizeAnchor == nil, let collectionView, !items.isEmpty,
                collectionView.bounds.width > 0,
                abs(newWidth - collectionView.bounds.width) > 0.5
            else { return }
            pendingResizeAnchor = currentResizeAnchor(in: collectionView) ?? settledResizeAnchor
        }

        func restoreResizeAnchorIfNeeded() {
            let held = pendingResizeAnchor ?? settledResizeAnchor
            pendingResizeAnchor = nil
            guard let held, let collectionView else { return }
            reconfigureTrayPositionsIfNeeded(in: collectionView)
            guard let indexPath = indexPath(of: held.id),
                let attributes = collectionView.layoutAttributesForItem(at: indexPath)
            else { return }
            let targetY =
                attributes.frame.minY - held.visibleTopOffset
                - collectionView.adjustedContentInset.top
            scrollToClampedOffsetY(targetY)
            settledResizeAnchor = currentResizeAnchor(in: collectionView) ?? held
        }

        private func activeColumns(in collectionView: UICollectionView) -> Int {
            let safeWidth = collectionView.safeAreaLayoutGuide.layoutFrame.width
            let width = safeWidth > 0 ? safeWidth : collectionView.bounds.width
            let isRegular =
                lastSizeClass == .regular
                || collectionView.traitCollection.horizontalSizeClass == .regular
            let isCompactHeight =
                lastVerticalSizeClass == .compact
                || collectionView.traitCollection.verticalSizeClass == .compact
            guard width > 0 else {
                return columnCount ?? (isRegular && !isCompactHeight ? 6 : 3)
            }
            return columnCount
                ?? GridCollectionView.columns(
                    width: width, regular: isRegular, compactHeight: isCompactHeight)
        }

        private func computeTrayPositions(
            in sections: [GridSection], columns: Int
        ) -> [GridCellItem.ID: GridGroupTrayPosition] {
            guard columns > 0 else { return [:] }
            var positions: [GridCellItem.ID: GridGroupTrayPosition] = [:]
            for section in sections where section.id == .photos {
                let cells = section.cells
                for index in cells.indices {
                    let item = cells[index]
                    guard let group = item.group, !group.isCover else { continue }
                    let col = index % columns
                    let connectsLeading =
                        index > 0
                        && col > 0
                        && cells[index - 1].group?.isCover == false
                        && cells[index - 1].group?.id == group.id
                    let connectsTrailing =
                        index + 1 < cells.count
                        && col + 1 < columns
                        && cells[index + 1].group?.isCover == false
                        && cells[index + 1].group?.id == group.id
                    positions[item.id] = GridGroupTrayPosition(
                        memberIndex: group.memberIndex ?? 0,
                        memberCount: group.count,
                        connectsLeading: connectsLeading,
                        connectsTrailing: connectsTrailing)
                }
            }
            return positions
        }

        private func reconfigureTrayPositionsIfNeeded(in collectionView: UICollectionView) {
            guard let dataSource else { return }
            let newTrayPositions = computeTrayPositions(
                in: sections, columns: activeColumns(in: collectionView))
            guard newTrayPositions != trayPositionsByID else { return }
            let previous = trayPositionsByID
            trayPositionsByID = newTrayPositions
            let changed = Set(previous.keys).union(newTrayPositions.keys).filter {
                previous[$0] != newTrayPositions[$0]
            }
            guard !changed.isEmpty else { return }
            DispatchQueue.main.async { [weak dataSource] in
                guard let dataSource else { return }
                let existing = Set(dataSource.snapshot().itemIdentifiers)
                let toReconfigure = changed.filter { existing.contains($0) }
                guard !toReconfigure.isEmpty else { return }
                var snapshot = dataSource.snapshot()
                snapshot.reconfigureItems(Array(toReconfigure))
                dataSource.apply(snapshot, animatingDifferences: false)
            }
        }

        private func currentResizeAnchor(in collectionView: UICollectionView) -> HeldResizeAnchor? {
            let visibleTop =
                collectionView.contentOffset.y + collectionView.adjustedContentInset.top
            if let currentPhoto,
                let cell = GridCellItem.cell(
                    for: currentPhoto, in: items, groups: groups, shown: shownPhotos),
                let indexPath = indexPath(of: cell),
                isItemVisible(at: indexPath, in: collectionView),
                let attributes = collectionView.layoutAttributesForItem(at: indexPath)
            {
                return HeldResizeAnchor(
                    id: cell, visibleTopOffset: attributes.frame.minY - visibleTop)
            }
            if let first = firstVisibleCellIndexPath(in: collectionView),
                let anchor = item(at: first)?.id,
                let attributes = collectionView.layoutAttributesForItem(at: first)
            {
                return HeldResizeAnchor(
                    id: anchor, visibleTopOffset: attributes.frame.minY - visibleTop)
            }
            return nil
        }

        private func firstVisibleCellIndexPath(in collectionView: UICollectionView) -> IndexPath? {
            if let first = collectionView.indexPathsForVisibleItems.min() {
                return first
            }
            let insets = collectionView.adjustedContentInset
            let visibleRect = CGRect(
                x: collectionView.contentOffset.x,
                y: collectionView.contentOffset.y + insets.top,
                width: collectionView.bounds.width,
                height: max(0, collectionView.bounds.height - insets.top - insets.bottom))
            return collectionView.collectionViewLayout.layoutAttributesForElements(in: visibleRect)?
                .filter { $0.representedElementCategory == .cell }
                .min { $0.indexPath < $1.indexPath }?
                .indexPath
        }

        /// Registers the cell and builds the diffable data source (PRD P0-03, P0-11).
        func attach(to collectionView: UICollectionView) {
            self.collectionView = collectionView
            let registration = UICollectionView.CellRegistration<GridPhotoCell, GridCellItem.ID> {
                [weak self] cell, _, id in
                guard let self, let item = self.itemsByID[id] else { return }
                cell.configure(
                    with: item, isSelected: self.showsSelected(item),
                    isCurrent: self.highlightsCurrentPhoto && self.highlightedCellID == item.id,
                    isSelecting: self.isSelecting,
                    trayPosition: self.trayPositionsByID[id],
                    thumbnails: self.thumbnails,
                    theme: self.theme,
                    language: self.language
                ) { [weak self] group in
                    self?.openGroup(group)
                }
            }
            dataSource = UICollectionViewDiffableDataSource<GridSection.ID, GridCellItem.ID>(
                collectionView: collectionView
            ) { view, indexPath, id in
                view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
            }
            // Even an empty grid needs its section so the opening footer can be displayed.
            var initialSnapshot = NSDiffableDataSourceSnapshot<GridSection.ID, GridCellItem.ID>()
            initialSnapshot.appendSections([.photos])
            dataSource?.apply(initialSnapshot, animatingDifferences: false)
            collectionView.register(
                GridGroupHeader.self, forSupplementaryViewOfKind: GridGroupHeader.kind,
                withReuseIdentifier: "groupHeader")
            collectionView.register(
                GridPlaceholderFooter.self,
                forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                withReuseIdentifier: "placeholders")
            dataSource?.supplementaryViewProvider = { [weak self] view, kind, indexPath in
                guard let self else { return nil }
                if kind == GridGroupHeader.kind {
                    let header = view.dequeueReusableSupplementaryView(
                        ofKind: kind, withReuseIdentifier: "groupHeader", for: indexPath)
                    guard let header = header as? GridGroupHeader,
                        self.sections.indices.contains(indexPath.section),
                        let group = self.sections[indexPath.section].expandedGroup
                    else { return header }
                    header.configure(
                        count: self.sections[indexPath.section].cells.count, group: group,
                        theme: self.theme,
                        language: self.language,
                        fold: self.foldExpandedGroup)
                    return header
                }
                let footer = view.dequeueReusableSupplementaryView(
                    ofKind: kind, withReuseIdentifier: "placeholders", for: indexPath)
                if let footer = footer as? GridPlaceholderFooter {
                    let safeWidth = view.safeAreaLayoutGuide.layoutFrame.width
                    let footerWidth = safeWidth > 0 ? safeWidth : view.bounds.width
                    let columns =
                        self.columnCount
                        ?? GridCollectionView.columns(
                            width: footerWidth,
                            regular: view.traitCollection.horizontalSizeClass == .regular,
                            compactHeight: view.traitCollection.verticalSizeClass == .compact)
                    footer.configure(
                        count: self.placeholderCount, columns: columns, theme: self.theme)
                }
                return footer
            }
            // A long press starts multi-select (PRD P0-09) and sweeps across cells while dragged.
            let longPress = UILongPressGestureRecognizer(
                target: self, action: #selector(handleLongPress(_:)))
            collectionView.addGestureRecognizer(longPress)
            longPressRecognizer = longPress

            let selectionPan = UIPanGestureRecognizer(
                target: self, action: #selector(handleSelectionPan(_:)))
            selectionPan.delegate = self
            selectionPan.maximumNumberOfTouches = 1
            selectionPan.isEnabled = setSelection != nil && isSelecting
            collectionView.addGestureRecognizer(selectionPan)
            selectionPanRecognizer = selectionPan
            collectionView.panGestureRecognizer.require(toFail: selectionPan)
        }

        /// Applies the runs SwiftUI handed over, holding the anchor cell's place (PRD P0-11).
        ///
        /// The anchor is measured before the snapshot changes: the cell that draws the current
        /// photo when the grid shows one, else the top visible cell. ``GridAnchorRule`` answers
        /// which cell takes that place afterwards, including when a filter or a group
        /// refinement removed the anchor, and the view scrolls that cell back to the same
        /// distance from the top. A refinement that moves the photo into a group with a new key
        /// still holds the photo, because both sides resolve the photo to its cell before the
        /// old place is measured and after the new cells arrive (PRD Grid, P0-11).
        ///
        /// Group Focus replaces the folder's run with the group's own run: entering starts that
        /// run at its header, folding gives the folder back its place, and later changes bring the
        /// current photo into view (issue #309).
        func apply(
            sections newSections: [GridSection], groups newGroups: [BrowsingGroup],
            shownPhotos newShownPhotos: Set<PhotoIdentity>, currentPhoto: PhotoIdentity?,
            selection newSelection: Set<PhotoIdentity>, sizeClass: UserInterfaceSizeClass?,
            verticalSizeClass: UserInterfaceSizeClass?,
            theme newTheme: CloveTheme,
            language newLanguage: ResolvedAppLanguage,
            isSelectingEmpty newSelectingEmpty: Bool,
            areGroupsUnfolded newAreGroupsUnfolded: Bool,
            reduceMotion: Bool
        ) {
            guard let collectionView, let dataSource else { return }
            let newItems = newSections.flatMap(\.cells)
            let wasEmpty = items.isEmpty
            let oldAreGroupsUnfolded = areGroupsUnfolded
            areGroupsUnfolded = newAreGroupsUnfolded
            let willBeSelecting = newSelectingEmpty || !newSelection.isEmpty
            if !willBeSelecting {
                pendingLongPressAnchorPhoto = nil
            }
            let styleChanged =
                theme != newTheme || language != newLanguage
                || isSelectingEmpty != newSelectingEmpty
                || drawnHighlight != highlightsCurrentPhoto
            let newHighlightedCellID: GridCellItem.ID? =
                highlightsCurrentPhoto
                ? currentPhoto.flatMap {
                    GridCellItem.cell(
                        for: $0, in: newItems, groups: newGroups, shown: newShownPhotos)
                }
                : nil
            let highlightChanged =
                highlightsCurrentPhoto && highlightedCellID != newHighlightedCellID && !styleChanged
            // The split pane's grid follows the open member, and its grid opens on the photo the
            // person left (#225, #309).
            let followsMoved =
                followsCurrentPhoto && (wasEmpty || drawnCurrentPhoto != currentPhoto)
            let highlightCells = Set([highlightedCellID, newHighlightedCellID].compactMap { $0 })
            highlightedCellID = newHighlightedCellID
            drawnCurrentPhoto = currentPhoto
            drawnHighlight = highlightsCurrentPhoto
            self.currentPhoto = currentPhoto
            theme = newTheme
            language = newLanguage
            isSelectingEmpty = newSelectingEmpty
            if sizeClass != lastSizeClass || verticalSizeClass != lastVerticalSizeClass {
                lastSizeClass = sizeClass
                lastVerticalSizeClass = verticalSizeClass
                collectionView.collectionViewLayout.invalidateLayout()
            }

            let oldFocusGroup = sections.compactMap(\.expandedGroup).first
            let newFocusGroup = newSections.compactMap(\.expandedGroup).first
            let before = BatchSelection(groups: groups, selection: selection)
            let after = BatchSelection(groups: newGroups, selection: newSelection)
            let previousTrayPositions = trayPositionsByID
            let newTrayPositions = computeTrayPositions(
                in: newSections, columns: activeColumns(in: collectionView))
            trayPositionsByID = newTrayPositions

            guard newSections != sections else {
                groups = newGroups
                shownPhotos = newShownPhotos
                selection = newSelection
                selectionPanRecognizer?.isEnabled = setSelection != nil && isSelecting
                let restyled = items.compactMap { item in
                    if highlightChanged && highlightCells.contains(item.id) { return item.id }
                    if previousTrayPositions[item.id] != newTrayPositions[item.id] {
                        return item.id
                    }
                    return !styleChanged && before.showsSelected(item) == after.showsSelected(item)
                        ? nil : item.id
                }
                if !restyled.isEmpty {
                    // Only the cells whose selection changed are redrawn, so a toggle never
                    // re-decodes a thumbnail (PRD P0-09, P0-03).
                    var snapshot = dataSource.snapshot()
                    snapshot.reconfigureItems(restyled)
                    dataSource.apply(snapshot, animatingDifferences: false)
                }
                if followsMoved {
                    follow()
                    updateSettledAnchor()
                }
                return
            }

            let previousIDs = items.map(\.id)
            pendingResizeAnchor = nil
            settledResizeAnchor = nil
            let previousByID = itemsByID
            let entersFocus = oldFocusGroup == nil && newFocusGroup != nil
            let leavesFocus = oldFocusGroup != nil && newFocusGroup == nil
            let previousPhotoIDs = Set(items.map(\.photo.id))
            let newPhotoIDs = Set(newItems.map(\.photo.id))
            let isGroupFoldTransition =
                oldAreGroupsUnfolded != newAreGroupsUnfolded
                && !entersFocus && !leavesFocus
                && !wasEmpty && !newItems.isEmpty
                && !previousPhotoIDs.isDisjoint(with: newPhotoIDs)
            // Group Focus replaces the folder's run with the group's own run, so the folder's
            // place is kept beside it and given back when the person folds (#309).
            let folderOffsetBeforeFocus: CGFloat? =
                entersFocus ? collectionView.contentOffset.y : nil
            let foldedOffsetY: CGFloat? = leavesFocus ? folderOffsetBeforeGroupFocus : nil
            if leavesFocus { folderOffsetBeforeGroupFocus = nil }

            // Measure against the existing layout and section plans before updating them (#241).
            // Both level transitions place their own content, so neither holds an old cell.
            let held: HeldPlace? =
                if entersFocus || leavesFocus {
                    nil
                } else {
                    hold(
                        currentPhoto: currentPhoto, groups: groups, shownPhotos: shownPhotos,
                        preferLongPressOrVisibleAnchor: isGroupFoldTransition)
                }
            pendingLongPressAnchorPhoto = nil
            let plans = newSections.map { SectionPlan(isGroup: $0.expandedGroup != nil) }
            if plans != sectionPlans {
                sectionPlans = plans
                // A group run adds a header and a surface, which the layout bounds.
                collectionView.collectionViewLayout.invalidateLayout()
            }
            sections = newSections
            items = newItems
            groups = newGroups
            shownPhotos = newShownPhotos
            selection = newSelection
            selectionPanRecognizer?.isEnabled = setSelection != nil && isSelecting
            itemsByID = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })
            if var drag = dragSelection {
                if let remapped = newItems.firstIndex(where: { $0.photo.id == drag.anchorPhotoID })
                {
                    drag.anchorIndex = remapped
                }
                dragSelection = drag
            }

            var snapshot = NSDiffableDataSourceSnapshot<GridSection.ID, GridCellItem.ID>()
            snapshot.appendSections(newSections.map(\.id))
            for section in newSections {
                snapshot.appendItems(section.cells.map(\.id), toSection: section.id)
            }
            let changed: [GridCellItem.ID] = newItems.compactMap { item in
                if highlightChanged && highlightCells.contains(item.id) { return item.id }
                guard let old = previousByID[item.id] else { return nil }
                if old != item || styleChanged
                    || previousTrayPositions[item.id] != newTrayPositions[item.id]
                {
                    return item.id
                }
                return before.showsSelected(old) != after.showsSelected(item) ? item.id : nil
            }
            if !changed.isEmpty { snapshot.reconfigureItems(changed) }

            if isGroupFoldTransition && !reduceMotion {
                UIView.animate(
                    withDuration: 0.28,
                    delay: 0,
                    usingSpringWithDamping: 0.86,
                    initialSpringVelocity: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState]
                ) {
                    dataSource.apply(snapshot, animatingDifferences: true)
                    if let held {
                        self.restore(
                            held: held, previousIDs: previousIDs, newItems: newItems,
                            newGroups: newGroups, newShownPhotos: newShownPhotos,
                            currentPhoto: currentPhoto,
                            mapGroupFoldAnchors: true)
                    }
                }
            } else {
                dataSource.apply(snapshot, animatingDifferences: false)

                if let foldedOffsetY {
                    if collectionView.bounds.height > 0 {
                        collectionView.layoutIfNeeded()
                    }
                    scrollToClampedOffsetY(foldedOffsetY)
                } else if let held {
                    restore(
                        held: held, previousIDs: previousIDs, newItems: newItems,
                        newGroups: newGroups, newShownPhotos: newShownPhotos,
                        currentPhoto: currentPhoto,
                        mapGroupFoldAnchors: isGroupFoldTransition)
                }
            }

            if entersFocus {
                folderOffsetBeforeGroupFocus =
                    folderOffsetBeforeFocus ?? -collectionView.adjustedContentInset.top
                if collectionView.bounds.height > 0 {
                    collectionView.layoutIfNeeded()
                }
                // Group Focus opens on its count header and fold control, so the fold is always
                // discoverable even when the Representative Photo is far down a long run. A member
                // beyond that first viewport is not centered away from them (#290, #309).
                scrollToClampedOffsetY(-collectionView.adjustedContentInset.top)
            } else if leavesFocus || followsMoved {
                // Later changes follow their photo: the member the person chooses inside Group
                // Focus, or the stack a fold leaves (#225, #241, #290).
                follow()
            }
            updateSettledAnchor()
        }

        /// One cell tapped: multi-select toggles it, a collapsed cover opens its group, and any
        /// other cell opens detail (PRD P0-09, PRD Grid).
        func collectionView(
            _ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath
        ) {
            collectionView.deselectItem(at: indexPath, animated: false)
            guard let item = item(at: indexPath) else { return }
            if isSelecting {
                if !areGroupsUnfolded {
                    pendingLongPressAnchorPhoto = item.photo.id
                    completeGroupUnfold()
                }
                toggleSelection(item)
            } else if let group = item.group, group.isCover {
                openGroup(group.id)
            } else {
                openPhoto(item.photo.id)
            }
        }

        /// Allows the 1-finger selection pan only when already in multi-select and moving
        /// predominantly horizontally, so vertical scrolling stays untouched.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === selectionPanRecognizer else { return true }
            guard setSelection != nil, isSelecting, dragSelection == nil,
                let pan = gestureRecognizer as? UIPanGestureRecognizer,
                let collectionView
            else { return false }
            let velocity = pan.velocity(in: collectionView)
            return abs(velocity.x) > 0 && abs(velocity.x) > abs(velocity.y) * 1.2
        }

        /// A long press starts multi-select on the pressed cell's photos (PRD P0-09) and sweeps
        /// selection across the spanned range while dragged.
        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let collectionView else { return }
            let point = recognizer.location(in: collectionView)
            switch recognizer.state {
            case .began:
                guard dragSelection == nil,
                    let indexPath = collectionView.indexPathForItem(at: point),
                    let item = item(at: indexPath)
                else { return }
                if !isSelecting {
                    pendingLongPressAnchorPhoto = item.photo.id
                }
                if setSelection == nil {
                    beginSelection(item)
                    return
                }
                beginDragSelection(
                    at: indexPath, item: item, fingerPointInCollectionView: point,
                    collectionView: collectionView)
            case .changed:
                guard dragSelection != nil else { return }
                dragSelection?.fingerViewportPoint = CGPoint(
                    x: point.x - collectionView.bounds.origin.x,
                    y: point.y - collectionView.bounds.origin.y)
                updateDragSelection(atCollectionPoint: point, in: collectionView)
                updateAutoScrollState()
            case .ended, .cancelled, .failed:
                stopDragSelection()
            default:
                break
            }
        }

        /// Horizontal 1-finger pan sweeps selection while already in multi-select mode.
        @objc private func handleSelectionPan(_ recognizer: UIPanGestureRecognizer) {
            guard let collectionView else { return }
            let point = recognizer.location(in: collectionView)
            switch recognizer.state {
            case .began:
                guard dragSelection == nil else { return }
                let translation = recognizer.translation(in: collectionView)
                let startPoint = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
                guard
                    let startIndexPath = collectionView.indexPathForItem(at: startPoint)
                        ?? nearestIndexPath(to: startPoint, in: collectionView),
                    let item = item(at: startIndexPath)
                else { return }
                if isSelecting && !areGroupsUnfolded {
                    pendingLongPressAnchorPhoto = item.photo.id
                    completeGroupUnfold()
                }
                beginDragSelection(
                    at: startIndexPath, item: item, fingerPointInCollectionView: point,
                    collectionView: collectionView)
                updateDragSelection(atCollectionPoint: point, in: collectionView)
                updateAutoScrollState()
            case .changed:
                guard dragSelection != nil else { return }
                dragSelection?.fingerViewportPoint = CGPoint(
                    x: point.x - collectionView.bounds.origin.x,
                    y: point.y - collectionView.bounds.origin.y)
                updateDragSelection(atCollectionPoint: point, in: collectionView)
                updateAutoScrollState()
            case .ended, .cancelled, .failed:
                stopDragSelection()
            default:
                break
            }
        }

        private func beginDragSelection(
            at indexPath: IndexPath,
            item: GridCellItem,
            fingerPointInCollectionView point: CGPoint,
            collectionView: UICollectionView
        ) {
            guard let anchorIndex = flatIndex(for: indexPath) else { return }
            let baseline = selection
            let selecting = isSelecting ? !showsSelected(item) : true
            let fingerViewportPoint = CGPoint(
                x: point.x - collectionView.bounds.origin.x,
                y: point.y - collectionView.bounds.origin.y)
            dragSelection = DragSelectionState(
                anchorPhotoID: item.photo.id,
                anchorIndex: anchorIndex,
                baseline: baseline,
                selecting: selecting,
                lastCurrentIndex: anchorIndex,
                fingerViewportPoint: fingerViewportPoint)
            let updated = BatchSelection(groups: groups, selection: baseline).rangeSelection(
                in: items, anchorIndex: anchorIndex, currentIndex: anchorIndex,
                selecting: selecting)
            if isSelecting && updated.isEmpty {
                keepSelectingWhenEmpty()
            }
            setSelection?(updated)
            updateAutoScrollState()
        }

        private func updateDragSelection(
            atCollectionPoint point: CGPoint,
            in collectionView: UICollectionView
        ) {
            guard var drag = dragSelection else { return }
            guard
                let indexPath = collectionView.indexPathForItem(at: point)
                    ?? nearestIndexPath(to: point, in: collectionView),
                let currentIndex = flatIndex(for: indexPath)
            else { return }
            guard currentIndex != drag.lastCurrentIndex else { return }
            drag.lastCurrentIndex = currentIndex
            dragSelection = drag
            let updated = BatchSelection(groups: groups, selection: drag.baseline).rangeSelection(
                in: items, anchorIndex: drag.anchorIndex, currentIndex: currentIndex,
                selecting: drag.selecting)
            if isSelecting && updated.isEmpty {
                keepSelectingWhenEmpty()
            }
            setSelection?(updated)
        }

        func stopDragSelection() {
            dragSelection = nil
            stopAutoScroll()
        }

        private func updateAutoScrollState() {
            guard let drag = dragSelection, let collectionView,
                autoScrollVelocity(
                    in: collectionView, fingerViewportPoint: drag.fingerViewportPoint)
                    != 0
            else {
                stopAutoScroll()
                return
            }
            guard autoScrollLink == nil else { return }
            let proxy = DisplayLinkProxy(target: self)
            let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
            link.add(to: .main, forMode: .common)
            autoScrollTarget = proxy
            autoScrollLink = link
            lastAutoScrollTimestamp = nil
        }

        private func stopAutoScroll() {
            autoScrollLink?.invalidate()
            autoScrollLink = nil
            autoScrollTarget = nil
            lastAutoScrollTimestamp = nil
        }

        fileprivate func autoScrollTick(_ link: CADisplayLink) {
            guard let drag = dragSelection, let collectionView else {
                stopAutoScroll()
                return
            }
            let dt =
                lastAutoScrollTimestamp.map { min(max(link.timestamp - $0, 0), 0.05) }
                ?? (1.0 / 60.0)
            lastAutoScrollTimestamp = link.timestamp
            let velocity = autoScrollVelocity(
                in: collectionView, fingerViewportPoint: drag.fingerViewportPoint)
            guard velocity != 0 else {
                stopAutoScroll()
                return
            }
            let insets = collectionView.adjustedContentInset
            let minY = -insets.top
            let maxY = max(
                collectionView.contentSize.height + insets.bottom - collectionView.bounds.height,
                minY)
            let nextY = min(max(collectionView.contentOffset.y + velocity * dt, minY), maxY)
            guard abs(nextY - collectionView.contentOffset.y) > 0.25 else {
                stopAutoScroll()
                return
            }
            collectionView.setContentOffset(
                CGPoint(x: collectionView.contentOffset.x, y: nextY), animated: false)
            let point = CGPoint(
                x: drag.fingerViewportPoint.x + collectionView.bounds.origin.x,
                y: drag.fingerViewportPoint.y + collectionView.bounds.origin.y)
            updateDragSelection(atCollectionPoint: point, in: collectionView)
        }

        private func autoScrollVelocity(
            in collectionView: UICollectionView,
            fingerViewportPoint: CGPoint
        ) -> CGFloat {
            let edgeMargin: CGFloat = 44
            let maxSpeed: CGFloat = 420
            let insets = collectionView.adjustedContentInset
            let visibleTop = insets.top
            let visibleBottom = collectionView.bounds.height - insets.bottom
            guard visibleBottom - visibleTop > edgeMargin * 2 else { return 0 }
            let topThreshold = visibleTop + edgeMargin
            let bottomThreshold = visibleBottom - edgeMargin
            if fingerViewportPoint.y < topThreshold {
                let fraction = min(max((topThreshold - fingerViewportPoint.y) / edgeMargin, 0), 1)
                return -fraction * maxSpeed
            }
            if fingerViewportPoint.y > bottomThreshold {
                let fraction = min(
                    max((fingerViewportPoint.y - bottomThreshold) / edgeMargin, 0), 1)
                return fraction * maxSpeed
            }
            return 0
        }

        private func flatIndex(for indexPath: IndexPath) -> Int? {
            guard sections.indices.contains(indexPath.section),
                sections[indexPath.section].cells.indices.contains(indexPath.item)
            else { return nil }
            var offset = 0
            for sectionIndex in 0..<indexPath.section {
                offset += sections[sectionIndex].cells.count
            }
            return offset + indexPath.item
        }

        private func nearestIndexPath(
            to point: CGPoint,
            in collectionView: UICollectionView
        ) -> IndexPath? {
            let visible = collectionView.indexPathsForVisibleItems
            guard !visible.isEmpty else { return nil }
            let candidates: [(indexPath: IndexPath, frame: CGRect)] = visible.compactMap {
                indexPath in
                guard let attributes = collectionView.layoutAttributesForItem(at: indexPath)
                else { return nil }
                return (indexPath, attributes.frame)
            }
            guard !candidates.isEmpty else { return nil }
            let sameRow = candidates.filter {
                point.y >= $0.frame.minY - 2 && point.y <= $0.frame.maxY + 2
            }
            if let bestSameRow = sameRow.min(by: {
                horizontalDistance(from: point.x, to: $0.frame)
                    < horizontalDistance(from: point.x, to: $1.frame)
            }) {
                return bestSameRow.indexPath
            }
            return candidates.min(by: {
                squaredDistance(from: point, to: $0.frame)
                    < squaredDistance(from: point, to: $1.frame)
            })?.indexPath
        }

        private func horizontalDistance(from x: CGFloat, to frame: CGRect) -> CGFloat {
            if x < frame.minX { return frame.minX - x }
            if x > frame.maxX { return x - frame.maxX }
            return 0
        }

        private func squaredDistance(from point: CGPoint, to frame: CGRect) -> CGFloat {
            let dx = horizontalDistance(from: point.x, to: frame)
            let dy: CGFloat =
                if point.y < frame.minY {
                    frame.minY - point.y
                } else if point.y > frame.maxY {
                    point.y - frame.maxY
                } else {
                    0
                }
            return dx * dx + dy * dy
        }

        /// Requests the next screenful before the cells appear (PRD P0-03, G1 scheduling row).
        func collectionView(
            _ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]
        ) {
            for indexPath in indexPaths {
                guard let item = item(at: indexPath), prefetchRequests[item.id] == nil else {
                    continue
                }
                let needsPrimary = thumbnails.cachedThumbnail(for: item.photo.id) == nil
                let peeking =
                    (item.group?.isCover == true ? (item.group?.peekingPhotos ?? []) : [])
                    .filter { thumbnails.cachedThumbnail(for: $0) == nil }
                guard needsPrimary || !peeking.isEmpty else { continue }
                let token = UUID()
                let task = Task { [weak self] in
                    if needsPrimary {
                        _ = await self?.thumbnails.thumbnail(
                            for: item.photo.id, priority: .prefetch)
                    }
                    for member in peeking {
                        guard !Task.isCancelled else { break }
                        _ = await self?.thumbnails.thumbnail(for: member, priority: .prefetch)
                    }
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

        /// A cell about to show: keep any in-flight prefetch alive so the visible request coalesces
        /// onto and promotes the partial decode instead of restarting from scratch.
        func collectionView(
            _ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            guard let cell = cell as? GridPhotoCell else { return }
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
            guard sections.indices.contains(indexPath.section) else { return nil }
            let cells = sections[indexPath.section].cells
            guard cells.indices.contains(indexPath.item) else { return nil }
            return cells[indexPath.item]
        }

        /// The place one cell draws in, across the grid's runs.
        private func indexPath(of id: GridCellItem.ID) -> IndexPath? {
            for (section, run) in sections.enumerated() {
                if let item = run.cells.firstIndex(where: { $0.id == id }) {
                    return IndexPath(item: item, section: section)
                }
            }
            return nil
        }

        /// Keeps the photo on screen in view for a change inside a level: the member chosen in
        /// Group Focus, or the stack a fold leaves (#225, #241, #290). Entry does not use it, so a
        /// long run's header and fold control stay where the person can find them (#309).
        private func follow() {
            guard followsCurrentPhoto, let collectionView, let currentPhoto,
                let cell = GridCellItem.cell(
                    for: currentPhoto, in: items, groups: groups, shown: shownPhotos),
                let indexPath = indexPath(of: cell)
            else { return }
            if collectionView.bounds.height > 0 {
                collectionView.layoutIfNeeded()
            }
            guard !isItemVisible(at: indexPath, in: collectionView) else { return }
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        }

        private func isItemVisible(at indexPath: IndexPath, in collectionView: UICollectionView)
            -> Bool
        {
            let insets = collectionView.adjustedContentInset
            let visibleHeight = collectionView.bounds.height - insets.top - insets.bottom
            guard visibleHeight > 0,
                let attributes = collectionView.layoutAttributesForItem(at: indexPath)
            else {
                return collectionView.indexPathsForVisibleItems.contains(indexPath)
            }
            let visibleTop = collectionView.contentOffset.y + insets.top
            let visibleBottom =
                collectionView.contentOffset.y + collectionView.bounds.height - insets.bottom
            if attributes.frame.height <= visibleHeight + 0.5 {
                return attributes.frame.minY >= visibleTop - 0.5
                    && attributes.frame.maxY <= visibleBottom + 0.5
            }
            return attributes.frame.maxY > visibleTop + 0.5
                && attributes.frame.minY < visibleBottom - 0.5
        }

        /// Whether the grid is in multi-select, which a non-empty selection means (PRD P0-09).
        private var isSelecting: Bool { isSelectingEmpty || !selection.isEmpty }

        /// Whether one cell draws as selected (PRD P0-09).
        private func showsSelected(_ item: GridCellItem) -> Bool {
            BatchSelection(groups: groups, selection: selection).showsSelected(item)
        }

        /// One anchor cell's old place on screen, and whether the current photo chose it (PRD P0-11).
        private struct HeldPlace {
            let id: GridCellItem.ID
            let photoID: PhotoIdentity?
            let offset: CGFloat?
            let isCurrentPhoto: Bool
        }

        /// The anchor cell and its distance from the top of the visible area, before an update.
        ///
        /// During inline fold/unfold transitions, a pressed tile (long press, tap, or pan start)
        /// wins first, then a visible current photo, else the top-most visible cell.
        /// For ordinary updates, the current photo wins when drawn, else the top visible cell.
        private func hold(
            currentPhoto: PhotoIdentity?, groups: [BrowsingGroup],
            shownPhotos: Set<PhotoIdentity>,
            preferLongPressOrVisibleAnchor: Bool = false
        ) -> HeldPlace? {
            guard let collectionView, !items.isEmpty else { return nil }
            if preferLongPressOrVisibleAnchor {
                if let anchorPhoto = pendingLongPressAnchorPhoto,
                    let cell = items.first(where: { $0.photo.id == anchorPhoto })?.id
                        ?? GridCellItem.cell(
                            for: anchorPhoto, in: items, groups: groups, shown: shownPhotos),
                    let offset = viewportOffset(of: cell)
                {
                    return HeldPlace(
                        id: cell, photoID: anchorPhoto, offset: offset, isCurrentPhoto: false)
                }
                if let currentPhoto,
                    let cell = GridCellItem.cell(
                        for: currentPhoto, in: items, groups: groups, shown: shownPhotos),
                    let indexPath = indexPath(of: cell),
                    isItemVisible(at: indexPath, in: collectionView),
                    let offset = viewportOffset(of: cell)
                {
                    return HeldPlace(
                        id: cell, photoID: currentPhoto, offset: offset, isCurrentPhoto: true)
                }
                guard let first = firstVisibleCellIndexPath(in: collectionView),
                    let anchorItem = item(at: first)
                else { return nil }
                let anchorPhoto: PhotoIdentity? =
                    (anchorItem.group?.isCover == true) ? nil : anchorItem.photo.id
                return HeldPlace(
                    id: anchorItem.id, photoID: anchorPhoto,
                    offset: viewportOffset(of: anchorItem.id), isCurrentPhoto: false)
            }
            if let currentPhoto,
                let cell = GridCellItem.cell(
                    for: currentPhoto, in: items, groups: groups, shown: shownPhotos),
                let offset = viewportOffset(of: cell)
            {
                return HeldPlace(
                    id: cell, photoID: currentPhoto, offset: offset, isCurrentPhoto: true)
            }
            guard let first = collectionView.indexPathsForVisibleItems.min(),
                let anchor = item(at: first)?.id
            else { return nil }
            return HeldPlace(
                id: anchor, photoID: nil, offset: viewportOffset(of: anchor), isCurrentPhoto: false)
        }

        /// How far one cell sits below the visible area's top edge, negative when above it.
        private func viewportOffset(of id: GridCellItem.ID) -> CGFloat? {
            guard let collectionView, let indexPath = indexPath(of: id),
                let attributes = collectionView.layoutAttributesForItem(at: indexPath)
            else { return nil }
            return attributes.frame.minY - collectionView.contentOffset.y
        }

        private func restore(
            held: HeldPlace, previousIDs: [GridCellItem.ID], newItems: [GridCellItem],
            newGroups: [BrowsingGroup], newShownPhotos: Set<PhotoIdentity>,
            currentPhoto: PhotoIdentity?,
            mapGroupFoldAnchors: Bool = false
        ) {
            // The current photo may now be drawn by a different cell, such as a cover keyed by
            // a refined group; hold that cell where the photo's old cell was.
            if held.isCurrentPhoto, let currentPhoto,
                let cell = GridCellItem.cell(
                    for: currentPhoto, in: newItems, groups: newGroups,
                    shown: newShownPhotos)
            {
                restore(cell, offset: held.offset)
                return
            }
            if mapGroupFoldAnchors {
                if let photoID = held.photoID,
                    let cell = newItems.first(where: { $0.photo.id == photoID })?.id
                        ?? GridCellItem.cell(
                            for: photoID, in: newItems, groups: newGroups,
                            shown: newShownPhotos)
                {
                    restore(cell, offset: held.offset)
                    return
                }
                if case .group(let groupID) = held.id,
                    let firstMemberCell = newItems.first(where: { $0.group?.id == groupID })?.id
                {
                    restore(firstMemberCell, offset: held.offset)
                    return
                }
                if case .photo(let photoID) = held.id,
                    let coverOrSelf = GridCellItem.cell(
                        for: photoID, in: newItems, groups: newGroups,
                        shown: newShownPhotos)
                {
                    restore(coverOrSelf, offset: held.offset)
                    return
                }
            }
            if newItems.contains(where: { $0.id == held.id }) {
                restore(held.id, offset: held.offset)
            } else if let index = GridAnchorRule.newIndex(
                of: held.id, previous: previousIDs, in: newItems.map(\.id))
            {
                restore(newItems[index].id, offset: held.offset)
            }
        }

        /// Scrolls the held cell back to its distance from the top before the update, clamped to
        /// the scrollable range.
        private func restore(_ id: GridCellItem.ID, offset: CGFloat?) {
            guard let collectionView else { return }
            if collectionView.bounds.height > 0 {
                collectionView.layoutIfNeeded()
            }
            guard let indexPath = indexPath(of: id),
                let frameMinY = collectionView.layoutAttributesForItem(at: indexPath)?.frame.minY
            else { return }
            scrollToClampedOffsetY(frameMinY - (offset ?? 0))
        }

        private func scrollToClampedOffsetY(_ requestedY: CGFloat) {
            guard let collectionView else { return }
            let insets = collectionView.adjustedContentInset
            let minimum = -insets.top
            let maximum = max(
                collectionView.contentSize.height + insets.bottom - collectionView.bounds.height,
                minimum)
            let y = min(max(requestedY, minimum), maximum)
            guard abs(y - collectionView.contentOffset.y) > 0.5 else { return }
            collectionView.setContentOffset(
                CGPoint(x: collectionView.contentOffset.x, y: y), animated: false)
        }
    }
}

@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var target: GridCollectionView.Coordinator?

    init(target: GridCollectionView.Coordinator) {
        self.target = target
    }

    @objc func tick(_ link: CADisplayLink) {
        target?.autoScrollTick(link)
    }
}
