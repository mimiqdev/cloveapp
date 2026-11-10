import Foundation
import Testing

import CloveCore

@Test func emptyStorageLoadsEveryDefault() {
    let storage = InMemorySettingsStorage()
    #expect(SettingsPersistence(storage: storage).load() == AppSettings())
}

@Test func savingAndLoadingRoundTripsEveryField() throws {
    let storage = InMemorySettingsStorage()
    let settings = try nonDefaultSettings()
    SettingsPersistence(storage: storage).save(settings)

    // A second persistence instance proves the values came back through the store.
    let reloaded = SettingsPersistence(storage: storage).load()
    #expect(reloaded == settings)
    #expect(reloaded != AppSettings())
}

@Test func savingWritesExactlyTheLaunchKeySet() {
    let storage = InMemorySettingsStorage()
    SettingsPersistence(storage: storage).save(AppSettings())
    #expect(storage.storedKeys.sorted() == launchSettingKeys)
}

@Test func everyCorruptFieldFallsBackAlone() throws {
    let custom = try nonDefaultSettings()
    let defaults = AppSettings()
    let invalid = "not a stored value"
    let cases: [(key: String, corrupt: String, applyDefault: (inout AppSettings) -> Void)] = [
        ("gestures.enabled", invalid, { $0.gesturesEnabled = defaults.gesturesEnabled }),
        ("ratings.enabled", "1,x,5", { $0.enabledRatings = defaults.enabledRatings }),
        (
            "autoAdvance.destination", invalid,
            { $0.autoAdvance.destination = defaults.autoAdvance.destination }
        ),
        (
            "autoAdvance.trigger.rating", invalid,
            { $0.autoAdvance.triggers.rating = defaults.autoAdvance.triggers.rating }
        ),
        (
            "autoAdvance.trigger.reject", invalid,
            { $0.autoAdvance.triggers.reject = defaults.autoAdvance.triggers.reject }
        ),
        (
            "autoAdvance.trigger.colourLabel", invalid,
            { $0.autoAdvance.triggers.colourLabel = defaults.autoAdvance.triggers.colourLabel }
        ),
        ("detail.doubleTap", invalid, { $0.doubleTap = defaults.doubleTap }),
        ("zoom.keepInGroups", invalid, { $0.keepZoom.inGroups = defaults.keepZoom.inGroups }),
        ("zoom.keepInDetail", invalid, { $0.keepZoom.inDetail = defaults.keepZoom.inDetail }),
        (
            "labels.extended", invalid,
            { $0.extendedColourLabelsEnabled = defaults.extendedColourLabelsEnabled }
        ),
        (
            "rejects.folderName", ".hidden",
            { $0.rejectsFolderName = defaults.rejectsFolderName }
        ),
        ("rejects.moveEnabled", invalid, { $0.moveRejectsEnabled = defaults.moveRejectsEnabled }),
        (
            "groups.similarEnabled", invalid,
            { $0.similarGroupsEnabled = defaults.similarGroupsEnabled }
        ),
        ("grid.groupDisplay", invalid, { $0.gridGroupDisplay = defaults.gridGroupDisplay }),
        ("groups.completion", invalid, { $0.groupCompletion = defaults.groupCompletion }),
        (
            "appearance.matchSystem", invalid,
            { $0.appearance.matchesSystemAppearance = defaults.appearance.matchesSystemAppearance }
        ),
        ("appearance.theme", invalid, { $0.appearance.theme = defaults.appearance.theme }),
    ]
    // The table covers every persisted key, so a new key cannot skip the fallback rule.
    #expect(cases.map(\.key).sorted() == launchSettingKeys)

    for (key, corrupt, applyDefault) in cases {
        let storage = InMemorySettingsStorage()
        let persistence = SettingsPersistence(storage: storage)
        persistence.save(custom)
        storage.setString(corrupt, forKey: key)

        var expected = custom
        applyDefault(&expected)
        #expect(persistence.load() == expected, "corrupt \(key)")
    }
}

