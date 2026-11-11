import SwiftUI

/// The finishing pill above detail's expanded filmstrip group (`group.rejectRest`).
struct PillAction: View {
    let title: String
    var identifier = "clove.pillAction"
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
