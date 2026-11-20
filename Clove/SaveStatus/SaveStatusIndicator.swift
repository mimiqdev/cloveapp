import CloveCore
import SwiftUI

/// Only folder access problems appear beside the navigation subtitle.
struct SaveStatusIndicator: View {
    let browsing: BrowsingModel
    let identifierPrefix: String
    @Environment(\.appLanguage) private var language

    var body: some View {
        if let situation = browsing.folderSituation {
            Image(
                systemName: situation == .driveDisconnected
                    ? "externaldrive.badge.xmark" : "lock.fill"
            )
            .foregroundStyle(Color.clove.text.secondary)
            .frame(width: 28, height: 24)
            .accessibilityLabel(
                AppLocalization.string(
                    situation == .driveDisconnected ? "Not connected" : "View only",
                    language: language)
            )
            .accessibilityIdentifier(identifierPrefix)
            .reportHeaderControlFrame(identifierPrefix)
        }
    }
}

struct FolderSaveBanner: View {
    let browsing: BrowsingModel
    let identifierPrefix: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                .reportHeaderControlFrame(identifierPrefix)
                .transition(
                    .asymmetric(
                        insertion: CloveMotion.slideTransition(
                            edge: .top, offset: 8, reduceMotion: reduceMotion),
                        removal: .identity))
            }
        }
        .animation(
            browsing.folderSituation != nil ? CloveMotion.chrome(reduceMotion: reduceMotion) : nil,
            value: browsing.folderSituation
        )
        .folderPicker(isPresented: $isPickingFolder) { url in
            await browsing.openPickedFolder(url)
        }
    }
}

struct SaveFailureBanner: View {
    let situation: SaveSituation
    let identifierPrefix: String
    let perform: (SaveAction) -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        if situation == .driveDisconnected {
            ErrorBanner(
                message: AppLocalization.string("The drive disconnected.", language: language),
                detail: AppLocalization.string(
                    "Reconnect it, then reopen this folder.", language: language),
                actionTitle: AppLocalization.string("Reopen", language: language),
                identifier: identifierPrefix
            ) { perform(.reopenFolder) }
        } else {
            ErrorBanner(
                message: AppLocalization.string(
                    "Access to this folder is no longer available.", language: language),
                detail: AppLocalization.string(
                    "Open it again to keep marking.", language: language),
                actionTitle: AppLocalization.string("Open", language: language),
                identifier: identifierPrefix
            ) { perform(.openFolder) }
        }
    }
}
