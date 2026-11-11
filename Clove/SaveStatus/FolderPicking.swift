import SwiftUI

/// Reports the chosen folder only after the system picker has finished dismissing.
/// A leave confirmation cannot be presented while that sheet is still dismissing.
struct FolderPickingModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onPick: (URL) async -> Void

    @State private var handoff = FolderPickHandoff()
    @State private var activePresentation: FolderPickHandoff.Presentation?
    @State private var shownPresentation: FolderPickHandoff.Presentation?

    func body(content: Content) -> some View {
        content
            .sheet(item: sheetPresentation, onDismiss: pickerDismissed) { presentation in
                FolderPicker(
                    onPick: { receive($0, from: presentation) },
                    onCancel: { cancel(presentation) }
                )
                .ignoresSafeArea()
            }
            .onChange(of: isPresented, initial: true) { _, requested in
                if requested {
                    presentIfRequested()
                } else {
                    shownPresentation = nil
                }
            }
    }

    private var sheetPresentation: Binding<FolderPickHandoff.Presentation?> {
        Binding(
            get: { shownPresentation },
            set: { next in
                let wasShown = shownPresentation != nil
                shownPresentation = next
                if next == nil, wasShown { isPresented = false }
            })
    }

    private func presentIfRequested() {
        // A second request waits for the previous sheet's dismissal callback.
        guard isPresented, activePresentation == nil else { return }
        let presentation = handoff.beginPresentation()
        activePresentation = presentation
        shownPresentation = presentation
    }

    private func receive(_ url: URL, from presentation: FolderPickHandoff.Presentation) {
        presentIfRequested()
        guard handoff.presentation == presentation else { return }
        handOff(handoff.picked(url, from: presentation))
        dismiss(presentation)
    }

    private func cancel(_ presentation: FolderPickHandoff.Presentation) {
        guard handoff.presentation == presentation else { return }
        handoff.cancel(presentation)
        dismiss(presentation)
    }

    private func dismiss(_ presentation: FolderPickHandoff.Presentation) {
        guard shownPresentation == presentation else { return }
        shownPresentation = nil
        isPresented = false
    }

    private func pickerDismissed() {
        guard let presentation = activePresentation else { return }
        dismiss(presentation)
        activePresentation = nil
        let picked = handoff.dismissed(presentation, requestedAgain: &isPresented)
        if isPresented {
            presentIfRequested()
        } else {
            handOff(picked)
        }
    }

    private func handOff(_ url: URL?) {
        guard let url else { return }
        Task { await onPick(url) }
    }
}

extension View {
    /// Presents the folder picker; `onPick` runs after the picker has finished dismissing
    /// (PRD P0-01, P0-02).
    func folderPicker(isPresented: Binding<Bool>, onPick: @escaping (URL) async -> Void)
        -> some View
    {
        modifier(FolderPickingModifier(isPresented: isPresented, onPick: onPick))
    }
}
