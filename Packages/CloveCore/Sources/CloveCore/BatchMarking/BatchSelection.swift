import Foundation

/// How the grid's cells read into a multi-selection (PRD P0-09, PRD Grid).
///
/// PRD P0-09 enters multi-select from the grid and applies one action to every selected photo.
/// The grid draws two kinds of cell: a photo's own cell, and a collapsed similar group's cover
/// that stands for the whole group (PRD Grid, collapsed). This value answers what one cell means
/// to the selection, so neither the collection view nor the browsing model expands a cover in a
/// way of its own.
///
/// PRD P0-09's selection is unordered (``BrowsingState/selection``), and this value never
/// depends on the order of taps: adding, removing and testing all work on the set, while
/// ``targets(selection:shown:)`` keeps the grid's own order for a batch write.
public struct BatchSelection: Hashable, Sendable {
    /// The groups grouping published for the open folder (PRD P0-11).
    public let groups: [BrowsingGroup]

    /// The photos multi-select has selected (PRD P0-09, P0-14).
    public let selection: Set<PhotoIdentity>

    /// Reads one selection against the folder's published groups (PRD P0-09).
    public init(groups: [BrowsingGroup] = [], selection: Set<PhotoIdentity> = []) {
        self.groups = groups
        self.selection = selection
    }

    /// The photo one grid cell selects or toggles (PRD P0-09).
    ///
    /// Select mode strictly maintains 1 cell = 1 visible photo: even if a cell is momentarily a
    /// collapsed cover during entry, interacting with it operates only on its visible cover photo
    /// (`cell.photo.id`) and never pulls in hidden or unshown group members.
    public func identities(for cell: GridCellItem) -> Set<PhotoIdentity> {
        [cell.photo.id]
    }

    /// The selection after tapping one cell (PRD P0-09).
    ///
    /// A tap adds the cell's photo, or removes it when already selected.
    public func toggling(_ cell: GridCellItem) -> Set<PhotoIdentity> {
        let identities = identities(for: cell)
        if identities.isSubset(of: selection) {
            return selection.subtracting(identities)
        }
        return selection.union(identities)
    }

    /// The selection with one cell's visible photo added, for the long press that starts
    /// multi-select (PRD P0-09).
    public func selecting(_ cell: GridCellItem) -> Set<PhotoIdentity> {
        selection.union(identities(for: cell))
    }

    /// The selection with every visible cell's photo added, for Select all visible (PRD P0-09).
    public func selectingAll(_ cells: [GridCellItem]) -> Set<PhotoIdentity> {
        cells.reduce(selection) { current, cell in current.union(identities(for: cell)) }
    }

    /// The selection with every visible photo added, ensuring Select all works identically even
    /// before inline group unfolding finishes.
    public func selectingAll(_ photos: [GridPhoto]) -> Set<PhotoIdentity> {
        selection.union(photos.map(\.id))
    }

    /// The selection with every visible cell's photo removed, for Deselect all visible (PRD P0-09).
    public func deselectingAll(_ cells: [GridCellItem]) -> Set<PhotoIdentity> {
        cells.reduce(selection) { current, cell in current.subtracting(identities(for: cell)) }
    }

    /// The selection with every visible photo removed while preserving any hidden selected photos.
    public func deselectingAll(_ photos: [GridPhoto]) -> Set<PhotoIdentity> {
        selection.subtracting(photos.map(\.id))
    }

    /// Whether every shown cell currently draws as selected (PRD P0-09).
    public func showsAllSelected(_ cells: [GridCellItem]) -> Bool {
        !cells.isEmpty && cells.allSatisfy(showsSelected)
    }

    /// Whether every visible photo is currently selected.
    public func showsAllSelected(_ photos: [GridPhoto]) -> Bool {
        !photos.isEmpty && photos.allSatisfy { selection.contains($0.id) }
    }

    /// Recomputes a drag-range selection from `selection` (the baseline captured at drag start)
    /// across the contiguous span between `anchorIndex` and `currentIndex` in `cells`.
    public func rangeSelection(
        in cells: [GridCellItem],
        anchorIndex: Int,
        currentIndex: Int,
        selecting: Bool
    ) -> Set<PhotoIdentity> {
        guard !cells.isEmpty,
            cells.indices.contains(anchorIndex),
            cells.indices.contains(currentIndex)
        else { return selection }
        let lower = min(anchorIndex, currentIndex)
        let upper = max(anchorIndex, currentIndex)
        return cells[lower...upper].reduce(selection) { current, cell in
            let cellIdentities = identities(for: cell)
            return selecting ? current.union(cellIdentities) : current.subtracting(cellIdentities)
        }
    }

    /// Whether a cell draws as selected: its visible photo is selected (PRD P0-09).
    public func showsSelected(_ cell: GridCellItem) -> Bool {
        selection.contains(cell.photo.id)
    }

    /// The photos one batch marks: the selection the grid shows, in grid order (PRD P0-09).
    ///
    /// A photo the filter hides stays selected (PRD P0-14 keeps the selection across a filter
    /// change) but is not marked, so a batch never writes a mark for a photo the user cannot
    /// see, and the bar's count is the number of photos it would mark.
    public static func targets(selection: Set<PhotoIdentity>, shown: [GridPhoto]) -> [GridPhoto] {
        shown.filter { selection.contains($0.id) }
    }
}
