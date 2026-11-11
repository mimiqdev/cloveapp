import SwiftUI

/// Presents the system folder picker and reports the chosen folder once it has dismissed.
///
/// PRD Failure and recovery's "Select it through Open" opens the picker from the save-state
/// banner, and a chosen folder can leave the open folder with unfinished writes, which raises the
/// leaving question. Presenting that question while the picker sheet is still dismissing makes
/// UIKit refuse the presentation, so the choice is handed back from the sheet's `onDismiss`,
/// after the dismissal has finished (PRD P0-01, P0-02).
///
/// The picker is the system document picker (PRD P0-01).
struct FolderPickingModifier: ViewModifier {
    /// Whether the picker is presented.
    @Binding var isPresented: Bool

    /// Runs with the chosen folder, after the picker finished dismissing.
    let onPick: (URL) async -> Void

    /// The folder the picker reported, kept until the dismissal completes.
    @State private var picked: URL?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: handOff) {
            FolderPicker(
                onPick: { url in
                    picked = url
                    isPresented = false
                },
                onCancel: { isPresented = false }
            )
            .ignoresSafeArea()
        }
    }

    /// Hands the chosen folder on once nothing is presenting over the screen any more.
    private func handOff() {
        guard let url = picked else { return }
        picked = nil
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
