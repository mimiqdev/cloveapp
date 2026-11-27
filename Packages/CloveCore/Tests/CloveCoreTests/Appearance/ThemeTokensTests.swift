import Foundation
import Testing

import CloveCore

/// Verifies self-contained invariants on Clove's built-in theme palettes and tokens.
@Suite("Theme tokens")
struct ThemeTokensTests {
    /// Tokens whose surfaces or inks are opaque across every palette.
    private static let opaqueTokens: [ThemeToken] = [
        .canvas,
        .stage,
        .sheet,
        .card,
        .primaryText,
        .accent,
        .ratingOn,
        .reject,
        .saved,
        .failed,
        .labelRed,
        .labelYellow,
        .labelGreen,
        .labelBlue,
        .labelPurple,
        .group,
        .focusOutline,
    ]

    /// Tokens that always carry translucency across every palette.
    private static let translucentTokens: [ThemeToken] = [
        .glass,
        .separator,
        .ratingOff,
        .focusEdge,
    ]

    /// All 12 palettes have complete, non-empty, unique identities and resolve all 23 tokens.
    @Test func allTwelveThemesAreCompleteDistinctAndResolveTwentyThreeTokens() {
        #expect(ThemeFamily.allCases.count == 6)
        #expect(CloveTheme.allCases.count == 12)
        #expect(ThemeToken.allCases.count == 22)

        let themeIDs = CloveTheme.allCases.map(\.id)
        let themeNames = CloveTheme.allCases.map(\.name)
        let rawTokens = ThemeToken.allCases.map(\.rawValue)

        #expect(Set(themeIDs).count == 12)
        #expect(Set(themeNames).count == 12)
        #expect(Set(rawTokens).count == 22)
        #expect(Set(CloveTheme.allCases.map(\.tokens)).count == 12)

        for token in ThemeToken.allCases {
            #expect(!token.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        for theme in CloveTheme.allCases {
            #expect(!theme.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(theme.id == theme.rawValue)
            #expect(!theme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            let tokens = theme.tokens
            let resolved = ThemeToken.allCases.map { tokens[$0] }
            #expect(resolved.count == 22)

            #expect(tokens[.canvas] == tokens.canvas)
            #expect(tokens[.stage] == tokens.stage)
            #expect(tokens[.glass] == tokens.glass)
            #expect(tokens[.sheet] == tokens.sheet)
            #expect(tokens[.card] == tokens.card)
            #expect(tokens[.primaryText] == tokens.primaryText)
            #expect(tokens[.secondaryText] == tokens.secondaryText)
            #expect(tokens[.separator] == tokens.separator)
            #expect(tokens[.accent] == tokens.accent)
            #expect(tokens[.ratingOn] == tokens.ratingOn)
            #expect(tokens[.ratingOff] == tokens.ratingOff)
            #expect(tokens[.reject] == tokens.reject)
            #expect(tokens[.saved] == tokens.saved)
            #expect(tokens[.failed] == tokens.failed)
            #expect(tokens[.labelRed] == tokens.labelRed)
            #expect(tokens[.labelYellow] == tokens.labelYellow)
            #expect(tokens[.labelGreen] == tokens.labelGreen)
            #expect(tokens[.labelBlue] == tokens.labelBlue)
            #expect(tokens[.labelPurple] == tokens.labelPurple)
            #expect(tokens[.group] == tokens.group)
            #expect(tokens[.focusOutline] == tokens.focusOutline)
            #expect(tokens[.focusEdge] == tokens.focusEdge)
        }
    }

    /// Every color token stays finite inside [0, 1], with valid alpha on opaque and translucent
    /// roles.
    @Test func everyColorTokenStaysFiniteInsideUnitBoundsWithValidAlpha() {
        let accounted = Set(Self.opaqueTokens)
            .union(Self.translucentTokens)
            .union([.secondaryText])
        #expect(accounted == Set(ThemeToken.allCases))

        for theme in CloveTheme.allCases {
            for token in ThemeToken.allCases {
                let colour = theme.tokens[token]
                for component in [colour.red, colour.green, colour.blue, colour.alpha] {
                    #expect(component.isFinite, "\(theme.id) \(token.rawValue)")
                    #expect((0...1).contains(component), "\(theme.id) \(token.rawValue)")
                }
            }

            for token in Self.opaqueTokens {
                #expect(
                    theme.tokens[token].alpha == 1,
                    "\(theme.id) \(token.rawValue) should be opaque")
            }

            for token in Self.translucentTokens {
                let alpha = theme.tokens[token].alpha
                #expect(
                    alpha > 0 && alpha < 1,
                    "\(theme.id) \(token.rawValue) should be translucent")
            }

