import CloveCore
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct SettingsAdaptiveTests {
    @Test func wideLayoutRequiresRegularSizeClassAndSufficientWidth() {
        #expect(SettingsLayoutMode.isWide(horizontalSizeClass: .regular, availableWidth: 768))
        #expect(SettingsLayoutMode.isWide(horizontalSizeClass: .regular, availableWidth: 680))
        #expect(!SettingsLayoutMode.isWide(horizontalSizeClass: .regular, availableWidth: 679))
        #expect(!SettingsLayoutMode.isWide(horizontalSizeClass: .compact, availableWidth: 900))
        #expect(!SettingsLayoutMode.isWide(horizontalSizeClass: .compact, availableWidth: 390))
        #expect(!SettingsLayoutMode.isWide(horizontalSizeClass: nil, availableWidth: 1024))
    }

    @Test func categorySelectionPersistsAcrossCompactAndWideTransitions() {
        let navigation = SettingsNavigationState()
        #expect(navigation.selectedCategory == .appearance)
        #expect(!navigation.showsCompactDetail)

        navigation.openCompactCategory(.browsingAndGroups)
        #expect(navigation.selectedCategory == .browsingAndGroups)
        #expect(navigation.showsCompactDetail)

        // Widening keeps the selected category and prepares compact fallback on later shrink.
        navigation.layoutChanged(isWide: true)
        #expect(navigation.selectedCategory == .browsingAndGroups)

        // Shrinking back keeps the selected category active in compact detail.
        navigation.layoutChanged(isWide: false)
        #expect(navigation.selectedCategory == .browsingAndGroups)
        #expect(navigation.showsCompactDetail)

        // Selecting in wide mode and shrinking keeps the newly selected category.
        navigation.layoutChanged(isWide: true)
        navigation.selectCategory(.moveRejects, wide: true)
        navigation.layoutChanged(isWide: false)
        #expect(navigation.selectedCategory == .moveRejects)
        #expect(navigation.showsCompactDetail)
    }

    @Test func subpagePreservesCullingParentCategoryAcrossResizes() {
        let navigation = SettingsNavigationState()
        navigation.openSubpage(.ratingScale)
        #expect(navigation.selectedCategory == .cullingAndMarking)
        #expect(navigation.activeSubpage == .ratingScale)

        navigation.layoutChanged(isWide: true)
        #expect(navigation.selectedCategory == .cullingAndMarking)
        #expect(navigation.activeSubpage == .ratingScale)

        navigation.layoutChanged(isWide: false)
        #expect(navigation.selectedCategory == .cullingAndMarking)
        #expect(navigation.activeSubpage == .ratingScale)
        #expect(navigation.showsCompactDetail)

        navigation.resetOnExit()
        #expect(navigation.activeSubpage == nil)
        #expect(!navigation.showsCompactDetail)
    }

    @Test func stayDisablesAutoAdvanceWhilePreservingTriggers() {
        let storage = SampleSettingsStorage()
        let store = SettingsStore(
            persistence: SettingsPersistence(storage: storage),
            rememberedAdvanceStorage: storage,
            physicalMemory: 8 * 1024 * 1024 * 1024)

        store.update {
            $0.autoAdvance.triggers.rating = false
            $0.autoAdvance.triggers.colourLabel = true
            $0.autoAdvance.destination = .stay
        }

        #expect(!store.settings.autoAdvance.shouldAdvance(after: .rating))
        #expect(!store.settings.autoAdvance.shouldAdvance(after: .reject))
        #expect(!store.settings.autoAdvance.shouldAdvance(after: .colourLabel))
        #expect(!store.settings.autoAdvance.triggers.rating)
        #expect(store.settings.autoAdvance.triggers.reject)
        #expect(store.settings.autoAdvance.triggers.colourLabel)

        store.update { $0.autoAdvance.destination = .nextUnmarkedPhoto }
        #expect(!store.settings.autoAdvance.shouldAdvance(after: .rating))
        #expect(store.settings.autoAdvance.shouldAdvance(after: .reject))
        #expect(store.settings.autoAdvance.shouldAdvance(after: .colourLabel))
    }

    @Test func resetRestoresPreferencesWithoutClearingInjectedDefaultMode() {
        let storage = SampleSettingsStorage()
        let store = SettingsStore(
            persistence: SettingsPersistence(storage: storage),
            rememberedAdvanceStorage: storage,
            physicalMemory: 4 * 1024 * 1024 * 1024)

        store.update {
            $0.moveRejectsEnabled = false
            $0.rejectsFolderName =
                (try? RejectsFolderName.validated("_Trash")) ?? .defaultFolderName
            $0.photoDisplayMode = .rawFirst
            $0.zoomedGestures = .pan
            $0.doubleTap = .zoomToTapPoint
            $0.appearance = AppearanceChoice(mode: .dark, family: .nord)
            $0.similarGroupsEnabled = false
            $0.groupingSensitivity = .timeOnly
            $0.groupingTimeWindow = .tenSeconds
        }
        #expect(store.photoDisplayMode == .rawFirst)
        #expect(store.settings.groupingSensitivity == .timeOnly)
        #expect(store.settings.groupingTimeWindow == .tenSeconds)

        store.resetToDefaults()
        #expect(store.settings == AppSettings())
        #expect(store.settings.appearance == AppearanceChoice(mode: .system, family: .default))
        #expect(store.settings.similarGroupsEnabled)
        #expect(store.settings.groupingSensitivity == .standard)
        #expect(store.settings.groupingTimeWindow == .twoSeconds)
        #expect(store.photoDisplayMode == .cameraPreviewFirst)
    }

    @Test func disablingSimilarGroupsPreservesTimeWindowAndSensitivity() {
        let storage = SampleSettingsStorage()
        let persistence = SettingsPersistence(storage: storage)
        let store = SettingsStore(
            persistence: persistence,
            rememberedAdvanceStorage: storage,
            physicalMemory: 8 * 1024 * 1024 * 1024)

        store.update {
            $0.groupingTimeWindow = .fiveSeconds
            $0.groupingSensitivity = .loose
        }
        store.update { $0.similarGroupsEnabled = false }

        #expect(!store.settings.similarGroupsEnabled)
        #expect(store.settings.groupingTimeWindow == .fiveSeconds)
        #expect(store.settings.groupingSensitivity == .loose)
        #expect(persistence.load().groupingTimeWindow == .fiveSeconds)
        #expect(persistence.load().groupingSensitivity == .loose)

        store.update { $0.similarGroupsEnabled = true }
        #expect(store.settings.groupingTimeWindow == .fiveSeconds)
        #expect(store.settings.groupingSensitivity == .loose)
    }

    @Test func independentAppearanceModeAndFamilyUpdatesPersistAndReset() {
        let storage = SampleSettingsStorage()
        let persistence = SettingsPersistence(storage: storage)
        let store = SettingsStore(
            persistence: persistence,
            rememberedAdvanceStorage: storage,
            physicalMemory: 8 * 1024 * 1024 * 1024)

        #expect(store.settings.appearance == AppearanceChoice(mode: .system, family: .default))

        store.update { $0.appearance.family = .catppuccin }
        #expect(store.settings.appearance == AppearanceChoice(mode: .system, family: .catppuccin))
        #expect(
            persistence.load().appearance == AppearanceChoice(mode: .system, family: .catppuccin))

        store.update { $0.appearance.mode = .light }
        #expect(store.settings.appearance == AppearanceChoice(mode: .light, family: .catppuccin))
        #expect(
            persistence.load().appearance == AppearanceChoice(mode: .light, family: .catppuccin))

        store.update { $0.appearance.family = .gruvbox }
        #expect(store.settings.appearance == AppearanceChoice(mode: .light, family: .gruvbox))
        #expect(persistence.load().appearance == AppearanceChoice(mode: .light, family: .gruvbox))

        store.update { $0.appearance.mode = .system }
        #expect(store.settings.appearance == AppearanceChoice(mode: .system, family: .gruvbox))
        #expect(persistence.load().appearance == AppearanceChoice(mode: .system, family: .gruvbox))

        store.resetToDefaults()
        #expect(store.settings.appearance == AppearanceChoice(mode: .system, family: .default))
        #expect(persistence.load().appearance == AppearanceChoice(mode: .system, family: .default))
    }

    @Test func resizingBrowseShellWhileOnSettingsPreservesWidthTransition() async throws {
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        model.showSettings()
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(
            rootView: BrowseShell(browsing: model).environment(SettingsStore.sample))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 1000)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        host.traitOverrides.horizontalSizeClass = .regular
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state.route == .settings)

        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.traitOverrides.horizontalSizeClass = .compact
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state.route == .settings)
    }

    @Test func systemAppearanceReaderTracksWindowSceneChangesAcrossWindowOverride() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousSceneStyle: UIUserInterfaceStyle? =
            scene.traitOverrides.contains(UITraitUserInterfaceStyle.self)
            ? scene.traitOverrides.userInterfaceStyle
            : nil
        scene.traitOverrides.userInterfaceStyle = .light
        defer {
            if let previousSceneStyle {
                scene.traitOverrides.userInterfaceStyle = previousSceneStyle
            } else {
                scene.traitOverrides.remove(UITraitUserInterfaceStyle.self)
            }
        }

        var reported: [ThemeAppearance] = []
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        // Simulate forced Light mode on the window while the scene changes underneath.
        window.overrideUserInterfaceStyle = .light
        let host = UIHostingController(
            rootView: SystemAppearanceReader { appearance in
                if reported.last != appearance { reported.append(appearance) }
            })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await Task.sleep(for: .milliseconds(50))
        #expect(reported.last == .light)

        scene.traitOverrides.userInterfaceStyle = .dark
        try await Task.sleep(for: .milliseconds(50))
        #expect(reported.last == .dark)

        scene.traitOverrides.userInterfaceStyle = .light
        try await Task.sleep(for: .milliseconds(50))
        #expect(reported.last == .light)
    }

    @Test func wideSplitSeparatesSidebarAndDetailCardsFromDivider() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        for size in [
            CGSize(width: 1024, height: 768),
            CGSize(width: 840, height: 680),
            CGSize(width: 680, height: 680),
        ] {
            let navigation = SettingsNavigationState()
            let framesBox = TestSettingsFramesBox()
            let host = UIHostingController(
                rootView: SettingsScreen(navigation: navigation, availableWidth: size.width)
                    .environment(SettingsStore.sample)
                    .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                        framesBox.frames = frames
                    })
            host.traitOverrides.horizontalSizeClass = .regular
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitForLayout("wide split layout did not stabilize at \(size)") {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                let collections = self.findSubviews(ofType: UICollectionView.self, in: window)
                return framesBox.frames["clove.settings.wideDivider"] != nil
                    && framesBox.frames["clove.settings.detailTitle"] != nil
                    && SettingsCategory.allCases.allSatisfy {
                        framesBox.frames["\($0.identifier).title"] != nil
                    }
                    && collections.count == 2
                    && collections.allSatisfy { !$0.visibleCells.isEmpty }
            }

            let divider = try #require(framesBox.frames["clove.settings.wideDivider"])
            #expect(divider.width > 0 && divider.width <= 1)

            let collections = findSubviews(ofType: UICollectionView.self, in: window)
                .sorted {
                    $0.convert($0.bounds, to: window).minX
                        < $1.convert($1.bounds, to: window).minX
                }
            let sidebarCollection = try #require(collections.first)
            let detailCollection = try #require(collections.last)
            let sidebarCollectionFrame = sidebarCollection.convert(
                sidebarCollection.bounds, to: window)
            let detailCollectionFrame = detailCollection.convert(
                detailCollection.bounds, to: window)

            // Both Lists span cleanly to the divider so gutters stay touchable and scroll
            // indicators are not clipped inward against the cards.
            #expect(abs(sidebarCollectionFrame.maxX - divider.minX) <= 1)
            #expect(abs(detailCollectionFrame.minX - divider.maxX) <= 1)
            #expect(sidebarCollection.contentSize.width <= sidebarCollection.bounds.width + 1)
            #expect(detailCollection.contentSize.width <= detailCollection.bounds.width + 1)

            let sidebarCells = sidebarCollection.visibleCells.sorted {
                $0.frame.minY < $1.frame.minY
            }
            #expect(sidebarCells.count == SettingsCategory.allCases.count + 1)
            for cell in sidebarCells {
                let cellFrame = cell.convert(cell.bounds, to: window)
                #expect(cellFrame.minX >= 14)
                #expect(divider.minX - cellFrame.maxX >= 14)
                #expect(divider.minX - cellFrame.maxX >= 16)
                #expect(cellFrame.height <= 56)
            }

            let firstSidebarCell = try #require(sidebarCells.first)
                .convert(try #require(sidebarCells.first).bounds, to: window)
            try verifySidebarTitlesSingleLineAndUntruncated(
                frames: framesBox.frames,
                selected: navigation.selectedCategory,
                cardMaxX: firstSidebarCell.maxX)

            let appearanceTitle = try #require(framesBox.frames["clove.settings.detailTitle"])
            #expect(appearanceTitle.minX - divider.maxX >= 16)

            let appearanceDetailCells = detailCollection.visibleCells.sorted {
                $0.frame.minY < $1.frame.minY
            }
            #expect(!appearanceDetailCells.isEmpty)
            for cell in appearanceDetailCells {
                let cellFrame = cell.convert(cell.bounds, to: window)
                #expect(cellFrame.minX - divider.maxX >= 14)
                #expect(cellFrame.minX - divider.maxX >= 16)
                #expect(size.width - cellFrame.maxX >= 14)
            }
            let firstDetailCell = try #require(appearanceDetailCells.first)
                .convert(try #require(appearanceDetailCells.first).bounds, to: window)
            let sidebarGap = divider.minX - firstSidebarCell.maxX
            let detailGap = firstDetailCell.minX - divider.maxX
            #expect(abs(sidebarGap - detailGap) <= 1)

            // Switch to Culling & marking (long selected title + dual section header).
            navigation.selectCategory(.cullingAndMarking, wide: true)
            try await waitForLayout("culling detail did not update at \(size)") {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                guard let currentTitle = framesBox.frames["clove.settings.detailTitle"] else {
                    return false
                }
                let updatedCollections = self.findSubviews(
                    ofType: UICollectionView.self, in: window
                ).sorted {
                    $0.convert($0.bounds, to: window).minX
                        < $1.convert($1.bounds, to: window).minX
                }
                return currentTitle.width > appearanceTitle.width + 10
                    && updatedCollections.count == 2
                    && !updatedCollections[1].visibleCells.isEmpty
            }

            try verifySidebarTitlesSingleLineAndUntruncated(
                frames: framesBox.frames,
                selected: .cullingAndMarking,
                cardMaxX: firstSidebarCell.maxX)

            let cullingTitle = try #require(framesBox.frames["clove.settings.detailTitle"])
            #expect(cullingTitle.minX - divider.maxX >= 16)

            let updatedDetailCollection = try #require(
                findSubviews(ofType: UICollectionView.self, in: window)
                    .sorted {
                        $0.convert($0.bounds, to: window).minX
                            < $1.convert($1.bounds, to: window).minX
                    }
                    .last)
            for cell in updatedDetailCollection.visibleCells {
                let cellFrame = cell.convert(cell.bounds, to: window)
                #expect(cellFrame.minX - divider.maxX >= 14)
                #expect(cellFrame.minX - divider.maxX >= 16)
                #expect(size.width - cellFrame.maxX >= 14)
            }
        }
    }

    private func verifySidebarTitlesSingleLineAndUntruncated(
        frames: [String: CGRect],
        selected: SettingsCategory,
        cardMaxX: CGFloat
    ) throws {
        let baseBodyFont = UIFont.preferredFont(forTextStyle: .body)
        for category in SettingsCategory.allCases {
            let titleFrame = try #require(frames["\(category.identifier).title"])
            let weight: UIFont.Weight = category == selected ? .medium : .regular
            let font = UIFont.systemFont(ofSize: baseBodyFont.pointSize, weight: weight)
            let expectedSize = (category.title as NSString).size(withAttributes: [.font: font])

            #expect(titleFrame.height <= ceil(font.lineHeight) + 4)
            #expect(titleFrame.width >= floor(expectedSize.width) - 2)
            #expect(titleFrame.maxX <= cardMaxX - 8)
        }
    }

    private func waitForLayout(
        _ message: String,
        timeout: Duration = .seconds(3),
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                Issue.record(Comment(rawValue: message))
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func findSubviews<T: UIView>(ofType type: T.Type, in root: UIView) -> [T] {
        var matches: [T] = []
        if let match = root as? T { matches.append(match) }
        for subview in root.subviews {
            matches.append(contentsOf: findSubviews(ofType: type, in: subview))
        }
        return matches
    }
}

@MainActor
@Observable
private final class TestSettingsFramesBox {
    var frames: [String: CGRect] = [:]
}
