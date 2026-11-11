/// What to do with a saved scene while its folder's scan delivers the photos it names.
public enum PendingBrowsingRestoreDecision: Hashable, Sendable {
    case apply(RestoredBrowsing)
    case wait
    case drop
}

/// A saved scene applies once its photos arrive, or at scan completion if some are gone.
/// Navigation after reopening drops the pending restore so it cannot overwrite the user's choice.
public struct PendingBrowsingRestore: Hashable, Sendable {
    public let saved: BrowsingState
    public let shown: BrowsingState

    public init(saved: BrowsingState, shown: BrowsingState) {
        self.saved = saved
        self.shown = shown
    }

    public func decision(
        current: BrowsingState, contents: FolderContents, scanFinished: Bool
    ) -> PendingBrowsingRestoreDecision {
        guard current == shown, contents.folder == saved.folder else { return .drop }
        var namedPhotos = saved.selection
        if let photo = saved.currentPhoto { namedPhotos.insert(photo) }
        guard scanFinished || namedPhotos.isSubset(of: Set(contents.photos)) else { return .wait }
        return .apply(saved.restored(from: .available(contents)))
    }
}
