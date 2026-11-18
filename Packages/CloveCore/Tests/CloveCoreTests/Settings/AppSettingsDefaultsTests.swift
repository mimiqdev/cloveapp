import Testing

import CloveCore

@Test func launchDefaultsMatchThePRD() {
    let settings = AppSettings()
    #expect(settings.gesturesEnabled)
    #expect(settings.enabledRatings == EnabledRatings.all)
    #expect(settings.autoAdvance.destination == .nextPhoto)
    #expect(settings.autoAdvance.triggers.rating)
    #expect(settings.autoAdvance.triggers.reject)
    #expect(!settings.autoAdvance.triggers.colourLabel)
    #expect(settings.doubleTap == .zoomToFocus)
    #expect(settings.zoomedGestures == .rateAndSwitch)
    #expect(!settings.extendedColourLabelsEnabled)
    #expect(settings.rejectsFolderName == .defaultFolderName)
    #expect(settings.rejectsFolderName.rawValue == "_Rejected")
    #expect(settings.moveRejectsEnabled)
    #expect(settings.similarGroupsEnabled)
    #expect(settings.appearance == AppearanceChoice())
    #expect(settings.appearance.mode == .system)
    #expect(settings.appearance.family == .default)
    #expect(settings.appearance.resolvedTheme(inSystemAppearance: .light) == .light)
    #expect(settings.appearance.resolvedTheme(inSystemAppearance: .dark) == .dark)
    #expect(settings.language == .system)
}

@Test func settingChoicesAreTheLaunchChoices() {
    #expect(MarkKind.allCases == [.rating, .reject, .colourLabel])
    #expect(AutoAdvanceDestination.allCases == [.stay, .nextPhoto, .nextUnmarkedPhoto])
    #expect(DoubleTapBehaviour.allCases == [.zoomToFocus, .zoomToTapPoint, .off])
    #expect(ZoomedGestures.allCases == [.rateAndSwitch, .pan])
    #expect(AppearanceMode.allCases == [.light, .dark, .system])
    #expect(ThemeFamily.allCases == [.default, .catppuccin, .darkroom, .night, .nord, .gruvbox])
    #expect(CloveTheme.allCases.first == .light)
    #expect(CloveTheme.allCases.count == 12)
    #expect(ThemeAppearance.allCases == [.light, .dark])
    #expect(
        AppLanguage.allCases == [.system, .english, .simplifiedChinese, .traditionalChinese])
    #expect(
        ResolvedAppLanguage.allCases == [.english, .simplifiedChinese, .traditionalChinese])
}

@Test func labelsOfferedFollowExtendedColours() {
    #expect(AppSettings().availableLabels == [.red, .yellow, .green, .blue, .purple])

    var settings = AppSettings()
    settings.extendedColourLabelsEnabled = true
    #expect(settings.availableLabels == LabelColour.allCases)
    #expect(Array(settings.availableLabels.suffix(2)) == [.orange, .pink])
}

@Test func settingsAreSendableValues() {
    requireSendable(AppSettings.self)
    requireSendable(ZoomedGestures.self)
    requireSendable(EnabledRatings.self)
    requireSendable(AutoAdvance.self)
    requireSendable(AutoAdvanceTriggers.self)
    requireSendable(RejectsFolderName.self)
    requireSendable(AppearanceChoice.self)
    requireSendable(AppLanguage.self)
    requireSendable(ResolvedAppLanguage.self)
    requireSendable(SettingsPersistence.self)
    requireSendable(UserDefaultsSettingsStorage.self)
}

private func requireSendable<Value: Sendable>(_: Value.Type) {}
