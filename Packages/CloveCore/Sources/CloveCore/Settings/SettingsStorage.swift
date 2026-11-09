import Foundation

/// The small storage surface settings persistence needs: one text value per stable key.
///
/// The store owns its namespace and lifecycle; persistence only reads and writes keys. A test
/// can supply an in-memory implementation, and production uses `UserDefaultsSettingsStorage`.
public protocol SettingsStorage: Sendable {
    /// The stored text for a setting key, or nil when nothing is stored.
    func string(forKey key: String) -> String?

    /// Stores text for a setting key, or removes the key when `text` is nil.
    func setString(_ text: String?, forKey key: String)
}

/// Production settings storage in `UserDefaults`, under one versioned key namespace.
///
/// Every key is prefixed with `keyPrefix`. The version is part of the prefix, so a future
/// settings shape can move to a new version and read defaults for every field without a
/// migration; old values stay in the previous namespace and are ignored.
public struct UserDefaultsSettingsStorage: SettingsStorage {
    /// The single key namespace for the launch settings version.
    public static let keyPrefix = "clove.settings.v1."

    private let suiteName: String?

    /// Uses the app's standard defaults, or an injected suite for tests and previews.
    ///
    /// A suite name the system refuses falls back to the standard defaults rather than writing
    /// nowhere; production passes nil and uses the standard defaults directly.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// Reads the namespaced value (PRD Gestures and keyboard, Grid, Similar groups, In-group
    /// culling, Move rejects and P0-06/P0-10/P0-11).
    public func string(forKey key: String) -> String? {
        defaults.string(forKey: Self.keyPrefix + key)
    }

    /// Writes the namespaced value, or removes it before the next read (PRD Settings defaults).
    public func setString(_ text: String?, forKey key: String) {
        let namespacedKey = Self.keyPrefix + key
        if let text {
            defaults.set(text, forKey: namespacedKey)
        } else {
            defaults.removeObject(forKey: namespacedKey)
        }
    }

    private var defaults: UserDefaults {
        guard let suiteName, let suite = UserDefaults(suiteName: suiteName) else {
            return UserDefaults.standard
        }
        return suite
    }
}
