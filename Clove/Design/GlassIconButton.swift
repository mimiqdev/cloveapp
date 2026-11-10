import CloveCore
import SwiftUI

/// The round glass button the navigation chrome uses for Info, Undo, Filter and "…"
/// (`design/handoff/components.md`, Glass icon button).
///
/// It is 44 × 44 with a 20 pt symbol on iPhone, 40 on iPad and 36 in the Duo dock. The active
/// state fills the circle with `accent` and draws the glyph white, which is how Filter shows that
/// a filter is on. The screen passes the SF Symbol, the accessibility label from `copy.md` and an
/// identifier it can find in a UI test.
struct GlassIconButton: View {
    /// The theme in effect, for the white glyph on the active fill (tokens.md).
    @Environment(\.cloveTheme) private var theme

    /// The accessibility label, from `design/handoff/copy.md` where it names one.
    let label: String

    /// The SF Symbol, from components.md's icon list.
    let symbol: String

    /// Whether the active state is on; the filter uses it (components.md).
    var isActive = false

    /// The size components.md measures on the device.
    var size: ControlSize = .phone

    /// The identifier the screen's UI test uses.
    let identifier: String

    /// What the tap does.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isActive {
                    Circle().fill(Color.clove.accent)
                }
                Image(systemName: symbol)
                    .font(symbolFont)
                    .foregroundStyle(isActive ? Color.white : theme.tokens.primaryText.color)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .cloveGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isActive ? "On" : "Off")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    /// The circle's diameter: 44 on iPhone, 40 on iPad and 36 in the Duo dock (components.md).
    private var diameter: CGFloat {
        switch size {
        case .phone: 44
        case .pad: 40
        case .duo: 36
        }
    }

    /// The 20 pt symbol of the 44 pt button, at the size each device's button takes (components.md).
    private var symbolFont: Font {
        switch size {
        case .phone: .title3
        case .pad: .body
        case .duo: .callout
        }
    }
}

#Preview("Glass icon buttons") {
    HStack(spacing: 12) {
        GlassIconButton(label: "Info", symbol: "info.circle", identifier: "preview.info") {}
        GlassIconButton(
            label: "Filter", symbol: "line.3.horizontal.decrease", isActive: true,
            identifier: "preview.filter"
        ) {}
        GlassIconButton(
            label: "More", symbol: "ellipsis", size: .pad, identifier: "preview.more"
        ) {}
    }
    .padding(24)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
