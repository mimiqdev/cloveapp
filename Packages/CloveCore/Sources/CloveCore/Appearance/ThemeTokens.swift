/// One of the 21 tokens the themes share, named as `design/handoff/tokens/clove-themes.json`
/// names it.
///
/// The colour tokens are the 20 `Color.clove.*` values the chrome uses; `opacity/rejected` is a
/// number and stays on ``ThemeTokens/rejectedOpacity``. A token added to the JSON needs a case
/// here, and the switch in ``ThemeTokens/subscript(_:)`` then fails to compile until the eight
/// palettes carry it.
public enum ThemeToken: String, CaseIterable, Hashable, Sendable {
    /// App background behind lists, grids and chrome.
    case canvas = "bg/canvas"

    /// The area around a photo in detail and zoom; never tints the photo.
    case stage = "bg/stage"

    /// Floating glass controls, paired with a background blur of about 36.
    case glass = "surface/glass"

    /// Sheets, menus and the grouped-list background.
    case sheet = "surface/sheet"

    /// Cells and cards on a sheet.
    case card = "surface/card"

    /// Primary text and icons.
    case primaryText = "text/primary"

    /// Secondary text, counts and metadata.
    case secondaryText = "text/secondary"

    /// Hairlines and tracks.
    case separator = "separator"

    /// Buttons, links, selection and progress while reading.
    case accent = "accent"

    /// Filled stars.
    case ratingOn = "rating/on"

    /// Empty stars.
    case ratingOff = "rating/off"

    /// The Reject circle and destructive text, deliberately softer than the system red.
    case reject = "reject"

    /// The saved dot and toggles that are on.
    case saved = "status/saved"

    /// Save and move failures.
    case failed = "status/failed"

    /// Color label red, the XMP `Red` value.
    case labelRed = "label/red"

    /// Color label yellow.
    case labelYellow = "label/yellow"

    /// Color label green.
    case labelGreen = "label/green"

    /// Color label blue.
    case labelBlue = "label/blue"

    /// Color label purple.
    case labelPurple = "label/purple"

    /// Similar groups: the count badge and the tint behind an expanded group.
    case group = "group"
}

/// The 20 colour tokens and the rejected-photo opacity of one theme.
///
/// Values come from `design/handoff/tokens/clove-themes.json`, the file a test reads and compares
/// token by token. The eight palettes live on this type; ``CloveTheme/tokens`` picks the one a
/// theme uses.
public struct ThemeTokens: Hashable, Sendable {
    /// See `bg/canvas`.
    public var canvas: ThemeColour
    /// See `bg/stage`.
    public var stage: ThemeColour
    /// See `surface/glass`.
    public var glass: ThemeColour
    /// See `surface/sheet`.
    public var sheet: ThemeColour
    /// See `surface/card`.
    public var card: ThemeColour
    /// See `text/primary`.
    public var primaryText: ThemeColour
    /// See `text/secondary`.
    public var secondaryText: ThemeColour
    /// See `separator`.
    public var separator: ThemeColour
    /// See `accent`.
    public var accent: ThemeColour
    /// See `rating/on`.
    public var ratingOn: ThemeColour
    /// See `rating/off`.
    public var ratingOff: ThemeColour
    /// See `reject`.
    public var reject: ThemeColour
    /// See `status/saved`.
    public var saved: ThemeColour
    /// See `status/failed`.
    public var failed: ThemeColour
    /// See `label/red`.
    public var labelRed: ThemeColour
    /// See `label/yellow`.
    public var labelYellow: ThemeColour
    /// See `label/green`.
    public var labelGreen: ThemeColour
    /// See `label/blue`.
    public var labelBlue: ThemeColour
    /// See `label/purple`.
    public var labelPurple: ThemeColour
    /// See `group`.
    public var group: ThemeColour

    /// `opacity/rejected`: the opacity of a rejected photo in the grid and strips.
    public var rejectedOpacity: Double

