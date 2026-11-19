import CloveCore
import Foundation
import Testing
import os

@testable import Clove

@MainActor
struct AppLocalizationTests {
    @Test func bundleResolvesDistinctEnglishAndChineseLprojDirectories() {
        let en = AppLocalization.bundle(for: .english)
        let hans = AppLocalization.bundle(for: .simplifiedChinese)
        let hant = AppLocalization.bundle(for: .traditionalChinese)

        #expect(en.bundleURL != hans.bundleURL)
        #expect(hans.bundleURL != hant.bundleURL)
        #expect(en.bundleURL.lastPathComponent == "en.lproj")
        #expect(hans.bundleURL.lastPathComponent == "zh-Hans.lproj")
        #expect(hant.bundleURL.lastPathComponent == "zh-Hant.lproj")
    }

    @Test func terminologyAndRegionalConventionsMatchDesignCopy() {
        // Core culling & move terminology shared across zh-Hans and zh-Hant.
        #expect(AppLocalization.string("Reject", language: .simplifiedChinese) == "淘汰")
        #expect(AppLocalization.string("Reject", language: .traditionalChinese) == "淘汰")
        #expect(AppLocalization.string("Rejected", language: .simplifiedChinese) == "已淘汰")
        #expect(AppLocalization.string("Rejected", language: .traditionalChinese) == "已淘汰")
        #expect(AppLocalization.string("Move rejects", language: .simplifiedChinese) == "整理淘汰片")
        #expect(AppLocalization.string("Move rejects", language: .traditionalChinese) == "整理淘汰片")

        // zh-Hans uses 照片/文件夹/打开; zh-Hant uses 相片/檔案夾/開啟.
        #expect(AppLocalization.string("Photos", language: .simplifiedChinese) == "照片")
        #expect(AppLocalization.string("Photos", language: .traditionalChinese) == "相片")
        #expect(AppLocalization.string("Open", language: .simplifiedChinese) == "打开")
        #expect(AppLocalization.string("Open", language: .traditionalChinese) == "開啟")
        #expect(AppLocalization.string("Open folder…", language: .simplifiedChinese) == "打开文件夹…")
        #expect(AppLocalization.string("Open folder…", language: .traditionalChinese) == "開啟檔案夾…")
        #expect(AppLocalization.string("Folder name", language: .simplifiedChinese) == "文件夹名称")
        #expect(AppLocalization.string("Folder name", language: .traditionalChinese) == "檔案夾名稱")
        #expect(AppLocalization.string("Keywords", language: .english) == "Keywords")
        #expect(AppLocalization.string("Keywords", language: .simplifiedChinese) == "关键词")
        #expect(AppLocalization.string("Keywords", language: .traditionalChinese) == "關鍵字")
        #expect(AppLocalization.string("Actions", language: .english) == "Actions")
        #expect(AppLocalization.string("Actions", language: .simplifiedChinese) == "操作")
        #expect(AppLocalization.string("Actions", language: .traditionalChinese) == "動作")
    }

