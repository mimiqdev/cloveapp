/// Everything a fold, an unfold, a resize and a relaunch must preserve (PRD P0-14).
///
/// G1's fold-state row decides the shape: layout follows the available geometry, so this value
/// holds no view, column, stack or device fact. A compact stack and a split layout both read it,
/// which is why switching between them keeps the same folder, photo, filter and selection.
///
/// The value is the saved unit, never the authority. A folder changes between launches, so
/// ``BrowsingState/restored(from:)`` narrows a saved state to what the folder holds now before
/// any screen reads it (PRD P0-13). Its encoded form is versioned, and a form this release cannot
/// read starts at entry (``BrowsingStateCoding``).
///
/// Write status is deliberately absent. PRD P0-14 preserves it across a fold, but it belongs to
/// the save state (C4/U7) and lives on the observing model, so a stored navigation state can
/// never claim an unfinished write was saved.
public struct BrowsingState: Hashable, Sendable, Codable {
    /// The state of a launch that has nothing saved, and of a restore that cannot use its saved
    /// state (PRD P0-14: never fail because a saved state is unreadable).
    public static let entry = BrowsingState()

    /// The open folder as folder access identifies it, or nil before a folder opens.
    ///
    /// G1 folder access makes identity the bookmark's durable key, never a path or a name, so a
    /// restored state can tell the remembered folder from a same-name card (PRD P0-02, P0-14).
    public var folder: FolderIdentity?

    /// The photo the browser is on, kept while the grid and the detail share one screen.
    ///
    /// PRD P0-14 preserves the current photo across folding, unfolding, resizing and reopening.
    /// The detail route needs it, and the grid route keeps it so the grid can hold that photo in
    /// place once the collection view lands (PRD P0-11).
    public var currentPhoto: PhotoIdentity?

    /// The grid's filter (PRD P0-03, P0-14). A filter never changes the order.
    public var filter: PhotoFilter

    /// The grid's order (PRD P0-03). Capture time with subseconds is the default.
    public var order: PhotoOrder

    /// The multi-selection, unordered so storing it never depends on the order of taps
    /// (PRD P0-09, P0-14).
    public var selection: Set<PhotoIdentity>

    /// The destination the browser shows (PRD P0-13).
    public var route: BrowserRoute

    /// Whether the route shows the folder's photos, which needs the folder those photos belong
    /// to (PRD P0-13).
    ///
    /// A restored scene uses this to tell a grid or detail route, which has to wait for
    /// the folder to deliver its photos, from entry or settings, which need none.
    public var showsPhotos: Bool {
        route == .grid || route == .detail
    }

    /// Collects every part PRD P0-14 preserves, with the launch defaults.
    public init(
        folder: FolderIdentity? = nil,
        currentPhoto: PhotoIdentity? = nil,
        filter: PhotoFilter = .all,
        order: PhotoOrder = .captureTime,
        selection: Set<PhotoIdentity> = [],
        route: BrowserRoute = .entry
    ) {
        self.folder = folder
        self.currentPhoto = currentPhoto
        self.filter = filter
        self.order = order
        self.selection = selection
        self.route = route
    }
}