    /// The colour of one token, for code that walks ``ThemeToken/allCases`` (tokens.md).
    public subscript(token: ThemeToken) -> ThemeColour {
        switch token {
        case .canvas: canvas
        case .stage: stage
        case .glass: glass
        case .sheet: sheet
        case .card: card
        case .primaryText: primaryText
        case .secondaryText: secondaryText
        case .separator: separator
        case .accent: accent
        case .ratingOn: ratingOn
        case .ratingOff: ratingOff
        case .reject: reject
        case .saved: saved
        case .failed: failed
        case .labelRed: labelRed
        case .labelYellow: labelYellow
        case .labelGreen: labelGreen
        case .labelBlue: labelBlue
        case .labelPurple: labelPurple
        case .group: group
        }
    }
}

// MARK: - The eight palettes

extension ThemeTokens {
    /// Light: the system light default (clove-themes.json).
    static let light = ThemeTokens(
        canvas: ThemeColour(hex: 0xFFFFFF),
        stage: ThemeColour(hex: 0xE6E6EB),
        glass: ThemeColour(hex: 0xFFFFFF, alpha: 204.0 / 255),
        sheet: ThemeColour(hex: 0xF2F2F7),
        card: ThemeColour(hex: 0xFFFFFF),
        primaryText: ThemeColour(hex: 0x000000),
        secondaryText: ThemeColour(hex: 0x3C3C43, alpha: 153.0 / 255),
        separator: ThemeColour(hex: 0x3C3C43, alpha: 31.0 / 255),
        accent: ThemeColour(hex: 0x007AFF),
        ratingOn: ThemeColour(hex: 0xFF9500),
        ratingOff: ThemeColour(hex: 0x3C3C43, alpha: 77.0 / 255),
        reject: ThemeColour(hex: 0xD4574E),
        saved: ThemeColour(hex: 0x34C759),
        failed: ThemeColour(hex: 0xD4574E),
        labelRed: ThemeColour(hex: 0xFF3B30),
        labelYellow: ThemeColour(hex: 0xFFCC00),
        labelGreen: ThemeColour(hex: 0x34C759),
        labelBlue: ThemeColour(hex: 0x007AFF),
        labelPurple: ThemeColour(hex: 0xAF52DE),
        group: ThemeColour(hex: 0x007AFF),
        rejectedOpacity: 0.28
    )

    /// Dark: the system dark default (clove-themes.json).
    static let dark = ThemeTokens(
        canvas: ThemeColour(hex: 0x000000),
        stage: ThemeColour(hex: 0x000000),
        glass: ThemeColour(hex: 0x1E1E20, alpha: 184.0 / 255),
        sheet: ThemeColour(hex: 0x1C1C1E),
        card: ThemeColour(hex: 0x2C2C2E),
        primaryText: ThemeColour(hex: 0xFFFFFF),
        secondaryText: ThemeColour(hex: 0xEBEBF5, alpha: 153.0 / 255),
        separator: ThemeColour(hex: 0xFFFFFF, alpha: 31.0 / 255),
        accent: ThemeColour(hex: 0x0A84FF),
        ratingOn: ThemeColour(hex: 0xFF9F0A),
        ratingOff: ThemeColour(hex: 0xEBEBF5, alpha: 77.0 / 255),
        reject: ThemeColour(hex: 0xE5675E),
        saved: ThemeColour(hex: 0x30D158),
        failed: ThemeColour(hex: 0xE5675E),
        labelRed: ThemeColour(hex: 0xFF453A),
        labelYellow: ThemeColour(hex: 0xFFD60A),
        labelGreen: ThemeColour(hex: 0x30D158),
        labelBlue: ThemeColour(hex: 0x0A84FF),
        labelPurple: ThemeColour(hex: 0xBF5AF2),
        group: ThemeColour(hex: 0x0A84FF),
        rejectedOpacity: 0.3
    )

