import Foundation

extension SimilarGroups {
    /// The published groups as the browsing screens and restore validation see them
    /// (PRD P0-11, PRD P0-14).
    ///
    /// Grouping publishes its groups in grid order already, keyed by the IDs that survive
    /// refinement and Run again, so this copies the order and the keys and never re-keys a group
    /// (PRD P0-11: the viewed photo and its group stay put through refinement). The refinement
    /// detail and ``GroupAnalysis`` stay with grouping; the grid and the saved scene read only a
    /// group's key and members (PRD Grid, PRD P0-14).
    public var browsingGroups: [BrowsingGroup] {
        groups.map { BrowsingGroup(id: $0.id, members: $0.members) }
    }
}
