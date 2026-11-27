import SwiftUI

/// The pill action in its own row above detail's filmstrip.
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

    /// What the button says.
    let title: String

    /// The identifier the screen's UI test uses.
    var identifier = "clove.pillAction"

    /// Visual tone for the pill's text.
    var tone: Tone = .destructive

    var identity: Identity {
        Identity(identifier: identifier, title: title, tone: tone)
    }

    /// Compact header presentation trims padding slightly while preserving capsule tap ergonomics.
    var compact = false

    /// What the tap does.
    let action: () -> Void

    @Environment(\.tapPickerTriggerRequest) private var tapPickerTriggerRequest

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
        .accessibilityIdentifier(identifier)
        .reportTapPickerFrame(identifier)
        .onChange(of: tapPickerTriggerRequest) { _, request in
            if request?.id == identifier {
                action()
            }
        }
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
