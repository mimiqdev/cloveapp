/// One theme colour, as sRGB components from 0 to 1.
///
/// `design/handoff/tokens/clove-themes.json` writes each token as `#RRGGBB` or `#RRGGBBAA`,
/// with alpha last, and `design/handoff/tokens/tokens.md` names the same values. ``init(hex:)``
/// keeps the palette declarations readable next to that file, and `alpha` stays separate so a
/// token's own transparency is never confused with a layer's opacity.
public struct ThemeColour: Hashable, Sendable {
    /// The red component, 0 to 1.
    public var red: Double

    /// The green component, 0 to 1.
    public var green: Double

    /// The blue component, 0 to 1.
    public var blue: Double

    /// The alpha component, 0 to 1; a token without an alpha byte is fully opaque.
    public var alpha: Double

    /// Creates a colour from its components, each 0 to 1 (tokens.md).
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Creates a colour from its `0xRRGGBB` form and a separate alpha.
    ///
    /// The hex spelling matches `clove-themes.json`, which puts alpha in a fourth byte; pass
    /// that byte as `alpha / 255`, or leave it out for an opaque token.
    public init(hex: UInt32, alpha: Double = 1) {
        self.red = Double((hex >> 16) & 0xFF) / 255
        self.green = Double((hex >> 8) & 0xFF) / 255
        self.blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }
}
