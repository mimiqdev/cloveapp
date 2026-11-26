import CloveCore
import SwiftUI

/// The round glass button the navigation chrome uses for Info, Undo, Filter and "…"
/// (`design/handoff/components.md`, Glass icon button).
///
/// It is 44 × 44 with a 20 pt symbol on iPhone, 40 on iPad and 36 in the Duo dock. The active
/// state keeps the translucent glass circle and tints only the symbol in `accent`, matching the
/// iOS system toolbar controls. The screen passes the SF Symbol, the accessibility label from
/// `copy.md` and an identifier it can find in a UI test.
struct GlassIconButton: View {
    /// The theme in effect, for the symbol colour (tokens.md).
    @Environment(\.cloveTheme) private var theme

    /// The accessibility label, from `design/handoff/copy.md` where it names one.
    let label: String

    /// The SF Symbol, from components.md's icon list.
    let symbol: String

    /// Whether the button's active state is on, or nil for a button that has none; active buttons
    /// tint only the symbol in `accent` and report On or Off (components.md).
    var isActive: Bool?

    /// Optional accessibility value override when `isActive` is non-nil.
    var activeAccessibilityValue: String?

    /// The size components.md measures on the device.
    var size: ControlSize = .phone

    /// The identifier the screen's UI test uses.
    let identifier: String

    /// What the tap does.
    let action: () -> Void

    /// The token used to tint the symbol in its active or inactive state.
    static func symbolToken(isActive: Bool?) -> ThemeToken {
        isActive == true ? .accent : .primaryText
    }

    /// The resolved symbol colour for `isActive` in `theme`.
    static func symbolColour(isActive: Bool?, in theme: CloveTheme) -> Color {
        theme.tokens[symbolToken(isActive: isActive)].color
    }

    /// The circle's diameter: 44 on iPhone, 40 on iPad and 36 in the Duo dock (components.md).
    static func diameter(for size: ControlSize) -> CGFloat {
        switch size {
        case .phone: 44
        case .pad: 40
        case .duo: 36
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(symbolFont)
                .foregroundStyle(Self.symbolColour(isActive: isActive, in: theme))
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .cloveGlass(in: Circle())
        }
        .buttonStyle(.cloveGlassPress)
        .accessibilityLabel(label)
        .modifier(
            ActiveStateAccessibility(isActive: isActive, valueOverride: activeAccessibilityValue)
        )
        .accessibilityIdentifier(identifier)
    }

    private var diameter: CGFloat {
        Self.diameter(for: size)
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

/// Reports a button's active state only when the button has one, so Info, Undo and More do not
/// announce On or Off they cannot be.
private struct ActiveStateAccessibility: ViewModifier {
    /// The active state, or nil for a button without one.
    let isActive: Bool?
    let valueOverride: String?
    @Environment(\.appLanguage) private var language

    func body(content: Content) -> some View {
        if let isActive {
            content
                .accessibilityValue(
                    valueOverride
                        ?? AppLocalization.string(isActive ? "On" : "Off", language: language)
                )
                .accessibilityAddTraits(isActive ? .isSelected : [])
        } else {
            content
        }
    }
}
