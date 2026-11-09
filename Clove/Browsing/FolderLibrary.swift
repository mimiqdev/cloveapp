import CloveCore

/// What the browsing screens read and change, behind one seam (PRD P0-13, P0-14).
///
/// Folder access (C11), the scan (C2), the order (C8), writes (C4) and grouping (C9) arrive with
/// U2 and U3. Until then ``TestLibrary`` stands in for them, and the screens read only these four
/// things, so replacing the library does not change a screen or the browsing state.
@MainActor
protocol FolderLibrary: AnyObject {
    /// The open folder's durable key, never a path or a name (G1 folder access, PRD P0-01).
    var folder: FolderIdentity { get }

    /// The folder's photos with their marks, in any order: the browsing state orders and filters
    /// them through its C8 order and C1 marks (PRD P0-03).
    var photos: [GridPhoto] { get }

    /// The groups grouping published for the folder, empty when grouping is off (PRD P0-11).
    var groups: [BrowsingGroup] { get }

    /// Applies marks to one photo (PRD P0-05). A failed or unconfirmed write is reported by the
    /// save state once C4 lands, never by this call.
    func apply(_ marks: PhotoMarks, to photo: PhotoIdentity)
}

extension FolderLibrary {
    /// What restore validation checks a saved state against (PRD P0-14).
    var contents: FolderContents {
        FolderContents(folder: folder, photos: photos.map(\.id), groups: groups)
    }
}