    /// Darkroom: a neutral mid-grey stage and muted accents for judging color and exposure
    /// (clove-themes.json).
    static let darkroom = ThemeTokens(
        canvas: ThemeColour(hex: 0x1E1E1E),
        stage: ThemeColour(hex: 0x474747),
        glass: ThemeColour(hex: 0x2E2E2E, alpha: 209.0 / 255),
        sheet: ThemeColour(hex: 0x262626),
        card: ThemeColour(hex: 0x333333),
        primaryText: ThemeColour(hex: 0xEDEDED),
        secondaryText: ThemeColour(hex: 0xBDBDBD),
        separator: ThemeColour(hex: 0xFFFFFF, alpha: 26.0 / 255),
        accent: ThemeColour(hex: 0x8AB4F8),
        ratingOn: ThemeColour(hex: 0xE8A33D),
        ratingOff: ThemeColour(hex: 0xFFFFFF, alpha: 64.0 / 255),
        reject: ThemeColour(hex: 0xC7665F),
        saved: ThemeColour(hex: 0x4CB86A),
        failed: ThemeColour(hex: 0xC7665F),
        labelRed: ThemeColour(hex: 0xE5534B),
        labelYellow: ThemeColour(hex: 0xE0C04A),
        labelGreen: ThemeColour(hex: 0x4CB86A),
        labelBlue: ThemeColour(hex: 0x5A8FD8),
        labelPurple: ThemeColour(hex: 0xA374C9),
        group: ThemeColour(hex: 0x8AB4F8),
        rejectedOpacity: 0.35
    )

    /// Night: warm, dim chrome with no blue light (clove-themes.json).
    static let night = ThemeTokens(
        canvas: ThemeColour(hex: 0x0C0908),
        stage: ThemeColour(hex: 0x000000),
        glass: ThemeColour(hex: 0x1C1614, alpha: 217.0 / 255),
        sheet: ThemeColour(hex: 0x141010),
        card: ThemeColour(hex: 0x1E1816),
        primaryText: ThemeColour(hex: 0xE6C9B8),
        secondaryText: ThemeColour(hex: 0x9C8576),
        separator: ThemeColour(hex: 0xE6C9B8, alpha: 26.0 / 255),
        accent: ThemeColour(hex: 0xE0A15E),
        ratingOn: ThemeColour(hex: 0xE0A15E),
        ratingOff: ThemeColour(hex: 0xE6C9B8, alpha: 56.0 / 255),
        reject: ThemeColour(hex: 0xC8665A),
        saved: ThemeColour(hex: 0x8FA36A),
        failed: ThemeColour(hex: 0xC8665A),
        labelRed: ThemeColour(hex: 0xB85A4E),
        labelYellow: ThemeColour(hex: 0xC9A24A),
        labelGreen: ThemeColour(hex: 0x7F9A5A),
        labelBlue: ThemeColour(hex: 0x6F86A8),
        labelPurple: ThemeColour(hex: 0x9A7AA8),
        group: ThemeColour(hex: 0xE0A15E),
        rejectedOpacity: 0.3
    )

    /// Catppuccin Latte: the light editor palette (clove-themes.json).
    static let catppuccinLatte = ThemeTokens(
        canvas: ThemeColour(hex: 0xEFF1F5),
        stage: ThemeColour(hex: 0xDCE0E8),
        glass: ThemeColour(hex: 0xEFF1F5, alpha: 204.0 / 255),
        sheet: ThemeColour(hex: 0xE6E9EF),
        card: ThemeColour(hex: 0xEFF1F5),
        primaryText: ThemeColour(hex: 0x4C4F69),
        secondaryText: ThemeColour(hex: 0x6C6F85),
        separator: ThemeColour(hex: 0x4C4F69, alpha: 31.0 / 255),
        accent: ThemeColour(hex: 0x8839EF),
        ratingOn: ThemeColour(hex: 0xDF8E1D),
        ratingOff: ThemeColour(hex: 0x4C4F69, alpha: 64.0 / 255),
        reject: ThemeColour(hex: 0xE64553),
        saved: ThemeColour(hex: 0x40A02B),
        failed: ThemeColour(hex: 0xE64553),
        labelRed: ThemeColour(hex: 0xD20F39),
        labelYellow: ThemeColour(hex: 0xDF8E1D),
        labelGreen: ThemeColour(hex: 0x40A02B),
        labelBlue: ThemeColour(hex: 0x1E66F5),
        labelPurple: ThemeColour(hex: 0x8839EF),
        group: ThemeColour(hex: 0x8839EF),
        rejectedOpacity: 0.28
    )

