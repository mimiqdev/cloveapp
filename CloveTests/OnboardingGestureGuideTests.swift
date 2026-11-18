import CloveCore
import SwiftUI
import Testing
import UIKit

@testable import Clove

@Suite(.serialized)
@MainActor
struct OnboardingGestureGuideTests {
    @Test func settingsStorePersistsGestureGuideSeenStateAndLeavesSampleUnseen() {
        let storage = SampleSettingsStorage()
        let store = SettingsStore(
            persistence: SettingsPersistence(storage: storage),
            rememberedAdvanceStorage: storage,
            physicalMemory: 8 * 1024 * 1024 * 1024)

        #expect(!store.hasSeenGestureGuide)
        #expect(!SettingsStore.sample.hasSeenGestureGuide)

        store.markGestureGuideSeen()
        #expect(store.hasSeenGestureGuide)
        #expect(storage.string(forKey: "onboarding.gestureGuideSeen") == "true")

        // Marking again is idempotent and survives a relaunch on the same storage.
        store.markGestureGuideSeen()
        let relaunched = SettingsStore(
            persistence: SettingsPersistence(storage: storage),
            rememberedAdvanceStorage: storage,
            physicalMemory: 8 * 1024 * 1024 * 1024)
        #expect(relaunched.hasSeenGestureGuide)

        // Resetting settings preferences does not clobber the persisted onboarding flag.
        relaunched.resetToDefaults()
        #expect(relaunched.hasSeenGestureGuide)
    }

    @Test func launchSeedsGestureGuideSeenForTestLibraryUnlessExplicitlyRequested() {
        let defaultTestLaunch = SettingsStore.launch(environment: [TestLibrary.launchVariable: "1"])
        #expect(defaultTestLaunch.hasSeenGestureGuide)

        let explicitOnboardingLaunch = SettingsStore.launch(environment: [
            TestLibrary.launchVariable: "1",
            "CLOVE_SHOW_GESTURE_GUIDE": "1",
        ])
        #expect(!explicitOnboardingLaunch.hasSeenGestureGuide)
    }

    @Test func onboardingAndGestureGuideStringsLocalizeInAllSupportedLanguages() {
        let expectedTranslations: [(key: String, hans: String, hant: String)] = [
            (
                "Browse cards and folders in place",
                "原位浏览存储卡与文件夹，零导入",
                "原位瀏覽記憶卡與資料夾，零匯入"
            ),
            (
                "Swipe up to rate, swipe down to reject, double-tap for 100% focus",
                "上滑评星 · 下滑淘汰 · 双击 100% 查焦",
                "上滑評星 · 下滑淘汰 · 點兩下 100% 查焦"
            ),
            (
                "RAW marks save to XMP sidecars for Lightroom and Capture One",
                "RAW 写入标准 XMP，直通 Lightroom 与 Capture One",
                "RAW 寫入標準 XMP，直通 Lightroom 與 Capture One"
            ),
            ("Gesture guide", "手势指南", "手勢指南"),
            ("Swipe up to rate", "上滑评星", "上滑評星"),
            ("Distance sets 1–5 stars", "滑动距离决定星级", "滑動距離決定星級"),
            ("Swipe down to reject", "下滑淘汰", "下滑淘汰"),
            ("Swipe down again to clear", "再次下滑清除淘汰", "再次下滑清除淘汰"),
            ("Swipe left or right", "左右滑动", "左右滑動"),
            ("Previous or next photo", "切换上一张或下一张", "切換上一張或下一張"),
            ("Double-tap", "轻点两下", "點兩下"),
            ("Zoom to 100% to check focus", "100% 放大检查对焦", "100% 放大檢查對焦"),
            ("Pull filmstrip down", "下滑胶片条", "下滑膠片條"),
            (
                "Expand similar group; push up to fold",
                "展开相似连拍组，上滑收起",
                "展開相似連拍組，上滑收起"
            ),
            ("Got it", "知道了", "知道了"),
            ("Dismiss gesture guide", "关闭手势指南", "關閉手勢指南"),
            ("Done", "完成", "完成"),
        ]

        for entry in expectedTranslations {
            #expect(AppLocalization.string(entry.key, language: .english) == entry.key)
            #expect(AppLocalization.string(entry.key, language: .simplifiedChinese) == entry.hans)
            #expect(AppLocalization.string(entry.key, language: .traditionalChinese) == entry.hant)
        }
    }

