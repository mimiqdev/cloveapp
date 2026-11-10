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
    /// Which folder open the history belongs to (PRD P0-14).
    var undoOpenGeneration: Int { get }
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
/// - **A failed or dropped step keeps the manager's stacks, drift and all.** A failed write keeps
///   its history entry (PRD P0-08), so the next undo runs that same entry again; a step that
///   restored nothing leaves an extra pair behind, which C5 answers with nothing. Rebuilding here
///   would throw away the manager's redo entries that C5 still offers, so the mirror is rebuilt
///   only when the folder's history is replaced and when the manager has no registration left to
///   offer. The cost is that a group's name can lag behind the history until the next rebuild.
/// - **One step at a time.** A request while a step runs is ignored, and the extra press cannot
///   apply a second action.
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

    /// One press that arrived while a step was running, run once that step finishes.
    ///
    /// The system manager has already taken the press's entry by then, so dropping it would leave
    /// ⌘Z and the three-finger gesture with nothing left to do while the history still has steps.
    /// The press remembers the folder open it was made in, because a queued press from a folder
    /// that closed must never run against the folder that replaced it (PRD P0-14).
    private struct QueuedPress {
        enum Direction {
            case undo
            case redo
        }

        let direction: Direction
        let openGeneration: Int
    }

    private var queuedPresses: [QueuedPress] = []

    /// Attaches the scene's undo manager and mirrors the history into it (PRD P0-05).
    ///
    /// Attaching the same manager twice, or from another screen, is what the split layout does on
    /// every update; only the first attach does anything.
    func attach(_ manager: UndoManager?) {
        guard let manager, self.manager == nil else { return }
        self.manager = manager
        // The window's undo manager is shared with UIKit text editing, so its event grouping and
        // its depth limit stay as the system set them; this bridge only wraps its own
        // registrations in a group and only touches its own actions.
        rebuild()
    }

    /// Mirrors one newly recorded action onto the system undo stack (PRD P0-05).
    ///
    /// The registration discards the manager's redo stack outside an undo application, which is
    /// what C5 does for a newly recorded action too (PRD P0-05's last-in, first-out undo).
    func historyDidRecord() {
        guard let host, host.undoAvailability.canUndo else { return }
        registerUndoOperation(named: host.undoAvailability.undoName)
    }

    /// Forgets every system step after the open folder's history was replaced or cleared
    /// (PRD P0-05).
    func historyDidReset() {
        // Presses queued for the history that is gone must not run against the new one.
        queuedPresses.removeAll()
        rebuild()
    }

    /// Undoes the history's next action, from the toolbar button (PRD P0-05).
    ///
    /// The manager is asked to undo while it holds a registration, so the button runs the same
    /// single operation that ⌘Z and the three-finger gesture run.
    func requestUndo() {
        guard let host, !isStepping, host.undoAvailability.canUndo else { return }
        // The window's manager also holds a Settings text field's edits, so the button takes the
        // manager's step only when its name is the one this bridge registered for the next mark;
        // otherwise it runs the history directly and never undoes a text edit.
        if let manager, manager.canUndo, manager.undoActionName == host.undoAvailability.undoName {
            manager.undo()
        } else {
            Task { await step(isUndo: true) }
        }
    }

    /// Redoes the history's next undone action, for ⇧⌘Z and the redo gesture (PRD P0-05).
    func requestRedo() {
        guard let host, !isStepping, host.undoAvailability.canRedo else { return }
        if let manager, manager.canRedo, manager.redoActionName == host.undoAvailability.redoName {
            manager.redo()
        } else {
            Task { await step(isUndo: false) }
        }
    }

    // MARK: - System registrations

    /// Runs one system undo: registers its redo pair while the manager applies it, then restores
    /// the marks through the history (PRD P0-05).
    ///
    /// A press that arrives while another step runs takes its place in a queue instead of being
    /// dropped, because the manager has already removed the entry this press stood for.
    private func handleSystemUndo() {
        guard let manager, let host else { return }
        let name = host.undoAvailability.undoName ?? "Mark"
        manager.registerUndo(withTarget: self) { bridge in bridge.handleSystemRedo() }
        manager.setActionName(name)
        guard beginStep() else {
            queuedPresses.append(
                QueuedPress(direction: .undo, openGeneration: host.undoOpenGeneration))
            return
        }
        Task { await finishStep(isUndo: true) }
    }

    /// Runs one system redo: registers the undo pair while the manager applies the redo, then
    /// re-applies the marks through the history (PRD P0-05).
    private func handleSystemRedo() {
        guard let manager, let host else { return }
        let name = host.undoAvailability.redoName ?? "Mark"
        manager.registerUndo(withTarget: self) { bridge in bridge.handleSystemUndo() }
        manager.setActionName(name)
        guard beginStep() else {
            queuedPresses.append(
                QueuedPress(direction: .redo, openGeneration: host.undoOpenGeneration))
            return
        }
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
    ///
    /// The action's redo pair was registered while the manager applied it, so the stacks stay as
    /// they are: a failed step keeps its history entry, and C5's next undo is the entry the
    /// manager still holds. Only a step the history could not take at all leaves the mirror
    /// without a matching entry, and that is rebuilt from the history. A press that arrived during
    /// the step runs next, with the pair its own application already registered.
    private func finishStep(isUndo: Bool) async {
        let result =
            isUndo ? await host?.undoThroughHistory() : await host?.redoThroughHistory()
        isStepping = false
        if result == nil { rebuild() }
        await runQueuedStep()
    }

    /// Runs the presses that arrived during a step, in the order they were made (PRD P0-05).
    ///
    /// A press queued in a folder that has since closed or been replaced is dropped: its entry
    /// belonged to the history that is gone (PRD P0-14).
    private func runQueuedStep() async {
        guard !queuedPresses.isEmpty, let host else { return }
        guard beginStep() else { return }
        let press = queuedPresses.removeFirst()
        guard press.openGeneration == host.undoOpenGeneration else {
            isStepping = false
            await runQueuedStep()
            return
        }
        let result: UndoStepResult?
        switch press.direction {
        case .undo: result = await host.undoThroughHistory()
        case .redo: result = await host.redoThroughHistory()
        }
        isStepping = false
        if result == nil { rebuild() }
        await runQueuedStep()
    }

    // MARK: - Mirror

    /// Registers the history's next action as one system undo, named for its menu (PRD P0-05).
    ///
    /// Event grouping is paused for this one registration, so two actions recorded in one run-loop
    /// turn still become two undo groups and one ⌘Z never restores both. The setting is restored
    /// at once, because the window's manager is also UIKit's text-editing undo manager and must
    /// keep grouping events for it.
    private func registerUndoOperation(named name: String?) {
        guard let manager else { return }
        let groupsByEvent = manager.groupsByEvent
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self) { bridge in bridge.handleSystemUndo() }
        if let name { manager.setActionName(name) }
        manager.endUndoGrouping()
        manager.groupsByEvent = groupsByEvent
    }

    /// Mirrors the history into a fresh system stack, one undo group per undoable action.
    ///
    /// The system's redo stack gains operations only while it applies an undo, so a rebuild cannot
    /// restore redo; the history keeps the undone actions, and undoing again registers their pair
    /// (PRD P0-05's last-in, first-out undo). Only the next action's name is known, so the groups
    /// below it carry that name until they are applied.
    private func rebuild() {
        guard let manager, let host else { return }
        // Only this bridge's steps are removed, so a Settings text field keeps its undo history.
        manager.removeAllActions(withTarget: self)
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
