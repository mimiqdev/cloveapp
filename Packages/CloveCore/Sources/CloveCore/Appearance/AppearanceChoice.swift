/// The Appearance setting: whether the system light or dark choice picks the theme, and the theme
/// that applies when it does not (`design/handoff/tokens/tokens.md`).
///
/// A chosen theme applies in both appearances, so a dark theme also darkens the app while the
/// system is light. The theme's own appearance then fixes the status bar and the keyboard
/// (tokens.md, `components.md`).
public struct AppearanceChoice: Hashable, Sendable {
    /// Whether the system appearance picks Light or Dark, the launch default (tokens.md).
    public var matchesSystemAppearance: Bool

    /// The theme the user chose; it applies only while ``matchesSystemAppearance`` is false, and
    /// Light is the launch default (tokens.md).
    public var theme: CloveTheme

    /// Creates the choice, matching the system and keeping Light as the chosen theme by default
    /// (tokens.md).
    public init(matchesSystemAppearance: Bool = true, theme: CloveTheme = .light) {
        self.matchesSystemAppearance = matchesSystemAppearance
        self.theme = theme
    }

    /// The theme in effect for a system appearance (tokens.md).
    ///
    /// Matching the system means Light for a light system and Dark for a dark one, whatever theme
    /// was chosen. Otherwise the chosen theme applies, in both appearances.
    public func theme(inSystemAppearance appearance: ThemeAppearance) -> CloveTheme {
        guard matchesSystemAppearance else { return theme }
        return appearance == .light ? .light : .dark
    }
}
