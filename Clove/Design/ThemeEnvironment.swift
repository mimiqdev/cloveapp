import CloveCore
import SwiftUI

/// The theme in effect, for every view below the one that sets it
/// (`design/handoff/tokens/tokens.md`).
///
/// `RootView` writes the value once, works it out from the Appearance setting and the system
/// appearance, and the tokens, the glass and the controls read it from there. A view that draws a
/// different theme on purpose, such as a theme tile, uses that theme's tokens directly.
private struct CloveThemeKey: EnvironmentKey {
    static let defaultValue = CloveTheme.light
}

extension EnvironmentValues {
    /// The theme in effect for this view and everything below it (tokens.md).
    var cloveTheme: CloveTheme {
        get { self[CloveThemeKey.self] }
        set { self[CloveThemeKey.self] = newValue }
    }
}

extension ThemeColour {
    /// The SwiftUI colour for the token's sRGB components (tokens.md).
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension ThemeAppearance {
    /// The color scheme the theme sets, so the status bar and the keyboard match it (tokens.md).
    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}
