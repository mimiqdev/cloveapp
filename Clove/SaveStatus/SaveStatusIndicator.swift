import CloveCore
import SwiftUI

/// A wordless save glyph in the navigation subtitle (owner decision, 2026-11-11).
///
/// The write state remains owned by CloveCore. Failed glyphs retry the failed change or batch.
/// A long press opens the existing unsaved list. Folder recovery keeps its separate glass banner.
struct SaveStatusIndicator: View {
    /// The scene's browsing state and the operations this indicator performs on it.
    let browsing: BrowsingModel

    /// The accessibility identifier this screen's indicator uses, so the grid and the detail
    /// view can be told apart when both are on screen.
    let identifierPrefix: String

    /// Nil summarises the folder; a photo reads only its own latest change.
    var photo: PhotoIdentity?
    var showsOnlyProblems = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A fresh indicator has no history; it must not invent a Saved glyph during the delay.
    @State private var previousGlyph: SaveGlyphState?
    @State private var previousPhoto: PhotoIdentity?
    @State private var revealedSaving: SavingDelayKey?
    @State private var pulse = false

    private struct SavingDelayKey: Hashable {
        let state: SaveGlyphState
        let photo: PhotoIdentity?
        let reduceMotion: Bool
    }

    private var delayKey: SavingDelayKey {
        SavingDelayKey(state: state, photo: photo, reduceMotion: reduceMotion)
    }

    private var renderedState: SaveGlyphState? {
        guard state == .saving else { return state }
        if revealedSaving == delayKey { return .saving }
        // Ignore another photo's history before the photo-change task has a chance to reset it.
        return previousPhoto == photo ? previousGlyph : nil
    }

    private var hidesUnneededGlyph: Bool {
        guard let renderedState else { return true }
        return showsOnlyProblems && ![.failed, .disconnected, .viewOnly].contains(renderedState)
    }

    /// Whether the unsaved photos' list is presented (PRD P0-08).
    @State private var showingUnsaved = false

