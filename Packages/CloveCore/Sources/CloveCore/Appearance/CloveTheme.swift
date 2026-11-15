/// Whether a resolved palette is a light or a dark appearance.
///
/// It decides the status bar and the keyboard, and the palette selected within a family when
/// ``AppearanceMode/system`` follows the device appearance (`design/handoff/tokens/tokens.md`).
public enum ThemeAppearance: String, CaseIterable, Hashable, Sendable {
    /// A light appearance (tokens.md).
    case light

    /// A dark appearance (tokens.md).
    case dark
}

/// The three-way appearance mode chosen by the user, independent of theme family.
public enum AppearanceMode: String, CaseIterable, Hashable, Identifiable, Sendable {
    /// Always resolve the light palette of the selected theme family.
    case light

    /// Always resolve the dark palette of the selected theme family.
    case dark

    /// Follow the device appearance within the selected theme family.
    case system

    /// Stable identifier for SwiftUI pickers and accessibility.
    public var id: String { rawValue }

    /// Display name shown in Settings and the design gallery.
    public var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }
}

/// One of the six paired theme families selectable in Settings.
///
/// Each family resolves to a paired light palette and dark palette; photos are never tinted.
public enum ThemeFamily: String, CaseIterable, Hashable, Identifiable, Sendable {
    /// Clove's system Light and Dark palettes.
    case `default`

    /// Catppuccin Latte (light) and Catppuccin Mocha (dark).
    case catppuccin

    /// Neutral mid-grey darkroom palettes (Clove-designed light companion and Darkroom).
    case darkroom

    /// Warm, low-blue-light palettes (Clove-designed warm light companion and Night).
    case night

    /// Arctic blue-grey Nord palettes (Clove-designed light companion and Nord).
    case nord

    /// Retro warm Gruvbox palettes (Clove-designed light companion and Gruvbox).
    case gruvbox

    /// Stable identifier used in storage and accessibility identifiers.
    public var id: String { rawValue }

    /// Display name shown under the family tile and in Settings summaries.
    public var name: String {
        switch self {
        case .default: "Default"
        case .catppuccin: "Catppuccin"
        case .darkroom: "Darkroom"
        case .night: "Night"
        case .nord: "Nord"
        case .gruvbox: "Gruvbox"
        }
    }

    /// The family's light palette.
    public var lightTheme: CloveTheme {
        switch self {
        case .default: .light
        case .catppuccin: .catppuccinLatte
        case .darkroom: .darkroomLight
        case .night: .nightLight
        case .nord: .nordLight
        case .gruvbox: .gruvboxLight
        }
    }

    /// The family's dark palette.
    public var darkTheme: CloveTheme {
        switch self {
        case .default: .dark
        case .catppuccin: .catppuccinMocha
        case .darkroom: .darkroom
        case .night: .night
        case .nord: .nord
        case .gruvbox: .gruvbox
        }
    }

    /// The resolved palette of this family for a given Light or Dark appearance.
    public func theme(for appearance: ThemeAppearance) -> CloveTheme {
        switch appearance {
        case .light: lightTheme
        case .dark: darkTheme
        }
    }
}

/// One of the twelve resolved chrome palettes (`design/handoff/tokens/clove-themes.json`).
///
/// Six paired ``ThemeFamily`` choices resolve to twelve palettes (light and dark for each family).
/// Photos are never tinted by a palette; only the chrome around them changes (tokens.md).
public enum CloveTheme: String, CaseIterable, Hashable, Identifiable, Sendable {
    /// Default light palette (tokens.md).
    case light

    /// Default dark palette.
    case dark

    /// Catppuccin's light palette (decisions-log, Themes).
    case catppuccinLatte = "catppuccin-latte"

    /// Catppuccin's dark palette (decisions-log, Themes).
    case catppuccinMocha = "catppuccin-mocha"

    /// Clove-designed light companion for Darkroom.
    case darkroomLight = "darkroom-light"

    /// Neutral mid-grey chrome for judging color and exposure (decisions-log, Themes).
    case darkroom

    /// Clove-designed warm light companion for Night.
    case nightLight = "night-light"

    /// Warm, dim chrome with no blue light (decisions-log, Themes).
    case night

    /// Clove-designed light companion for Nord.
    case nordLight = "nord-light"

    /// The Nord palette (decisions-log, Themes).
    case nord

    /// Clove-designed light companion for Gruvbox.
    case gruvboxLight = "gruvbox-light"

    /// The Gruvbox palette (decisions-log, Themes).
    case gruvbox

    /// The stable identity used in `clove-themes.json` and legacy settings migration.
    public var id: String { rawValue }

    /// The palette's display name (`clove-themes.json` `name`).
    public var name: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .catppuccinLatte: "Catppuccin Latte"
        case .catppuccinMocha: "Catppuccin Mocha"
        case .darkroomLight: "Darkroom Light"
        case .darkroom: "Darkroom"
        case .nightLight: "Night Light"
        case .night: "Night"
        case .nordLight: "Nord Light"
        case .nord: "Nord"
        case .gruvboxLight: "Gruvbox Light"
        case .gruvbox: "Gruvbox"
        }
    }

    /// The paired theme family this palette belongs to.
    public var family: ThemeFamily {
        switch self {
        case .light, .dark: .default
        case .catppuccinLatte, .catppuccinMocha: .catppuccin
        case .darkroomLight, .darkroom: .darkroom
        case .nightLight, .night: .night
        case .nordLight, .nord: .nord
        case .gruvboxLight, .gruvbox: .gruvbox
        }
    }

    /// Whether the palette sets a light or a dark color scheme (tokens.md).
    public var appearance: ThemeAppearance {
        switch self {
        case .light, .catppuccinLatte, .darkroomLight, .nightLight, .nordLight, .gruvboxLight:
            .light
        case .dark, .catppuccinMocha, .darkroom, .night, .nord, .gruvbox:
            .dark
        }
    }

    /// The palette's 23 tokens (`clove-themes.json`).
    public var tokens: ThemeTokens {
        switch self {
        case .light: .light
        case .dark: .dark
        case .catppuccinLatte: .catppuccinLatte
        case .catppuccinMocha: .catppuccinMocha
        case .darkroomLight: .darkroomLight
        case .darkroom: .darkroom
        case .nightLight: .nightLight
        case .night: .night
        case .nordLight: .nordLight
        case .nord: .nord
        case .gruvboxLight: .gruvboxLight
        case .gruvbox: .gruvbox
        }
    }
}
