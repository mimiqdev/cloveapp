import CloveCore
import Foundation
import Synchronization

/// The sample launch's settings storage: values live only in this process.
///
/// The UI test and the previews browse the sample library, so their settings start from C12's
/// launch defaults on every run and never reach the user's defaults. A run that switches a
/// setting therefore cannot change what the next run sees, and nothing is written to disk.
final class TestLaunchSettingsStorage: SettingsStorage {
    private let values = Mutex<[String: String]>([:])

    /// The stored text for one key, or nil when nothing was stored in this launch.
    func string(forKey key: String) -> String? {
        values.withLock { $0[key] }
    }

    /// Keeps or removes one value for the rest of this launch.
    func setString(_ text: String?, forKey key: String) {
        values.withLock { $0[key] = text }
    }
}
