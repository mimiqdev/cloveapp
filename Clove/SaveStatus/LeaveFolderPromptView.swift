import CloveCore
import SwiftUI

/// The system alert for unfinished marks (handoff Errors; PRD P0-08).
/// Wait uses the existing drain/recheck path; Leave anyway uses the existing close path.
struct LeaveFolderPromptView: ViewModifier {
    let browsing: BrowsingModel
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .alert("Some marks haven't finished saving.", isPresented: $isPresented) {
                Button("Leave anyway", role: .destructive) {
                    Task { await browsing.leaveAnyway() }
                }
                .accessibilityIdentifier("clove.leavePrompt.leaveAnyway")
                Button("Wait", role: .cancel) {
                    Task {
                        await browsing.waitForWrites()
                        isPresented = browsing.leavePrompt != nil
                    }
                }
                .disabled(browsing.isWaitingForWrites)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("clove.leavePrompt.wait")
            } message: {
                Text(
                    browsing.isWaitingForWrites
                        ? "Waiting for writes… You can still leave anyway."
                        : countText
                )
            }
            .onChange(of: browsing.leavePrompt?.id, initial: true) { _, prompt in
                isPresented = prompt != nil
            }
            .task(id: browsing.isWaitingForWrites) {
                guard browsing.isWaitingForWrites else { return }
                // Let the first system alert finish dismissing before presenting the waiting
                // alert. Leave anyway stays available while the existing drain is running.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, browsing.leavePrompt != nil else { return }
                isPresented = true
            }
    }

    private var countText: String {
        let count = browsing.leaveConfirmation.unfinishedCount
        return count == 1
            ? "1 change isn't confirmed yet. Leaving now may lose it."
            : "\(count) changes aren't confirmed yet. Leaving now may lose them."
    }
}
