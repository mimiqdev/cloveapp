/// A kind of mark whose write can start auto-advance (PRD Auto-advance).
public enum MarkKind: String, CaseIterable, Hashable, Sendable {
    /// A star rating (PRD Marking rules).
    case rating

    /// Clove's internal Reject toggle (PRD Marking rules and G1 decision 5).
    case reject

    /// A colour label (PRD Marking rules).
    case colourLabel
}

/// Where the detail view moves after it writes a mark (PRD Auto-advance).
public enum AutoAdvanceDestination: String, CaseIterable, Hashable, Sendable {
    /// Keep the current photo.
    case stay

    /// Move to the next photo in the current order.
    case nextPhoto

    /// Move to the next photo without a rating, label, or Reject.
    case nextUnmarkedPhoto
}

/// Which marks start auto-advance (PRD Auto-advance and P0-06 acceptance).
public struct AutoAdvanceTriggers: Hashable, Sendable {
    /// Ratings advance by default (PRD Auto-advance).
    public var rating: Bool
    /// Reject advances by default (PRD Auto-advance).
    public var reject: Bool
    /// Colour labels never advance by default (PRD Auto-advance).
    public var colourLabel: Bool

    /// Creates trigger switches; ratings and Reject are on, colour labels are off (PRD
    /// Auto-advance).
    public init(rating: Bool = true, reject: Bool = true, colourLabel: Bool = false) {
        self.rating = rating
        self.reject = reject
        self.colourLabel = colourLabel
    }
}

/// Auto-advance destination plus the marks that trigger it (PRD Auto-advance).
public struct AutoAdvance: Hashable, Sendable {
    /// Where to go after a triggering mark (PRD Auto-advance).
    public var destination: AutoAdvanceDestination
    /// Which marks trigger the move (PRD Auto-advance).
    public var triggers: AutoAdvanceTriggers

    /// Creates the setting; next photo with ratings and Reject triggering is the default
    /// (PRD Auto-advance).
    public init(
        destination: AutoAdvanceDestination = .nextPhoto,
        triggers: AutoAdvanceTriggers = AutoAdvanceTriggers()
    ) {
        self.destination = destination
        self.triggers = triggers
    }

    /// Whether a written mark of this kind starts the pause-then-advance behavior.
    ///
    /// Staying on the current photo never advances, whatever the trigger switches say; the
    /// switches only choose destinations. Group views override the next photo with the next
    /// undecided photo in the group (PRD In-group culling).
    public func shouldAdvance(after mark: MarkKind) -> Bool {
        guard destination != .stay else { return false }
        switch mark {
        case .rating: return triggers.rating
        case .reject: return triggers.reject
        case .colourLabel: return triggers.colourLabel
        }
    }
}
