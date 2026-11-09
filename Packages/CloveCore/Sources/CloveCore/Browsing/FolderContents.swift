/// One similar group as the browsing screens and restore validation see it (PRD P0-11, P0-14).
///
/// Grouping publishes groups with refinement details it owns; this value keeps only what browsing
/// needs, so the screens never depend on the grouping algorithm and the in-memory library can
/// stand in for it until grouping lands.
public struct BrowsingGroup: Identifiable, Hashable, Sendable {
    /// The stable group key that survives refinement and Run again (PRD P0-11).
    public let id: GroupID

    /// Members in the group view's order; a published group holds at least two (PRD P0-11).
    public let members: [PhotoIdentity]

    /// Describes one group by its key and members, in the order the group view shows them.
    public init(id: GroupID, members: [PhotoIdentity]) {
        self.id = id
        self.members = members
    }
}

/// What an open folder holds now: the facts restore validation checks a saved state against
/// (PRD P0-13, P0-14).
///
/// A folder changes between launches, so the saved state is only a request. Everything here comes
/// from the scan and grouping of the folder as it is this launch; the value does no I/O.
public struct FolderContents: Hashable, Sendable {
    /// The open folder's durable key. A saved state for another folder never applies here
    /// (G1 folder access).
    public let folder: FolderIdentity

    /// Every photo a grid can show, by identity. Order and filter are not read; lookups are.
    public let photos: [PhotoIdentity]

    /// The published groups, empty when grouping is off (PRD P0-11).
    public let groups: [BrowsingGroup]

    /// Records what the folder holds now, for restore validation to narrow a saved state.
    public init(folder: FolderIdentity, photos: [PhotoIdentity], groups: [BrowsingGroup] = []) {
        self.folder = folder
        self.photos = photos
        self.groups = groups
    }

    /// The group with one stable key, or nil when grouping no longer publishes it (PRD P0-11).
    public func group(with id: GroupID) -> BrowsingGroup? {
        groups.first { $0.id == id }
    }

    /// The group holding one photo, or nil when the photo is not grouped (PRD P0-11).
    public func group(containing photo: PhotoIdentity) -> BrowsingGroup? {
        groups.first { $0.members.contains(photo) }
    }

    /// The group-view place the folder can still show, or nil when it can show none.
    ///
    /// PRD P0-14 keeps the group-view position across a fold or a relaunch, and PRD P0-11 lets
    /// grouping refine between them. The saved group wins while it still holds the saved photo;
    /// otherwise the group that holds that photo now is used, so the view stays on the same photo;
    /// when neither exists the position is dropped and the caller returns to the grid.
    public func position(for saved: BrowsingGroupPosition) -> BrowsingGroupPosition? {
        if let group = group(with: saved.group), group.members.contains(saved.photo) {
            return saved
        }
        if let group = group(containing: saved.photo) {
            return BrowsingGroupPosition(group: group.id, photo: saved.photo)
        }
        return nil
    }
}

/// The saved folder as a launch finds it: readable, or with the reason it did not open
/// (PRD P0-02, P0-14).
///
/// PRD P0-02 requires asking for the folder again instead of failing silently, so the reason is
/// carried to entry rather than flattened into "unavailable".
public enum FolderAvailability: Hashable, Sendable {
    /// The folder opened and holds what this launch's scan found.
    case available(FolderContents)

    /// The folder did not open; entry asks for a new selection and keeps this reason
    /// (PRD P0-02).
    case unavailable(FolderAccessFailure)
}
