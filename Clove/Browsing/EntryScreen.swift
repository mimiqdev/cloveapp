import CloveCore
import SwiftUI

/// Entry: open a folder, or see why the last one could not open (PRD Entry, P0-02).
///
/// Design placeholder: opening a real folder and the Recents list arrive with entry and Recents.
struct EntryScreen: View {
    /// The scene's browsing state and the operations this screen performs on it.
    let browsing: BrowsingModel

    var body: some View {
        List {
            Section {
                if browsing.hasFolderContents {
                    Button("Open the test library") { browsing.openFolder() }
                        .accessibilityIdentifier("clove.entry.openFolder")
                } else {
                    Text("No folder is open.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("clove.entry.noFolder")
                }
            } header: {
                Text("Folder")
            } footer: {
                if browsing.folderFailure == nil {
                    Text("Opening a folder arrives with entry and Recents.")
                } else {
                    // PRD P0-02 asks for an explicit answer instead of a silent failure; the
                    // saved reason itself is already on the model for U2's copy.
                    Text("The last folder could not be opened. Choose it again.")
                        .accessibilityIdentifier("clove.entry.folderFailure")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.entry")
    }
}
