import SwiftUI
import UIKit

/// Gives the browsing model's undo bridge the scene's undo manager (PRD P0-05).
///
/// PRD P0-05's Undo row uses the system undo mechanism, and the system's ⌘Z, ⇧⌘Z and three-finger
/// gestures act on the `UndoManager` of the window the view was installed in. SwiftUI publishes
/// that manager in the environment; when a scene has none yet, the view reads it from the window
/// it was installed in. Detail, the group view and the grid attach the same manager, and the
/// bridge ignores every attach after the first.
struct UndoHistoryAttachment: ViewModifier {
    /// The scene's browsing state, whose undo bridge registers with the manager.
    let browsing: BrowsingModel

    /// The manager SwiftUI publishes for this scene, when it has one.
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        content
            .background {
                WindowUndoManagerReader { manager in
                    browsing.attachUndoManager(manager)
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            .onAppear { browsing.attachUndoManager(undoManager) }
    }
}

extension View {
    /// Registers this screen's browsing model with the scene's undo manager (PRD P0-05).
    func undoHistory(browsing: BrowsingModel) -> some View {
        modifier(UndoHistoryAttachment(browsing: browsing))
    }
}

/// A zero-sized view whose only job is to read its window's `UndoManager` (PRD P0-05).
private struct WindowUndoManagerReader: UIViewRepresentable {
    /// Receives the manager the view's window uses, or nil while it has no window.
    let report: (UndoManager?) -> Void

    func makeUIView(context: Context) -> UndoManagerReadingView {
        let view = UndoManagerReadingView()
        view.report = report
        return view
    }

    func updateUIView(_ view: UndoManagerReadingView, context: Context) {
        view.report = report
        view.reportManager()
    }
}

/// The window's view, which reports the manager as soon as it joins a window (PRD P0-05).
final class UndoManagerReadingView: UIView {
    /// Receives the window's manager; the bridge ignores a repeat of the same one.
    var report: ((UndoManager?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportManager()
    }

    /// Reports the manager of the window this view belongs to.
    ///
    /// The call is deferred by one turn, so a registration that changes the model's observable
    /// state never runs inside a SwiftUI view update.
    func reportManager() {
        guard window != nil else { return }
        let manager = window?.undoManager
        Task { @MainActor [report] in report?(manager) }
    }
}
