import CloveCore
import SwiftUI

/// Only folder access problems appear beside the navigation subtitle.
struct SaveStatusIndicator: View {
    let browsing: BrowsingModel
    let identifierPrefix: String

    var body: some View {
        if let situation = browsing.folderSituation {
            Image(
                systemName: situation == .driveDisconnected
                    ? "externaldrive.badge.xmark" : "lock.fill"
            )
            .foregroundStyle(Color.clove.text.secondary)
            .frame(width: 28, height: 24)
            .accessibilityLabel(situation == .driveDisconnected ? "Not connected" : "View only")
            .accessibilityIdentifier(identifierPrefix)
        }
    }
}

struct FolderSaveBanner: View {
    let browsing: BrowsingModel
    let identifierPrefix: String
    @State private var isPickingFolder = false

    var body: some View {
        Group {
            if let situation = browsing.folderSituation {
                SaveFailureBanner(situation: situation, identifierPrefix: identifierPrefix) {
                    action in
                    if action == .reopenFolder {
                        Task { await browsing.reopenOpenFolder() }
                    } else {
                        isPickingFolder = true
                    }
                }
                .padding(12)
            }
        }
        .folderPicker(isPresented: $isPickingFolder) { url in
            await browsing.openPickedFolder(url)
        }
    }
}

struct SaveFailureBanner: View {
    let situation: SaveSituation
    let identifierPrefix: String
    let perform: (SaveAction) -> Void

    var body: some View {
        if situation == .driveDisconnected {
            ErrorBanner(
                message: "The drive disconnected.",
                detail: "Reconnect it, then reopen this folder.",
                actionTitle: "Reopen", identifier: identifierPrefix
            ) { perform(.reopenFolder) }
        } else {
            ErrorBanner(
                message: "Access to this folder is no longer available.",
                detail: "Open it again to keep marking.",
                actionTitle: "Open", identifier: identifierPrefix
            ) { perform(.openFolder) }
        }
    }
}
