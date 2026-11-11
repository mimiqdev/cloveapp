import SwiftUI

/// The glass toast that reports a finished batch (`design/handoff/components.md`, Toast).
///
/// It is 358 × 55, radius 26, with a padding of 18/8 and a gap of 12. The text sits on the left and
/// the action on the right, as accent text in a 72 × 38 target; a second line in `reject` says how
/// many photos stayed behind. The screen hides it after about 6 seconds and keeps Undo available in
/// the top bar, so the timing lives with the screen rather than in the view.
struct Toast: View {
    /// The first line, for example "Moved 42 to _Rejected" (copy.md `move.toast.done`).
    let message: String

    /// The optional second line, in `reject`, for example "2 couldn't be moved" (copy.md
    /// `move.toast.failed`).
    var detail: String?

    /// The action's title, "Undo" or "Details" (copy.md `move.toast.undo` and `.details`), or nil
    /// for a toast with no action.
    var actionTitle: String?

    /// An optional second action, such as Details beside Undo.
    var secondaryActionTitle: String?
    var onSecondaryAction: (() -> Void)?

    /// The identifier the screen's UI test uses.
    var identifier = "clove.toast"

    /// What the action does.
    var onAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.clove.text.primary)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.clove.reject)
                }
            }
            Spacer(minLength: 8)
            if let secondaryActionTitle, let onSecondaryAction {
                action(
                    secondaryActionTitle, identifier: "secondaryAction", perform: onSecondaryAction)
            }
            if let actionTitle, let onAction {
                action(actionTitle, identifier: "action", perform: onAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: 358, minHeight: 55)
        .cloveGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func action(_ title: String, identifier suffix: String, perform: @escaping () -> Void)
        -> some View
    {
        Button(action: perform) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.clove.accent)
                .frame(minWidth: 72, minHeight: 38)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(identifier).\(suffix)")
    }
}

#Preview("Toast") {
    VStack(spacing: 12) {
        Toast(
            message: "Moved 42 to _Rejected", actionTitle: "Undo",
            identifier: "preview.toast", onAction: {})
        Toast(
            message: "Moved 40 to _Rejected", detail: "2 couldn't be moved", actionTitle: "Details",
            identifier: "preview.toast.details", onAction: {})
    }
    .padding(16)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