    var body: some View {
        ZStack {
            if let renderedState {
                Button {
                    guard state == .failed else { return }
                    Task {
                        if let photo {
                            await browsing.retryLatestChange(for: photo)
                        } else if browsing.batchReport?.canRetry == true {
                            await browsing.retryFailedBatch()
                        } else {
                            for change in browsing.unsavedChanges where change.state.failure != nil
                            {
                                await browsing.retryLatestChange(for: change.photo)
                            }
                        }
                    }
                } label: {
                    glyph(for: renderedState)
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(renderedState.label)
                .accessibilityIdentifier(identifierPrefix)
                .opacity(hidesUnneededGlyph ? 0 : 1)
                .accessibilityHidden(hidesUnneededGlyph)
                .contextMenu {
                    if !browsing.unsavedChanges.isEmpty {
                        Button("Unsaved marks") { showingUnsaved = true }
                    }
                }
            }
        }
        .frame(height: 24)
        .task(id: delayKey) {
            withAnimation(nil) {
                if previousPhoto != photo {
                    previousGlyph = nil
                    previousPhoto = photo
                }
                revealedSaving = nil
                pulse = false
            }
            guard state == .saving else {
                previousGlyph = state
                return
            }
            let key = delayKey
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            revealedSaving = key
            if !reduceMotion {
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        // The sheet hangs off the indicator itself, not off the button that opens it, so it is
        // not torn down when a retry makes the last unsaved row go away (PRD P0-08).
        .sheet(isPresented: $showingUnsaved) {
            UnsavedChangesView(browsing: browsing)
        }
    }

    @ViewBuilder private func glyph(for shown: SaveGlyphState) -> some View {
        switch shown {
        case .saved, .cloveOnly:
            Circle().fill(Color.clove.status.saved).frame(width: 8, height: 8)
        case .saving:
            Circle().fill(Color.clove.text.secondary).frame(width: 8, height: 8)
                .opacity(reduceMotion ? 1 : (pulse ? 0.4 : 1))
                .id(delayKey)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.clove.status.failed)
        case .disconnected, .viewOnly:
            Image(
                systemName: shown == .disconnected
                    ? "externaldrive.badge.xmark" : "lock.fill"
            )
            .foregroundStyle(Color.clove.text.secondary)
        }
    }

    private var state: SaveGlyphState {
        if let situation = browsing.folderSituation {
            return situation == .driveDisconnected ? .disconnected : .viewOnly
        }
        if let photo {
            switch browsing.latestChange(for: photo)?.state {
            case .pending, .writing: return .saving
            case .failed: return .failed
            case .savedInCloveOnly: return .cloveOnly
            default: return .saved
            }
        }
        let summary = browsing.saveSummary
        if summary.failed > 0 { return .failed }
        if summary.writing > 0 { return .saving }
        if summary.savedInCloveOnly > 0 { return .cloveOnly }
        return .saved
    }

}

private enum SaveGlyphState: Hashable {
    case saved, saving, failed, disconnected, viewOnly, cloveOnly

    var label: String {
        switch self {
        case .saved: "Saved"
        case .saving: "Saving"
        case .failed: "Save failed. Double-tap to retry."
        case .disconnected: "Not connected"
        case .viewOnly: "View only"
        case .cloveOnly: "Saved in Clove only"
        }
    }
}

/// The folder's recovery banner retains V4's words below the wordless navigation subtitle.
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
                    } else if action == .openFolder {
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

/// The PRD's copy for one failure, with the actions its row offers (PRD Failure and recovery).
///
/// The text and the action titles come from CloveCore's ``SaveSituation``, so the grid, the
/// detail view and entry never word a failure themselves. The parent decides what each action
/// does, because reopening the open folder, choosing another folder and retrying one change are
/// different calls.
///
/// Folder loss uses V1's ErrorBanner (handoff Errors); other failures retain their actions.
struct SaveFailureBanner: View {
    /// The situation to explain, with its PRD copy and actions.
    let situation: SaveSituation

    /// The accessibility identifier prefix, so a caller's test can find this banner.
    let identifierPrefix: String

    /// Performs one of the situation's actions (PRD Failure and recovery).
    let perform: (SaveAction) -> Void

    var body: some View {
        if situation == .driveDisconnected {
            ErrorBanner(
                message: "The drive disconnected.",
                detail: "Reconnect it, then reopen this folder.",
                actionTitle: "Reopen", identifier: identifierPrefix
            ) { perform(.reopenFolder) }
        } else if situation == .lostPermission || situation == .locationUnavailable {
            ErrorBanner(
                message: "Access to this folder is no longer available.",
                detail: "Open it again to keep marking.",
                actionTitle: "Open", identifier: identifierPrefix
            ) { perform(.openFolder) }
        } else {
            otherFailure
        }
    }

    private var otherFailure: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(situation.message)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.caption)
            .foregroundStyle(Color.clove.status.failed)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(situation.message)
            .accessibilityIdentifier("\(identifierPrefix).message")
            HStack(spacing: 8) {
                ForEach(situation.actions, id: \.self) { action in
                    Button(action.title) { perform(action) }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .accessibilityIdentifier("\(identifierPrefix).\(action.rawValue)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The photos whose change has not finished saving, each with Retry (PRD P0-08).
///
/// The list is short on purpose: it names the photos whose marks are not confirmed instead of
/// repeating the whole folder. Retry resends one photo's latest failed change, and Retry all
/// makes the same call for each, so a row never claims a save C4 has not confirmed.
///
/// Uses a system list and sheet for the retry details outside the designed error banner.
struct UnsavedChangesView: View {
    /// The scene's browsing state and the retry calls this list makes.
    let browsing: BrowsingModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if browsing.unsavedChanges.isEmpty {
                    Text("Nothing is waiting to be saved now.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("clove.saveState.unsaved.empty")
                } else {
                    ForEach(browsing.unsavedChanges) { change in
                        row(change)
                    }
                }
            }
            .navigationTitle("Unsaved marks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("clove.saveState.unsaved.close")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Retry all") {
                        Task { await browsing.retryAllUnfinishedChanges() }
                    }
                    .disabled(browsing.unsavedChanges.isEmpty)
                    .accessibilityIdentifier("clove.saveState.retryAll")
                }
            }
            .accessibilityIdentifier("clove.saveState.unsaved")
        }
    }

    /// One photo's row: its name, its save state and its own Retry (PRD P0-08).
    ///
    /// A folder whose location was reported gone makes an unfinished row read **Not saved**, so
    /// the list never keeps **Writing…** on screen after the loss either.
    private func row(_ change: UnsavedChange) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(change.fileName)
                    .lineLimit(1)
                Text(
                    SaveStatus.text(
                        for: change.state, folderLost: browsing.folderLocationLoss != nil)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Retry") {
                Task { await browsing.retryLatestChange(for: change.photo) }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("clove.saveState.retry.\(change.photo.stem)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.saveState.unsaved.\(change.photo.stem)")
    }
}
