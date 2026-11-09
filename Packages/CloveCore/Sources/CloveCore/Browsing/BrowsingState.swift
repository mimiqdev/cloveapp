/// Everything a fold, an unfold, a resize and a relaunch must preserve (PRD P0-14).
///
/// G1's fold-state row decides the shape: layout follows the available geometry, so this value
/// holds no view, column, stack or device fact. A compact stack and a split layout both read it,
/// which is why switching between them keeps the same folder, photo, filter, selection and group
/// view (PRD P0-14, G1 fold-state row).
///
/// The value is the saved unit, never the authority. A folder changes between launches, so
/// ``BrowsingState/restored(from:)-(FolderAvailability)`` narrows a saved state to what the
/// folder holds now before any screen reads it (PRD P0-13).
public struct BrowsingState: Hashable, Sendable {
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
    /// The grid route reads it to avoid jumping, and the detail route needs it.
    public var currentPhoto: PhotoIdentity?

    /// The grid's filter (PRD P0-03, P0-14). A filter never changes the order.
    public var filter: PhotoFilter

    /// The grid's order (PRD P0-03). Capture time with subseconds is the default.
    public var order: PhotoOrder

    /// The multi-selection, unordered so storing it never depends on the order of taps
    /// (PRD P0-09, P0-14).
    public var selection: Set<PhotoIdentity>

    /// The group view's place: its group and the photo inside it (PRD P0-12, P0-14).
    public var groupPosition: BrowsingGroupPosition?

    /// The destination the browser shows (PRD P0-13).
    public var route: BrowserRoute

    /// Collects every part PRD P0-14 preserves, with the launch defaults.
    public init(
        folder: FolderIdentity? = nil,
        currentPhoto: PhotoIdentity? = nil,
        filter: PhotoFilter = .all,
        order: PhotoOrder = .captureTime,
        selection: Set<PhotoIdentity> = [],
        groupPosition: BrowsingGroupPosition? = nil,
        route: BrowserRoute = .entry
    ) {
        self.folder = folder
        self.currentPhoto = currentPhoto
        self.filter = filter
        self.order = order
        self.selection = selection
        self.groupPosition = groupPosition
        self.route = route
    }
}

/// The group view's place during in-group culling (PRD P0-12, P0-14).
///
/// Both halves are needed to come back to the same frame of the same group. The group key is
/// stable across refinement and Run again (see ``GroupID``), so a restored placeholder can tell
/// a still-published group from one that split or disappeared.
public struct BrowsingGroupPosition: Hashable, Sendable {
    /// The stable group key the view was showing (PRD P0-11).
    public var group: GroupID

    /// The photo the group view was showing; a member of `group` in a valid state (PRD P0-12).
    public var photo: PhotoIdentity

    /// Pairs one group with the photo the view is on (PRD P0-12).
    public init(group: GroupID, photo: PhotoIdentity) {
        self.group = group
        self.photo = photo
    }
}
