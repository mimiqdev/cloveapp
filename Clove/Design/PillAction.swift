import SwiftUI

/// The pill action above the mark capsule or the filmstrip in group review
/// (`design/handoff/components.md`, Pill action).
///
/// It is a glass capsule with one line of semibold text: "Reject 6 unmarked" in `reject` or
/// "Continue →" in `accent` (copy.md `group.rejectRest` and `group.continue`). Which one it is and
/// when it appears stays with the group view (PRD In-group culling, V3).
struct PillAction: View {
    /// What the button says (`design/handoff/copy.md`).
    let title: String

    /// Whether the action finishes the group in `accent` or rejects the rest in `reject`.
    var tone: Tone = .accent

    /// The identifier the screen's UI test uses.
    var identifier = "clove.pillAction"

    /// What the tap does.
    let action: () -> Void

    /// The two tones components.md draws the pill action in.
    enum Tone {
        /// "Continue →", in `accent`.
        case accent

        /// "Reject N unmarked", in `reject`.
        case reject

        /// The token the text uses.
        var colour: CloveColour {
            switch self {
            case .accent: Color.clove.accent
            case .reject: Color.clove.reject
            }
        }
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tone.colour)
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
    VStack(spacing: 12) {
        PillAction(
            title: "Reject 6 unmarked", tone: .reject, identifier: "preview.pill.reject"
        ) {}
        PillAction(title: "Continue →", tone: .accent, identifier: "preview.pill.accent") {}
    }
    .padding(24)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
