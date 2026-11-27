/// One theme colour, as sRGB components from 0 to 1.
///
/// Palettes define each colour using a `#RRGGBB` hex value and optional `alpha`, keeping `alpha`
/// separate so a token's own transparency is never confused with a layer's opacity.
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
    /// Pass any translucent alpha byte as `alpha / 255`, or leave it out for an opaque token.
    public init(hex: UInt32, alpha: Double = 1) {
        self.red = Double((hex >> 16) & 0xFF) / 255
        self.green = Double((hex >> 8) & 0xFF) / 255
        self.blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }
}
