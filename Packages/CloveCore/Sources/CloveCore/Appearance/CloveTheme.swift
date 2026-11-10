/// Whether a theme is a light or a dark appearance.
///
/// It decides the status bar and the keyboard, and the theme the system appearance picks when
/// "Match system light/dark" is on (`design/handoff/tokens/tokens.md`).
public enum ThemeAppearance: String, CaseIterable, Hashable, Sendable {
    /// A light appearance: Light and Catppuccin Latte (tokens.md).
    case light

    /// A dark appearance: every other theme (tokens.md).
    case dark
}

/// One of the eight chrome themes (`design/handoff/tokens/clove-themes.json`).
///
/// A theme is its queryable identity, its display name, its light or dark appearance and its 21
/// tokens. Photos are never tinted by a theme; only the chrome around them changes (tokens.md).
public enum CloveTheme: String, CaseIterable, Hashable, Identifiable, Sendable {
    /// The system light theme, and the chosen theme before the user picks another (tokens.md).
    case light

    /// The system dark theme.
    case dark

    /// Neutral mid-grey chrome for judging color and exposure (decisions-log, Themes).
    case darkroom

    /// Warm, dim chrome with no blue light (decisions-log, Themes).
    case night

    /// Catppuccin's light palette (decisions-log, Themes).
    case catppuccinLatte = "catppuccin-latte"

    /// Catppuccin's dark palette (decisions-log, Themes).
    case catppuccinMocha = "catppuccin-mocha"

    /// The Nord palette (decisions-log, Themes).
    case nord

    /// The Gruvbox palette (decisions-log, Themes).
    case gruvbox

    /// The stable identity the theme picker and storage use (clove-themes.json `id`).
    public var id: String { rawValue }

    /// The name the theme picker shows (clove-themes.json `name`).
    public var name: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .darkroom: "Darkroom"
        case .night: "Night"
        case .catppuccinLatte: "Catppuccin Latte"
        case .catppuccinMocha: "Catppuccin Mocha"
        case .nord: "Nord"
        case .gruvbox: "Gruvbox"
        }
    }

    /// Whether the theme sets a light or a dark color scheme (tokens.md).
    public var appearance: ThemeAppearance {
        switch self {
        case .light, .catppuccinLatte: .light
        case .dark, .darkroom, .night, .catppuccinMocha, .nord, .gruvbox: .dark
        }
    }

    /// The theme's 21 tokens (clove-themes.json).
    public var tokens: ThemeTokens {
        switch self {
        case .light: .light
        case .dark: .dark
        case .darkroom: .darkroom
        case .night: .night
        case .catppuccinLatte: .catppuccinLatte
        case .catppuccinMocha: .catppuccinMocha
        case .nord: .nord
        case .gruvbox: .gruvbox
        }
    }
}
