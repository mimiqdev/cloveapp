import CloveCore
import SwiftUI

/// The question before leaving a folder with unconfirmed writes (PRD Failure and recovery,
/// last row).
///
/// PRD P0-08 requires the question and PRD Failure and recovery forbids treating unconfirmed
/// changes as saved after leaving. The copy and the two action titles come from CloveCore's
/// ``LeaveFolderConfirmation``. **Wait for writes** holds the question with a visible waiting
/// state while C4 drains and still lets the user choose **Leave anyway**; **Leave anyway** closes
/// the folder and goes where the user was heading.
///
/// Design placeholder: a plain stack with system buttons stands in for the design's confirmation.
struct LeaveFolderPromptView: View {
    /// The scene's browsing state, which owns the question and its answer.
    let browsing: BrowsingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LeaveFolderConfirmation.message)
                .font(.headline)
                .accessibilityIdentifier("clove.leavePrompt.title")
            Text(countText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("clove.leavePrompt.detail")
            if browsing.isWaitingForWrites {
                ProgressView("Waiting for writes…")
                    .accessibilityIdentifier("clove.leavePrompt.waiting")
            }
            Spacer(minLength: 0)
            Button(browsing.leaveConfirmation.waitTitle) {
                Task { await browsing.waitForWrites() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(browsing.isWaitingForWrites)
            .accessibilityIdentifier("clove.leavePrompt.wait")
            Button(browsing.leaveConfirmation.leaveTitle) {
                Task { await browsing.leaveAnyway() }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("clove.leavePrompt.leaveAnyway")
            Button(SaveAction.cancel.title) { browsing.cancelLeave() }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("clove.leavePrompt.cancel")
        }
        .padding(20)
        .presentationDetents([.medium])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.leavePrompt")
    }

    /// How many changes the question is about, so "Some marks" has a number (PRD P0-08).
    private var countText: String {
        let count = browsing.leaveConfirmation.unfinishedCount
        return count == 1
            ? "1 change isn't confirmed yet." : "\(count) changes aren't confirmed yet."
    }
}
