import CloveCore
import Foundation
import SwiftUI

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue: ResolvedAppLanguage = .english
}

extension EnvironmentValues {
    var appLanguage: ResolvedAppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}

/// Resolves localized UI strings and plurals against the active `ResolvedAppLanguage`
/// without restarting the process or mutating `AppleLanguages`.
enum AppLocalization {
    private static let enBundle: Bundle = loadBundle(for: .english)
    private static let zhHansBundle: Bundle = loadBundle(for: .simplifiedChinese)
    private static let zhHantBundle: Bundle = loadBundle(for: .traditionalChinese)

    private static func loadBundle(for language: ResolvedAppLanguage) -> Bundle {
        if let path = Bundle.main.path(forResource: language.bundleCode, ofType: "lproj"),
            let bundle = Bundle(path: path)
        {
            return bundle
        }
        return .main
    }

    static func bundle(for language: ResolvedAppLanguage) -> Bundle {
        switch language {
        case .english: enBundle
        case .simplifiedChinese: zhHansBundle
        case .traditionalChinese: zhHantBundle
        }
    }

    static func string(_ key: String, language: ResolvedAppLanguage) -> String {
        bundle(for: language).localizedString(forKey: key, value: key, table: nil)
    }

    static func format(
        _ key: String, language: ResolvedAppLanguage, _ arguments: CVarArg...
    ) -> String {
        let template = string(key, language: language)
        return String(format: template, locale: language.locale, arguments: arguments)
    }

    static func languageDisplayName(_ option: AppLanguage, language: ResolvedAppLanguage) -> String
    {
        switch option {
        case .system: string("Follow System", language: language)
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        }
    }

    static func resolvedLanguageAutonym(_ resolved: ResolvedAppLanguage) -> String {
        switch resolved {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        }
    }

    static func colourName(_ colour: LabelColour, language: ResolvedAppLanguage) -> String {
        string(colour.rawValue, language: language)
    }

    static func starCount(_ count: Int, language: ResolvedAppLanguage) -> String {
        format("%lld stars", language: language, Int64(count))
    }

    static func ratingTitle(_ rating: Rating, language: ResolvedAppLanguage) -> String {
        if let stars = rating.starCount {
            return starCount(stars, language: language)
        }
        return string("Unrated", language: language)
    }

    static func filterTitle(
        for filter: PhotoFilter, labelFilter: LabelColour?, language: ResolvedAppLanguage
    ) -> String {
        if let labelFilter { return colourName(labelFilter, language: language) }
        switch filter {
        case .all: return string("All", language: language)
        case .unmarked: return string("Unmarked", language: language)
        case .rejected: return string("Rejected", language: language)
        case .ratedAtLeast(let rating):
            return format("★%lld+", language: language, Int64(rating.starCount ?? 0))
        case .subfolder(let path):
            return path
        }
    }

    static func appearanceTitle(_ mode: AppearanceMode, language: ResolvedAppLanguage) -> String {
        string(mode.title, language: language)
    }

    static func themeTitle(_ family: ThemeFamily, language: ResolvedAppLanguage) -> String {
        string(family.name, language: language)
    }

    static func groupingSensitivityTitle(
        _ sensitivity: GroupingSensitivity, language: ResolvedAppLanguage
    ) -> String {
        switch sensitivity {
        case .tight: string("Tight", language: language)
        case .standard: string("Standard", language: language)
        case .loose: string("Loose", language: language)
        case .timeOnly: string("Time only", language: language)
        }
    }

    static func groupingTimeWindowTitle(
        _ window: GroupingTimeWindow, language: ResolvedAppLanguage
    ) -> String {
        format("%llds", language: language, Int64(window.wholeSeconds))
    }

    static func saveSituationMessage(_ situation: SaveSituation, language: ResolvedAppLanguage)
        -> String
    {
        string(situation.message, language: language)
    }

    static func folderFailureText(
        for failure: FolderAccessFailure, language: ResolvedAppLanguage
    ) -> String {
        string(FolderFailureExplanation.text(for: failure), language: language)
    }
}
