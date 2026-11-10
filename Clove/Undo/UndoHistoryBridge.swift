import CloveCore
import Foundation

/// What the undo bridge asks the browsing model to do (PRD P0-05).
///
/// The bridge never touches a folder library or a C4 queue itself: every step goes through the
/// browsing model, which owns the open folder's session and applies C5's return-to-the-photo rule.
@MainActor
protocol UndoHistoryHost: AnyObject {
    /// What the open folder's history offers now (PRD P0-05).
    var undoAvailability: UndoAvailability { get }
    /// Undoes the history's next action through the open folder (PRD P0-05).
    func undoThroughHistory() async -> UndoStepResult?
    /// Redoes the history's next undone action through the open folder (PRD P0-05).
    func redoThroughHistory() async -> UndoStepResult?
}

/// Bridges the open folder's undo history to the scene's system undo manager (PRD P0-05).
///
/// PRD P0-05's Undo row asks for the system undo mechanism: a toolbar button, ⌘Z on a hardware
/// keyboard and the iOS three-finger gestures. All three reach the scene's one `UndoManager`, so
/// this bridge is the single place that registers with it:
///
/// - **One registration per recorded action.** The browsing model records an action once, after
///   C4 admitted it, and calls ``historyDidChange()``. Whichever screen attaches the manager, the
///   registration happens here and only here, so a toolbar press and the system gesture can never
///   apply one action twice.
/// - **The toolbar goes through the same manager.** ``requestUndo()`` asks the manager to undo
///   while it holds a registration, exactly as ⌘Z and the gesture do, so one press is one step.
/// - **The manager's redo pair is registered while it applies the undo.** That is the only moment
///   its redo stack can gain an operation, so ⇧⌘Z and the three-finger redo gesture work.
/// - **A step that moves nothing rebuilds the stack.** A failed write keeps its history entry
///   (PRD P0-08) and a dropped entry leaves nothing to redo, so the system stack is rebuilt from
///   the history instead of keeping a pair that would undo a different action.
/// - **One step at a time.** A request while a step runs is ignored; the running step rebuilds the
///   stack when it finishes, so the extra press can never apply a second action.
@MainActor
final class UndoHistoryBridge {
    /// The browsing model this bridge undoes through, held weakly for the scene's lifetime.
    weak var host: UndoHistoryHost?

    /// The scene's undo manager, once a screen has found it.
    ///
    /// The first manager wins for the scene: a second screen attaching its own copy changes
    /// nothing, which is what keeps the split layout's grid and detail from registering twice.
    private(set) weak var manager: UndoManager?

    /// Whether a step is running, so a second press cannot apply another action.
    private(set) var isStepping = false

    /// Whether the history changed while a step ran, so the stack is rebuilt when it finishes.
    private var changedDuringStep = false

    /// Attaches the scene's undo manager and mirrors the history into it (PRD P0-05).
    ///
    /// Attaching the same manager twice, or from another screen, is what the split layout does on
    /// every update; only the first attach does anything.
    func attach(_ manager: UndoManager?) {
        guard let manager, self.manager == nil else { return }
        self.manager = manager
        // A folder session keeps C5's history to this many actions, so the system stack does too.
        manager.levelsOfUndo = MarkUndoHistory.defaultDepthLimit
        rebuild()
    }

    /// Mirrors the history after a recorded action (PRD P0-05).
    func historyDidChange() {
        guard !isStepping else {
            changedDuringStep = true
            return
        }
        rebuild()
    }

    /// Undoes the history's next action, from the toolbar button (PRD P0-05).
    ///
    /// The manager is asked to undo while it holds a registration, so the button runs the same
    /// single operation that ⌘Z and the three-finger gesture run.
    func requestUndo() {
        guard let host, !isStepping, host.undoAvailability.canUndo else { return }
        if let manager, manager.canUndo {
            manager.undo()
        } else {
            Task { await step(isUndo: true) }
        }
    }

    /// Redoes the history's next undone action, for ⇧⌘Z and the redo gesture (PRD P0-05).
    func requestRedo() {
        guard let host, !isStepping, host.undoAvailability.canRedo else { return }
        if let manager, manager.canRedo {
            manager.redo()
        } else {
            Task { await step(isUndo: false) }
        }
    }

    // MARK: - System registrations

    /// Runs one system undo: registers its redo pair while the manager applies it, then restores
    /// the marks through the history (PRD P0-05).
    private func handleSystemUndo() {
        guard let manager, let host, beginStep() else {
            changedDuringStep = true
            return
        }
        let name = host.undoAvailability.undoName ?? "Mark"
        manager.registerUndo(withTarget: self) { bridge in bridge.handleSystemRedo() }
        manager.setActionName(name)
        Task { await finishStep(isUndo: true) }
    }

    /// Runs one system redo: registers the undo pair while the manager applies the redo, then
    /// re-applies the marks through the history (PRD P0-05).
    private func handleSystemRedo() {
        guard let manager, let host, beginStep() else {
            changedDuringStep = true
            return
        }
        let name = host.undoAvailability.redoName ?? "Mark"
        manager.registerUndo(withTarget: self) { bridge in bridge.handleSystemUndo() }
        manager.setActionName(name)
        Task { await finishStep(isUndo: false) }
    }

    /// Runs one step the manager holds no registration for, such as a scene with no undo manager
    /// (PRD P0-05).
    private func step(isUndo: Bool) async {
        guard beginStep() else { return }
        _ = isUndo ? await host?.undoThroughHistory() : await host?.redoThroughHistory()
        isStepping = false
        rebuild()
    }

    /// Finishes one step that a system registration started (PRD P0-05).
    private func finishStep(isUndo: Bool) async {
        let result =
            isUndo ? await host?.undoThroughHistory() : await host?.redoThroughHistory()
        isStepping = false
        let changed = changedDuringStep
        changedDuringStep = false
        // The pair registered above belongs to this step only while the step moved the history.
        let moved = result.map { $0.failureSummary == nil && !$0.droppedFromHistory } ?? false
        if changed || !moved {
            rebuild()
            return
        }
        if isUndo { registerNextUndo() }
    }

    /// Registers the history's next undo as one system operation, named for its menu
    /// (PRD P0-05).
    ///
    /// The group is begun explicitly, so two registrations in one run-loop turn stay two
    /// operations and one ⌘Z never restores two actions.
    private func registerNextUndo() {
        guard let manager, let host, host.undoAvailability.canUndo else { return }
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self) { bridge in bridge.handleSystemUndo() }
        manager.setActionName(host.undoAvailability.undoName ?? "Mark")
        manager.endUndoGrouping()
    }

    /// Mirrors the history into a fresh system stack: one undo registration for its next action.
    ///
    /// The system's redo stack gains operations only while it applies an undo, so a rebuild cannot
    /// restore redo. The history keeps the undone actions, and the next undo registers their pair
    /// again (PRD P0-05's last-in, first-out undo).
    private func rebuild() {
        guard let manager else { return }
        manager.removeAllActions()
        registerNextUndo()
    }

    /// Marks a step as running, or reports that one already is.
    private func beginStep() -> Bool {
        guard !isStepping else { return false }
        isStepping = true
        return true
    }
}
