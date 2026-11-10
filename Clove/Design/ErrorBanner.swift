import SwiftUI

/// The glass error banner that pins under the toolbar when a folder cannot be read
/// (`design/handoff/components.md`, Banner).
///
/// It holds the message, an optional explanation, and one button, Reopen or Open, filled with
/// `accent`. The grid behind it is dimmed by the screen showing it (screens.md, Errors).
struct ErrorBanner: View {
    /// The message, for example "The drive disconnected." (copy.md, screens.md Errors).
    let message: String

    /// The explanation under it, for example "Reconnect it, then reopen this folder."
    var detail: String?

    /// The button's title: "Reopen" or "Open" (screens.md, Errors).
    let actionTitle: String

    /// The identifier the screen's UI test uses.
    var identifier = "clove.banner"

    /// What the button does.
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.clove.text.primary)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.clove.text.secondary)
                }
            }
            Spacer(minLength: 8)
            Button(action: action) {
                Text(actionTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.clove.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(identifier).action")
        }
        .padding(16)
        .cloveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Error banner") {
    ErrorBanner(
        message: "The drive disconnected.", detail: "Reconnect it, then reopen this folder.",
        actionTitle: "Reopen", identifier: "preview.banner", action: {}
    )
    .padding(16)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
