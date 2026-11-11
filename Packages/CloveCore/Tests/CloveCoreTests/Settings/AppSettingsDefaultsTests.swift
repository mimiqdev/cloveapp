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
    #expect(settings.doubleTap == .zoom)
    #expect(!settings.keepZoom.inDetail)
    #expect(!settings.extendedColourLabelsEnabled)
    #expect(settings.rejectsFolderName == .defaultFolderName)
    #expect(settings.rejectsFolderName.rawValue == "_Rejected")
    #expect(settings.moveRejectsEnabled)
    #expect(settings.similarGroupsEnabled)
    #expect(settings.gridGroupDisplay == .expanded)
    #expect(settings.appearance == AppearanceChoice())
    #expect(settings.appearance.matchesSystemAppearance)
    #expect(settings.appearance.theme == .light)
    #expect(settings.appearance.theme(inSystemAppearance: .dark) == .dark)
}

@Test func settingChoicesAreTheLaunchChoices() {
    #expect(MarkKind.allCases == [.rating, .reject, .colourLabel])
    #expect(AutoAdvanceDestination.allCases == [.stay, .nextPhoto, .nextUnmarkedPhoto])
    #expect(DoubleTapBehaviour.allCases == [.zoom, .off])
    #expect(GridGroupDisplay.allCases == [.expanded, .collapsed])
    #expect(CloveTheme.allCases.first == .light)
    #expect(ThemeAppearance.allCases == [.light, .dark])
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
    requireSendable(EnabledRatings.self)
    requireSendable(AutoAdvance.self)
    requireSendable(AutoAdvanceTriggers.self)
    requireSendable(KeepZoom.self)
    requireSendable(RejectsFolderName.self)
    requireSendable(AppearanceChoice.self)
    requireSendable(SettingsPersistence.self)
    requireSendable(UserDefaultsSettingsStorage.self)
}

private func requireSendable<Value: Sendable>(_: Value.Type) {}
