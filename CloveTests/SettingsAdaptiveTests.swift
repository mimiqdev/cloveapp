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
            $0.confirmBatchActions = true
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
        #expect(!store.settings.confirmBatchActions)
        #expect(store.photoDisplayMode == .cameraPreviewFirst)
    }

    @Test func cullingSettingsIncludesBatchActionsConfirmationToggleAndPersists() async throws {
        let storage = SampleSettingsStorage()
        let persistence = SettingsPersistence(storage: storage)
        let store = SettingsStore(
            persistence: persistence,
            rememberedAdvanceStorage: storage,
            physicalMemory: 8 * 1024 * 1024 * 1024)
        #expect(!store.settings.confirmBatchActions)

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(
            rootView: List {
                CullingAndMarkingSettingsSections(showsCategoryTitle: false)
            }
            .listStyle(.insetGrouped)
            .environment(store)
            .environment(\.cloveTheme, .light))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitForLayout("culling settings list did not settle") {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            guard
                let collection = self.findSubviews(ofType: UICollectionView.self, in: window).first
            else {
                return false
            }
            return collection.numberOfSections == 4
                && collection.numberOfItems(inSection: 3) == 1
        }

        store.update { $0.confirmBatchActions = true }
        #expect(persistence.load().confirmBatchActions)
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
            CGSize(width: 1366, height: 1024),
            CGSize(width: 1024, height: 768),
            CGSize(width: 840, height: 680),
            CGSize(width: 680, height: 680),
        ] {
            let navigation = SettingsNavigationState()
            let framesBox = TestSettingsFramesBox()
            let host = UIHostingController(
                rootView: SettingsScreen(navigation: navigation, availableWidth: size.width)
                    .environment(SettingsStore.sample)
                    .environment(\.cloveTheme, .light)
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
                    && framesBox.frames["clove.settings.sidebarTitle"] != nil
                    && framesBox.frames["clove.settings.detailTitle"] != nil
                    && framesBox.frames["clove.settings.done"] != nil
                    && SettingsCategory.allCases.allSatisfy {
                        framesBox.frames["\($0.identifier).title"] != nil
                    }
                    && collections.count == 2
                    && collections.allSatisfy { !$0.visibleCells.isEmpty }
            }

            let divider = try #require(framesBox.frames["clove.settings.wideDivider"])
            #expect(divider.width > 0 && divider.width <= 1)

            let sidebarTitle = try #require(framesBox.frames["clove.settings.sidebarTitle"])
            #expect(sidebarTitle.minX >= 20 - 0.5)
            #expect(divider.minX - sidebarTitle.maxX >= 20 - 0.5)

            let doneFrame = try #require(framesBox.frames["clove.settings.done"])
            #expect(doneFrame.minX > divider.maxX)
            #expect(size.width - doneFrame.maxX >= 20 - 0.5)

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

            let expectedSheet = try renderedRGBA(CloveTheme.light.tokens.sheet.color)
            let expectedCard = try renderedRGBA(CloveTheme.light.tokens.card.color)
            let windowSnapshot = windowPixels(from: window)

            let sidebarCells = sidebarCollection.visibleCells.sorted {
                $0.frame.minY < $1.frame.minY
            }
            #expect(sidebarCells.count == SettingsCategory.allCases.count + 1)
            for (index, cell) in sidebarCells.enumerated() {
                let cellFrame = cell.convert(cell.bounds, to: window)
                #expect(cellFrame.minX >= 14)
                #expect(divider.minX - cellFrame.maxX >= 19.5)
                #expect(cellFrame.height <= 56)

                // Only the selected category carries a card background; other sidebar rows and
                // Reset sit directly on `surface/sheet`.
                let sampleX = Int((cellFrame.maxX - 8).rounded())
                let sampleY = Int(cellFrame.midY.rounded())
                let pixel = windowSnapshot.pixel(x: sampleX, y: sampleY)
                if index == 0 {
                    assertRGBAClose(pixel, expectedCard, "selected sidebar row card background")
                } else {
                    assertRGBAClose(pixel, expectedSheet, "unselected sidebar row sits on sheet")
                }
            }

            let firstSidebarCell = try #require(sidebarCells.first)
                .convert(try #require(sidebarCells.first).bounds, to: window)
            try verifySidebarTitlesSingleLineAndUntruncated(
                frames: framesBox.frames,
                selected: navigation.selectedCategory,
                cardMaxX: firstSidebarCell.maxX)

            let appearanceTitle = try #require(framesBox.frames["clove.settings.detailTitle"])
            #expect(appearanceTitle.minX - divider.maxX >= 19.5)

            let appearanceDetailCells = detailCollection.visibleCells.sorted {
                $0.frame.minY < $1.frame.minY
            }
            #expect(!appearanceDetailCells.isEmpty)
            for cell in appearanceDetailCells {
                let cellFrame = cell.convert(cell.bounds, to: window)
                #expect(cellFrame.minX - divider.maxX >= 19.5)
                #expect(size.width - cellFrame.maxX >= 19.5)
                #expect(cellFrame.width <= 640.5)
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
            #expect(cullingTitle.minX - divider.maxX >= 19.5)

            let updatedDetailCollection = try #require(
                findSubviews(ofType: UICollectionView.self, in: window)
                    .sorted {
                        $0.convert($0.bounds, to: window).minX
                            < $1.convert($1.bounds, to: window).minX
                    }
                    .last)
            for cell in updatedDetailCollection.visibleCells {
                let cellFrame = cell.convert(cell.bounds, to: window)
                #expect(cellFrame.minX - divider.maxX >= 19.5)
                #expect(size.width - cellFrame.maxX >= 19.5)
                #expect(cellFrame.width <= 640.5)
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

    @Test func pairedThemeTileMatchesReferenceGeometryAndRendersLightDarkMiniCards() throws {
        #expect(ThemeTile.tileSize == CGSize(width: 108, height: 94))
        #expect(ThemeTile.previewSize == CGSize(width: 108, height: 68))
        #expect(ThemeTile.previewCornerRadius == 10)
        #expect(ThemeTile.previewPadding == 4)
        #expect(ThemeTile.cardGap == 4)
        #expect(ThemeTile.cardSize == CGSize(width: 48, height: 60))
        #expect(ThemeTile.cardCornerRadius == 6)
        #expect(ThemeTile.selectionBorderWidth == 1.5)

        let hosted = UIHostingController(
            rootView: ThemeTile(family: .catppuccin, isSelected: true)
                .environment(\.cloveTheme, .light))
        let fittedSize = hosted.sizeThatFits(in: CGSize(width: 400, height: 400))
        #expect(abs(fittedSize.width - 108) <= 0.5)
        #expect(abs(fittedSize.height - 94) <= 1.0)

        let lightSample = try renderTilePixels(
            ThemeTile(family: .catppuccin, isSelected: false),
            theme: .light)
        let darkSelectedSample = try renderTilePixels(
            ThemeTile(family: .catppuccin, isSelected: true),
            theme: .dark)
        let lightSelectedSample = try renderTilePixels(
            ThemeTile(family: .catppuccin, isSelected: true),
            theme: .light)

        // Left mini-card stage uses Catppuccin Latte (`stage` = #DCE0E8), right uses Mocha (#11111B).
        let expectedLatteStage = try renderedRGBA(
            ThemeFamily.catppuccin.lightTheme.tokens.stage.color)
        let expectedMochaStage = try renderedRGBA(
            ThemeFamily.catppuccin.darkTheme.tokens.stage.color)
        assertRGBAClose(lightSample.pixel(x: 20, y: 40), expectedLatteStage, "left mini-card stage")
        assertRGBAClose(
            lightSample.pixel(x: 196, y: 40), expectedMochaStage, "right mini-card stage")

        // Sample photo pixels stay identical across Light/Dark mini-cards and active themes.
        let leftPhotoPixel = lightSample.pixel(x: 56, y: 46)
        let rightPhotoPixel = lightSample.pixel(x: 160, y: 46)
        let darkThemeLeftPhotoPixel = darkSelectedSample.pixel(x: 56, y: 46)
        assertRGBAClose(leftPhotoPixel, rightPhotoPixel, "photo untinted between light/dark")
        assertRGBAClose(
            leftPhotoPixel, darkThemeLeftPhotoPixel, "photo untinted across active themes")

        // Selected tile renders the 1.5 pt accent selection border and bottom-right checkmark badge.
        let expectedLightAccent = try renderedRGBA(CloveTheme.light.tokens.accent.color)
        let expectedDarkAccent = try renderedRGBA(CloveTheme.dark.tokens.accent.color)
        assertRGBAClose(
            lightSelectedSample.pixel(x: 108, y: 1), expectedLightAccent,
            "selected light border top")
        assertRGBAClose(
            darkSelectedSample.pixel(x: 108, y: 1), expectedDarkAccent,
            "selected dark border top")

        // Badge area near bottom-right corner of 108 x 68 preview frame (scale 2 => 216 x 136):
        // unselected shows Mocha canvas (#1E1E2E), selected shows accent circle + white glyph.
        let unselectedCornerRegion = (182...202).flatMap { x in
            (102...122).map { y in lightSample.pixel(x: x, y: y) }
        }
        let selectedCornerRegion = (182...202).flatMap { x in
            (102...122).map { y in lightSelectedSample.pixel(x: x, y: y) }
        }
        #expect(!unselectedCornerRegion.contains { rgbaClose($0, expectedLightAccent) })
        #expect(selectedCornerRegion.contains { rgbaClose($0, expectedLightAccent) })
        #expect(
            selectedCornerRegion.contains {
                rgbaClose($0, TileRGBA(r: 255, g: 255, b: 255, a: 255), tolerance: 24)
            })
    }

    @Test func themePickerLayoutAdaptsAcrossWidthsWithoutHorizontalOverflow() {
        let narrow = ThemePickerLayout.resolve(availableWidth: 280)
        #expect(narrow.scale < 1)
        #expect(
            3 * narrow.tileWidth + 2 * narrow.columnSpacing <= 280.01)

        let compact375 = ThemePickerLayout.resolve(availableWidth: 335)
        #expect(compact375.scale < 1)
        #expect(
            3 * compact375.tileWidth + 2 * compact375.columnSpacing <= 335.01)

        let standard390 = ThemePickerLayout.resolve(availableWidth: 350)
        #expect(standard390.scale == 1)
        #expect(standard390.tileWidth == 108)
        #expect(abs(standard390.columnSpacing - 13) <= 0.01)
        #expect(
            3 * standard390.tileWidth + 2 * standard390.columnSpacing <= 350.01)

        let phone402 = ThemePickerLayout.resolve(availableWidth: 370)
        #expect(phone402.scale == 1)
        #expect(phone402.tileWidth == 108)
        #expect(abs(phone402.columnSpacing - 23) <= 0.01)
        #expect(3 * phone402.tileWidth + 2 * phone402.columnSpacing <= 370.01)

        let wideSplit = ThemePickerLayout.resolve(availableWidth: 364)
        #expect(wideSplit.scale == 1)
        #expect(wideSplit.tileWidth == 108)
        #expect(wideSplit.columnSpacing <= ThemePickerLayout.maxColumnSpacing)

        let ipad = ThemePickerLayout.resolve(availableWidth: 640)
        #expect(ipad.scale == 1)
        #expect(ipad.tileWidth == 108)
        #expect(ipad.columnSpacing == ThemePickerLayout.maxColumnSpacing)
    }

    @Test func appearanceSettingsUsesSeparateCheckmarkListAndUnboxedThemeSection() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let store = SettingsStore(
            persistence: SettingsPersistence(storage: SampleSettingsStorage()),
            rememberedAdvanceStorage: SampleSettingsStorage(),
            physicalMemory: 8 * 1024 * 1024 * 1024)

        for width in [CGFloat(320), CGFloat(390), CGFloat(680), CGFloat(1024)] {
            let host = UIHostingController(
                rootView: List {
                    AppearanceSettingsSections(showsCategoryTitle: width >= 680)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clove.surface.sheet)
                .environment(store)
                .environment(\.cloveTheme, .light))
            host.traitOverrides.horizontalSizeClass = width >= 680 ? .regular : .compact

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 844)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitForLayout("appearance settings list did not settle at width \(width)") {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                guard
                    let collection = self.findSubviews(ofType: UICollectionView.self, in: window)
                        .first
                else {
                    return false
                }
                return collection.numberOfSections == 2
                    && collection.numberOfItems(inSection: 0) == 3
                    && collection.numberOfItems(inSection: 1) == 1
                    && !collection.visibleCells.isEmpty
            }

            let collection = try #require(
                findSubviews(ofType: UICollectionView.self, in: window).first)
            #expect(collection.numberOfSections == 2)
            #expect(collection.numberOfItems(inSection: 0) == 3)
            #expect(collection.numberOfItems(inSection: 1) == 1)
            #expect(collection.contentSize.width <= collection.bounds.width + 1)

            // Section 1 (THEME) row sits unboxed directly on `surface/sheet` with zero card fill.
            let themeCell = try #require(
                collection.cellForItem(at: IndexPath(item: 0, section: 1)))
            let bgColor =
                themeCell.backgroundConfiguration?.backgroundColor ?? themeCell.backgroundColor
            let alpha = bgColor?.cgColor.alpha ?? 0
            #expect(alpha == 0)
        }
    }

    @Test func compactHomeGroupsWorkspaceAndWorkflowWithSubtitlesAndNeutralReset() async throws {
        #expect(
            SettingsCategoryGroup.workspace.categories == [
                .appearance, .language, .browsingAndGroups, .photoDisplay,
            ])
        #expect(SettingsCategoryGroup.workflow.categories == [.cullingAndMarking, .moveRejects])
        #expect(
            SettingsCategory.allCases
                == SettingsCategoryGroup.workspace.categories
                + SettingsCategoryGroup.workflow.categories)
        for category in SettingsCategory.allCases {
            #expect(!category.subtitle(language: .english).isEmpty)
        }

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(
            rootView: NavigationStack {
                SettingsScreen(availableWidth: 390)
            }
            .environment(SettingsStore.sample)
            .environment(\.cloveTheme, .light))
        host.traitOverrides.horizontalSizeClass = .compact
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitForLayout("compact settings home did not settle") {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            guard
                let collection = self.findSubviews(ofType: UICollectionView.self, in: window).first
            else {
                return false
            }
            return collection.numberOfSections == 3
                && collection.numberOfItems(inSection: 0) == 4
                && collection.numberOfItems(inSection: 1) == 2
                && collection.numberOfItems(inSection: 2) == 1
        }

        let collection = try #require(
            findSubviews(ofType: UICollectionView.self, in: window).first)
        #expect(collection.numberOfSections == 3)
        #expect(collection.numberOfItems(inSection: 0) == 4)
        #expect(collection.numberOfItems(inSection: 1) == 2)
        #expect(collection.numberOfItems(inSection: 2) == 1)
    }

    @Test func compactSubpagesUseLargeNavigationBarTitleMode() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        for root in [
            AnyView(SettingsCategoryScreen(category: .photoDisplay)),
            AnyView(SettingsSubpageScreen(subpage: .ratingScale)),
            AnyView(SettingsSubpageScreen(subpage: .autoAdvanceDestination)),
        ] {
            let navController = UINavigationController(
                rootViewController: UIHostingController(
                    rootView: root.environment(SettingsStore.sample)))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = navController
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitForLayout("compact subpage navigation did not settle") {
                navController.view.setNeedsLayout()
                navController.view.layoutIfNeeded()
                return navController.topViewController?.navigationItem.largeTitleDisplayMode
                    == .always
            }
        }
    }

    @Test func photoDisplayAndRatingScaleAndSubpageSectionsMatchFigma() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let store = SettingsStore(
            persistence: SettingsPersistence(storage: SampleSettingsStorage()),
            rememberedAdvanceStorage: SampleSettingsStorage(),
            physicalMemory: 8 * 1024 * 1024 * 1024)

        // Photo display: SHOW PHOTOS AS section with 2 checkmark rows (Camera preview, RAW).
        do {
            let host = UIHostingController(
                rootView: List {
                    PhotoDisplaySettingsSections(showsCategoryTitle: false)
                }
                .listStyle(.insetGrouped)
                .environment(store)
                .environment(\.cloveTheme, .light))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitForLayout("photo display list did not settle") {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                guard
                    let collection = self.findSubviews(ofType: UICollectionView.self, in: window)
                        .first
                else {
                    return false
                }
                return collection.numberOfSections == 1
                    && collection.numberOfItems(inSection: 0) == 2
            }
        }

        // Rating scale rows render 1...5 filled stars only (width grows monotonically from 1 to 5).
        var starRowWidths: [CGFloat] = []
        for count in 1...5 {
            let rowHost = UIHostingController(
                rootView: CumulativeRatingStarsRow(starCount: count, isEnabled: true)
                    .environment(\.cloveTheme, .light))
            let fitted = rowHost.sizeThatFits(in: CGSize(width: 400, height: 100))
            starRowWidths.append(fitted.width)
        }
        for index in 1..<starRowWidths.count {
            #expect(starRowWidths[index] > starRowWidths[index - 1] + 8)
        }
    }

    private func renderTilePixels<V: View>(_ view: V, theme: CloveTheme) throws -> TilePixelBuffer {
        let renderer = ImageRenderer(
            content:
                view
                .environment(\.cloveTheme, theme)
                .environment(\.appLanguage, .english))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        return try tilePixels(from: image)
    }

    private func renderedRGBA(_ color: Color) throws -> TileRGBA {
        let renderer = ImageRenderer(content: Rectangle().fill(color).frame(width: 4, height: 4))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        return try tilePixels(from: image).pixel(x: 2, y: 2)
    }

    private func tilePixels(from image: CGImage) throws -> TilePixelBuffer {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmapInfo =
            CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try #require(
            CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return TilePixelBuffer(width: width, height: height, bytes: bytes)
    }

    private func windowPixels(from window: UIWindow) -> TilePixelBuffer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return (try? tilePixels(from: image.cgImage!))
            ?? TilePixelBuffer(width: 1, height: 1, bytes: [0, 0, 0, 0])
    }

    private func assertRGBAClose(
        _ actual: TileRGBA, _ expected: TileRGBA, _ label: String, tolerance: Int = 12,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            rgbaClose(actual, expected, tolerance: tolerance),
            "\(label): actual \(actual) != expected \(expected)",
            sourceLocation: sourceLocation)
    }

    private func rgbaClose(_ actual: TileRGBA, _ expected: TileRGBA, tolerance: Int = 12) -> Bool {
        abs(Int(actual.r) - Int(expected.r)) <= tolerance
            && abs(Int(actual.g) - Int(expected.g)) <= tolerance
            && abs(Int(actual.b) - Int(expected.b)) <= tolerance
            && abs(Int(actual.a) - Int(expected.a)) <= tolerance
    }
}

private struct TileRGBA: CustomStringConvertible {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

    var description: String { "(\(r), \(g), \(b), \(a))" }
}

private struct TilePixelBuffer {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    func pixel(x: Int, y: Int) -> TileRGBA {
        let offset = (y * width + x) * 4
        return TileRGBA(
            r: bytes[offset], g: bytes[offset + 1], b: bytes[offset + 2], a: bytes[offset + 3])
    }
}

@MainActor
@Observable
private final class TestSettingsFramesBox {
    var frames: [String: CGRect] = [:]
}
