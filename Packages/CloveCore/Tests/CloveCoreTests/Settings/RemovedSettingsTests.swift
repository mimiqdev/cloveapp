import Foundation
import Testing

import CloveCore

@Test func settingsPropertiesAreTheLaunchSettingsOnly() {
    #expect(
        propertyLabels(of: AppSettings()) == [
            "gesturesEnabled",
            "enabledRatings",
            "autoAdvance",
            "doubleTap",
            "keepZoom",
            "extendedColourLabelsEnabled",
            "rejectsFolderName",
            "moveRejectsEnabled",
            "similarGroupsEnabled",
            "gridGroupDisplay",
            "groupCompletion",
        ])
    #expect(propertyLabels(of: AutoAdvance()) == ["destination", "triggers"])
    #expect(propertyLabels(of: AutoAdvanceTriggers()) == ["rating", "reject", "colourLabel"])
    #expect(propertyLabels(of: KeepZoom()) == ["inGroups", "inDetail"])
}

@Test func removedSettingsAreNeitherStoredNorRead() {
    let removedKeys = [
        "rejectExport",
        "rejects.export",
        "alsoWriteRatingMinusOne",
        "rating.minusOne",
        "embeddedWrites",
        "writeEmbeddedMetadata",
        "groupingSensitivity",
    ]
    let storage = InMemorySettingsStorage()
    for key in removedKeys {
        storage.setString("true", forKey: key)
    }

    let persistence = SettingsPersistence(storage: storage)
    // A removed setting must not resurrect a value from old or foreign storage.
    #expect(persistence.load() == AppSettings())

    persistence.save(AppSettings())
    // Saving this version writes only its own keys and leaves removed ones untouched.
    for key in removedKeys {
        #expect(storage.string(forKey: key) == "true")
        storage.setString(nil, forKey: key)
    }
    #expect(storage.storedKeys.sorted() == launchSettingKeys)
}

private func propertyLabels(of value: Any) -> [String] {
    Mirror(reflecting: value).children.compactMap(\.label)
}