    @Test func pluralStringsFormatSingularAndPluralInAllSupportedLanguages() {
        #expect(AppLocalization.format("%lld photos", language: .english, Int64(1)) == "1 photo")
        #expect(AppLocalization.format("%lld photos", language: .english, Int64(4)) == "4 photos")
        #expect(
            AppLocalization.format("%lld photos", language: .simplifiedChinese, Int64(1))
                == "1 张照片")
        #expect(
            AppLocalization.format("%lld photos", language: .traditionalChinese, Int64(1))
                == "1 張相片")

        #expect(
            AppLocalization.format("%lld hidden by filter", language: .english, Int64(1))
                == "1 hidden by filter")
        #expect(
            AppLocalization.format("%lld hidden by filter", language: .english, Int64(3))
                == "3 hidden by filter")
        #expect(
            AppLocalization.format("%lld hidden by filter", language: .simplifiedChinese, Int64(3))
                == "3 张因筛选隐藏")
        #expect(
            AppLocalization.format("%lld hidden by filter", language: .traditionalChinese, Int64(3))
                == "3 張因篩選隱藏")

        #expect(
            AppLocalization.format("Order %lld photos", language: .english, Int64(1))
                == "Order 1 photo")
        #expect(
            AppLocalization.format("Order %lld photos", language: .english, Int64(4))
                == "Order 4 photos")
        #expect(
            AppLocalization.format("Order %lld photos", language: .simplifiedChinese, Int64(1))
                == "排序 1 张照片")
        #expect(
            AppLocalization.format("Order %lld photos", language: .traditionalChinese, Int64(1))
                == "排序 1 張相片")

        #expect(
            AppLocalization.format("Renaming %lld photos…", language: .english, Int64(1))
                == "Renaming 1 photo…")
        #expect(
            AppLocalization.format("Renaming %lld photos…", language: .english, Int64(4))
                == "Renaming 4 photos…")

        #expect(
            AppLocalization.format("Renamed %lld photos", language: .english, Int64(1))
                == "Renamed 1 photo")
        #expect(
            AppLocalization.format("Renamed %lld photos", language: .english, Int64(3))
                == "Renamed 3 photos")
        #expect(
            AppLocalization.format("Renamed %lld photos", language: .simplifiedChinese, Int64(1))
                == "已重命名 1 张照片")
        #expect(
            AppLocalization.format("Renamed %lld photos", language: .traditionalChinese, Int64(1))
                == "已重新命名 1 張相片")

        #expect(
            AppLocalization.format("Move %lld rejected photos", language: .english, Int64(1))
                == "Move 1 rejected photo")
        #expect(
            AppLocalization.format("Move %lld rejected photos", language: .english, Int64(2))
                == "Move 2 rejected photos")
        #expect(
            AppLocalization.format(
                "Move %lld rejected photos", language: .simplifiedChinese, Int64(2))
                == "移出 2 张淘汰照片")
        #expect(
            AppLocalization.format(
                "Move %lld rejected photos", language: .traditionalChinese, Int64(2))
                == "移出 2 張淘汰相片")

        #expect(
            AppLocalization.format(
                "%lld name is already used in the destination.", language: .english, Int64(1))
                == "1 name is already used in the destination.")
        #expect(
            AppLocalization.format(
                "%lld name is already used in the destination.", language: .english, Int64(3))
                == "3 names are already used in the destination.")
        #expect(
            AppLocalization.format(
                "%lld name is already used in the destination.", language: .simplifiedChinese,
                Int64(3)) == "目标位置已有 3 个同名文件。")
        #expect(
            AppLocalization.format(
                "%lld name is already used in the destination.", language: .traditionalChinese,
                Int64(3)) == "目標位置已有 3 個同名檔案。")

        #expect(
            AppLocalization.format("Reject %lld unmarked", language: .simplifiedChinese, Int64(6))
                == "淘汰 6 张未标记")
        #expect(
            AppLocalization.format("Reject %lld unmarked", language: .traditionalChinese, Int64(6))
                == "淘汰 6 張未標記")

        #expect(AppLocalization.starCount(1, language: .english) == "1 star")
        #expect(AppLocalization.starCount(5, language: .english) == "5 stars")
        #expect(AppLocalization.starCount(5, language: .simplifiedChinese) == "5 星")
    }

    @Test func xmpColourRawValuesAndRejectsFolderNameStayUnlocalized() {
        #expect(LabelColour.red.rawValue == "Red")
        #expect(LabelColour.green.rawValue == "Green")
        #expect(RejectsFolderName.defaultFolderName.rawValue == "_Rejected")
        #expect(AppLocalization.colourName(.red, language: .simplifiedChinese) == "红色")
        #expect(AppLocalization.colourName(.red, language: .traditionalChinese) == "紅色")
    }

    @Test func settingsStoreSyncsBidirectionallyWithoutWritingAppleLanguages() {
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        let initialAppleLanguages = UserDefaults.standard.stringArray(forKey: "AppleLanguages")

        let currentSystemLanguages = OSAllocatedUnfairLock(initialState: ["en-US"])
        let storage = SampleSettingsStorage()
        let persistence = SettingsPersistence(storage: storage)

        let store = SettingsStore(
            persistence: persistence,
            rememberedAdvanceStorage: storage,
            physicalMemory: 8 * 1024 * 1024 * 1024,
            systemPreferredLanguages: { currentSystemLanguages.withLock { $0 } })

        #expect(store.settings.language == .system)
        #expect(store.resolvedLanguage == .english)

        // System change updates resolvedLanguage immediately when on Follow System.
        currentSystemLanguages.withLock { $0 = ["zh-Hans-CN"] }
        #expect(store.resolvedLanguage == .simplifiedChinese)

        // Switching in-app takes effect live without touching AppleLanguages.
        store.update { $0.language = .traditionalChinese }
        #expect(store.resolvedLanguage == .traditionalChinese)
        #expect(
            UserDefaults.standard.stringArray(forKey: "AppleLanguages") == initialAppleLanguages)
        if let bundleID = Bundle.main.bundleIdentifier {
            let domain = UserDefaults.standard.persistentDomain(forName: bundleID)
            #expect(domain?["AppleLanguages"] == nil)
        }

        // Relaunching while system language stays the same keeps the explicit in-app choice.
        let relaunchedSameSystem = SettingsStore(
            persistence: persistence,
            rememberedAdvanceStorage: storage,
            physicalMemory: 8 * 1024 * 1024 * 1024,
            systemPreferredLanguages: { currentSystemLanguages.withLock { $0 } })
        #expect(relaunchedSameSystem.settings.language == .traditionalChinese)
        #expect(relaunchedSameSystem.resolvedLanguage == .traditionalChinese)

        // Changing iOS System Settings (different baseline on relaunch) resets in-app choice to .system.
        currentSystemLanguages.withLock { $0 = ["en-US"] }
        let relaunchedChangedSystem = SettingsStore(
            persistence: persistence,
            rememberedAdvanceStorage: storage,
            physicalMemory: 8 * 1024 * 1024 * 1024,
            systemPreferredLanguages: { currentSystemLanguages.withLock { $0 } })
        #expect(relaunchedChangedSystem.settings.language == .system)
        #expect(relaunchedChangedSystem.resolvedLanguage == .english)
        #expect(persistence.load().language == .system)
    }

    @Test func settingsCategoryPlacesLanguageImmediatelyAfterAppearance() {
        let categories = SettingsCategory.allCases
        let appearanceIndex = categories.firstIndex(of: .appearance)
        let languageIndex = categories.firstIndex(of: .language)
        #expect(appearanceIndex == 0)
        #expect(languageIndex == 1)
    }

    @Test func helpersAndStatesLocalizeAcrossLanguages() throws {
        let ratedAndLabelled = PhotoMarks(
            rating: try #require(Rating(rawValue: 4)),
            label: ColourLabel(colour: .green))
        #expect(
            MarkSummary.text(for: ratedAndLabelled, language: .simplifiedChinese) == "4 星 · 绿色")
        #expect(
            MarkSummary.text(for: ratedAndLabelled, language: .traditionalChinese) == "4 星 · 綠色")

        let rejected = PhotoMarks(rating: .rejected, label: .clear)
        #expect(MarkSummary.text(for: rejected, language: .simplifiedChinese) == "已淘汰")
        #expect(MarkSummary.text(for: rejected, language: .traditionalChinese) == "已淘汰")

        #expect(
            AppLocalization.filterTitle(
                for: .rejected, labelFilter: nil, language: .simplifiedChinese)
                == "已淘汰")
        #expect(
            AppLocalization.filterTitle(
                for: .all, labelFilter: .blue, language: .traditionalChinese) == "藍色")

        let folder = FolderIdentity(rawValue: "loc-prep")
        let status = FolderPreparationStatus(
            folder: folder,
            folderName: "Test",
            generation: 1,
            isEnumerating: false,
            isPartialScan: false,
            waitingReason: nil,
            totalPhotos: 10,
            analysis: FolderPreparationTaskCounts(completed: 4),
            previews: FolderPreparationTaskCounts(completed: 6),
            readyForBothCount: 3,
            bothSettledCount: 3,
            issues: [])
        #expect(
            FolderPreparationAccessibility.summaryText(for: status, language: .simplifiedChinese)
                == "已就绪 3 / 10")
        #expect(
            FolderPreparationAccessibility.summaryText(for: status, language: .traditionalChinese)
                == "已就緒 3 / 10")

        let detected = DetailFocusFaceIndicator.detected
        let none = DetailFocusFaceIndicator.noFacesDetected
        let indicators = DetailFocusResultIndicators(
            face: detected, missingAutofocusMetadata: true)

        #expect(detected.accessibilityLabel(language: .english) == "Face detected")
        #expect(detected.accessibilityLabel(language: .simplifiedChinese) == "检测到人脸")
        #expect(detected.accessibilityLabel(language: .traditionalChinese) == "偵測到人臉")

        #expect(none.accessibilityLabel(language: .english) == "No faces detected")
        #expect(none.accessibilityLabel(language: .simplifiedChinese) == "未检测到人脸")
        #expect(none.accessibilityLabel(language: .traditionalChinese) == "未偵測到人臉")

        #expect(
            indicators.missingAutofocusAccessibilityLabel(language: .english)
                == "No autofocus metadata")
        #expect(
            indicators.missingAutofocusAccessibilityLabel(language: .simplifiedChinese)
                == "无自动对焦元数据")
        #expect(
            indicators.missingAutofocusAccessibilityLabel(language: .traditionalChinese)
                == "無自動對焦中繼資料")
    }
}
