import CloveCore
import Foundation

/// Persists the last-used batch rename naming defaults (prefix, digits, separator) without
/// touching the main SettingsStore.
@MainActor
final class BatchRenameDefaults {
    private static let prefixKey = "rename.lastPrefix"
    private static let digitsKey = "rename.lastDigits"
    private static let separatorKey = "rename.lastSeparator"

    static let defaultPrefix = ""
    static let defaultDigits = 3
    static let defaultSeparator: RenameSeparator = .underscore

    private let storage: any SettingsStorage

    init(storage: any SettingsStorage) {
        self.storage = storage
    }

    static func launch(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> BatchRenameDefaults {
        if environment[TestLibrary.launchVariable] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
        {
            return BatchRenameDefaults(storage: SampleSettingsStorage())
        }
        return BatchRenameDefaults(storage: UserDefaultsSettingsStorage())
    }

    var prefix: String {
        storage.string(forKey: Self.prefixKey) ?? Self.defaultPrefix
    }

    var digits: Int {
        guard let raw = storage.string(forKey: Self.digitsKey),
            let parsed = Int(raw),
            (1...255).contains(parsed)
        else { return Self.defaultDigits }
        return parsed
    }

    var separator: RenameSeparator {
        guard let raw = storage.string(forKey: Self.separatorKey),
            let parsed = RenameSeparator(rawValue: raw)
        else { return Self.defaultSeparator }
        return parsed
    }

    func loadOptions() -> RenameOptions {
        RenameOptions(
            prefix: prefix,
            digits: digits,
            separator: separator
        )
    }

    func save(prefix: String, digits: Int, separator: RenameSeparator) {
        storage.setString(prefix, forKey: Self.prefixKey)
        let clampedDigits = min(max(digits, 1), 255)
        storage.setString(String(clampedDigits), forKey: Self.digitsKey)
        storage.setString(separator.rawValue, forKey: Self.separatorKey)
    }
}