            let secondaryAlpha = theme.tokens[.secondaryText].alpha
            #expect(
                secondaryAlpha > 0 && secondaryAlpha <= 1,
                "\(theme.id) text/secondary should be visible")
        }
    }

    /// Rejected photo opacity stays finite in (0, 1) and within the expected dimmed range.
    @Test func rejectedOpacityStaysInExpectedDimmedRange() {
        for theme in CloveTheme.allCases {
            let opacity = theme.tokens.rejectedOpacity
            #expect(opacity.isFinite, "\(theme.id)")
            #expect(opacity > 0 && opacity < 1, "\(theme.id)")
            #expect((0.2...0.5).contains(opacity), "\(theme.id) opacity=\(opacity)")
        }
    }

    /// Paired Light/Dark families resolve cleanly and distinctly across System, Light, and Dark
    /// modes.
    @Test func pairedFamiliesResolveCleanlyAndDistinctlyAcrossAppearanceModes() {
        #expect(ThemeFamily.allCases.count == 6)
        #expect(Set(ThemeFamily.allCases.map(\.id)).count == 6)
        #expect(Set(ThemeFamily.allCases.map(\.name)).count == 6)

        var resolvedLightThemes: [CloveTheme] = []
        var resolvedDarkThemes: [CloveTheme] = []

        for family in ThemeFamily.allCases {
            #expect(!family.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!family.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            let lightChoice = AppearanceChoice(mode: .light, family: family)
            let darkChoice = AppearanceChoice(mode: .dark, family: family)
            let systemChoice = AppearanceChoice(mode: .system, family: family)

            let lightTheme = family.lightTheme
            let darkTheme = family.darkTheme
            #expect(lightTheme != darkTheme)
            #expect(lightTheme.family == family)
            #expect(darkTheme.family == family)
            #expect(lightTheme.appearance == .light)
            #expect(darkTheme.appearance == .dark)

            #expect(
                Self.luminance(of: lightTheme.tokens.canvas)
                    > Self.luminance(of: darkTheme.tokens.canvas),
                "\(family.id) light canvas should exceed dark canvas luminance")

            #expect(lightChoice.resolvedTheme(inSystemAppearance: .light) == lightTheme)
            #expect(lightChoice.resolvedTheme(inSystemAppearance: .dark) == lightTheme)
            #expect(darkChoice.resolvedTheme(inSystemAppearance: .light) == darkTheme)
            #expect(darkChoice.resolvedTheme(inSystemAppearance: .dark) == darkTheme)
            #expect(systemChoice.resolvedTheme(inSystemAppearance: .light) == lightTheme)
            #expect(systemChoice.resolvedTheme(inSystemAppearance: .dark) == darkTheme)

            resolvedLightThemes.append(lightTheme)
            resolvedDarkThemes.append(darkTheme)
        }

        #expect(Set(resolvedLightThemes).count == 6)
        #expect(Set(resolvedDarkThemes).count == 6)
        #expect(Set(resolvedLightThemes).isDisjoint(with: Set(resolvedDarkThemes)))
    }

    /// `ThemeColour(hex:alpha:)` decodes `#RRGGBB` bytes and preserves explicit alpha cleanly.
    @Test func themeColourHexInitializerExtractsRGBAComponents() {
        let black = ThemeColour(hex: 0x000000)
        #expect(black == ThemeColour(red: 0, green: 0, blue: 0, alpha: 1))

        let white = ThemeColour(hex: 0xFFFFFF)
        #expect(white == ThemeColour(red: 1, green: 1, blue: 1, alpha: 1))

        let mutedSlate = ThemeColour(hex: 0x3C3C43, alpha: 153.0 / 255)
        #expect(mutedSlate.red == 0x3C / 255.0)
        #expect(mutedSlate.green == 0x3C / 255.0)
        #expect(mutedSlate.blue == 0x43 / 255.0)
        #expect(mutedSlate.alpha == 153.0 / 255.0)

        let masked = ThemeColour(hex: 0xFF123456, alpha: 0.5)
        #expect(masked == ThemeColour(hex: 0x123456, alpha: 0.5))
    }

    private static func luminance(of colour: ThemeColour) -> Double {
        0.2126 * colour.red + 0.7152 * colour.green + 0.0722 * colour.blue
    }
}
