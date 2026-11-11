import CloveCore
import SwiftUI

/// The Reject circle: a 36 pt circle with a `reject` outline and ✕ when off, filled `reject` with a
/// white ✕ when on (`design/handoff/components.md`, Reject circle).
///
/// The iPad rail uses 40 and the Duo dock 32. The control is icon-only; the accessibility label
/// comes from `copy.md`'s `a11y.reject` and `a11y.rejected`, so VoiceOver reads the state.
struct RejectCircle: View {
    /// The theme in effect, for the glyph colour that is not a token (tokens.md).
    @Environment(\.cloveTheme) private var theme

    /// Whether the photo is rejected (PRD P0-05: the rating −1).
    let isRejected: Bool

    /// The size components.md measures on the device.
    var size: ControlSize = .phone

    /// The identifier the screen's UI test uses.
    var identifier = "clove.mark.reject"

    /// Toggles Reject, the rating −1 (PRD Marking rules).
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                if isRejected {
                    Circle().fill(Color.clove.reject)
                } else {
                    Circle().strokeBorder(Color.clove.reject, lineWidth: 1.5)
                }
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isRejected ? Color.white : theme.tokens.reject.color)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRejected ? "Rejected" : "Reject")
        .accessibilityAddTraits(isRejected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    /// The circle's diameter: 36 on iPhone, 40 on iPad and 32 in the Duo dock (components.md).
    private var diameter: CGFloat {
        switch size {
        case .phone: 36
        case .pad: 40
        case .duo: 32
        }
    }
}

#Preview("Reject circle") {
    HStack(spacing: 16) {
        RejectCircle(isRejected: false, identifier: "preview.reject.off") {}
        RejectCircle(isRejected: true, identifier: "preview.reject.on") {}
    }
    .padding(24)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
