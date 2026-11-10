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

    /// The photos one cell adds or removes (PRD P0-09, PRD Grid).
    ///
    /// A photo's own cell means that photo. A collapsed group's cover means every photo in its
    /// group, including members the current filter hides, because the cover stands for the
    /// group the user sees it for. A cover whose group is no longer published falls back to its
    /// own photo, so a stale cell never selects a group nobody can open.
    public func identities(for cell: GridCellItem) -> Set<PhotoIdentity> {
        guard let mark = cell.group, mark.isCover,
            let group = groups.first(where: { $0.id == mark.id })
        else { return [cell.photo.id] }
        let members = Set(group.members)
        return members.isEmpty ? [cell.photo.id] : members
    }

    /// The selection after tapping one cell (PRD P0-09).
    ///
    /// A tap adds the cell's photos, or removes all of them when every one is already selected.
    /// A collapsed cover that is only partly selected therefore completes its group rather than
    /// clearing the part the user already chose.
    public func toggling(_ cell: GridCellItem) -> Set<PhotoIdentity> {
        let identities = identities(for: cell)
        if identities.isSubset(of: selection) {
            return selection.subtracting(identities)
        }
        return selection.union(identities)
    }

    /// The selection with one cell's photos added, for the long press that starts multi-select
    /// (PRD P0-09).
    public func selecting(_ cell: GridCellItem) -> Set<PhotoIdentity> {
        selection.union(identities(for: cell))
    }

    /// The selection with every shown cell added, for Select all visible (PRD P0-09).
    ///
    /// A collapsed cover adds its whole group, so Select all covers every photo the user sees
    /// a cell for instead of only the covers' own photos.
    public func selectingAll(_ cells: [GridCellItem]) -> Set<PhotoIdentity> {
        cells.reduce(selection) { current, cell in current.union(identities(for: cell)) }
    }

    /// Whether a cell draws as selected: every photo it stands for is selected (PRD P0-09).
    public func showsSelected(_ cell: GridCellItem) -> Bool {
        identities(for: cell).isSubset(of: selection)
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
