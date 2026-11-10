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
                Button("Wait") {
                    Task {
                        await browsing.waitForWrites()
                        isPresented = browsing.leavePrompt != nil
                    }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("clove.leavePrompt.wait")
            } message: {
                Text(
                    "\(browsing.leaveConfirmation.unfinishedCount) changes aren't confirmed yet. Leaving now may lose them."
                )
            }
            .onChange(of: browsing.leavePrompt?.id, initial: true) { _, prompt in
                isPresented = prompt != nil
            }
    }
}
