import CloveCore
import SwiftUI

/// The label circle of the mark capsule: filled with the photo's label colour, or an empty outlined
/// circle when it has none (`design/handoff/components.md`, Label circle).
///
/// It is 36 pt in the capsule, the iPad rail and the Duo dock. Tapping it opens the label picker;
/// the control only asks, the screen decides where the picker appears.
struct LabelCircle: View {
    /// The photo's label, or nil when it has none (PRD Marking rules).
    let label: LabelColour?

    /// The identifier the screen's UI test uses.
    var identifier = "clove.mark.label"

    /// Opens the label picker.
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(Color.clove.label.colour(for: label))
                    .overlay {
                        Circle().strokeBorder(
                            Color.clove.text.secondary, lineWidth: label == nil ? 1.5 : 0)
                    }
            }
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }

    /// The accessibility label from `copy.md`'s `a11y.label`, which names the colour.
    private var accessibilityLabel: String {
        guard let label else { return "Label" }
        return "Label, \(label.rawValue)"
    }
}

#Preview("Label circle") {
    HStack(spacing: 16) {
        LabelCircle(label: nil, identifier: "preview.label.none") {}
        LabelCircle(label: .green, identifier: "preview.label.green") {}
        LabelCircle(label: .purple, identifier: "preview.label.purple") {}
    }
    .padding(24)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
