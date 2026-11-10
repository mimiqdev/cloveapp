import CloveCore
import SwiftUI

/// The open folder's one save-state indicator, with the PRD's recovery copy when the folder
/// itself failed (PRD P0-08).
///
/// The grid and the detail view both show it, and both read ``BrowsingModel``: the summary
/// (**Writing…**, **All saved**, or how many photos are not saved), the folder's own location
/// loss, and the photos whose change has not finished. A save state is never guessed here: the
/// words come from CloveCore's mapping, which shows **Saved** only for a confirmed sidecar write
/// and **Saved in Clove only** only for confirmed Clove storage.
///
/// The unsaved count opens a short list of those photos, each with Retry, plus Retry all, which
/// makes the same per-photo call for each. Reaching a lost folder offers the PRD's
/// Reconnect/reopen or Select-through-Open action.
///
/// Folder losses use the handoff's glass banner and subtitle (screens.md, Errors).
struct SaveStatusIndicator: View {
    /// The scene's browsing state and the operations this indicator performs on it.
    let browsing: BrowsingModel

    /// The accessibility identifier this screen's indicator uses, so the grid and the detail
    /// view can be told apart when both are on screen.
    let identifierPrefix: String

    /// Whether the unsaved photos' list is presented (PRD P0-08).
    @State private var showingUnsaved = false

    /// Whether the system folder picker is presented for an Open action (PRD P0-01).
    @State private var isPickingFolder = false

    var body: some View {
        Group {
            if let situation = browsing.folderSituation {
                VStack(alignment: .leading, spacing: 10) {
                    Text(situation == .driveDisconnected ? "Not connected" : "View only")
                        .font(.caption)
                        .foregroundStyle(Color.clove.text.secondary)
                        .accessibilityIdentifier("\(identifierPrefix).subtitle")
                    SaveFailureBanner(
                        situation: situation, identifierPrefix: "\(identifierPrefix).failure",
                        perform: perform)
                }
            } else {
                summaryControl
            }
        }
        // The sheet hangs off the indicator itself, not off the button that opens it, so it is
        // not torn down when a retry makes the last unsaved row go away (PRD P0-08).
        .sheet(isPresented: $showingUnsaved) {
            UnsavedChangesView(browsing: browsing)
        }
        // PRD Failure and recovery's Select-it-through-Open action opens the system picker here
        // too, so a lost location is recoverable from the grid and from detail (PRD P0-01). The
        // choice arrives after the picker dismisses, so a leaving question can present.
        .folderPicker(isPresented: $isPickingFolder) { url in
            await browsing.openPickedFolder(url)
        }
    }

    /// The folder's one save-state line, which opens the unsaved list when there is one.
    private var summaryControl: some View {
        let summary = browsing.saveSummary
        return Group {
            // The list stays reachable while anything is unfinished, even when the line is
            // showing Writing… (PRD Failure and recovery).
            if !browsing.unsavedChanges.isEmpty {
                Button {
                    showingUnsaved = true
                } label: {
                    summaryLabel(summary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifierPrefix)
                .accessibilityHint("Shows the photos whose marks haven't been saved")
            } else {
                summaryLabel(summary)
                    .accessibilityIdentifier(identifierPrefix)
            }
        }
    }

    /// One line with a symbol and the summary's own words (PRD P0-08).
    private func summaryLabel(_ summary: FolderSaveSummary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol(for: summary))
            Text(summary.text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.text)
        .accessibilityValue(summary.text)
    }

    /// One symbol per reading, so the state is not carried by words alone (PRD P0-15). A failure
    /// wins, so it is never hidden behind a running write (PRD Failure and recovery).
    private func symbol(for summary: FolderSaveSummary) -> String {
        if summary.failed > 0 { return "exclamationmark.triangle" }
        if summary.writing > 0 { return "arrow.triangle.2.circlepath" }
        if summary.isAllSaved { return "checkmark.circle" }
        if summary.savedInCloveOnly > 0 || summary.storedInClove > 0 { return "internaldrive" }
        return "circle.dashed"
    }

    /// Performs one recovery action from the PRD's table (PRD Failure and recovery).
    private func perform(_ action: SaveAction) {
        switch action {
        case .retry, .freeSpaceAndRetry:
            Task { await browsing.retryAllUnfinishedChanges() }
        case .cancel:
            break
        case .reopenFolder:
            Task { await browsing.reopenOpenFolder() }
        case .openFolder:
            isPickingFolder = true
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
/// Design placeholder: a system list, sheet and buttons stand in for the design's list.
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
