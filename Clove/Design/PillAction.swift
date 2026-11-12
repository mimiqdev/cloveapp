import SwiftUI

/// The pill action in its own row above detail's filmstrip
/// (`design/handoff/components.md`, Pill action).
///
/// It is a glass capsule with one line of semibold text: "Reject N unmarked" in `reject`
/// (copy.md `group.rejectRest`). The detail view decides when it appears (PRD In-group culling).
struct PillAction: View {
    /// What the button says (`design/handoff/copy.md`).
    let title: String

    /// The identifier the screen's UI test uses.
    var identifier = "clove.pillAction"

    /// What the tap does.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.clove.reject)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .contentShape(Capsule())
                .cloveGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Pill action") {
    PillAction(title: "Reject 6 unmarked", identifier: "preview.pill.reject") {}
        .padding(24)
        .background(Rectangle().fill(Color.clove.bg.canvas))
}
