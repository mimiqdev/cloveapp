import CloveCore
import Foundation
import Synchronization
import Testing

/// A thread-safe store for tests; production uses `UserDefaultsSettingsStorage`.
final class InMemorySettingsStorage: SettingsStorage {
    private let values = Mutex<[String: String]>([:])

    var storedKeys: [String] {
        values.withLock { Array($0.keys) }
    }

    func string(forKey key: String) -> String? {
        values.withLock { $0[key] }
    }

    func setString(_ text: String?, forKey key: String) {
        values.withLock { $0[key] = text }
    }
}

/// A store that accepts every write and keeps nothing, like storage that is unavailable.
///
/// The persistence tests use it to prove that a dropped write is reported instead of appearing
/// saved.
final class DroppingSettingsStorage: SettingsStorage {
    func string(forKey key: String) -> String? { nil }

    func setString(_ text: String?, forKey key: String) {}
}

/// The exact persisted key set for this settings version; a test pins it.
///
/// The literal, rather than `SettingsKey`, makes the test fail when a key is added, renamed, or
/// brought back for a setting the PRD removed.
let launchSettingKeys = [
    "app.language",
    "appearance.family",
    "appearance.mode",
    "autoAdvance.destination",
    "autoAdvance.trigger.colourLabel",
    "autoAdvance.trigger.rating",
    "autoAdvance.trigger.reject",
    "batch.confirmActions",
    "detail.doubleTap",
    "detail.zoomedGestures",
    "gestures.enabled",
    "groups.sensitivity",
    "groups.similarEnabled",
    "groups.timeWindow",
    "labels.extended",
    "ratings.enabled",
    "rejects.folderName",
    "rejects.moveEnabled",
]

/// Settings where every field differs from its default, so a round trip exercises every key.
func nonDefaultSettings() throws -> AppSettings {
    let one = try #require(Rating(rawValue: 1))
    let three = try #require(Rating(rawValue: 3))
    let five = try #require(Rating(rawValue: 5))
    let ratings = try #require(EnabledRatings([one, three, five]))
    let folderName = try #require(RejectsFolderName(rawValue: "Keepers"))
    return AppSettings(
        gesturesEnabled: false,
        enabledRatings: ratings,
        autoAdvance: AutoAdvance(
            destination: .nextUnmarkedPhoto,
            triggers: AutoAdvanceTriggers(rating: false, reject: false, colourLabel: true)
        ),
        doubleTap: .off,
        zoomedGestures: .pan,
        extendedColourLabelsEnabled: true,
        confirmBatchActions: true,
        rejectsFolderName: folderName,
        moveRejectsEnabled: false,
        similarGroupsEnabled: false,
        groupingSensitivity: .timeOnly,
        groupingTimeWindow: .tenSeconds,
        appearance: AppearanceChoice(mode: .dark, family: .nord),
        photoDisplayMode: .cameraPreviewFirst,
        language: .simplifiedChinese
    )
}
