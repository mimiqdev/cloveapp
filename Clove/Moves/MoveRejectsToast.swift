import CloveCore
import SwiftUI

/// The toast a completed Move rejects run shows over the grid (design handoff, PRD P0-10).
///
/// The design handoff shows "Moved N to <folder>", adds "<M> couldn't be moved" with Details on a
/// partial run, and leaves a slot for Undo. C14 owns Undo, so this task deliberately shows no
/// Undo button; a later task can pass the action into ``undo`` without changing the toast.
///
/// Design placeholder: a system material capsule stands in for the handoff's glass toast.
struct MoveRejectsToast: View {
    /// The completed move's result, kept photos and folder name (PRD P0-10).
    let completed: CompletedRejectMove
    /// Opens the details sheet for the failed sets (design handoff, P0-10).
    let showDetails: () -> Void
    /// C14's undo action once move undo lands; nil keeps the slot hidden (PRD P0-10).
    var undo: (() -> Void)?

    var body: some View {
        let copy = RejectMoveToast(
            result: completed.result, rejectsFolderName: completed.rejectsFolderName)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.message)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("clove.moves.toast")
                if let failure = copy.failureMessage {
                    Text(failure)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("clove.moves.toast.failure")
                }
                if let skipped = copy.skippedMessage {
                    Text(skipped)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("clove.moves.toast.skipped")
                }
                if let notRejected = copy.noLongerRejectedMessage {
                    Text(notRejected)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("clove.moves.toast.noLongerRejected")
                }
            }
            Spacer(minLength: 0)
            if let undo {
                Button("Undo", action: undo)
                    .accessibilityIdentifier("clove.moves.undo")
            }
            if copy.showsDetails {
                Button("Details", action: showDetails)
                    .accessibilityIdentifier("clove.moves.details")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.moves.toast.container")
    }
}

/// The details sheet behind a partial Move rejects toast (design handoff, PRD P0-10).
///
/// The handoff's title and subtitle say the failed photos stay rejected and nothing was deleted,
/// and each row names the photo set and reason. Try again runs C6's retry of failed sets only.
///
/// Design placeholder: system text, a list and buttons stand in for the handoff's glass sheet.
struct MoveRejectsDetailsSheet: View {
    /// The browsing state the retry goes through (PRD P0-10).
    let browsing: BrowsingModel
    /// The completed move the toast showed (PRD P0-10).
    let completed: CompletedRejectMove

    @Environment(\.dismiss) private var dismiss

    /// The current result, replaced when Try again returns a new one (PRD P0-10).
    @State private var result: RejectMoveResult

    /// The latest completed record, so a second Try again uses the new retry handle (P0-10).
    @State private var current: CompletedRejectMove

    /// A retry that could not run, shown in the sheet instead of being swallowed (P0-10).
    @State private var retryError: String?

    /// Creates the sheet from the completed move's result.
    init(browsing: BrowsingModel, completed: CompletedRejectMove) {
        self.browsing = browsing
        self.completed = completed
        _result = State(initialValue: completed.result)
        _current = State(initialValue: completed)
    }

    var body: some View {
        let details = RejectMoveDetails(result: result)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(details.subtitle)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("clove.moves.details.subtitle")
                    if let skipped = details.skippedMessage {
                        Text(skipped)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("clove.moves.details.skipped")
                    }
                    if let notRejected = details.noLongerRejectedMessage {
                        Text(notRejected)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("clove.moves.details.noLongerRejected")
                    }
                    if let retryError {
                        Text(retryError)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("clove.moves.details.error")
                    }
                    ForEach(details.rows) { row in
                        rowView(row)
                    }
                    HStack {
                        Button("Done") {
                            browsing.dismissRejectMoveToast()
                            dismiss()
                        }
                        .accessibilityIdentifier("clove.moves.details.done")
                        Spacer()
                        if details.canRetry {
                            Button("Try again") { retry() }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("clove.moves.details.retry")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(details.title)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("clove.moves.details.sheet")
        }
        .accessibilityElement(children: .contain)
    }

    /// One failed set's file name and reason (design handoff, P0-10).
    private func rowView(_ row: RejectMoveDetails.Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.fileName)
                .font(.headline)
            Text(row.reason)
                .font(.subheadline)
                .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clove.moves.details.row.\(row.id.stem)")
    }

    /// Retries only the failed sets, then closes the sheet once nothing failed is left (P0-10).
    private func retry() {
        Task {
            retryError = nil
            do {
                guard let retried = try await browsing.retryRejectMove(current) else {
                    retryError = "Those photos can no longer be retried."
                    return
                }
                result = retried
                current = CompletedRejectMove(
                    result: retried, keptIdentities: current.keptIdentities,
                    rejectsFolderName: current.rejectsFolderName,
                    folder: current.folder, openGeneration: current.openGeneration)
                let details = RejectMoveDetails(result: retried)
                if details.rows.isEmpty {
                    // The updated toast now reports the retry's total; closing the sheet leaves
                    // it visible instead of dismissing the result the person just asked for.
                    dismiss()
                }
            } catch {
                retryError = "The failed photos couldn't be retried."
            }
        }
    }
}
