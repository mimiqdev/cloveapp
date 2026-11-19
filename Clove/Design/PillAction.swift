import SwiftUI

/// The pill action in its own row above detail's filmstrip
/// (`design/handoff/components.md`, Pill action).
///
/// It is a glass capsule with one line of semibold text: `"Reject N unmarked"` in `reject`
/// (`copy.md` `group.rejectRest`) or `"Expand N photos"` in `text.primary`. The detail view decides
/// when each pill appears (issue #304).
struct PillAction: View {
    enum Tone: Hashable {
        case destructive
        case neutral

        var textColor: CloveColour {
            switch self {
            case .destructive: Color.clove.reject
            case .neutral: Color.clove.text.primary
            }
        }
    }

    struct Identity: Hashable {
        let identifier: String
        let title: String
        let tone: Tone
    }

    /// What the button says (`design/handoff/copy.md`).
    let title: String

    /// The identifier the screen's UI test uses.
    var identifier = "clove.pillAction"

    /// Visual tone for the pill's text.
    var tone: Tone = .destructive

    var identity: Identity {
        Identity(identifier: identifier, title: title, tone: tone)
    }

    /// Incrementing this counter pulses a subtle scale bounce (used for read-only nudges).
    var nudgeTrigger: Int = 0

    /// Compact header presentation trims padding slightly while preserving capsule tap ergonomics.
    var compact = false

    /// What the tap does.
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isNudged = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(tone.textColor)
                .padding(.horizontal, compact ? 14 : 20)
                .padding(.vertical, compact ? 8 : 10)
                .contentShape(Capsule())
                .cloveGlass(in: Capsule())
        }
        .frame(minHeight: compact ? 44 : nil)
        .buttonStyle(.cloveGlassPress)
        .scaleEffect(isNudged && !reduceMotion ? 1.08 : 1)
        .animation(CloveMotion.nudge(reduceMotion: reduceMotion), value: isNudged)
        .task(id: nudgeTrigger) {
            guard nudgeTrigger > 0 else { return }
            isNudged = true
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            isNudged = false
        }
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Pill action") {
    VStack(spacing: 12) {
        PillAction(title: "Expand 4 photos", identifier: "preview.pill.expand", tone: .neutral) {}
        PillAction(title: "Reject 6 unmarked", identifier: "preview.pill.reject") {}
    }
    .padding(24)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
