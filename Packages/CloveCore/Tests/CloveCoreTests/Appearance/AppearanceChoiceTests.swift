import Testing

import CloveCore

/// Checks the Appearance setting's resolution matrix and independent mode/family state
/// (`tokens.md`).
@Suite("Appearance setting")
struct AppearanceChoiceTests {
    /// Launch defaults select System + Default.
    @Test func defaultsToSystemAndDefaultFamily() {
        let choice = AppearanceChoice()
        #expect(choice.mode == .system)
        #expect(choice.family == .default)
        #expect(choice.resolvedAppearance(inSystemAppearance: .light) == .light)
        #expect(choice.resolvedAppearance(inSystemAppearance: .dark) == .dark)
        #expect(choice.resolvedTheme(inSystemAppearance: .light) == .light)
        #expect(choice.resolvedTheme(inSystemAppearance: .dark) == .dark)
    }

    /// Complete 3 × 6 × 2 resolution matrix across modes, families, and system appearances.
    @Test func fullResolutionMatrixAcrossModesFamiliesAndSystemAppearances() {
        let expectedPairs: [ThemeFamily: (light: CloveTheme, dark: CloveTheme)] = [
            .default: (.light, .dark),
            .catppuccin: (.catppuccinLatte, .catppuccinMocha),
            .darkroom: (.darkroomLight, .darkroom),
            .night: (.nightLight, .night),
            .nord: (.nordLight, .nord),
            .gruvbox: (.gruvboxLight, .gruvbox),
        ]

        #expect(AppearanceMode.allCases.count == 3)
        #expect(ThemeFamily.allCases.count == 6)
        #expect(ThemeAppearance.allCases.count == 2)

        for family in ThemeFamily.allCases {
            let pair = expectedPairs[family]!
            #expect(family.lightTheme == pair.light)
            #expect(family.darkTheme == pair.dark)

            for mode in AppearanceMode.allCases {
                for systemAppearance in ThemeAppearance.allCases {
                    let choice = AppearanceChoice(mode: mode, family: family)
                    let expectedAppearance: ThemeAppearance =
                        switch mode {
                        case .light: .light
                        case .dark: .dark
                        case .system: systemAppearance
                        }
                    let expectedTheme =
                        expectedAppearance == .light ? pair.light : pair.dark

                    #expect(
                        choice.resolvedAppearance(inSystemAppearance: systemAppearance)
                            == expectedAppearance,
                        "\(mode) + \(family) in \(systemAppearance)")
                    #expect(
                        choice.resolvedTheme(inSystemAppearance: systemAppearance) == expectedTheme,
                        "\(mode) + \(family) in \(systemAppearance)")
                }
            }
        }
    }

    /// Changing mode preserves family, and changing family preserves mode; System + non-default
    /// family never falls back to Default.
    @Test func changingModeOrFamilyPreservesTheOtherAxis() {
        for initialFamily in ThemeFamily.allCases {
            for nextMode in AppearanceMode.allCases {
                var choice = AppearanceChoice(mode: .system, family: initialFamily)
                choice.mode = nextMode
                #expect(choice.family == initialFamily)
                #expect(choice.mode == nextMode)
            }
        }

        for initialMode in AppearanceMode.allCases {
            for nextFamily in ThemeFamily.allCases {
                var choice = AppearanceChoice(mode: initialMode, family: .default)
                choice.family = nextFamily
                #expect(choice.mode == initialMode)
                #expect(choice.family == nextFamily)
            }
        }

        let systemCatppuccin = AppearanceChoice(mode: .system, family: .catppuccin)
        #expect(systemCatppuccin.resolvedTheme(inSystemAppearance: .light) == .catppuccinLatte)
        #expect(systemCatppuccin.resolvedTheme(inSystemAppearance: .dark) == .catppuccinMocha)
        #expect(systemCatppuccin.family == .catppuccin)
    }

    /// Six families resolve cleanly to twelve distinct palettes (six light, six dark).
    @Test func sixFamiliesResolveToTwelveDistinctPalettes() {
        #expect(ThemeFamily.allCases.count == 6)
        #expect(CloveTheme.allCases.count == 12)
        #expect(Set(CloveTheme.allCases).count == 12)

        let light = CloveTheme.allCases.filter { $0.appearance == .light }
        let dark = CloveTheme.allCases.filter { $0.appearance == .dark }
        #expect(
            light == [
                .light, .catppuccinLatte, .darkroomLight, .nightLight, .nordLight, .gruvboxLight,
            ])
        #expect(dark == [.dark, .catppuccinMocha, .darkroom, .night, .nord, .gruvbox])
        #expect(CloveTheme.catppuccinLatte.id == "catppuccin-latte")
        #expect(CloveTheme.catppuccinMocha.id == "catppuccin-mocha")
        #expect(CloveTheme.darkroomLight.id == "darkroom-light")
        #expect(CloveTheme.nightLight.id == "night-light")
        #expect(CloveTheme.nordLight.id == "nord-light")
        #expect(CloveTheme.gruvboxLight.id == "gruvbox-light")

        for theme in CloveTheme.allCases {
            #expect(theme.family.theme(for: theme.appearance) == theme)
        }
    }

    /// The model types are Sendable values like the rest of C12's settings.
    @Test func appearanceTypesAreSendableValues() {
        requireSendable(AppearanceChoice.self)
        requireSendable(AppearanceMode.self)
        requireSendable(ThemeFamily.self)
        requireSendable(CloveTheme.self)
        requireSendable(ThemeAppearance.self)
        requireSendable(ThemeColour.self)
        requireSendable(ThemeTokens.self)
        requireSendable(ThemeToken.self)
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