@Test func malformedRatingListsFallBackToAllFive() throws {
    let custom = try nonDefaultSettings()
    let malformed = ["", "0", "1,", ",1", "1,6", "one", "1, 3", "1;3", "1,3,5,9"]
    for text in malformed {
        let storage = InMemorySettingsStorage()
        let persistence = SettingsPersistence(storage: storage)
        persistence.save(custom)
        storage.setString(text, forKey: "ratings.enabled")

        var expected = custom
        expected.enabledRatings = AppSettings().enabledRatings
        #expect(persistence.load() == expected, "ratings \(text)")
    }

    // Storage text from this version always loads back unchanged.
    let storage = InMemorySettingsStorage()
    let persistence = SettingsPersistence(storage: storage)
    persistence.save(custom)
    #expect(persistence.load().enabledRatings == custom.enabledRatings)
}

/// Storage written before the Appearance setting existed loads its launch defaults, so an update
/// needs no migration step and keeps every other stored value.
@Test func appearanceReadsItsDefaultsFromOlderStorage() {
    let storage = InMemorySettingsStorage()
    var older = AppSettings()
    older.gesturesEnabled = false
    older.keepZoom = KeepZoom(inGroups: false, inDetail: true)
    SettingsPersistence(storage: storage).save(older)
    // What the previous version wrote: every key it knew, and none of the Appearance keys.
    storage.setString(nil, forKey: "appearance.matchSystem")
    storage.setString(nil, forKey: "appearance.theme")

    var expected = older
    expected.appearance = AppearanceChoice()
    #expect(SettingsPersistence(storage: storage).load() == expected)
}

@Test func aNewSettingReadsItsDefaultWithoutMigration() {
    let storage = InMemorySettingsStorage()
    storage.setString("false", forKey: "gestures.enabled")
    storage.setString("from-a-later-version", forKey: "future.editorSetting")

    let loaded = SettingsPersistence(storage: storage).load()
    var expected = AppSettings()
    expected.gesturesEnabled = false
    #expect(loaded == expected)
    // Keys this version does not own are left for the version that does.
    #expect(storage.string(forKey: "future.editorSetting") == "from-a-later-version")
}

@Test func saveVerificationConfirmsEveryStoredSetting() throws {
    let settings = try nonDefaultSettings()
    let storage = InMemorySettingsStorage()
    #expect(SettingsPersistence(storage: storage).saveVerified(settings))
    // The check is a real read-back, not the write's own success: another instance sees it.
    #expect(SettingsPersistence(storage: storage).load() == settings)
}

@Test func saveVerificationReportsStorageThatDropsTheWrite() throws {
    let settings = try nonDefaultSettings()
    let persistence = SettingsPersistence(storage: DroppingSettingsStorage())
    #expect(!persistence.saveVerified(settings))
    // Nothing reached storage, so the next launch sees the defaults rather than the change.
    #expect(persistence.load() == AppSettings())
}

@Test func savingTheDefaultsResetsEveryStoredSetting() throws {
    let storage = InMemorySettingsStorage()
    let persistence = SettingsPersistence(storage: storage)
    persistence.save(try nonDefaultSettings())
    #expect(persistence.load() != AppSettings())

    // The settings screen's Reset to defaults is this call: every key goes back to its launch
    // value, and the change is confirmed the same way as any other.
    #expect(persistence.saveVerified(AppSettings()))
    #expect(SettingsPersistence(storage: storage).load() == AppSettings())
    #expect(storage.storedKeys.sorted() == launchSettingKeys)
}

@Test func userDefaultsStorageRoundTripsUnderOneVersionedNamespace() throws {
    let suiteName = "clove.tests.settings.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: suiteName))
    defer { suite.removePersistentDomain(forName: suiteName) }

    let settings = try nonDefaultSettings()
    SettingsPersistence(storage: UserDefaultsSettingsStorage(suiteName: suiteName)).save(settings)
    #expect(
        SettingsPersistence(storage: UserDefaultsSettingsStorage(suiteName: suiteName)).load()
            == settings)

    let prefix = UserDefaultsSettingsStorage.keyPrefix
    let storedKeys = suite.dictionaryRepresentation().keys
        .filter { $0.hasPrefix(prefix) }
        .map { String($0.dropFirst(prefix.count)) }
        .sorted()
    #expect(storedKeys == launchSettingKeys)
}
