/// The two actions that finish a group (PRD In-group culling, finishing actions; PRD P0-12).
///
/// Neither action ever rejects a photo that already has a rating or colour label, and both
/// plan their changes before anything is written, so the group view can show what is about to
/// happen (PRD In-group culling, finishing actions; PRD P0-12).
public enum GroupFinishingAction: String, CaseIterable, Hashable, Sendable {
    /// Keep this, reject the rest: the current photo keeps its marks, and rejects the rest
    /// rejects the other unmarked members (PRD In-group culling, finishing actions).
    case keepThis

    /// Keep rated, reject the rest: rated photos stay as they are, and rejects the rest
    /// rejects the other unmarked members (PRD In-group culling, finishing actions).
    case keepRated
}

/// Whether a finishing action may run on a group, and the one reason it may not
/// (PRD In-group culling, finishing actions).
public enum GroupFinishingAvailability: Hashable, Sendable {
    /// The action can run; its plan may still be empty when there is nothing to change.
    case available

    /// Keep rated, reject the rest needs at least one rated photo in the group
    /// (PRD In-group culling, finishing actions).
    case noRatedPhoto

    /// Whether the action may run and record a completion (PRD P0-12).
    public var isAvailable: Bool { self == .available }
}

/// What one planned change does for one photo (PRD In-group culling, finishing actions).
public enum GroupFinishingChangeKind: Hashable, Sendable {
    /// The current photo's own change for Keep this, reject the rest: the lowest enabled
    /// rating when it has none, and clearing Reject (PRD In-group culling, finishing actions).
    case keep

    /// Reject one unmarked photo (PRD P0-12; PRD In-group culling, finishing actions).
    case reject
}

/// One photo a finishing action changes: its marks before the action and the requested change.
///
/// The change is what C4's write queue receives, and the marks before it are the record C5
/// undoes from (PRD P0-12: finishing actions can be undone; DEV-PLAN C5). A plain value, so a
/// plan can be shown before anything is written and checked in a test.
public struct GroupFinishingChange: Hashable, Sendable {
    /// The photo the change belongs to (C1's stable identity).
    public let photo: PhotoIdentity

    /// Whether this is the current photo's keep change or a reject (PRD In-group culling).
    public let kind: GroupFinishingChangeKind

    /// The marks read when the change was planned, kept for C5's undo (DEV-PLAN C5).
    public let marksBefore: PhotoMarks

    /// The requested change, routed through C4's write queue (PRD P0-12, P0-09).
    public let change: MarkChange

    /// Describes one planned change, built only by ``GroupFinishingPlan`` or the executor.
    init(
        photo: PhotoIdentity,
        kind: GroupFinishingChangeKind,
        marksBefore: PhotoMarks,
        change: MarkChange
    ) {
        self.photo = photo
        self.kind = kind
        self.marksBefore = marksBefore
        self.change = change
    }
}
