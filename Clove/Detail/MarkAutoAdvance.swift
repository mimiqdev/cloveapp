import CloveCore

/// The pause between a written mark and the move auto-advance asks for (PRD Auto-advance).
///
/// PRD Auto-advance waits about 0.3 seconds after marking so the user sees the mark take effect,
/// then moves. Where to go, and which photo was marked, come from C13's ``AutoAdvancePlan``; this
/// type owns only the wait and its cancellation.
///
/// A new mark, a navigation and leaving the view all cancel the pending move, so a photo the user
/// has already left is never replaced by an advance that was still waiting.
@MainActor
final class MarkAutoAdvance {
    /// The advance waiting out its pause, or nil when nothing is pending.
    private var task: Task<Void, Never>?

    /// Cancels a pending advance; call it for a new mark, a navigation and leaving the view.
    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Waits C13's pause and then hands the target to `move`, unless something cancels first
    /// (PRD Auto-advance).
    ///
    /// A plan that stays keeps nothing waiting, so a mark that does not advance leaves no task
    /// behind.
    func schedule(_ plan: AutoAdvancePlan, move: @escaping @MainActor (AutoAdvanceTarget) -> Void) {
        cancel()
        guard plan.advances else { return }
        let target = plan.target
        task = Task {
            try? await Task.sleep(for: AutoAdvance.pause)
            guard !Task.isCancelled else { return }
            move(target)
        }
    }
}
