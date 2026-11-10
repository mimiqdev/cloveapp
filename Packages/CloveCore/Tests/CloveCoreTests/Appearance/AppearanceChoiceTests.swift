import Testing

import CloveCore

/// Checks the Appearance setting's rule for the theme in effect (`tokens.md`).
@Suite("Appearance setting")
struct AppearanceChoiceTests {
    /// Matching the system picks Light or Dark, whatever theme was chosen last.
    @Test func matchingTheSystemPicksLightOrDark() {
        var choice = AppearanceChoice()
        #expect(choice.matchesSystemAppearance)
        #expect(choice.theme == .light)
        #expect(choice.theme(inSystemAppearance: .light) == .light)
        #expect(choice.theme(inSystemAppearance: .dark) == .dark)

        choice.theme = .gruvbox
        #expect(choice.theme(inSystemAppearance: .light) == .light)
        #expect(choice.theme(inSystemAppearance: .dark) == .dark)
    }

    /// A chosen theme applies in both appearances when the system does not pick.
    @Test func aChosenThemeAppliesInBothAppearances() {
        for theme in CloveTheme.allCases {
            let choice = AppearanceChoice(matchesSystemAppearance: false, theme: theme)
            #expect(choice.theme(inSystemAppearance: .light) == theme)
            #expect(choice.theme(inSystemAppearance: .dark) == theme)
        }
    }

    /// Choosing Light or Dark while matching the system changes nothing, because the system already
    /// picks between them; choosing any other theme stops matching
    /// (`design/handoff/interactions.md`, Theme switching).
    @Test func choosingATileFollowsTheThemeSwitchingRule() {
        let matching = AppearanceChoice()
        #expect(matching.choosing(.light) == matching)
        #expect(matching.choosing(.dark) == matching)

        for theme in CloveTheme.allCases where theme != .light && theme != .dark {
            let chosen = matching.choosing(theme)
            #expect(!chosen.matchesSystemAppearance)
            #expect(chosen.theme == theme)
        }

        // A theme already chosen stays when Light or Dark is picked while matching is off.
        for theme in CloveTheme.allCases {
            let chosen = AppearanceChoice(matchesSystemAppearance: false, theme: theme)
            for tile in CloveTheme.allCases {
                let next = chosen.choosing(tile)
                #expect(!next.matchesSystemAppearance)
                #expect(next.theme == tile)
            }
        }
    }

    /// Light and Catppuccin Latte are light appearances and the other six are dark (tokens.md).
    @Test func themesAreLightOrDarkAppearances() {
        #expect(CloveTheme.allCases.count == 8)
        let light = CloveTheme.allCases.filter { $0.appearance == .light }
        #expect(light == [.light, .catppuccinLatte])
        #expect(Set(CloveTheme.allCases).count == 8)
        #expect(CloveTheme.catppuccinLatte.id == "catppuccin-latte")
        #expect(CloveTheme.catppuccinMocha.id == "catppuccin-mocha")
    }

    /// The model types are Sendable values like the rest of C12's settings.
    @Test func appearanceTypesAreSendableValues() {
        requireSendable(AppearanceChoice.self)
        requireSendable(CloveTheme.self)
        requireSendable(ThemeAppearance.self)
        requireSendable(ThemeColour.self)
        requireSendable(ThemeTokens.self)
        requireSendable(ThemeToken.self)
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
