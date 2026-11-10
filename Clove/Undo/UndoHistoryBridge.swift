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
/// - **One registration per recorded action.** The browsing model records an action once and asks
///   the bridge to mirror it; the bridge registers exactly one system operation for it, in its own
///   undo group. Whichever screen attaches the manager, registration happens here and only here,
///   so a toolbar press and the system gesture can never apply one action twice.
/// - **The toolbar goes through the same manager.** ``requestUndo()`` asks the manager to undo
///   while it holds a registration, exactly as ⌘Z and the gesture do, so one press is one step.
/// - **The manager's redo pair is registered while it applies the undo**, which is the only moment
///   its redo stack can gain an operation, so ⇧⌘Z and the redo gesture work. Registering a new
///   action outside such an application is exactly what discards the redo future, which is also
///   C5's rule for a newly recorded action (PRD P0-05's last-in, first-out undo).
/// - **A step that leaves the stacks out of step rebuilds them.** A failed write keeps its history
///   entry (PRD P0-08) and a step that restored nothing drops it, so the mirror is rebuilt from the
///   history then instead of keeping a pair that would run a different action.
/// - **One step at a time.** A request while a step runs is ignored; the running step rebuilds the
///   stack when it finishes, so the extra press can never apply a second action.
///
/// The bridge groups registrations itself (`groupsByEvent` off), because two registrations in one
/// run-loop turn would otherwise join one system undo and a single ⌘Z would restore two actions.
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
        // Each recorded action is one system undo group, and the folder session keeps C5's history
        // to this many actions, so the system stack is bounded the same way.
        manager.groupsByEvent = false
        manager.levelsOfUndo = MarkUndoHistory.defaultDepthLimit
        rebuild()
    }

    /// Mirrors one newly recorded action onto the system undo stack (PRD P0-05).
    ///
    /// The registration discards the manager's redo stack outside an undo application, which is
    /// what C5 does for a newly recorded action too (PRD P0-05's last-in, first-out undo).
    func historyDidRecord() {
        guard !isStepping else {
            changedDuringStep = true
            return
        }
        guard let host, host.undoAvailability.canUndo else { return }
        registerUndoOperation(named: host.undoAvailability.undoName)
    }

    /// Forgets every system step after the open folder's history was replaced or cleared
    /// (PRD P0-05).
    func historyDidReset() {
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
        // The manager held no registration for this step, so its stacks no longer describe the
        // history; the mirror is rebuilt from the history.
        rebuild()
    }

    /// Finishes one step that a system registration started (PRD P0-05).
    private func finishStep(isUndo: Bool) async {
        let result =
            isUndo ? await host?.undoThroughHistory() : await host?.redoThroughHistory()
        isStepping = false
        let changed = changedDuringStep
        changedDuringStep = false
        // The pair registered above belongs to this step only while the step moved the history:
        // a failed restore keeps its entry (PRD P0-08) and a dropped entry leaves nothing behind.
        let moved = result.map { $0.failureSummary == nil && !$0.droppedFromHistory } ?? false
        if changed || !moved { rebuild() }
    }

    // MARK: - Mirror

    /// Registers the history's next action as one system undo, named for its menu (PRD P0-05).
    private func registerUndoOperation(named name: String?) {
        guard let manager else { return }
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self) { bridge in bridge.handleSystemUndo() }
        if let name { manager.setActionName(name) }
        manager.endUndoGrouping()
    }

    /// Mirrors the history into a fresh system stack, one undo group per undoable action.
    ///
    /// The system's redo stack gains operations only while it applies an undo, so a rebuild cannot
    /// restore redo; the history keeps the undone actions, and undoing again registers their pair
    /// (PRD P0-05's last-in, first-out undo). Only the next action's name is known, so the groups
    /// below it carry that name until they are applied.
    private func rebuild() {
        guard let manager, let host else { return }
        manager.removeAllActions()
        guard host.undoAvailability.canUndo else { return }
        let name = host.undoAvailability.undoName
        for _ in 0..<undoDepth(of: host) {
            registerUndoOperation(named: name)
        }
    }

    /// How many system undo groups the history can still undo (PRD P0-05).
    private func undoDepth(of host: UndoHistoryHost) -> Int {
        host.undoAvailability.undoDepth
    }

    /// Marks a step as running, or reports that one already is.
    private func beginStep() -> Bool {
        guard !isStepping else { return false }
        isStepping = true
        return true
    }
}
