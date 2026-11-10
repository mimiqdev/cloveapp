import Foundation

/// What to do with a saved scene that is waiting for its folder's scan (PRD P0-02, P0-14).
public enum PendingBrowsingRestoreDecision: Hashable, Sendable {
    /// The folder now holds every photo the saved state names, so the saved state is validated
    /// and applied.
    case apply(RestoredBrowsing)

    /// The saved folder is still delivering the photos the saved state names; keep waiting.
    case wait

    /// The saved state no longer applies: the user moved on, another folder opened, or the
    /// folder that answered the saved identity is not the saved folder.
    case drop
}

/// A saved scene kept pending while its folder's scan delivers the photos it names
/// (PRD P0-02, P0-14).
///
/// A launch reopens the saved folder's grid at once, because a large RAW folder's metadata read
/// can take a while and entry must not wait for it. The saved state cannot be validated at that
/// moment: U1's ``BrowsingState/restored(from:)`` drops a photo the folder does not hold yet, so
/// validating early would drop the saved photo, selection and group place on every launch.
///
/// The pending state therefore applies once the folder holds every photo it names, and always
/// once the scan has finished, because a photo that is gone by then has to fall back the way U1
/// defined instead of holding the restore forever; a partial scan counts as finished. It applies
/// only while the scene still shows exactly what the reopen produced: any navigation inside the
/// restored folder, another folder opened, or a folder that stopped answering drops it, so a
/// restore can never overwrite what the user did after the launch. The decision is pure: it reads
/// no file and changes nothing.
public struct PendingBrowsingRestore: Hashable, Sendable {
    /// The state read back from the scene's storage.
    public let saved: BrowsingState

    /// The state the launch showed when the saved folder reopened, which is what the screen shows
    /// until the pending state applies.
    public let shown: BrowsingState

    /// Pairs the saved state with the state the reopen produced.
    public init(saved: BrowsingState, shown: BrowsingState) {
        self.saved = saved
        self.shown = shown
    }

    /// Decides from the state the screens show now, the folder's current contents and whether its
    /// scan has finished.
    ///
    /// A state that differs from ``shown`` means the user navigated, another folder replaced the
    /// saved one, or the session ended; the pending state is dropped rather than applied late.
    /// Before the scan finishes, the saved photo, selection and group-view photo all have to be
    /// present, because validating earlier would drop them. Once it has finished — a partial scan
    /// included — the saved state is validated either way, so a photo that moved or disappeared
    /// takes U1's fallback (the detail route returns to the grid, the selection drops the missing
    /// photo, the group view drops or moves) instead of waiting for a photo that will never come.
    public func decision(
        current: BrowsingState, contents: FolderContents, scanFinished: Bool
    ) -> PendingBrowsingRestoreDecision {
        guard current == shown, contents.folder == saved.folder else { return .drop }
        guard scanFinished || namedPhotos.isSubset(of: Set(contents.photos)) else { return .wait }
        return .apply(saved.restored(from: .available(contents)))
    }

    /// The photos the saved state points at: its current photo, its selection and its group
    /// view's photo (PRD P0-09, P0-12, P0-14).
    private var namedPhotos: Set<PhotoIdentity> {
        var photos = saved.selection
        if let photo = saved.currentPhoto { photos.insert(photo) }
        if let photo = saved.groupPosition?.photo { photos.insert(photo) }
        return photos
    }
}
