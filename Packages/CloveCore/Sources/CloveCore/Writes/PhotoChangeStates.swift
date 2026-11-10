import Foundation

/// The latest save state of each photo's change, merged as C4 publishes transitions (PRD P0-08).
///
/// A change's state arrives only from C4's ``MarkWriteQueue/stateUpdates()`` stream, which yields
/// each transition in admission order, so a status of a change already recorded is a transition
/// of that change and a status of an unseen change is a newer one. Nothing may feed this type from
/// an awaited ``MarkWriteQueue/apply(_:to:)-swift.method`` return: that value can arrive after a
/// newer change was admitted, which would let an older finished state replace the newer one. The
/// reader that owns the stream keeps this value and a photo's marks from the same ordered source.
///
/// A change already recorded never moves backwards: once it is finished, an earlier-lived pending
/// or writing state for the same change is ignored. A newer change to the same photo replaces the
/// older one, which is what U7 reads for its retry (PRD How marks reach disk, rule 8).
public struct PhotoChangeStates: Sendable {
    /// The latest change per photo, by photo identity.
    private var latest: [PhotoIdentity: MarkChangeStatus] = [:]
    /// Every change identity already seen, so a repeated state is treated as a transition of that
    /// change rather than as a newer change.
    private var seen: Set<MarkChangeID> = []

    /// Starts with no change recorded; a photo with nothing requested has no state at all.
    public init() {}

    /// Whether no change has been recorded.
    public var isEmpty: Bool { latest.isEmpty }

    /// How many photos have a recorded change.
    public var count: Int { latest.count }

    /// Records one state and reports whether it became the photo's latest.
    ///
    /// The first state of a change replaces its photo's state, because it is the newest change
    /// admitted. A state of a change already recorded only replaces that change's own state, only
    /// while it is still the photo's latest, and never after it reached a finished one. The
    /// return value is what the caller uses to decide whether the change's fields still belong on
    /// the photo: a refused status is an older change a newer one replaced (PRD disk rule 8).
    @discardableResult
    public mutating func insert(_ status: MarkChangeStatus) -> Bool {
        guard !seen.contains(status.id) else {
            guard let current = latest[status.identity], current.id == status.id else {
                return false
            }
            guard !(current.state.isFinished && !status.state.isFinished) else { return false }
            latest[status.identity] = status
            return true
        }
        seen.insert(status.id)
        latest[status.identity] = status
        return true
    }

    /// The latest change to one photo, or nil when nothing has been requested for it.
    public func latest(for photo: PhotoIdentity) -> MarkChangeStatus? { latest[photo] }
}
