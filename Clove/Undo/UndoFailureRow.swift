import SwiftUI

/// One undo or redo step whose writes did not all confirm, with the counts and a retry
/// (PRD P0-09; PRD P0-08).
///
/// C5 keeps a failed step's entry, so the retry runs that same step again; U7's save state also
/// lists the individual photos whose writes need resending, so both paths lead to the same marks.
///
/// Design placeholder: a system warning symbol, a caption and a bordered button stand in for the
/// handoff's treatment; V2 moves the Undo result into the top bar and a toast.
struct UndoFailureRow: View {
    /// C5's partial-failure line, from ``MarkUndoResult/partialFailureSummary``
    /// (PRD Failure and recovery, partial batch failure).
    let summary: String

    /// Retries the failed step in the direction it failed (PRD P0-08).
    let retry: () -> Void

    /// The accessibility identifier prefix, so the grid and detail rows can be told apart.
    let identifierPrefix: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(summary)
                .font(.footnote)
                .accessibilityIdentifier("\(identifierPrefix).message")
            Spacer(minLength: 8)
            Button("Try again", action: retry)
                .accessibilityIdentifier("\(identifierPrefix).retry")
        }
        .font(.footnote)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifierPrefix)
    }
}