    /// Catppuccin Mocha: the dark editor palette (clove-themes.json).
    static let catppuccinMocha = ThemeTokens(
        canvas: ThemeColour(hex: 0x1E1E2E),
        stage: ThemeColour(hex: 0x11111B),
        glass: ThemeColour(hex: 0x313244, alpha: 217.0 / 255),
        sheet: ThemeColour(hex: 0x181825),
        card: ThemeColour(hex: 0x313244),
        primaryText: ThemeColour(hex: 0xCDD6F4),
        secondaryText: ThemeColour(hex: 0xA6ADC8),
        separator: ThemeColour(hex: 0xCDD6F4, alpha: 26.0 / 255),
        accent: ThemeColour(hex: 0xCBA6F7),
        ratingOn: ThemeColour(hex: 0xF9E2AF),
        ratingOff: ThemeColour(hex: 0xCDD6F4, alpha: 56.0 / 255),
        reject: ThemeColour(hex: 0xEBA0AC),
        saved: ThemeColour(hex: 0xA6E3A1),
        failed: ThemeColour(hex: 0xEBA0AC),
        labelRed: ThemeColour(hex: 0xF38BA8),
        labelYellow: ThemeColour(hex: 0xF9E2AF),
        labelGreen: ThemeColour(hex: 0xA6E3A1),
        labelBlue: ThemeColour(hex: 0x89B4FA),
        labelPurple: ThemeColour(hex: 0xCBA6F7),
        group: ThemeColour(hex: 0xCBA6F7),
        rejectedOpacity: 0.3
    )

    /// Nord: the arctic blue-grey editor palette (clove-themes.json).
    static let nord = ThemeTokens(
        canvas: ThemeColour(hex: 0x2E3440),
        stage: ThemeColour(hex: 0x242933),
        glass: ThemeColour(hex: 0x3B4252, alpha: 217.0 / 255),
        sheet: ThemeColour(hex: 0x2E3440),
        card: ThemeColour(hex: 0x3B4252),
        primaryText: ThemeColour(hex: 0xECEFF4),
        secondaryText: ThemeColour(hex: 0xD8DEE9, alpha: 153.0 / 255),
        separator: ThemeColour(hex: 0xECEFF4, alpha: 26.0 / 255),
        accent: ThemeColour(hex: 0x88C0D0),
        ratingOn: ThemeColour(hex: 0xEBCB8B),
        ratingOff: ThemeColour(hex: 0xD8DEE9, alpha: 64.0 / 255),
        reject: ThemeColour(hex: 0xBF616A),
        saved: ThemeColour(hex: 0xA3BE8C),
        failed: ThemeColour(hex: 0xBF616A),
        labelRed: ThemeColour(hex: 0xBF616A),
        labelYellow: ThemeColour(hex: 0xEBCB8B),
        labelGreen: ThemeColour(hex: 0xA3BE8C),
        labelBlue: ThemeColour(hex: 0x81A1C1),
        labelPurple: ThemeColour(hex: 0xB48EAD),
        group: ThemeColour(hex: 0x88C0D0),
        rejectedOpacity: 0.3
    )

    /// Gruvbox: the retro warm editor palette (clove-themes.json).
    static let gruvbox = ThemeTokens(
        canvas: ThemeColour(hex: 0x282828),
        stage: ThemeColour(hex: 0x1D2021),
        glass: ThemeColour(hex: 0x3C3836, alpha: 217.0 / 255),
        sheet: ThemeColour(hex: 0x282828),
        card: ThemeColour(hex: 0x3C3836),
        primaryText: ThemeColour(hex: 0xEBDBB2),
        secondaryText: ThemeColour(hex: 0xA89984),
        separator: ThemeColour(hex: 0xEBDBB2, alpha: 26.0 / 255),
        accent: ThemeColour(hex: 0x83A598),
        ratingOn: ThemeColour(hex: 0xFABD2F),
        ratingOff: ThemeColour(hex: 0xEBDBB2, alpha: 56.0 / 255),
        reject: ThemeColour(hex: 0xEA6962),
        saved: ThemeColour(hex: 0xB8BB26),
        failed: ThemeColour(hex: 0xEA6962),
        labelRed: ThemeColour(hex: 0xFB4934),
        labelYellow: ThemeColour(hex: 0xFABD2F),
        labelGreen: ThemeColour(hex: 0xB8BB26),
        labelBlue: ThemeColour(hex: 0x83A598),
        labelPurple: ThemeColour(hex: 0xD3869B),
        group: ThemeColour(hex: 0x83A598),
        rejectedOpacity: 0.3
    )
}