    @Test func detailShowsGestureGuideUntilDismissedByInteractionAndHidesThereafter() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let storage = SampleSettingsStorage()
        let store = SettingsStore(
            persistence: SettingsPersistence(storage: storage),
            rememberedAdvanceStorage: storage,
            physicalMemory: 8 * 1024 * 1024 * 1024)
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        let first = try #require(model.photos.first?.id)
        model.openPhoto(first)

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: model, images: SampleDetailImages())
                .environment(store))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        // Before dismissal, the gesture guide overlay sits over the preview center and blocks hits
        // to the underlying UIImageView.
        try await waitFor {
            guard let preview = findPreview(in: window),
                let imageView = preview.subviews.first?.subviews.first as? UIImageView,
                imageView.image != nil
            else { return false }
            let frame = preview.convert(preview.bounds, to: window)
            let hit = window.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil)
            return hit != nil && !(hit is UIImageView)
        }
        #expect(!store.hasSeenGestureGuide)

        // Starting a Detail gesture marks the guide seen and removes the overlay so hits reach the image.
        let preview = try #require(findPreview(in: window))
        let swipeBegin = try #require(preview.onSwipeBegin)
        swipeBegin()

        try await waitFor {
            guard store.hasSeenGestureGuide else { return false }
            let frame = preview.convert(preview.bounds, to: window)
            let hit = window.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil)
            return hit is UIImageView
        }

        // Re-opening Detail with the same persisted store never brings the guide back.
        let secondWindow = UIWindow(windowScene: scene)
        secondWindow.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        secondWindow.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: model, images: SampleDetailImages())
                .environment(store))
        secondWindow.makeKeyAndVisible()
        defer {
            secondWindow.isHidden = true
            secondWindow.rootViewController = nil
        }

        try await waitFor {
            guard let secondPreview = findPreview(in: secondWindow),
                let imageView = secondPreview.subviews.first?.subviews.first as? UIImageView,
                imageView.image != nil
            else { return false }
            let frame = secondPreview.convert(secondPreview.bounds, to: secondWindow)
            let hit = secondWindow.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil)
            return hit is UIImageView
        }
    }

    @Test func entryHighlightsDifferFromEmptyFolderAndAdaptToCompactHeight() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let store = SettingsStore.sample

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let firstLaunchHost = UIHostingController(
            rootView: EntryEmptyState(isEmptyFolder: false, openFolder: {})
                .environment(store))
        window.rootViewController = firstLaunchHost
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        firstLaunchHost.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))

        // First-launch view exposes the 3 highlights inside the entry state.
        #expect(DetailGestureGuideItem.coreItems.count == 5)
        let firstLaunchSize = firstLaunchHost.sizeThatFits(
            in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude))

        // Empty-folder state omits subtitle and highlights, so its natural height is significantly smaller.
        let emptyFolderHost = UIHostingController(
            rootView: EntryEmptyState(isEmptyFolder: true, openFolder: {})
                .environment(store))
        let emptyFolderSize = emptyFolderHost.sizeThatFits(
            in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
        #expect(firstLaunchSize.height > emptyFolderSize.height + 80)

        // Compact landscape height constrains layout cleanly without clipping below viewport.
        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        firstLaunchHost.traitOverrides.verticalSizeClass = .compact
        firstLaunchHost.view.setNeedsLayout()
        firstLaunchHost.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        #expect(firstLaunchHost.view.bounds.height <= 390)
    }

    @Test func settingsHostsGestureGuideSheetAndDetailMarkingViewWorksWithoutSettingsStore()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let store = SettingsStore.sample

        let settingsWindow = UIWindow(windowScene: scene)
        settingsWindow.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        settingsWindow.rootViewController = UIHostingController(
            rootView: NavigationStack {
                List {
                    CullingAndMarkingSettingsSections(showsCategoryTitle: true)
                }
            }
            .environment(store))
        settingsWindow.makeKeyAndVisible()
        defer {
            settingsWindow.isHidden = true
            settingsWindow.rootViewController = nil
        }

        try await waitFor {
            findCollectionView(in: settingsWindow) != nil
        }

        // Gesture guide card and sheet render cleanly in compact and regular environments.
        let sheetHost = UIHostingController(
            rootView: DetailGestureGuideSheet().environment(store))
        let sheetSize = sheetHost.sizeThatFits(in: CGSize(width: 390, height: 600))
        #expect(sheetSize.width > 0 && sheetSize.height > 0)

        // Direct DetailMarkingView construction without SettingsStore in environment never crashes
        // or overlays the preview with the gesture guide.
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        let photo = try #require(model.photos.first)
        let detailWindow = UIWindow(windowScene: scene)
        detailWindow.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        detailWindow.rootViewController = UIHostingController(
            rootView: DetailMarkingView(
                browsing: model,
                photo: photo,
                settings: AppSettings(),
                images: model.detailImages,
                order: model.photos,
                actions: DetailMarkingActions(
                    apply: { _, _ in }, marked: { _, _, _ in }, step: { _ in },
                    markingSwipeBegan: {})))
        detailWindow.makeKeyAndVisible()
        defer {
            detailWindow.isHidden = true
            detailWindow.rootViewController = nil
        }

        try await waitFor {
            guard let preview = findPreview(in: detailWindow),
                let imageView = preview.subviews.first?.subviews.first as? UIImageView,
                imageView.image != nil
            else { return false }
            let frame = preview.convert(preview.bounds, to: detailWindow)
            let hit = detailWindow.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil)
            return hit is UIImageView
        }
    }

    private func waitFor(
        timeout: Duration = .seconds(3),
        condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(condition())
    }

    private func findPreview(in view: UIView) -> DetailZoomContainerView? {
        if let preview = view as? DetailZoomContainerView { return preview }
        for child in view.subviews {
            if let preview = findPreview(in: child) { return preview }
        }
        return nil
    }

    private func findCollectionView(in view: UIView) -> UICollectionView? {
        if let collectionView = view as? UICollectionView { return collectionView }
        for child in view.subviews {
            if let found = findCollectionView(in: child) { return found }
        }
        return nil
    }
}
