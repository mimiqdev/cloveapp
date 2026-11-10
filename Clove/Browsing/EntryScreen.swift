import CloveCore
import SwiftUI

/// Entry: open a folder, reopen one from Recents, or see why a remembered folder could not open
/// (PRD Entry, P0-01, P0-02).
///
/// The primary action opens the system folder picker; C11 validates the picked folder with a real
/// read before the grid appears. Each Recents row shows the fields PRD P0-02 lists and reopens its
/// remembered location with one tap.
///
/// Design placeholder: the visual design replaces the list, the row layout and the button style;
/// the copy for every failure stays U7's. U2's files keep only this structure and the identifiers
/// its UI test uses.
struct EntryScreen: View {
    /// The scene's browsing state and the operations this screen performs on it.
    let browsing: BrowsingModel

    /// Whether the system folder picker is presented (PRD P0-01).
    @State private var isPickingFolder = false

    var body: some View {
        List {
            Section {
                Button("Open folder…", systemImage: "folder.badge.plus") {
                    isPickingFolder = true
                }
                .accessibilityIdentifier("clove.entry.pickFolder")
                if browsing.canContinueBrowsing {
                    // The open folder stays open when entry comes back into view, so returning to
                    // it needs no second pick and no second scan (PRD P0-01).
                    Button("Continue browsing", systemImage: "photo.on.rectangle") {
                        browsing.openFolder()
                    }
                    .accessibilityIdentifier("clove.entry.openFolder")
                } else {
                    Text("No folder is open.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("clove.entry.noFolder")
                }
            } header: {
                Text("Folder")
            } footer: {
                folderFooter
            }
            Section {
                if browsing.recents.isEmpty {
                    Text("No recent folders.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("clove.entry.noRecents")
                } else {
                    ForEach(browsing.recents) { recent in
                        recentRow(recent)
                    }
                }
            } header: {
                Text("Recents")
            }
        }
        .folderPicker(isPresented: $isPickingFolder) { url in
            await browsing.openPickedFolder(url)
        }
        .task { await browsing.reloadRecents() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.entry")
    }

    /// Why the last pick or launch restore did not open a folder, or the entry hint (PRD P0-02).
    @ViewBuilder
    private var folderFooter: some View {
        if let failure = browsing.folderFailure {
            Text(FolderFailureExplanation.text(for: failure))
                .accessibilityIdentifier("clove.entry.folderFailure")
        } else if browsing.recentsFailure != nil {
            // PRD P0-02: a stored list that cannot be read is explained, not shown as empty.
            Text("Clove could not read its list of recent folders.")
                .accessibilityIdentifier("clove.entry.recentsFailure")
        } else {
            Text("Choose a folder to browse its photos. Nothing is copied into Clove.")
                .accessibilityIdentifier("clove.entry.hint")
        }
    }

    /// One remembered folder: its path, the fields P0-02 lists, and why it did not reopen.
    private func recentRow(_ recent: RecentFolder) -> some View {
        Button {
            Task { await browsing.reopen(recent) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(recent.pathSummary)
                Text(RecentFolderSummary.detail(for: recent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let failure = browsing.recentFailure(for: recent.id) {
                    // PRD P0-02 asks for the reason on the item and for the folder again, so the
                    // reason never replaces the row or the tap that retries it.
                    Text(FolderFailureExplanation.text(for: failure))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("clove.entry.recentFailure")
                }
            }
        }
        .accessibilityIdentifier("clove.entry.recent.\(recent.id.uuidString)")
    }
}
