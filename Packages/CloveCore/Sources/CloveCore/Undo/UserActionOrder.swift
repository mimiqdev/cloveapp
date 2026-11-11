/// The order user actions run in, one ticket each (PRD P0-05's Undo row).
///
/// PRD P0-05's Undo row is last in, first out over the actions the user took, so the order the
/// actions *arrive* in is the order they must start in, even when one of them is a slow write and
/// the next is an undo step. A step must also finish before any later action, because a later
/// mark replaced the value the step would restore.
///
/// The value is a ticket queue over the main actor:
///
/// - ``reserve(_:)`` takes the next ticket synchronously with the caller's arrival, before any
///   await, so two taps keep the order they were made in.
/// - ``start(_:)`` waits until every earlier ticket has started and every earlier step has
///   finished, then marks this one started. A ticket whose action never runs is dropped with
///   ``cancel(_:)``, so it cannot hold later actions back.
/// - ``finishStep(_:)`` ends a step's ticket, letting later actions through.
///
/// Waiting never deadlocks: a ticket only waits for earlier tickets, and earlier tickets cannot
/// wait for it.
@MainActor
public final class UserActionOrder {
    /// What one ticket's action is, which decides how later tickets wait for it (PRD P0-05).
    public enum Kind: Sendable {
        /// A mark, a batch, a retry or a Move rejects: later actions wait for it to start.
        case action
        /// An undo or redo step: later actions wait for it to finish.
        case step
    }

    /// One reserved place in the order.
    private struct Entry {
        let ticket: Int
        let kind: Kind
        var started = false
        var finished = false
    }

    /// The tickets later actions may still have to wait for, in arrival order.
    private var entries: [Entry] = []
    /// The last ticket handed out.
    private var lastTicket = 0
    /// Callers parked in ``start(_:)``.
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Creates an empty order.
    public init() {}

    /// Takes the next ticket for one action, in arrival order (PRD P0-05).
    ///
    /// It is synchronous on the main actor, so the caller takes it before any await and two
    /// actions cannot swap places.
    public func reserve(_ kind: Kind) -> Int {
        lastTicket += 1
        entries.append(Entry(ticket: lastTicket, kind: kind))
        return lastTicket
    }

    /// Waits for this ticket's turn and marks it started (PRD P0-05).
    ///
    /// A ticket waits for every earlier ticket to start, and for every earlier step to finish.
    /// - Returns: `false` when the ticket was cancelled or never reserved, so its action must not
    ///   run unordered; `true` when it may run.
    @discardableResult
    public func start(_ ticket: Int) async -> Bool {
        while isBlocked(ticket) {
            await withCheckedContinuation { waiters.append($0) }
        }
        guard let index = entries.firstIndex(where: { $0.ticket == ticket }) else { return false }
        entries[index].started = true
        prune()
        wake()
        return true
    }

    /// Ends a step's ticket, so later actions may start (PRD P0-05).
    public func finishStep(_ ticket: Int) {
        guard let index = entries.firstIndex(where: { $0.ticket == ticket }) else { return }
        entries[index].finished = true
        prune()
        wake()
    }

    /// Drops a ticket whose action will never run, so later actions are not held up (PRD P0-05).
    public func cancel(_ ticket: Int) {
        entries.removeAll { $0.ticket == ticket }
        prune()
        wake()
    }

    /// Whether this ticket still has an earlier ticket to wait for.
    private func isBlocked(_ ticket: Int) -> Bool {
        guard let index = entries.firstIndex(where: { $0.ticket == ticket }) else { return false }
        for earlier in entries[..<index] {
            if earlier.kind == .step {
                if !earlier.finished { return true }
            } else if !earlier.started {
                return true
            }
        }
        return false
    }

    /// Drops the tickets no later ticket has to wait for any more.
    private func prune() {
        while let first = entries.first {
            guard first.started else { return }
            if first.kind == .step, !first.finished { return }
            entries.removeFirst()
        }
    }

    /// Wakes every parked caller to check its ticket again.
    private func wake() {
        let parked = waiters
        waiters = []
        for continuation in parked { continuation.resume() }
    }
}
