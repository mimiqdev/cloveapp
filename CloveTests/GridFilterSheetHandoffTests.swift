import CloveCore
import Foundation
import Testing

@testable import Clove

@Suite("Grid filter popover to metadata sheet handoff")
struct GridFilterSheetHandoffTests {
    private let folderA = FolderIdentity(rawValue: "folder-a")
    private let folderB = FolderIdentity(rawValue: "folder-b")

    @Test func tappingMoreFiltersDefersSheetUntilPopoverDisappearsThenConsumesOnce() {
        var handoff = GridFilterSheetHandoff()
        handoff.setFiltersPresented(true)
        #expect(handoff.showsFilters)
        #expect(!handoff.pendingMetadataFiltersAfterPopover)

        handoff.requestMetadataFiltersFromPopover(folder: folderA)
        #expect(!handoff.showsFilters)
        #expect(handoff.pendingMetadataFiltersAfterPopover)

        let shouldPresent = handoff.consumePendingMetadataFiltersOnPopoverDisappear(
            currentFolder: folderA,
            isSceneActive: true,
            canPresent: true)
        #expect(shouldPresent)
        #expect(!handoff.pendingMetadataFiltersAfterPopover)

        // A duplicate onDisappear after consumption must not re-open the sheet.
        let secondPresent = handoff.consumePendingMetadataFiltersOnPopoverDisappear(
            currentFolder: folderA,
            isSceneActive: true,
            canPresent: true)
        #expect(!secondPresent)
    }

    @Test func dismissingPopoverNormallyDoesNotOpenMetadataSheet() {
        var handoff = GridFilterSheetHandoff()
        handoff.setFiltersPresented(true)
        handoff.setFiltersPresented(false)

        #expect(!handoff.showsFilters)
        #expect(!handoff.pendingMetadataFiltersAfterPopover)
        let shouldPresent = handoff.consumePendingMetadataFiltersOnPopoverDisappear(
            currentFolder: folderA,
            isSceneActive: true,
            canPresent: true)
        #expect(!shouldPresent)
    }

    @Test func folderChangeCancelsPendingMetadataSheetHandoff() {
        var handoff = GridFilterSheetHandoff()
        handoff.setFiltersPresented(true)
        handoff.requestMetadataFiltersFromPopover(folder: folderA)

        // Folder changed before popover finished disappearing -> rejected and cleared.
        let afterFolderChange = handoff.consumePendingMetadataFiltersOnPopoverDisappear(
            currentFolder: folderB,
            isSceneActive: true,
            canPresent: true)
        #expect(!afterFolderChange)
        #expect(!handoff.pendingMetadataFiltersAfterPopover)

        // Explicit folder-change reset clears both popover visibility and pending state.
        handoff.setFiltersPresented(true)
        handoff.requestMetadataFiltersFromPopover(folder: folderA)
        handoff.dismissFiltersAndCancelPending()
        #expect(!handoff.showsFilters)
        #expect(!handoff.pendingMetadataFiltersAfterPopover)
        let afterReset = handoff.consumePendingMetadataFiltersOnPopoverDisappear(
            currentFolder: folderA,
            isSceneActive: true,
            canPresent: true)
        #expect(!afterReset)
    }

    @Test func sceneDeactivationCancelsPendingMetadataSheetHandoff() {
        var handoff = GridFilterSheetHandoff()
        handoff.setFiltersPresented(true)
        handoff.requestMetadataFiltersFromPopover(folder: folderA)

        let whileInactive = handoff.consumePendingMetadataFiltersOnPopoverDisappear(
            currentFolder: folderA,
            isSceneActive: false,
            canPresent: true)
        #expect(!whileInactive)
        #expect(!handoff.pendingMetadataFiltersAfterPopover)

        handoff.setFiltersPresented(true)
        handoff.requestMetadataFiltersFromPopover(folder: folderA)
        handoff.dismissFiltersAndCancelPending()
        #expect(!handoff.showsFilters)
        #expect(!handoff.pendingMetadataFiltersAfterPopover)
    }

