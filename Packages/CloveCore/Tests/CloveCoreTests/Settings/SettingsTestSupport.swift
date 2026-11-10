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
    "autoAdvance.destination",
    "autoAdvance.trigger.colourLabel",
    "autoAdvance.trigger.rating",
    "autoAdvance.trigger.reject",
    "detail.doubleTap",
    "gestures.enabled",
    "grid.groupDisplay",
    "groups.completion",
    "groups.similarEnabled",
    "labels.extended",
    "ratings.enabled",
    "rejects.folderName",
    "rejects.moveEnabled",
    "zoom.keepInDetail",
    "zoom.keepInGroups",
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
        keepZoom: KeepZoom(inGroups: false, inDetail: true),
        extendedColourLabelsEnabled: true,
        rejectsFolderName: folderName,
        moveRejectsEnabled: false,
        similarGroupsEnabled: false,
        gridGroupDisplay: .collapsed,
        groupCompletion: .stay
    )
}
