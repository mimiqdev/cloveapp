import Foundation

/// One run of the folder grid drawn together (PRD Grid, P0-11; owner decision, #225).
///
/// ``GridDisplay`` joins the shown photos with the published groups. A section adds the one
/// thing the expanded Duo's split needs: the photo's group draws as its own run, with a
/// header and a shared surface, instead of one collapsed cover. That run sits at the group's
/// place in the folder, so the surrounding photos and other collapsed groups keep theirs.
///
/// The folder's own cells are a section too, so the grid always draws from sections and a
/// plain grid is one run. Only a group run gets a header and a surface, which leaves the
/// iPhone, iPad and folded Duo grids exactly as they were.
public struct GridSection: Identifiable, Hashable, Sendable {
    /// What the run draws: the folder's own cells, or one group expanded in place.
    public enum ID: Hashable, Sendable {
        /// A run of the folder's own photos and its collapsed groups. A split expanded group
        /// leaves one run before it (0) and one after it (1), so the plain runs keep their
        /// identity while a group opens and closes.
        case photos(Int)

        /// The photo's group, expanded in place in the Duo's split (owner decision, #225).
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

    /// The expanded group this run draws, or nil for one of the folder's own runs.
    public var expandedGroup: GroupID? {
        guard case .group(let id) = id else { return nil }
        return id
    }
}
