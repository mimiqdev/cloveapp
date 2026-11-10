import CloveCore
import Foundation
import Synchronization

/// Settings storage for the sample library: values live only in this process.
///
/// The UI test and the previews browse the sample library, so their settings start from C12's
/// launch defaults every time and never reach the user's defaults. A run that switches a setting
/// therefore cannot change what the next run or the user sees, and nothing is written to disk.
final class SampleSettingsStorage: SettingsStorage {
    private let values = Mutex<[String: String]>([:])

    /// The stored text for one key, or nil when nothing was stored in this process.
    func string(forKey key: String) -> String? {
        values.withLock { $0[key] }
    }

    /// Keeps or removes one value for the rest of this process.
    func setString(_ text: String?, forKey key: String) {
        values.withLock { $0[key] = text }
    }
}
