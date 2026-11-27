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
        #expect(AppLocalization.string("Add Keywords…", language: .english) == "Add Keywords…")
        #expect(AppLocalization.string("Add Keywords…", language: .simplifiedChinese) == "添加关键词…")
        #expect(AppLocalization.string("Add Keywords…", language: .traditionalChinese) == "加入關鍵字…")
        #expect(AppLocalization.string("Suggestions", language: .english) == "Suggestions")
        #expect(AppLocalization.string("Suggestions", language: .simplifiedChinese) == "建议")
        #expect(AppLocalization.string("Suggestions", language: .traditionalChinese) == "建議")
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
            AppLocalization.format("%lld keywords", language: .english, Int64(1))
                == "1 keyword")
        #expect(
            AppLocalization.format("%lld keywords", language: .english, Int64(3))
                == "3 keywords")
        #expect(
            AppLocalization.format("%lld keywords", language: .simplifiedChinese, Int64(3))
                == "3 个关键词")
        #expect(
            AppLocalization.format("%lld keywords", language: .traditionalChinese, Int64(3))
                == "3 個關鍵字")

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

        #expect(
            AppLocalization.format(
                "Group %lld of %lld", language: .english, Int64(1), Int64(3))
                == "Group 1 of 3")
        #expect(
            AppLocalization.format(
                "Group %lld of %lld", language: .simplifiedChinese, Int64(1), Int64(3))
                == "第 1 / 3 张（相似组）")
        #expect(
            AppLocalization.format(
                "Group %lld of %lld", language: .traditionalChinese, Int64(2), Int64(4))
                == "第 2 / 4 張（相似組）")
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

    @Test func settingsHomeAndSubpagesLocalizeAcrossLanguages() {
        let pairs: [(key: String, en: String, hans: String, hant: String)] = [
            ("Workspace", "Workspace", "工作区", "工作區"),
            ("Workflow", "Workflow", "工作流程", "工作流程"),
            (
                "Light, dark, or system mode and theme.",
                "Light, dark, or system mode and theme.",
                "浅色、深色或跟随系统模式与主题。",
                "淺色、深色或跟隨系統模式與主題。"
            ),
            (
                "App language for controls and menus.",
                "App language for controls and menus.",
                "应用控件与菜单的显示语言。",
                "應用程式控制項與選單的顯示語言。"
            ),
            (
                "Similar shot grouping, time window, and detail zoom.",
                "Similar shot grouping, time window, and detail zoom.",
                "相似照片分组、时间窗口与大图缩放。",
                "相似相片群組、時間窗口與大圖縮放。"
            ),
            (
                "Choose camera previews or full RAW colors.",
                "Choose camera previews or full RAW colors.",
                "选择相机预览或 RAW 文件原本色彩。",
                "選擇相機預覽或 RAW 檔案原本色彩。"
            ),
            (
                "Gestures, rating scale, color labels, and auto-advance.",
                "Gestures, rating scale, color labels, and auto-advance.",
                "手势、评分范围、颜色标签与自动跳转。",
                "手勢、評分範圍、顏色標籤與自動跳轉。"
            ),
            (
                "Move rejected photos to a subfolder instead of deleting.",
                "Move rejected photos to a subfolder instead of deleting.",
                "将淘汰照片移至子文件夹，而不是删除。",
                "將淘汰相片移至子檔案夾，而非刪除。"
            ),
            (
                "Your preferences apply to every layout.",
                "Your preferences apply to every layout.",
                "你的偏好设置会应用于所有布局。",
                "你的偏好設定會套用於所有版面。"
            ),
            ("Quicker and lighter", "Quicker and lighter", "更快更轻量", "更快更輕量"),
            ("The file's own colors", "The file's own colors", "文件本身的色彩", "檔案本身的色彩"),
            ("Enabled levels", "Enabled levels", "启用的评分等级", "已啟用的評分等級"),
            ("Offer Move Rejects", "Offer Move Rejects", "提供整理淘汰片", "提供整理淘汰片"),
            ("After marking", "After marking", "标记后跳转", "標記後跳轉"),
        ]
        for pair in pairs {
            #expect(AppLocalization.string(pair.key, language: .english) == pair.en)
            #expect(AppLocalization.string(pair.key, language: .simplifiedChinese) == pair.hans)
            #expect(AppLocalization.string(pair.key, language: .traditionalChinese) == pair.hant)
        }
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

        #expect(AppLocalization.string("Focal length", language: .english) == "Focal length")
        #expect(AppLocalization.string("Focal length", language: .simplifiedChinese) == "焦距")
        #expect(AppLocalization.string("Focal length", language: .traditionalChinese) == "焦距")
        #expect(AppLocalization.string("Color Labels", language: .english) == "Color Labels")
        #expect(AppLocalization.string("Color Labels", language: .simplifiedChinese) == "颜色标签")
        #expect(AppLocalization.string("Color Labels", language: .traditionalChinese) == "顏色標籤")
        #expect(AppLocalization.string("Similar Groups", language: .english) == "Similar Groups")
        #expect(AppLocalization.string("Similar Groups", language: .simplifiedChinese) == "相似照片组")
        #expect(AppLocalization.string("Similar Groups", language: .traditionalChinese) == "相似相片組")
        #expect(AppLocalization.string("Similar groups", language: .english) == "Similar groups")
        #expect(AppLocalization.string("More filters", language: .simplifiedChinese) == "更多筛选")
        #expect(AppLocalization.string("More filters", language: .traditionalChinese) == "更多篩選")
        #expect(AppLocalization.string("Clear", language: .simplifiedChinese) == "清除")
        #expect(AppLocalization.string("Clear", language: .traditionalChinese) == "清除")
        #expect(AppLocalization.string("Clear filters", language: .simplifiedChinese) == "清除筛选")
        #expect(AppLocalization.string("Clear filters", language: .traditionalChinese) == "清除篩選")
        #expect(
            AppLocalization.focalLengthBucketLabel(.ultraWide, language: .english)
                == "Ultra-wide · < 24 mm")
        #expect(
            AppLocalization.focalLengthBucketLabel(.wide, language: .simplifiedChinese)
                == "广角 · 24–35 mm")
        #expect(
            AppLocalization.focalLengthBucketLabel(.shortTelephoto, language: .traditionalChinese)
                == "中長焦 · 71–135 mm")
        #expect(
            AppLocalization.format("%lld filters", language: .english, Int64(1)) == "1 filter")
        #expect(
            AppLocalization.format("%lld filters", language: .english, Int64(3)) == "3 filters")
        #expect(
            AppLocalization.format("%lld filters", language: .simplifiedChinese, Int64(2))
                == "2 项筛选")
        #expect(
            AppLocalization.format("%lld filters", language: .traditionalChinese, Int64(2))
                == "2 項篩選")

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
        #expect(
            FolderPreparationAccessibility.retryButtonTitle(language: .english) == "Retry")
        #expect(
            FolderPreparationAccessibility.retryButtonTitle(language: .simplifiedChinese) == "重试")
        #expect(
            FolderPreparationAccessibility.retryButtonTitle(language: .traditionalChinese) == "重試")
        #expect(
            FolderPreparationAccessibility.retryButtonAccessibilityLabel(language: .english)
                == "Retry preparation issues")
        #expect(
            FolderPreparationAccessibility.retryButtonAccessibilityLabel(
                language: .simplifiedChinese) == "重试准备问题")
        #expect(
            FolderPreparationAccessibility.retryButtonAccessibilityLabel(
                language: .traditionalChinese) == "重試準備問題")
        #expect(
            FolderPreparationAccessibility.retryButtonAccessibilityHint(
                for: status, language: .simplifiedChinese) == "重新运行失败或延迟的分析与预览任务。")
        #expect(
            FolderPreparationAccessibility.retryButtonAccessibilityHint(
                for: status, language: .traditionalChinese) == "重新執行失敗或延遲的分析與預覽任務。")
        var pausedStatus = status
        pausedStatus.waitingReason = .memoryPressure
        #expect(
            FolderPreparationAccessibility.retryButtonAccessibilityHint(
                for: pausedStatus, language: .simplifiedChinese) == "文件夹准备已暂停时不可用。")
        #expect(
            FolderPreparationAccessibility.retryButtonAccessibilityHint(
                for: pausedStatus, language: .traditionalChinese) == "檔案夾準備已暫停時無法使用。")

        #expect(AppLocalization.string("Paused", language: .english) == "Paused")
        #expect(AppLocalization.string("Paused", language: .simplifiedChinese) == "已暂停")
        #expect(AppLocalization.string("Paused", language: .traditionalChinese) == "已暫停")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: status, progress: .analyzing(completed: 0, total: 0), language: .english)
                == "Finding similar shots…")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: status, progress: .analyzing(completed: 0, total: 0),
                language: .simplifiedChinese) == "正在查找相似照片…")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: status, progress: .analyzing(completed: 0, total: 0),
                language: .traditionalChinese) == "正在尋找相似相片…")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: status, progress: .analyzing(completed: 12, total: 24), language: .english)
                == "12 of 24 analyzed")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: status, progress: .analyzing(completed: 12, total: 24),
                language: .simplifiedChinese) == "已分析 12 / 24")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: status, progress: .analyzing(completed: 12, total: 24),
                language: .traditionalChinese) == "已分析 12 / 24")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: status, progress: .idle, language: .english) == "Waiting for photo count")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: status, progress: .idle, language: .simplifiedChinese) == "等待统计照片数量")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: status, progress: .idle, language: .traditionalChinese) == "等待統計相片數量")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: status, progress: .complete, groupCount: 1, language: .english) == "1 group")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: status, progress: .complete, groupCount: 3, language: .english) == "3 groups")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: status, progress: .complete, groupCount: 3, language: .simplifiedChinese)
                == "3 组")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: status, progress: .complete, groupCount: 3, language: .traditionalChinese)
                == "3 組")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: pausedStatus, progress: .analyzing(completed: 12, total: 24),
                language: .english)
                == "Paused")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: pausedStatus, progress: .analyzing(completed: 12, total: 24),
                language: .simplifiedChinese) == "已暂停")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: pausedStatus, progress: .analyzing(completed: 12, total: 24),
                language: .traditionalChinese) == "已暫停")
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(
                for: .idle, isFindingSimilarShots: true,
                groupingProgress: .analyzing(completed: 12, total: 24), language: .english)
                == "Finding similar shots, 12 of 24 analyzed")
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(
                for: .idle, isFindingSimilarShots: true,
                groupingProgress: .analyzing(completed: 12, total: 24),
                language: .simplifiedChinese) == "正在查找相似照片，已分析 12 / 24")
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(
                for: .idle, isFindingSimilarShots: true,
                groupingProgress: .analyzing(completed: 12, total: 24),
                language: .traditionalChinese) == "正在尋找相似相片，已分析 12 / 24")

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

    @Test func saveToPhotosLocalizesAcrossLanguagesAndPlurals() {
        #expect(AppLocalization.string("Save to Photos", language: .english) == "Save to Photos")
        #expect(
            AppLocalization.string("Save to Photos", language: .simplifiedChinese) == "存储到照片")
        #expect(
            AppLocalization.string("Save to Photos", language: .traditionalChinese) == "儲存到相片")

        #expect(
            PhotosSaveToastMessage.saved(savedCount: 1, skippedRawCount: 0)
                .localizedText(language: .english) == "Saved 1 photo to Photos")
        #expect(
            PhotosSaveToastMessage.saved(savedCount: 3, skippedRawCount: 0)
                .localizedText(language: .english) == "Saved 3 photos to Photos")
        #expect(
            PhotosSaveToastMessage.saved(savedCount: 2, skippedRawCount: 1)
                .localizedText(language: .english) == "Saved 2 photos to Photos · 1 RAW skipped")
        #expect(
            PhotosSaveToastMessage.saved(savedCount: 2, skippedRawCount: 1)
                .localizedText(language: .simplifiedChinese) == "已将 2 张照片存储到照片 · 已跳过 1 张 RAW")
        #expect(
            PhotosSaveToastMessage.saved(savedCount: 2, skippedRawCount: 1)
                .localizedText(language: .traditionalChinese) == "已將 2 張相片儲存到相片 · 已略過 1 張 RAW")

        #expect(
            AppLocalization.format("Save %lld photos to Photos?", language: .english, Int64(1))
                == "Save 1 photo to Photos?")
        #expect(
            AppLocalization.format("Save %lld photos to Photos?", language: .english, Int64(4))
                == "Save 4 photos to Photos?")
        #expect(
            AppLocalization.format(
                "%lld RAW-only photos have no JPEG or HEIF and will be skipped.",
                language: .english, Int64(1))
                == "1 RAW-only photo has no JPEG or HEIF and will be skipped.")
        #expect(
            AppLocalization.format(
                "%lld RAW-only photos have no JPEG or HEIF and will be skipped.",
                language: .english, Int64(2))
                == "2 RAW-only photos have no JPEG or HEIF and will be skipped.")

        #expect(
            PhotosSaveToastMessage.permissionDenied.localizedText(language: .english)
                == "Allow Photos access in Settings to save photos.")
        #expect(
            PhotosSaveToastMessage.failed.localizedText(language: .english)
                == "Couldn't save to Photos.")

        for language in [
            ResolvedAppLanguage.english, .simplifiedChinese, .traditionalChinese,
        ] {
            let bundle = AppLocalization.bundle(for: language)
            let usage = bundle.localizedString(
                forKey: "NSPhotoLibraryAddUsageDescription", value: nil, table: "InfoPlist")
            #expect(!usage.isEmpty && usage != "NSPhotoLibraryAddUsageDescription")
        }
    }

    @Test func groupingSettingsLocalizeAcrossLanguages() {
        #expect(AppLocalization.string("Time window", language: .english) == "Time window")
        #expect(AppLocalization.string("Time window", language: .simplifiedChinese) == "时间窗口")
        #expect(AppLocalization.string("Time window", language: .traditionalChinese) == "時間窗口")

        #expect(
            AppLocalization.string("Similarity sensitivity", language: .english)
                == "Similarity sensitivity")
        #expect(
            AppLocalization.string("Similarity sensitivity", language: .simplifiedChinese)
                == "相似度灵敏度")
        #expect(
            AppLocalization.string("Similarity sensitivity", language: .traditionalChinese)
                == "相似度靈敏度")

        #expect(AppLocalization.groupingSensitivityTitle(.tight, language: .english) == "Tight")
        #expect(
            AppLocalization.groupingSensitivityTitle(.tight, language: .simplifiedChinese) == "严格")
        #expect(
            AppLocalization.groupingSensitivityTitle(.tight, language: .traditionalChinese) == "嚴格")

        #expect(
            AppLocalization.groupingSensitivityTitle(.standard, language: .english) == "Standard")
        #expect(
            AppLocalization.groupingSensitivityTitle(.standard, language: .simplifiedChinese)
                == "标准")
        #expect(
            AppLocalization.groupingSensitivityTitle(.standard, language: .traditionalChinese)
                == "標準")

        #expect(AppLocalization.groupingSensitivityTitle(.loose, language: .english) == "Loose")
        #expect(
            AppLocalization.groupingSensitivityTitle(.loose, language: .simplifiedChinese) == "宽松")
        #expect(
            AppLocalization.groupingSensitivityTitle(.loose, language: .traditionalChinese) == "寬鬆")

        #expect(
            AppLocalization.groupingSensitivityTitle(.timeOnly, language: .english) == "Time only")
        #expect(
            AppLocalization.groupingSensitivityTitle(.timeOnly, language: .simplifiedChinese)
                == "仅按时间")
        #expect(
            AppLocalization.groupingSensitivityTitle(.timeOnly, language: .traditionalChinese)
                == "僅依時間")

        #expect(
            AppLocalization.groupingTimeWindowTitle(.twoSeconds, language: .english) == "2s")
        #expect(
            AppLocalization.groupingTimeWindowTitle(.twoSeconds, language: .simplifiedChinese)
                == "2 秒")
        #expect(
            AppLocalization.groupingTimeWindowTitle(.thirtySeconds, language: .traditionalChinese)
                == "30 秒")
    }

    @Test func compareStringsLocalizeAcrossLanguages() {
        let pairs: [(key: String, en: String, hans: String, hant: String)] = [
            ("Compare", "Compare", "对比", "對比"),
            ("Sync On", "Sync On", "同步开", "同步開"),
            ("Sync Off", "Sync Off", "同步关", "同步關"),
            ("Set as A", "Set as A", "设为 A", "設為 A"),
            ("Previous candidate", "Previous candidate", "上一张候选", "上一張候選"),
            ("Next candidate", "Next candidate", "下一张候选", "下一張候選"),
            ("Reference photo A", "Reference photo A", "参考照片 A", "參考相片 A"),
            ("Challenger photo B", "Challenger photo B", "对比照片 B", "對比相片 B"),
        ]
        for pair in pairs {
            #expect(AppLocalization.string(pair.key, language: .english) == pair.en)
            #expect(AppLocalization.string(pair.key, language: .simplifiedChinese) == pair.hans)
            #expect(AppLocalization.string(pair.key, language: .traditionalChinese) == pair.hant)
        }
        #expect(
            AppLocalization.format("Reference photo %@", language: .simplifiedChinese, "IMG_01.ARW")
                == "参考照片 IMG_01.ARW")
        #expect(
            AppLocalization.format(
                "Challenger photo %@", language: .traditionalChinese, "IMG_02.ARW")
                == "對比相片 IMG_02.ARW")
    }

    @Test func rawProgressiveDecodeStringsLocalizeAcrossLanguages() {
        let pairs: [(key: String, en: String, hans: String, hant: String)] = [
            ("Preview", "Preview", "预览", "預覽"),
            ("Preview only", "Preview only", "仅预览", "僅預覽"),
        ]
        for pair in pairs {
            #expect(AppLocalization.string(pair.key, language: .english) == pair.en)
            #expect(AppLocalization.string(pair.key, language: .simplifiedChinese) == pair.hans)
            #expect(AppLocalization.string(pair.key, language: .traditionalChinese) == pair.hant)
        }
        #expect(
            AppLocalization.format("%@ · %@", language: .simplifiedChinese, "100%", "预览")
                == "100% · 预览")
        #expect(
            AppLocalization.format("%@ · %@", language: .traditionalChinese, "100%", "預覽")
                == "100% · 預覽")
    }

    @Test func groupPickerStringsLocalizeAcrossLanguages() {
        let pairs: [(key: String, en: String, hans: String, hant: String)] = [
            ("Show group photos", "Show group photos", "显示组内照片", "顯示群組相片"),
            ("Similar group", "Similar group", "相似照片组", "相似相片組"),
            ("Collapse group", "Collapse group", "收起分组", "收合群組"),
            ("Done", "Done", "完成", "完成"),
        ]
        for pair in pairs {
            #expect(AppLocalization.string(pair.key, language: .english) == pair.en)
            #expect(AppLocalization.string(pair.key, language: .simplifiedChinese) == pair.hans)
            #expect(AppLocalization.string(pair.key, language: .traditionalChinese) == pair.hant)
        }
        #expect(AppLocalization.format("%lld photos", language: .english, Int64(1)) == "1 photo")
        #expect(AppLocalization.format("%lld photos", language: .english, Int64(12)) == "12 photos")
        #expect(
            AppLocalization.format("%lld photos", language: .simplifiedChinese, Int64(12))
                == "12 张照片")
        #expect(
            AppLocalization.format("%lld photos", language: .traditionalChinese, Int64(12))
                == "12 張相片")
        #expect(
            AppLocalization.format("Burst of %lld", language: .english, Int64(11))
                == "Burst of 11")
        #expect(
            AppLocalization.format("Burst of %lld", language: .simplifiedChinese, Int64(11))
                == "连拍 11 张")
        #expect(
            AppLocalization.format("Burst of %lld", language: .traditionalChinese, Int64(11))
                == "連拍 11 張")
    }

    @Test func appearanceAndThemeStringsLocalizeAcrossLanguages() {
        let pairs: [(key: String, en: String, hans: String, hant: String)] = [
            ("Appearance", "Appearance", "外观", "外觀"),
            ("Theme", "Theme", "主题", "主題"),
            ("Light", "Light", "浅色", "淺色"),
            ("Dark", "Dark", "深色", "深色"),
            ("System", "System", "跟随系统", "跟隨系統"),
            (
                "System follows your device's appearance and keeps your selected theme.",
                "System follows your device's appearance and keeps your selected theme.",
                "“跟随系统”会跟随设备外观，并保留你选择的主题。",
                "「跟隨系統」會跟隨裝置外觀，並保留你選擇的主題。"
            ),
            (
                "Each theme includes Light and Dark. Photos are never tinted.",
                "Each theme includes Light and Dark. Photos are never tinted.",
                "每个主题均包含浅色和深色。照片本身绝不会偏色。",
                "每個主題均包含淺色與深色。相片本身絕不會偏色。"
            ),
        ]
        for pair in pairs {
            #expect(AppLocalization.string(pair.key, language: .english) == pair.en)
            #expect(AppLocalization.string(pair.key, language: .simplifiedChinese) == pair.hans)
            #expect(AppLocalization.string(pair.key, language: .traditionalChinese) == pair.hant)
        }

        for family in ThemeFamily.allCases {
            for language in [ResolvedAppLanguage.english, .simplifiedChinese, .traditionalChinese] {
                let localized = AppLocalization.themeTitle(family, language: language)
                #expect(!localized.isEmpty)
            }
        }
        #expect(AppLocalization.themeTitle(.default, language: .simplifiedChinese) == "默认")
        #expect(AppLocalization.themeTitle(.default, language: .traditionalChinese) == "預設")
        #expect(AppLocalization.themeTitle(.darkroom, language: .simplifiedChinese) == "暗房")
        #expect(AppLocalization.themeTitle(.night, language: .traditionalChinese) == "夜間")
    }

    @Test func workflowsFigmaStringsLocalizeAcrossLanguages() {
        let pairs: [(key: String, en: String, hans: String, hant: String)] = [
            ("Preparing folder", "Preparing folder", "正在准备文件夹", "正在準備檔案夾"),
            ("Face & focus analysis", "Face & focus analysis", "人脸与对焦分析", "人臉與對焦分析"),
            ("Preview optimization", "Preview optimization", "预览优化", "預覽最佳化"),
            (
                "You can keep browsing. The current photo is prioritized. Originals are unchanged.",
                "You can keep browsing. The current photo is prioritized. Originals are unchanged.",
                "可继续浏览。当前照片会优先处理。原图保持不变。",
                "可繼續瀏覽。目前相片會優先處理。原圖保持不變。"
            ),
            (
                "Cancel discards changes to the order.",
                "Cancel discards changes to the order.",
                "取消将放弃对顺序的更改。",
                "取消將捨棄對順序的變更。"
            ),
            (
                "Preview names before applying changes.",
                "Preview names before applying changes.",
                "应用更改前可预览名称。",
                "套用變更前可預覽名稱。"
            ),
            (
                "Replacements are flagged in the preview.",
                "Replacements are flagged in the preview.",
                "替换操作会在预览中标出。",
                "取代項目會在預覽中標示。"
            ),
        ]
        for pair in pairs {
            #expect(AppLocalization.string(pair.key, language: .english) == pair.en)
            #expect(AppLocalization.string(pair.key, language: .simplifiedChinese) == pair.hans)
            #expect(AppLocalization.string(pair.key, language: .traditionalChinese) == pair.hant)
        }

        #expect(
            AppLocalization.format("%lld photos ready for both", language: .english, Int64(1))
                == "1 photo ready for both")
        #expect(
            AppLocalization.format("%lld photos ready for both", language: .english, Int64(15))
                == "15 photos ready for both")
        #expect(
            AppLocalization.format(
                "%lld photos ready for both", language: .simplifiedChinese, Int64(15))
                == "15 张照片两项均已就绪")
        #expect(
            AppLocalization.format(
                "%lld photos ready for both", language: .traditionalChinese, Int64(15))
                == "15 張相片兩項均已就緒")
    }

    @Test func batchToolbarHeaderAndConfirmationStringsLocalizeAcrossLanguages() {
        let pairs: [(key: String, en: String, hans: String, hant: String)] = [
            ("Save to Photos…", "Save to Photos…", "存储到照片…", "儲存到相片…"),
            ("Select All", "Select All", "全选", "全選"),
            ("Deselect All", "Deselect All", "取消全选", "取消全選"),
            ("Batch actions", "Batch actions", "批量操作", "批次動作"),
            (
                "Confirm Save to Photos & Keywords",
                "Confirm Save to Photos & Keywords",
                "确认存储到照片与关键词",
                "確認儲存到相片與關鍵字"
            ),
            (
                "When enabled, Save to Photos and Add Keywords show a confirmation sheet before applying. When off, they apply immediately.",
                "When enabled, Save to Photos and Add Keywords show a confirmation sheet before applying. When off, they apply immediately.",
                "开启后，存储到照片和添加关键词会在应用前显示确认表单；关闭时立即应用。",
                "開啟後，儲存到相片與加入關鍵字會在套用前顯示確認表單；關閉時會立即套用。"
            ),
            ("Ready to save", "Ready to save", "准备存储", "準備儲存"),
            ("RAW only · skipped", "RAW only · skipped", "仅 RAW · 已跳过", "僅 RAW · 已略過"),
            ("Add Keywords", "Add Keywords", "添加关键词", "加入關鍵字"),
            ("Recent", "Recent", "最近", "最近"),
        ]
        for pair in pairs {
            #expect(AppLocalization.string(pair.key, language: .english) == pair.en)
            #expect(AppLocalization.string(pair.key, language: .simplifiedChinese) == pair.hans)
            #expect(AppLocalization.string(pair.key, language: .traditionalChinese) == pair.hant)
        }

        #expect(
            AppLocalization.format("Save %lld Photos", language: .english, Int64(0))
                == "Save 0 Photos")
        #expect(
            AppLocalization.format("Save %lld Photos", language: .english, Int64(1))
                == "Save 1 Photo")
        #expect(
            AppLocalization.format("Save %lld Photos", language: .english, Int64(3))
                == "Save 3 Photos")
        #expect(
            AppLocalization.format("Save %lld Photos", language: .simplifiedChinese, Int64(3))
                == "存储 3 张照片")
        #expect(
            AppLocalization.format("Save %lld Photos", language: .traditionalChinese, Int64(3))
                == "儲存 3 張相片")

        #expect(
            AppLocalization.format("Add to %lld Photos", language: .english, Int64(1))
                == "Add to 1 Photo")
        #expect(
            AppLocalization.format("Add to %lld Photos", language: .english, Int64(4))
                == "Add to 4 Photos")
        #expect(
            AppLocalization.format("Add to %lld Photos", language: .simplifiedChinese, Int64(4))
                == "添加到 4 张照片")
        #expect(
            AppLocalization.format("Add to %lld Photos", language: .traditionalChinese, Int64(4))
                == "加入到 4 張相片")
    }

    @Test func detailUndoToastLocalizationsCoverSingularPluralAndHiddenByFilter() {
        #expect(
            DetailUndoToast(kind: .rejectedBatch(count: 1)).localizedMessage(language: .english)
                == "Rejected 1 photo")
        #expect(
            DetailUndoToast(kind: .rejectedBatch(count: 6)).localizedMessage(language: .english)
                == "Rejected 6 photos")
        #expect(
            DetailUndoToast(kind: .rejectedBatch(count: 1)).localizedMessage(
                language: .simplifiedChinese) == "已淘汰 1 张照片")
        #expect(
            DetailUndoToast(kind: .rejectedBatch(count: 6)).localizedMessage(
                language: .traditionalChinese) == "已淘汰 6 張相片")

        #expect(
            DetailUndoToast(kind: .hiddenByFilter(action: .rejected)).localizedMessage(
                language: .english) == "Rejected · hidden by filter")
        #expect(
            DetailUndoToast(kind: .hiddenByFilter(action: .rejected)).localizedMessage(
                language: .simplifiedChinese) == "已淘汰 · 因筛选隐藏")
        #expect(
            DetailUndoToast(kind: .hiddenByFilter(action: .rejected)).localizedMessage(
                language: .traditionalChinese) == "已淘汰 · 因篩選隱藏")

        #expect(
            DetailUndoToast(kind: .hiddenByFilter(action: .rated(4))).localizedMessage(
                language: .english) == "4 stars · hidden by filter")
        #expect(
            DetailUndoToast(kind: .hiddenByFilter(action: .labelled(.green))).localizedMessage(
                language: .english) == "Green · hidden by filter")
        #expect(
            DetailUndoToast(kind: .hiddenByFilter(action: .clearedReject)).localizedMessage(
                language: .english) == "Cleared reject · hidden by filter")
        #expect(
            DetailUndoToast(kind: .hiddenByFilter(action: .clearedReject)).localizedMessage(
                language: .simplifiedChinese) == "已取消淘汰 · 因筛选隐藏")
        #expect(
            DetailUndoToast(kind: .hiddenByFilter(action: .clearedReject)).localizedMessage(
                language: .traditionalChinese) == "已取消淘汰 · 因篩選隱藏")

        #expect(
            DetailUndoToast.Action(
                change: .rating(.unrated), previousMarks: PhotoMarks(rating: .rejected))
                == .clearedReject)
        #expect(
            DetailUndoToast.Action(
                change: .rating(.unrated),
                previousMarks: PhotoMarks(rating: Rating(rawValue: 3)!))
                == .clearedRating)
        #expect(
            DetailUndoToast.Action(
                change: .label(.clear),
                previousMarks: PhotoMarks(label: ColourLabel(colour: .blue)))
                == .clearedLabel)
    }

    @Test func gridAllReviewedLocalizesAcrossLanguagesAndCounts() {
        #expect(
            AppLocalization.string("Show all photos", language: .english) == "Show all photos")
        #expect(
            AppLocalization.string("Show all photos", language: .simplifiedChinese) == "显示全部照片")
        #expect(
            AppLocalization.string("Show all photos", language: .traditionalChinese) == "顯示全部相片")

        let summary = GridReviewSummary(
            totalCount: 24, highRatedCount: 12, ratedCount: 14, labelledOnlyCount: 0,
            rejectedCount: 5, moveRejectsEnabled: true)
        #expect(summary.localizedTitle(language: .english) == "All 24 photos reviewed")
        #expect(summary.localizedTitle(language: .simplifiedChinese) == "全部 24 张照片已审阅")
        #expect(summary.localizedTitle(language: .traditionalChinese) == "全部 24 張相片已審閱")
        #expect(summary.localizedSubtitle(language: .english) == "12 ★4+ · 5 rejected")
        #expect(summary.localizedSubtitle(language: .simplifiedChinese) == "12 张 ★4+ · 5 张已淘汰")
        #expect(summary.localizedSubtitle(language: .traditionalChinese) == "12 張 ★4+ · 5 張已淘汰")
        #expect(summary.localizedMoveRejectsTitle(language: .english) == "Move 5 rejects")
        #expect(summary.localizedMoveRejectsTitle(language: .simplifiedChinese) == "整理 5 张淘汰片")
        #expect(summary.localizedMoveRejectsTitle(language: .traditionalChinese) == "整理 5 張淘汰片")
    }
}