    @Test func directOpenOrReopeningPopoverOrDisallowedLayoutCancelsPendingHandoff() {
        var handoff = GridFilterSheetHandoff()

        // Direct open / sheet presentation cancels any pending handoff.
        handoff.setFiltersPresented(true)
        handoff.requestMetadataFiltersFromPopover(folder: folderA)
        handoff.cancelPendingMetadataFilters()
        #expect(!handoff.pendingMetadataFiltersAfterPopover)

        // Re-opening the filter popover cancels stale pending state.
        handoff.requestMetadataFiltersFromPopover(folder: folderA)
        handoff.setFiltersPresented(true)
        #expect(handoff.showsFilters)
        #expect(!handoff.pendingMetadataFiltersAfterPopover)

        // Disallowed presentation context (e.g. regular iPad or non-dock detail) rejects and clears.
        handoff.requestMetadataFiltersFromPopover(folder: folderA)
        let whenDisallowed = handoff.consumePendingMetadataFiltersOnPopoverDisappear(
            currentFolder: folderA,
            isSceneActive: true,
            canPresent: false)
        #expect(!whenDisallowed)
        #expect(!handoff.pendingMetadataFiltersAfterPopover)

        // Requesting from nil folder never arms pending state.
        handoff.requestMetadataFiltersFromPopover(folder: nil)
        #expect(!handoff.showsFilters)
        #expect(!handoff.pendingMetadataFiltersAfterPopover)
    }

    @MainActor
    @Test func testLibraryMetadataSamplesExposeAllFilterDimensions() {
        let library = TestLibrary.forLaunch(environment: [
            TestLibrary.launchVariable: "1",
            TestLibrary.metadataSamplesVariable: "1",
        ])
        let model = BrowsingModel(library: library)
        model.openFolder()

        let options = model.metadataFilterOptions
        #expect(options.hasAnyDimension)
        #expect(options.cameras.map(\.value) == ["ILCE-1M2", "ILCE-7M4"])
        #expect(
            options.lenses.map(\.value) == [
                "FE 24-70mm F2.8 GM II", "FE 35mm F1.4 GM", "FE 85mm F1.4 GM",
            ])
        #expect(options.focalLengths.map(\.value) == [.wide, .standard, .shortTelephoto])
        #expect(options.keywords.map(\.value) == ["Coast", "Portrait"])
    }

    @MainActor
    @Test func gridScreenAndDetailMarkingAllowsMetadataFiltersInDuoExpandedCoverAndPadDetail() {
        // Ordinary phone Grid and Compact iPad Grid allow "More filters"; Regular iPad Grid uses sidebar.
        #expect(
            GridScreen.allowsMetadataFiltersFromPopover(
                isRegular: false, usesDock: false, route: .grid))
        #expect(
            !GridScreen.allowsMetadataFiltersFromPopover(
                isRegular: true, usesDock: false, route: .grid))
        // Expanded Duo Grid & Duo Cover Grid always allow "More filters" even when Expanded Duo is .regular.
        #expect(
            GridScreen.allowsMetadataFiltersFromPopover(
                isRegular: true, usesDock: true, route: .grid))
        #expect(
            GridScreen.allowsMetadataFiltersFromPopover(
                isRegular: false, usesDock: true, route: .grid))
        // GridScreen's own filterButton does not hand off when route is .detail (Detail owns its sheet).
        #expect(
            !GridScreen.allowsMetadataFiltersFromPopover(
                isRegular: false, usesDock: true, route: .detail))

        // DetailMarkingView allows "More filters" across Phone, iPad, Duo Cover, and Expanded Duo unless comparing.
        #expect(DetailMarkingView.allowsMetadataFiltersFromPopover(isComparing: false))
        #expect(!DetailMarkingView.allowsMetadataFiltersFromPopover(isComparing: true))
    }
}
