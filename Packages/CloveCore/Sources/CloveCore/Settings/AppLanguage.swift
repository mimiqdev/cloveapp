import Foundation

/// User-selectable app language preference (issue #325).
public enum AppLanguage: String, CaseIterable, Hashable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese
    case traditionalChinese

    public var id: Self { self }

    /// Resolves this preference against the ordered preferred language identifiers.
    public func resolved(preferredLanguages: [String]) -> ResolvedAppLanguage {
        switch self {
        case .system:
            Self.resolveSystem(preferredLanguages: preferredLanguages)
        case .english:
            .english
        case .simplifiedChinese:
            .simplifiedChinese
        case .traditionalChinese:
            .traditionalChinese
        }
    }

    /// Resolves `.system` against ordered BCP-47 preferred language identifiers.
    ///
    /// Inspects identifiers in priority order and returns the first supported match:
    /// - Traditional Chinese (`zh-Hant`, `zh-TW`, `zh-HK`, `zh-MO`, or `zh` with `Hant`/`TW`/`HK`/`MO`)
    /// - Simplified Chinese (`zh-Hans`, `zh-CN`, `zh-SG`, bare `zh`, or `zh` with `Hans`/`CN`/`SG`)
    /// - English (`en` or `en-*`)
    ///
    /// Falls back to `.english` if no identifier matches.
    public static func resolveSystem(preferredLanguages: [String]) -> ResolvedAppLanguage {
        for rawIdentifier in preferredLanguages {
            if let matched = matchIdentifier(rawIdentifier) {
                return matched
            }
        }
        return .english
    }

    private static func matchIdentifier(_ rawIdentifier: String) -> ResolvedAppLanguage? {
        let normalized =
            rawIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        let subtags = normalized.split(separator: "-").map(String.init)
        guard let languageCode = subtags.first else { return nil }

        if languageCode == "en" {
            return .english
        }

        if languageCode == "zh" {
            let remaining = Set(subtags.dropFirst())
            if remaining.contains("hant")
                || remaining.contains("tw")
                || remaining.contains("hk")
                || remaining.contains("mo")
            {
                return .traditionalChinese
            }
            if remaining.contains("hans")
                || remaining.contains("cn")
                || remaining.contains("sg")
                || remaining.isEmpty
            {
                return .simplifiedChinese
            }
            return .simplifiedChinese
        }

        return nil
    }
}

/// Concrete app language used for formatting, resource bundles, and SwiftUI environment locale.
public enum ResolvedAppLanguage: String, CaseIterable, Hashable, Sendable {
    case english
    case simplifiedChinese
    case traditionalChinese

    /// Canonical BCP-47 identifier matching Xcode `.lproj` resource directories.
    public var localeIdentifier: String {
        switch self {
        case .english:
            "en"
        case .simplifiedChinese:
            "zh-Hans"
        case .traditionalChinese:
            "zh-Hant"
        }
    }

    /// Resource bundle folder code (`en`, `zh-Hans`, `zh-Hant`) inside the app bundle.
    public var bundleCode: String {
        localeIdentifier
    }

    /// Foundation locale matching this resolved language.
    public var locale: Locale {
        Locale(identifier: localeIdentifier)
    }
}
