import Foundation
import Testing

import CloveCore

@Test func systemResolutionMatchesPreferredIdentifiersInPriorityOrder() {
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["en-US"]) == .english)
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["en"]) == .english)
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["zh-Hans"]) == .simplifiedChinese)
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["zh-Hans-CN"]) == .simplifiedChinese)
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["zh-CN"]) == .simplifiedChinese)
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["zh-SG"]) == .simplifiedChinese)
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["zh"]) == .simplifiedChinese)
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["zh-Hant"]) == .traditionalChinese)
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["zh-Hant-TW"]) == .traditionalChinese)
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["zh-TW"]) == .traditionalChinese)
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["zh-HK"]) == .traditionalChinese)
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["zh-MO"]) == .traditionalChinese)
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["zh_Hant_HK"]) == .traditionalChinese)

    // Unrecognized primary languages fall through to the next supported preferred identifier.
    #expect(
        AppLanguage.resolveSystem(preferredLanguages: ["fr-FR", "zh-HK", "en-US"])
            == .traditionalChinese)
    #expect(
        AppLanguage.resolveSystem(preferredLanguages: ["ja-JP", "zh-CN", "en-US"])
            == .simplifiedChinese)

    // Empty or wholly unsupported lists fall back to English.
    #expect(AppLanguage.resolveSystem(preferredLanguages: []) == .english)
    #expect(AppLanguage.resolveSystem(preferredLanguages: ["fr-FR", "de-DE"]) == .english)
}

@Test func explicitLanguagesOverrideSystemPreferredLanguages() {
    #expect(AppLanguage.english.resolved(preferredLanguages: ["zh-Hant-TW"]) == .english)
    #expect(
        AppLanguage.simplifiedChinese.resolved(preferredLanguages: ["en-US"])
            == .simplifiedChinese)
    #expect(
        AppLanguage.traditionalChinese.resolved(preferredLanguages: ["zh-Hans-CN"])
            == .traditionalChinese)
    #expect(
        AppLanguage.system.resolved(preferredLanguages: ["zh-Hant-HK"])
            == .traditionalChinese)
}

@Test func resolvedLanguagesExposeCanonicalBundleCodesAndLocales() {
    #expect(ResolvedAppLanguage.english.bundleCode == "en")
    #expect(ResolvedAppLanguage.english.localeIdentifier == "en")
    #expect(ResolvedAppLanguage.english.locale == Locale(identifier: "en"))

    #expect(ResolvedAppLanguage.simplifiedChinese.bundleCode == "zh-Hans")
    #expect(ResolvedAppLanguage.simplifiedChinese.localeIdentifier == "zh-Hans")
    #expect(ResolvedAppLanguage.simplifiedChinese.locale == Locale(identifier: "zh-Hans"))

    #expect(ResolvedAppLanguage.traditionalChinese.bundleCode == "zh-Hant")
    #expect(ResolvedAppLanguage.traditionalChinese.localeIdentifier == "zh-Hant")
    #expect(ResolvedAppLanguage.traditionalChinese.locale == Locale(identifier: "zh-Hant"))
}
