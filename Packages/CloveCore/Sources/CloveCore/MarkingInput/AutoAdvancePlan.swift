/// Where auto-advance sends the detail view, resolved to the photo to show.
///
/// `AutoAdvance.destination` chooses the policy (PRD Auto-advance); this value is the answer for
/// one written mark on one ordered list. A group view replaces the policy's next photo with the
/// caller's next undecided photo (PRD In-group culling).
public enum AutoAdvanceTarget: Hashable, Sendable {
    /// Keep the current photo: the setting says stay, the mark kind does not trigger an
    /// advance, or there is no photo to move to (PRD Auto-advance).
    case stay

    /// Show the next photo in the current order (PRD Auto-advance default).
    case nextPhoto(PhotoIdentity)

    /// Show the next photo without a rating, label or Reject (PRD Auto-advance, using the
    /// Unmarked rule from P0-03).
    case nextUnmarkedPhoto(PhotoIdentity)

    /// Show the caller's next undecided photo in the group (PRD In-group culling).
    case groupUndecidedPhoto(PhotoIdentity)
}

/// The move one written mark starts, and the photo undo has to return to (PRD Auto-advance).
///
/// The UI waits `AutoAdvance.pause` before applying a target, so the user sees the mark take
/// effect. Timers are the UI's job; the rules only say where to go and which photo to come back
/// to (PRD Undo row: undoing after auto-advance returns to the photo whose mark was undone).
public struct AutoAdvancePlan: Hashable, Sendable {
    /// Where the detail view goes after the pause.
    public let target: AutoAdvanceTarget

    /// The photo that was just marked; undo returns here (PRD Undo row).
    public let markedPhoto: PhotoIdentity

    /// Pairs one target with the photo that was marked.
    public init(target: AutoAdvanceTarget, markedPhoto: PhotoIdentity) {
        self.target = target
        self.markedPhoto = markedPhoto
    }

    /// Whether the view moves at all.
    public var advances: Bool {
        if case .stay = target { return false }
        return true
    }
}

extension AutoAdvance {
    /// The pause before the view moves, so the user sees the mark take effect (PRD
    /// Auto-advance: about 0.3 seconds).
    ///
    /// Only the value lives here; waiting for it is the UI's job.
    public static let pause: Duration = .milliseconds(300)
}
