import CloveCore
import SwiftUI

/// A theme token as a shape style that resolves from the theme in effect.
///
/// `design/handoff/tokens/tokens.md` names the tokens `Color.clove.<group>.<name>`, and that is
/// how the controls write them: `Color.clove.bg.canvas`, `Color.clove.rating.on`. A `Color` value
/// cannot read the environment, so the leaves are shape styles: `foregroundStyle`, `fill`,
/// `background` and `stroke` resolve them against the theme the view is drawn in, and a theme
/// change draws them again. Where SwiftUI needs a real `Color`, the view reads
/// `@Environment(\.cloveTheme)` and uses `theme.tokens[...].color`.
struct CloveColour: ShapeStyle {
    /// What the value draws: one of the theme's tokens, an extended label, or nothing.
    private enum Source {
        case token(ThemeToken)
        case extendedLabel(LabelColour)
        case transparent
    }

    private let source: Source

    /// One token of the theme in effect (tokens.md).
    init(_ token: ThemeToken) {
        self.source = .token(token)
    }

    /// A label colour: the theme's token for the five default labels, or the closest system colour
    /// for Orange and Pink, which have no token (C12, PRD Marking rules).
    init(_ label: LabelColour?) {
        switch label {
        case .red: self.source = .token(.labelRed)
        case .yellow: self.source = .token(.labelYellow)
        case .green: self.source = .token(.labelGreen)
        case .blue: self.source = .token(.labelBlue)
        case .purple: self.source = .token(.labelPurple)
        case .orange: self.source = .extendedLabel(.orange)
        case .pink: self.source = .extendedLabel(.pink)
        case .none: self.source = .transparent
        }
    }

    /// Draws the token with the theme the view is drawn in (tokens.md).
    func resolve(in environment: EnvironmentValues) -> Color {
        let theme = environment.cloveTheme
        switch source {
        case .token(let token):
            return theme.tokens[token].color
        case .extendedLabel(let label):
            return Self.systemColour(for: label, in: theme.appearance)
        case .transparent:
            return .clear
        }
    }

    /// The closest system colour for Orange and Pink, per appearance.
    ///
    /// The eight themes have no token for the two extended labels (C12, PRD Marking rules), so
    /// they use the system orange and pink of the theme's appearance: `#FF9500` and `#FF2D55` in
    /// light, `#FF9F0A` and `#FF375F` in dark. The tokens themselves are untouched.
    private static func systemColour(
        for label: LabelColour, in appearance: ThemeAppearance
    ) -> Color {
        switch (label, appearance) {
        case (.orange, .light): ThemeColour(hex: 0xFF9500).color
        case (.orange, .dark): ThemeColour(hex: 0xFF9F0A).color
        case (.pink, .light): ThemeColour(hex: 0xFF2D55).color
        case (.pink, .dark): ThemeColour(hex: 0xFF375F).color
        default: ThemeColour(hex: 0xFF9500).color
        }
    }
}

/// The token groups `tokens.md` names, under `Color.clove` (tokens.md).
extension Color {
    /// The theme tokens, resolved from the theme in effect when SwiftUI draws them (tokens.md).
    static var clove: CloveColours { CloveColours() }
}

/// The token groups behind `Color.clove` (tokens.md).
struct CloveColours {
    /// `Color.clove.bg.*`.
    var bg: CloveBackgroundColours { CloveBackgroundColours() }

    /// `Color.clove.surface.*`.
    var surface: CloveSurfaceColours { CloveSurfaceColours() }

    /// `Color.clove.text.*`.
    var text: CloveTextColours { CloveTextColours() }

    /// `Color.clove.separator`.
    var separator: CloveColour { CloveColour(.separator) }

    /// `Color.clove.accent`.
    var accent: CloveColour { CloveColour(.accent) }

    /// `Color.clove.rating.*`.
    var rating: CloveRatingColours { CloveRatingColours() }

    /// `Color.clove.reject`.
    var reject: CloveColour { CloveColour(.reject) }

    /// `Color.clove.status.*`.
    var status: CloveStatusColours { CloveStatusColours() }

    /// `Color.clove.label.*`.
    var label: CloveLabelColours { CloveLabelColours() }

    /// `Color.clove.group`.
    var group: CloveColour { CloveColour(.group) }

    /// `Color.clove.focus.*`.
    var focus: CloveFocusColours { CloveFocusColours() }
}

/// `Color.clove.bg.*`: the app background and the area around a photo (tokens.md).
struct CloveBackgroundColours {
    /// Behind lists, grids and chrome.
    var canvas: CloveColour { CloveColour(.canvas) }

    /// Around a photo in detail and zoom; never tints the photo.
    var stage: CloveColour { CloveColour(.stage) }
}

/// `Color.clove.surface.*`: glass, sheets and cards (tokens.md).
struct CloveSurfaceColours {
    /// Floating glass controls, behind a background blur of about 36.
    var glass: CloveColour { CloveColour(.glass) }

    /// Sheets, menus and the grouped-list background.
    var sheet: CloveColour { CloveColour(.sheet) }

    /// Cells and cards on a sheet.
    var card: CloveColour { CloveColour(.card) }
}

/// `Color.clove.text.*`: text and icons (tokens.md).
struct CloveTextColours {
    /// Primary text and icons.
    var primary: CloveColour { CloveColour(.primaryText) }

    /// Secondary text, counts and metadata.
    var secondary: CloveColour { CloveColour(.secondaryText) }
}

/// `Color.clove.rating.*`: filled and empty stars (tokens.md).
struct CloveRatingColours {
    /// Filled stars.
    var on: CloveColour { CloveColour(.ratingOn) }

    /// Empty stars.
    var off: CloveColour { CloveColour(.ratingOff) }
}

/// `Color.clove.status.*`: saved and failed states (tokens.md).
struct CloveStatusColours {
    /// The saved dot, and toggles that are on.
    var saved: CloveColour { CloveColour(.saved) }

    /// Save and move failures.
    var failed: CloveColour { CloveColour(.failed) }
}

/// `Color.clove.focus.*`: camera-style focus overlay outline and contrast edge (`tokens.md`).
struct CloveFocusColours {
    /// Normal focus frame outline.
    var outline: CloveColour { CloveColour(.focusOutline) }

    /// Subtle dark contrast edge behind focus overlay outlines.
    var edge: CloveColour { CloveColour(.focusEdge) }
}

/// `Color.clove.label.*`: the five colour labels with a token, and the two extended ones, which
/// use the closest system colour per appearance (tokens.md, C12).
struct CloveLabelColours {
    /// Color label red.
    var red: CloveColour { CloveColour(.red) }

    /// Color label yellow.
    var yellow: CloveColour { CloveColour(.yellow) }

    /// Color label green.
    var green: CloveColour { CloveColour(.green) }

    /// Color label blue.
    var blue: CloveColour { CloveColour(.blue) }

    /// Color label purple.
    var purple: CloveColour { CloveColour(.purple) }

    /// Extended label orange, drawn in the system orange of the theme's appearance.
    var orange: CloveColour { CloveColour(.orange) }

    /// Extended label pink, drawn in the system pink of the theme's appearance.
    var pink: CloveColour { CloveColour(.pink) }

    /// The colour of one label, or clear when the photo has none (PRD Marking rules).
    func colour(for label: LabelColour?) -> CloveColour { CloveColour(label) }
}
