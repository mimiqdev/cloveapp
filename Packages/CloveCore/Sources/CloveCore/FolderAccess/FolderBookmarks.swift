import Foundation

/// Bookmark creation and resolution for remembered folders (G1 folder access).
///
/// The bookmark carries the picker's grant on iOS, so default data is used. Resolution suppresses
/// UI, mounting and implicit scope starts; the caller starts access explicitly afterwards (S1).
enum FolderBookmarks {
    /// Creates default bookmark data while access to the folder is held (S1).
    static func data(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves bookmark data, reporting whether the system marked it stale.
    ///
    /// Stale means the data needs refreshing, not that permission was lost (G1 folder access).
    static func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI, .withoutMounting, .withoutImplicitStartAccessing],
            relativeTo: nil, bookmarkDataIsStale: &isStale)
        return (url, isStale)
    }
}
