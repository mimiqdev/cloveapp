import SwiftUI

/// A finishing action's partial failure: what was saved, what still needs a retry, and the two
/// ways out (PRD In-group culling, finishing actions; PRD P0-09; PRD Failure and recovery).
///
/// PRD P0-09 and PRD Failure and recovery keep successful writes saved and offer a retry of only
/// the failed items, so the bar shows C10's counts and a retry that sends just those changes. Its
/// wording and layout follow the PRD's batch rules, and the text itself is
/// ``GroupFinishingResult/partialFailureSummary``'s, which keeps one source for the counts
/// (PRD P0-12).
///
/// Design placeholder: a system warning symbol and bordered buttons stand in for the visual
/// design's failure bar.
struct GroupFinishingFailureBar: View {
    /// The counts C10 reports for the finished action (PRD Failure and recovery).
    let summary: String

    /// Whether a finishing action or retry is already running, so the retry waits for it
    /// (PRD P0-09).
    let isBusy: Bool

    /// Sends the failed changes again, and only those (PRD P0-09).
    let retry: () -> Void

    /// Hides the bar without retrying; the failed changes stay unsaved (PRD P0-08).
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(summary)
                .font(.footnote)
                .accessibilityIdentifier("clove.group.failure")
            Spacer(minLength: 8)
            Button("Retry failed items", action: retry)
                .disabled(isBusy)
                .accessibilityIdentifier("clove.group.failure.retry")
            Button("Cancel", action: cancel)
                .accessibilityIdentifier("clove.group.failure.cancel")
        }
        .font(.footnote)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.group.failureBar")
    }
}
