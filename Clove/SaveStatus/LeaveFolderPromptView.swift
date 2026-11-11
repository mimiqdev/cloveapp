import CloveCore
import SwiftUI

/// The system alert for unfinished marks (handoff Errors; PRD P0-08).
/// Wait dismisses the question and stays in the folder while existing writes continue.
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
                Button("Wait", role: .cancel) { browsing.cancelLeave() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("clove.leavePrompt.wait")
            } message: {
                Text(countText)
            }
            .onChange(of: browsing.leavePrompt?.id, initial: true) { _, prompt in
                isPresented = prompt != nil
            }
    }

    private var countText: String {
        let count = browsing.leaveConfirmation.unfinishedCount
        return count == 1
            ? "1 change isn't confirmed yet. Leaving now may lose it."
            : "\(count) changes aren't confirmed yet. Leaving now may lose them."
    }
}
