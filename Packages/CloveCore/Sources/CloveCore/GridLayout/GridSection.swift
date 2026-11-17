import Foundation

/// One run of the folder grid drawn together (PRD Grid, P0-11).
///
/// ``GridDisplay`` joins the shown photos with the published groups. A run is either the folder's
/// own cells, or the one group Detail is focused on: its visible members draw with a header and a
/// shared surface in place of their collapsed cover (issue #309). Only a group run gets a header
/// and a surface, which leaves every other grid exactly as it was.
public struct GridSection: Identifiable, Hashable, Sendable {
    /// What the run draws: the folder's own cells, or the group in Group Focus.
    public enum ID: Hashable, Sendable {
        /// A run of the folder's own photos and its collapsed groups.
        case photos

        /// The group Detail is focused on (Group Focus).
        case group(GroupID)
    }

    /// The run's stable identity across grid updates.
    public let id: ID

    /// The cells the run draws, in grid order.
    public let cells: [GridCellItem]

    /// Describes one run of cells.
    public init(id: ID, cells: [GridCellItem]) {
        self.id = id
        self.cells = cells
    }

    /// The focused group this run draws, or nil for the folder's own run.
    public var expandedGroup: GroupID? {
        guard case .group(let id) = id else { return nil }
        return id
    }
}
