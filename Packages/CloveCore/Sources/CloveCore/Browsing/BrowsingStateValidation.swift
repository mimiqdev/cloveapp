/// A saved state after restore validation, with what entry must explain (PRD P0-02, P0-14).
///
/// The state is always usable: restore validation never reports an error, because a saved
/// navigation state is a convenience and must not stop a launch (PRD P0-14).
public struct RestoredBrowsing: Hashable, Sendable {
    /// The browsing state the screens read: the saved one narrowed to the folder as it is now,
    /// or ``BrowsingState/entry``.
    public let state: BrowsingState

    /// Why the saved folder did not open, or nil when there is nothing to explain.
    ///
    /// PRD P0-02 asks for an explicit "select it again" message rather than a silent failure;
    /// entry shows this reason when U2 adds that message.
    public let folderFailure: FolderAccessFailure?

    /// Pairs the restored state with the reason entry explains, if any.
    public init(state: BrowsingState, folderFailure: FolderAccessFailure? = nil) {
        self.state = state
        self.folderFailure = folderFailure
    }
}

extension BrowsingState {
    /// Restore validation: the saved state narrowed to what the folder actually holds now
    /// (PRD P0-14, P0-13).
    ///
    /// A folder that cannot be opened falls back to entry and keeps the reason
    /// (PRD P0-02). A saved state that belongs to another folder, or to no folder at all, never
    /// applies to this one, so it also starts at entry: applying a saved photo to a folder that
    /// does not hold it would show the wrong set.
    ///
    /// A photo that no longer exists is dropped, so a detail route on it falls back to the grid;
    /// the multi-selection drops missing photos (PRD P0-09); the group-view position keeps the
    /// saved group while it still holds the saved photo, else moves to the group holding that
    /// photo, else drops, so a group route on it falls back to the grid (PRD P0-11, P0-12).
    ///
    /// The function is pure: it reads no file and changes no folder.
    public func restored(from folder: FolderAvailability) -> RestoredBrowsing {
        switch folder {
        case .unavailable(let failure):
            return RestoredBrowsing(state: .entry, folderFailure: failure)
        case .available(let contents):
            return RestoredBrowsing(state: restored(in: contents))
        }
    }

    /// The saved state narrowed to one folder's contents, or entry when it does not apply.
    private func restored(in contents: FolderContents) -> BrowsingState {
        guard folder == contents.folder else { return .entry }

        var state = self
        if let photo = state.currentPhoto, !contents.photos.contains(photo) {
            state.currentPhoto = nil
        }
        state.selection.formIntersection(contents.photos)
        state.groupPosition = state.groupPosition.flatMap(contents.position(for:))

        switch state.route {
        case .entry, .grid, .settings:
            break
        case .detail where state.currentPhoto == nil:
            state.route = .grid
        case .group where state.groupPosition == nil:
            state.route = .grid
        case .detail, .group:
            break
        }
        return state
    }
}
