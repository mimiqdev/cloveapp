/// The Appearance setting: an independent three-way appearance mode (Light / Dark / System)
/// and a paired theme family (`design/handoff/tokens/tokens.md`).
///
/// Changing mode preserves the selected family, and changing family preserves the selected mode.
/// In System mode, the effective palette follows the actual system appearance within the selected
/// family. Explicit Light and Dark modes ignore system appearance changes.
public struct AppearanceChoice: Hashable, Sendable {
    /// Whether the app forces Light, forces Dark, or follows the device appearance; System by
    /// default.
    public var mode: AppearanceMode

    /// The paired theme family in effect; Default by default.
    public var family: ThemeFamily

    /// Creates an Appearance choice, defaulting to System + Default.
    public init(mode: AppearanceMode = .system, family: ThemeFamily = .default) {
        self.mode = mode
        self.family = family
    }

    /// Resolves whether the app renders in Light or Dark for the given actual system appearance.
    public func resolvedAppearance(inSystemAppearance systemAppearance: ThemeAppearance)
        -> ThemeAppearance
    {
        switch mode {
        case .light: .light
        case .dark: .dark
        case .system: systemAppearance
        }
    }

    /// Resolves the effective palette centrally from mode, family, and actual system appearance.
    public func resolvedTheme(inSystemAppearance systemAppearance: ThemeAppearance) -> CloveTheme {
        family.theme(for: resolvedAppearance(inSystemAppearance: systemAppearance))
    }
}
