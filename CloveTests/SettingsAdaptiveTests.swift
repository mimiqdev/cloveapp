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
            $0.zoomedRatingSwipe = .singleFingerAxisLock
            $0.keepZoom.inDetail = true
        }
        #expect(store.photoDisplayMode == .rawFirst)

        store.resetToDefaults()
        #expect(store.settings == AppSettings())
        #expect(store.photoDisplayMode == .cameraPreviewFirst)
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
}
