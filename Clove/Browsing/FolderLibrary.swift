import CloveCore

/// What the browsing screens read and change, behind one seam (PRD P0-08, P0-13, P0-14).
///
/// Folder access (C11), the scan (C2), the order (C8), writes (C4) and grouping (C9) arrive with
/// U2 and U3. The seam already speaks C4's `MarkChange` and `MarkChangeStatus`, so those tasks
/// replace the implementation without changing a screen or this protocol's shape.
///
/// This build reads the library when it opens a folder, restores a scene and applies a change.
/// U2 and U3 push their updates in: the model consumes one `AsyncStream` of scan batches and
/// grouping results, the way C4's `MarkWriteQueue.stateUpdates()` already streams statuses.
@MainActor
protocol FolderLibrary: AnyObject {
    /// The open folder's durable key, never a path or a name (G1 folder access, PRD P0-01).
    var folder: FolderIdentity { get }

    /// The folder's photos with their marks, in any order: the browsing state orders and filters
    /// them through its C8 order and C1 marks (PRD P0-03).
    var photos: [GridPhoto] { get }

    /// The groups grouping published for the folder, empty when grouping is off (PRD P0-11).
    var groups: [BrowsingGroup] { get }

    /// Applies one change and returns its status (PRD P0-08).
    ///
    /// The call is asynchronous because C4's `MarkWriteQueue.apply(_:to:)` is: U2 resolves the
    /// identity to its scanned set and awaits the queue without changing this signature. A failed
    /// or unconfirmed write is reported by the returned status, never by throwing.
    func apply(_ change: MarkChange, to photo: PhotoIdentity) async -> MarkChangeStatus

    /// The latest change to one photo with its save state (PRD P0-08).
    ///
    /// Mirrors C4's `MarkWriteQueue.latestChange(for:)`: U7 reads the same status for its retry.
    /// Nil means nothing has been requested for the photo, not that everything is saved.
    func latestChange(for photo: PhotoIdentity) -> MarkChangeStatus?
}

extension FolderLibrary {
    /// What restore validation checks a saved state against (PRD P0-14).
    var contents: FolderContents {
        FolderContents(folder: folder, photos: photos.map(\.id), groups: groups)
    }
}
