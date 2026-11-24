import CloveCore
import CloveImaging
import CoreGraphics
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
@Suite("Compare flow", .serialized)
struct CompareFlowTests {
    @Test("Detail Timeline entry starts stepping mode with challenger focused and skips A on step")
    func timelineEntryAndSteppingSkipsReference() {
        let library = ControlledPhotoLibrary(rejected: [], stems: ["p1", "p2", "p3", "p4"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        model.openPhoto(library.identity("p2"))

        let timeline = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        let entered = model.enterCompareFromDetail(timeline: timeline)
        #expect(entered)
        #expect(model.state.route == .detail)
        #expect(model.compareSession?.mode == .stepping)
        #expect(model.compareSession?.scopeKind == .timeline)
        #expect(model.compareSession?.reference == library.identity("p2"))
        #expect(model.compareSession?.challenger == library.identity("p3"))
        #expect(model.compareSession?.activeSide == .challenger)
        #expect(model.compareSession?.isSyncLocked == true)

        // Stepping `<` jumps over A (p2) directly to p1.
        let steppedBack = model.stepCompareChallenger(offset: -1)
        #expect(steppedBack)
        #expect(model.compareSession?.challenger == library.identity("p1"))
        #expect(model.compareSession?.canStepPreviousChallenger == false)

        // Filmstrip tap on A is ignored; tapping p4 updates B.
        let tappedA = model.selectCompareChallenger(library.identity("p2"))
        #expect(!tappedA)
        #expect(model.compareSession?.challenger == library.identity("p1"))

        let tappedP4 = model.selectCompareChallenger(library.identity("p4"))
        #expect(tappedP4)
        #expect(model.compareSession?.challenger == library.identity("p4"))
    }

    @Test(
        "Group Focus entry scopes Compare to visible group members and Set as A promotes or swaps")
    func groupFocusEntryAndPromoteBehavior() async throws {
        let library = ControlledPhotoLibrary(
            rejected: [], stems: ["solo", "g1", "g2", "g3", "twoA", "twoB"])
        let threeGroup = BrowsingGroup(
            id: GroupID(rawValue: "three"),
            members: ["g1", "g2", "g3"].map { library.identity($0) })
        let twoGroup = BrowsingGroup(
            id: GroupID(rawValue: "two"),
            members: ["twoA", "twoB"].map { library.identity($0) })
        library.groups = [threeGroup, twoGroup]
        let model = BrowsingModel(library: library)
        model.openFolder()
        library.reportScanFinished()
        try await waitUntil { !model.isFolderOpening && model.groups.count == 2 }

        model.openGroup(threeGroup.id, on: library.identity("g1"))
        #expect(model.expandedGroup == threeGroup.id)

        let timeline = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        #expect(model.enterCompareFromDetail(timeline: timeline))
        #expect(model.compareSession?.scopeKind == .group(threeGroup.id))
        #expect(model.compareSession?.scope == threeGroup.members)
        #expect(model.compareSession?.reference == library.identity("g1"))
        #expect(model.compareSession?.challenger == library.identity("g2"))

        // Set as A promotes g2 to A and loads g3 as B without touching marks.
        #expect(model.promoteCompareChallengerToReference())
        #expect(model.compareSession?.reference == library.identity("g2"))
        #expect(model.compareSession?.challenger == library.identity("g3"))
        #expect(model.shownMarks(for: library.identity("g2")).isUnmarked)

        // Two-member Group Focus swaps A and B cleanly on Set as A.
        model.exitCompare()
        model.openGroup(twoGroup.id, on: library.identity("twoA"))
        #expect(model.expandedGroup == twoGroup.id)
        let twoTimeline = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        #expect(model.enterCompareFromDetail(timeline: twoTimeline))
        #expect(model.compareSession?.reference == library.identity("twoA"))
        #expect(model.compareSession?.challenger == library.identity("twoB"))
        #expect(model.promoteCompareChallengerToReference())
        #expect(model.compareSession?.reference == library.identity("twoB"))
        #expect(model.compareSession?.challenger == library.identity("twoA"))
        #expect(model.shownMarks(for: library.identity("twoA")).isUnmarked)
        #expect(model.shownMarks(for: library.identity("twoB")).isUnmarked)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }

    @Test("Grid two-photo multi-select enters fixed pair mode preserving grid order")
    func gridTwoPhotoSelectionFixedPairMode() {
        let library = ControlledPhotoLibrary(rejected: [], stems: ["p1", "p2", "p3"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        model.setSelection([library.identity("p3"), library.identity("p1")])

        #expect(model.batchTargets.map(\.id) == [library.identity("p1"), library.identity("p3")])
        let entered = model.enterCompareFromBatchSelection()
        #expect(entered)
        #expect(model.state.route == .detail)
        #expect(model.compareSession?.mode == .fixedPair)
        #expect(model.compareSession?.reference == library.identity("p1"))
        #expect(model.compareSession?.challenger == library.identity("p3"))
        #expect(model.compareSession?.activeSide == .reference)
        #expect(model.compareSession?.isSyncLocked == true)
        #expect(!model.stepCompareChallenger(offset: 1))
        #expect(!model.promoteCompareChallengerToReference())
    }

    @Test(
        "Marking and Undo keep Compare pair intact even when Grid filter excludes newly marked photo"
    )
    func markingAndUndoPreservePairUnderFilter() async {
        let library = ControlledPhotoLibrary(rejected: [], stems: ["p1", "p2", "p3"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        model.setFilter(.unmarked)

        let timeline = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        model.openPhoto(library.identity("p1"))
        #expect(model.enterCompareFromDetail(timeline: timeline))

        let p1 = library.identity("p1")
        let p2 = library.identity("p2")
        #expect(model.compareSession?.activePhoto == p2)

        // Rate active challenger B with 4 stars -> disappears from `.unmarked` `model.photos`,
        // yet Compare pair stays mounted, `placedPhoto(for:)` preserves live marks, and Undo works on B.
        let fourStars = Rating(rawValue: 4)!
        model.apply(MarkChange(rating: fourStars), to: p2)
        #expect(!model.photos.contains(where: { $0.id == p2 }))
        #expect(model.compareSession?.reference == p1)
        #expect(model.compareSession?.challenger == p2)
        #expect(model.placedPhoto(for: p2)?.marks.rating == fourStars)
        #expect(model.canUndoCompareMark)

        // Switching focus to A disables Compare Undo because last mark belongs to B,
        // and marking A acts strictly on A while keeping pair intact.
        model.selectCompareSide(.reference)
        #expect(!model.canUndoCompareMark)
        model.apply(MarkChange(label: ColourLabel(colour: .green)), to: p1)
        #expect(!model.photos.contains(where: { $0.id == p1 }))
        #expect(model.placedPhoto(for: p1)?.marks.label.colour == .green)
        #expect(model.placedPhoto(for: p2)?.marks.rating == fourStars)
        #expect(model.canUndoCompareMark)

        // Undoing while A is active restores only A without closing Compare or jumping navigation.
        model.undoCompareMark()
        #expect(model.placedPhoto(for: p1)?.marks.isUnmarked == true)
        #expect(model.placedPhoto(for: p2)?.marks.rating == fourStars)
        #expect(model.compareSession?.reference == p1)
        #expect(model.compareSession?.challenger == p2)
        #expect(model.compareSession?.activeSide == .reference)
        await model.drainActions()
    }

    @Test("Exiting Compare returns Detail to active side photo across A and B focus switches")
    func exitCompareReturnsToActiveSidePhoto() {
        let library = ControlledPhotoLibrary(rejected: [], stems: ["p1", "p2", "p3"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        model.openPhoto(library.identity("p1"))
        let timeline = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        #expect(model.enterCompareFromDetail(timeline: timeline))

        // Default active side in stepping is challenger B (p2). Exiting keeps currentPhoto on p2.
        model.exitCompare()
        #expect(model.compareSession == nil)
        #expect(model.state.route == .detail)
        #expect(model.state.currentPhoto == library.identity("p2"))

        // Re-enter on p2 (B defaults to p3), switch active focus back to A (p2), then exit -> stays on p2.
        let timeline2 = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        #expect(model.enterCompareFromDetail(timeline: timeline2))
        #expect(model.compareSession?.reference == library.identity("p2"))
        #expect(model.compareSession?.challenger == library.identity("p3"))
        #expect(model.compareSession?.activePhoto == library.identity("p3"))
        model.selectCompareSide(.reference)
        #expect(model.compareSession?.activePhoto == library.identity("p2"))
        model.exitCompare()
        #expect(model.state.currentPhoto == library.identity("p2"))
    }

    @Test(
        "DetailZoomContainerView suspends marking pan in Compare mode and syncs viewports between panes"
    )
    func compareZoomContainerSuspendsMarkingAndSyncsViewports() {
        let paneA = DetailZoomContainerView(
            frame: CGRect(x: 0, y: 0, width: 420, height: 320))
        let paneB = DetailZoomContainerView(
            frame: CGRect(x: 0, y: 0, width: 420, height: 320))
        paneA.isCompareMode = true
        paneB.isCompareMode = true
        paneA.layoutIfNeeded()
        paneB.layoutIfNeeded()

        let imgA = makeSolidCGImage(width: 2400, height: 1600)
        let imgB = makeSolidCGImage(width: 2400, height: 1600)
        paneA.setImage(imgA, fullResolutionPixels: CGSize(width: 2400, height: 1600))
        paneB.setImage(imgB, fullResolutionPixels: CGSize(width: 2400, height: 1600))
        paneA.layoutIfNeeded()
        paneB.layoutIfNeeded()

        #expect(!paneA.markingPanIsEnabled)
        #expect(!paneA.twoFingerMarkingSwipeIsEnabled)
        #expect(paneA.chromeTapIsEnabled)
        #expect(paneA.doubleTapIsEnabled)

        var syncedScalesOnB: [CGFloat] = []
        paneB.onSyncedScaleApplied = { syncedScalesOnB.append($0) }

        let anchor = DetailZoomAnchor(x: 0.72, y: 0.35)
        paneA.applySyncedViewport(scale: 2.5, anchor: anchor)
        paneB.applySyncedViewport(scale: 2.5, anchor: anchor)

        let snapA = paneA.zoomSnapshot
        let snapB = paneB.zoomSnapshot
        #expect(snapA != nil && snapB != nil)
        #expect(abs((snapA?.scale ?? 0) - 2.5) < 0.01)
        #expect(abs((snapB?.scale ?? 0) - 2.5) < 0.01)
        #expect(abs((snapA?.anchor.x ?? 0) - (snapB?.anchor.x ?? 1)) < 0.02)
        #expect(abs((snapA?.anchor.y ?? 0) - (snapB?.anchor.y ?? 1)) < 0.02)
        #expect(!syncedScalesOnB.isEmpty)
    }

    @Test("SampleDetailImages holds two full renders during Compare and evicts down to one on exit")
    func sampleDetailImagesRespectsTwoEntryBudgetInCompare() async {
        let folder = FolderIdentity(rawValue: "sample-budget")
        let p1 = PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "a")
        let p2 = PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "b")
        let p3 = PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "c")

        let source = SampleDetailImages()
        let request = DetailPixelRequest(
            displayPixels: 3000, need: .fullResolution, mode: .rawFirst)

        #expect(source.activeFullCacheLimit == 1)
        await source.setCompareRetention(active: true, keeping: nil)
        #expect(source.activeFullCacheLimit == 2)

        _ = await source.image(for: p1, request: request, consumer: UUID())
        _ = await source.image(for: p2, request: request, consumer: UUID())
        #expect(source.heldFullCount == 2)

        // Third full render evicts oldest, never exceeding 2.
        _ = await source.image(for: p3, request: request, consumer: UUID())
        #expect(source.heldFullCount == 2)

        // Exiting Compare restores limit to 1 and keeps only the active photo.
        await source.setCompareRetention(active: false, keeping: p3)
        #expect(source.activeFullCacheLimit == 1)
        #expect(source.heldFullCount == 1)
    }

    @Test(
        "CompareView exits cleanly to active photo in Detail when resizing to portrait or folding to Duo Cover"
    )
    func hostedCompareExitsCleanlyOnPortraitOrCoverFold() async throws {
        let library = ControlledPhotoLibrary(rejected: [], stems: ["p1", "p2", "p3"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        library.reportScanFinished()
        try await waitUntil { !model.isFolderOpening && model.photos.count == 3 }

        let p1 = library.identity("p1")
        let p2 = library.identity("p2")
        model.openPhoto(p1)
        let timeline = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        #expect(model.enterCompareFromDetail(timeline: timeline))

        // Mark B (p2) before rotating so mark preservation is also asserted.
        model.apply(MarkChange(rating: Rating(rawValue: 5)!), to: p2)
        #expect(model.compareSession?.activePhoto == p2)

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(
            rootView: DetailScreen(browsing: model, images: SampleDetailImages())
                .environment(SettingsStore.sample))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 852, height: 393)
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .compact
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.compareSession != nil)

        // Rotate to portrait phone -> auto-exits Compare to Detail on active side's photo (p2) with mark intact.
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .regular
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitUntil { model.compareSession == nil }

        #expect(model.state.route == .detail)
        #expect(model.state.currentPhoto == p2)
        #expect(model.placedPhoto(for: p2)?.marks.rating == Rating(rawValue: 5))
    }

    @Test(
        "Sync On preserves Pane A zoom and opens stepped Pane B zoomed across warm and cold loads"
    )
    func syncOnSteppingPreservesZoomOnWarmAndColdLoads() async throws {
        let library = ControlledPhotoLibrary(
            rejected: [], stems: ["p1", "p2", "p3", "p4", "p5"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        library.reportScanFinished()
        try await waitUntil { !model.isFolderOpening && model.photos.count == 5 }

        let p1 = library.identity("p1")
        let p2 = library.identity("p2")
        let p3 = library.identity("p3")
        let p4 = library.identity("p4")
        let p5 = library.identity("p5")
        model.openPhoto(p1)
        let timeline = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        #expect(model.enterCompareFromDetail(timeline: timeline))

        let images = CompareTestDetailImages()
        let hosted = try await mountCompare(model: model, images: images)
        defer { hosted.tearDown() }

        try await waitUntil {
            images.deliveries.contains { $0.0 == p1 && $0.2 == .screenRAW }
                && images.deliveries.contains { $0.0 == p2 && $0.2 == .screenRAW }
        }
        let (paneA, paneB) = try requirePanes(in: hosted.window)

        // Zoom Pane A to 100% around an off-center anchor; Sync On mirrors Pane B.
        let targetAnchor = DetailZoomAnchor(x: 0.72, y: 0.35)
        paneA.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: targetAnchor.x, y: targetAnchor.y)))
        try await waitUntil {
            paneA.isZoomed && paneB.isZoomed
                && images.deliveries.contains { $0.0 == p1 && $0.2 == .nativeRAW }
                && images.deliveries.contains { $0.0 == p2 && $0.2 == .nativeRAW }
        }
        await flushMainRunLoop()
        let beforeA = try #require(paneA.zoomSnapshot)
        let beforeB = try #require(paneB.zoomSnapshot)
        #expect(abs(beforeA.scale - beforeB.scale) < 0.02)
        #expect(abs(beforeA.anchor.x - beforeB.anchor.x) < 0.02)
        #expect(abs(beforeA.anchor.y - beforeB.anchor.y) < 0.02)

        // 1. Cold step B (p2 -> p3): A stays zoomed and p3 opens at matching scale/anchor + upgrades RAW.
        #expect(model.stepCompareChallenger(offset: 1))
        #expect(model.compareSession?.challenger == p3)
        try await waitUntil {
            images.deliveries.contains { $0.0 == p3 && $0.2 == .nativeRAW }
                && paneB.isZoomed
        }
        await flushMainRunLoop()
        try await Task.sleep(for: .milliseconds(80))
        await flushMainRunLoop()

        let afterColdA = try #require(paneA.zoomSnapshot)
        let afterColdB = try #require(paneB.zoomSnapshot)
        #expect(abs(afterColdA.scale - beforeA.scale) < 0.02)
        #expect(abs(afterColdA.anchor.x - beforeA.anchor.x) < 0.02)
        #expect(abs(afterColdA.anchor.y - beforeA.anchor.y) < 0.02)
        #expect(abs(afterColdB.scale - beforeA.scale) < 0.02)
        #expect(abs(afterColdB.anchor.x - beforeA.anchor.x) < 0.02)
        #expect(abs(afterColdB.anchor.y - beforeA.anchor.y) < 0.02)
        #expect(
            images.requests.contains { $0.0 == p3 && $0.1.need == .fullResolution })

        // 2. Warm step B (p3 -> p4): stale .fit must NOT overwrite synced zoom after runloop flush.
        images.warmPhotos.insert(p4)
        #expect(model.stepCompareChallenger(offset: 1))
        #expect(model.compareSession?.challenger == p4)
        try await waitUntil {
            images.deliveries.contains { $0.0 == p4 && $0.2 == .nativeRAW }
                && paneB.isZoomed
        }
        await flushMainRunLoop()
        try await Task.sleep(for: .milliseconds(80))
        await flushMainRunLoop()

        let afterWarmA = try #require(paneA.zoomSnapshot)
        let afterWarmB = try #require(paneB.zoomSnapshot)
        #expect(abs(afterWarmA.scale - beforeA.scale) < 0.02)
        #expect(abs(afterWarmB.scale - beforeA.scale) < 0.02)
        #expect(abs(afterWarmB.anchor.x - beforeA.anchor.x) < 0.02)
        #expect(abs(afterWarmB.anchor.y - beforeA.anchor.y) < 0.02)
        #expect(
            images.requests.contains { $0.0 == p4 && $0.1.need == .fullResolution })

        // 3. Filmstrip selection step (p4 -> p5) and backward step (p5 -> p4) also keep zoom.
        #expect(model.selectCompareChallenger(p5))
        try await waitUntil {
            images.deliveries.contains { $0.0 == p5 && $0.2 == .nativeRAW }
                && paneB.isZoomed
        }
        await flushMainRunLoop()
        let afterFilmstripB = try #require(paneB.zoomSnapshot)
        #expect(abs(afterFilmstripB.scale - beforeA.scale) < 0.02)
        #expect(abs(afterFilmstripB.anchor.x - beforeA.anchor.x) < 0.02)
        #expect(abs(afterFilmstripB.anchor.y - beforeA.anchor.y) < 0.02)

        #expect(model.stepCompareChallenger(offset: -1))
        #expect(model.compareSession?.challenger == p4)
        await flushMainRunLoop()
        try await Task.sleep(for: .milliseconds(80))
        await flushMainRunLoop()
        let afterBackB = try #require(paneB.zoomSnapshot)
        #expect(abs(afterBackB.scale - beforeA.scale) < 0.02)
        #expect(abs(afterBackB.anchor.x - beforeA.anchor.x) < 0.02)
        #expect(abs(afterBackB.anchor.y - beforeA.anchor.y) < 0.02)
    }

    @Test(
        "Sync Off preserves Pane B zoom across stepping and rapid multi-step before pixels arrive"
    )
    func syncOffSteppingPreservesPaneBZoomAndRapidMultiStep() async throws {
        let library = ControlledPhotoLibrary(
            rejected: [], stems: ["p1", "p2", "p3", "p4", "p5"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        library.reportScanFinished()
        try await waitUntil { !model.isFolderOpening && model.photos.count == 5 }

        let p1 = library.identity("p1")
        let p2 = library.identity("p2")
        let p3 = library.identity("p3")
        let p4 = library.identity("p4")
        let p5 = library.identity("p5")
        model.openPhoto(p1)
        let timeline = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        #expect(model.enterCompareFromDetail(timeline: timeline))

        let images = CompareTestDetailImages()
        let hosted = try await mountCompare(model: model, images: images)
        defer { hosted.tearDown() }

        try await waitUntil {
            images.deliveries.contains { $0.0 == p1 && $0.2 == .screenRAW }
                && images.deliveries.contains { $0.0 == p2 && $0.2 == .screenRAW }
        }
        let (paneA, paneB) = try requirePanes(in: hosted.window)

        // Disable sync and give Pane A and Pane B independent zoomed viewports.
        model.toggleCompareSyncLock()
        #expect(model.compareSession?.isSyncLocked == false)

        paneA.applySyncedViewport(scale: 2.2, anchor: DetailZoomAnchor(x: 0.28, y: 0.30))
        paneB.applySyncedViewport(scale: 2.6, anchor: DetailZoomAnchor(x: 0.74, y: 0.66))
        await flushMainRunLoop()
        let snapA = try #require(paneA.zoomSnapshot)
        let snapB = try #require(paneB.zoomSnapshot)

        // Step B (p2 -> p3): Pane B keeps its own scale/anchor (not A's, and not Fit).
        #expect(model.stepCompareChallenger(offset: 1))
        #expect(model.compareSession?.challenger == p3)
        try await waitUntil {
            images.deliveries.contains { $0.0 == p3 && $0.2 == .nativeRAW }
                && paneB.isZoomed
        }
        await flushMainRunLoop()
        try await Task.sleep(for: .milliseconds(80))
        await flushMainRunLoop()

        let afterStepA = try #require(paneA.zoomSnapshot)
        let afterStepB = try #require(paneB.zoomSnapshot)
        #expect(abs(afterStepA.scale - snapA.scale) < 0.02)
        #expect(abs(afterStepA.anchor.x - snapA.anchor.x) < 0.02)
        #expect(abs(afterStepB.scale - snapB.scale) < 0.02)
        #expect(abs(afterStepB.anchor.x - snapB.anchor.x) < 0.02)
        #expect(abs(afterStepB.anchor.y - snapB.anchor.y) < 0.02)

        // Rapid multi-step p3 -> p4 (slow) -> p5 before p4 finishes loading:
        // p5 must still inherit p3's zoomed viewport instead of resetting to Fit.
        images.delayedColdPhotos[p4] = .milliseconds(400)
        #expect(model.stepCompareChallenger(offset: 1))
        #expect(model.compareSession?.challenger == p4)
        try await Task.sleep(for: .milliseconds(40))
        #expect(model.stepCompareChallenger(offset: 1))
        #expect(model.compareSession?.challenger == p5)

        try await waitUntil {
            images.deliveries.contains { $0.0 == p5 && $0.2 == .nativeRAW }
                && paneB.isZoomed
        }
        await flushMainRunLoop()
        try await Task.sleep(for: .milliseconds(80))
        await flushMainRunLoop()

        let afterRapidB = try #require(paneB.zoomSnapshot)
        #expect(abs(afterRapidB.scale - snapB.scale) < 0.02)
        #expect(abs(afterRapidB.anchor.x - snapB.anchor.x) < 0.02)
        #expect(abs(afterRapidB.anchor.y - snapB.anchor.y) < 0.02)
    }

    @Test(
        "Set as A preserves zoom across Sync On, Sync Off 3+ promote, and Sync Off 2-photo swap"
    )
    func setAsAPreservesZoomAcrossModesAndTwoPhotoSwap() async throws {
        let library = ControlledPhotoLibrary(
            rejected: [], stems: ["p1", "p2", "p3", "twoA", "twoB"])
        let threeGroup = BrowsingGroup(
            id: GroupID(rawValue: "three"),
            members: ["p1", "p2", "p3"].map { library.identity($0) })
        let twoGroup = BrowsingGroup(
            id: GroupID(rawValue: "two"),
            members: ["twoA", "twoB"].map { library.identity($0) })
        library.groups = [threeGroup, twoGroup]
        let model = BrowsingModel(library: library)
        model.openFolder()
        library.reportScanFinished()
        try await waitUntil { !model.isFolderOpening && model.groups.count == 2 }

        let p1 = library.identity("p1")
        let p2 = library.identity("p2")
        let p3 = library.identity("p3")
        let twoA = library.identity("twoA")
        let twoB = library.identity("twoB")

        model.openGroup(threeGroup.id, on: p1)
        let timeline = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        #expect(model.enterCompareFromDetail(timeline: timeline))

        let images = CompareTestDetailImages()
        let hosted = try await mountCompare(model: model, images: images)
        defer { hosted.tearDown() }

        try await waitUntil {
            images.deliveries.contains { $0.0 == p1 && $0.2 == .screenRAW }
                && images.deliveries.contains { $0.0 == p2 && $0.2 == .screenRAW }
        }
        let (paneA, paneB) = try requirePanes(in: hosted.window)

        // 1. Sync On Set as A: both new A (p2) and new B (p3) keep synced zoom.
        paneA.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.70, y: 0.34)))
        try await waitUntil {
            paneA.isZoomed && paneB.isZoomed
                && images.deliveries.contains { $0.0 == p1 && $0.2 == .nativeRAW }
                && images.deliveries.contains { $0.0 == p2 && $0.2 == .nativeRAW }
        }
        await flushMainRunLoop()
        let syncScale = try #require(paneB.zoomSnapshot).scale
        let syncAnchor = try #require(paneB.zoomSnapshot).anchor

        #expect(model.promoteCompareChallengerToReference())
        #expect(model.compareSession?.reference == p2)
        #expect(model.compareSession?.challenger == p3)
        try await waitUntil {
            images.deliveries.contains { $0.0 == p3 && $0.2 == .nativeRAW }
                && paneA.isZoomed && paneB.isZoomed
        }
        await flushMainRunLoop()
        try await Task.sleep(for: .milliseconds(80))
        await flushMainRunLoop()

        let promotedSyncA = try #require(paneA.zoomSnapshot)
        let promotedSyncB = try #require(paneB.zoomSnapshot)
        #expect(abs(promotedSyncA.scale - syncScale) < 0.02)
        #expect(abs(promotedSyncA.anchor.x - syncAnchor.x) < 0.02)
        #expect(abs(promotedSyncA.anchor.y - syncAnchor.y) < 0.02)
        #expect(abs(promotedSyncB.scale - syncScale) < 0.02)
        #expect(abs(promotedSyncB.anchor.x - syncAnchor.x) < 0.02)
        #expect(abs(promotedSyncB.anchor.y - syncAnchor.y) < 0.02)

        // 2. Sync Off 3+-photo promote (A=p2, B=p3 -> A=p3, B=p1):
        // New A and new B both inherit old B's zoom (distinct from old A's zoom).
        model.toggleCompareSyncLock()
        applyUserZoom(to: paneA, scale: 2.0, anchor: DetailZoomAnchor(x: 0.25, y: 0.25))
        applyUserZoom(to: paneB, scale: 2.7, anchor: DetailZoomAnchor(x: 0.76, y: 0.68))
        await flushMainRunLoop()
        let oldBScale = try #require(paneB.zoomSnapshot).scale
        let oldBAnchor = try #require(paneB.zoomSnapshot).anchor

        #expect(model.promoteCompareChallengerToReference())
        #expect(model.compareSession?.reference == p3)
        #expect(model.compareSession?.challenger == p1)
        try await waitUntil {
            images.deliveries.contains { $0.0 == p1 && $0.2 == .nativeRAW }
                && paneA.isZoomed && paneB.isZoomed
        }
        await flushMainRunLoop()
        try await Task.sleep(for: .milliseconds(80))
        await flushMainRunLoop()

        let promotedOffA = try #require(paneA.zoomSnapshot)
        let promotedOffB = try #require(paneB.zoomSnapshot)
        #expect(abs(promotedOffA.scale - oldBScale) < 0.02)
        #expect(abs(promotedOffA.anchor.x - oldBAnchor.x) < 0.02)
        #expect(abs(promotedOffA.anchor.y - oldBAnchor.y) < 0.02)
        #expect(abs(promotedOffB.scale - oldBScale) < 0.02)
        #expect(abs(promotedOffB.anchor.x - oldBAnchor.x) < 0.02)
        #expect(abs(promotedOffB.anchor.y - oldBAnchor.y) < 0.02)

        // 3. Sync Off 2-photo swap (A=twoA, B=twoB -> A=twoB, B=twoA):
        // New A inherits old B's zoom, and new B inherits old A's zoom.
        model.exitCompare()
        await flushMainRunLoop()
        try await waitUntil { self.findPanes(in: hosted.window).count < 2 }
        model.openGroup(twoGroup.id, on: twoA)
        let twoTimeline = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        #expect(model.enterCompareFromDetail(timeline: twoTimeline))
        try await waitUntil {
            self.findPanes(in: hosted.window).count == 2
                && images.deliveries.contains { $0.0 == twoA && $0.2 == .screenRAW }
                && images.deliveries.contains { $0.0 == twoB && $0.2 == .screenRAW }
        }
        let (swapPaneA, swapPaneB) = try requirePanes(in: hosted.window)
        model.toggleCompareSyncLock()
        applyUserZoom(to: swapPaneA, scale: 2.3, anchor: DetailZoomAnchor(x: 0.28, y: 0.30))
        applyUserZoom(to: swapPaneB, scale: 1.7, anchor: DetailZoomAnchor(x: 0.72, y: 0.68))
        await flushMainRunLoop()
        let beforeSwapA = try #require(swapPaneA.zoomSnapshot)
        let beforeSwapB = try #require(swapPaneB.zoomSnapshot)

        #expect(model.promoteCompareChallengerToReference())
        #expect(model.compareSession?.reference == twoB)
        #expect(model.compareSession?.challenger == twoA)
        await flushMainRunLoop()
        try await Task.sleep(for: .milliseconds(80))
        await flushMainRunLoop()

        let afterSwapA = try #require(swapPaneA.zoomSnapshot)
        let afterSwapB = try #require(swapPaneB.zoomSnapshot)
        #expect(abs(afterSwapA.scale - beforeSwapB.scale) < 0.02)
        #expect(abs(afterSwapA.anchor.x - beforeSwapB.anchor.x) < 0.02)
        #expect(abs(afterSwapA.anchor.y - beforeSwapB.anchor.y) < 0.02)
        #expect(abs(afterSwapB.scale - beforeSwapA.scale) < 0.02)
        #expect(abs(afterSwapB.anchor.x - beforeSwapA.anchor.x) < 0.02)
        #expect(abs(afterSwapB.anchor.y - beforeSwapA.anchor.y) < 0.02)

        // 4. Sync Off 2-photo swap when A is Fit and B is zoomed:
        // New A inherits B's zoom, and new B resets to A's Fit.
        applyUserZoom(to: swapPaneA, scale: 1, anchor: .centre)
        applyUserZoom(to: swapPaneB, scale: 2.5, anchor: DetailZoomAnchor(x: 0.62, y: 0.38))
        await flushMainRunLoop()
        #expect(!swapPaneA.isZoomed)
        let beforeFitSwapB = try #require(swapPaneB.zoomSnapshot)

        #expect(model.promoteCompareChallengerToReference())
        #expect(model.compareSession?.reference == twoA)
        #expect(model.compareSession?.challenger == twoB)
        await flushMainRunLoop()
        try await Task.sleep(for: .milliseconds(80))
        await flushMainRunLoop()

        #expect(swapPaneA.isZoomed)
        #expect(!swapPaneB.isZoomed)
        let afterFitSwapA = try #require(swapPaneA.zoomSnapshot)
        #expect(abs(afterFitSwapA.scale - beforeFitSwapB.scale) < 0.02)
        #expect(abs(afterFitSwapA.anchor.x - beforeFitSwapB.anchor.x) < 0.02)
        #expect(abs(afterFitSwapA.anchor.y - beforeFitSwapB.anchor.y) < 0.02)
    }

    @Test(
        "Sync On converts scale across differing native resolutions and retargets when RAW size arrives"
    )
    func syncOnSteppingConvertsScaleAndRetargetsFullResolution() async throws {
        let library = ControlledPhotoLibrary(
            rejected: [], stems: ["p1big", "p2small", "p3late"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        library.reportScanFinished()
        try await waitUntil { !model.isFolderOpening && model.photos.count == 3 }

        let bigA = library.identity("p1big")
        let smallB = library.identity("p2small")
        let lateRawC = library.identity("p3late")
        model.openPhoto(bigA)
        let timeline = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        #expect(model.enterCompareFromDetail(timeline: timeline))

        let images = CompareTestDetailImages()
        let bigSize = CGSize(width: 6000, height: 4000)
        let smallSize = CGSize(width: 3000, height: 2000)
        let lateSize = CGSize(width: 4500, height: 3000)
        images.customFullSizes = [bigA: bigSize, smallB: smallSize, lateRawC: lateSize]
        images.unknownInitialFullSizePhotos.insert(lateRawC)

        let hosted = try await mountCompare(model: model, images: images)
        defer { hosted.tearDown() }

        try await waitUntil {
            images.deliveries.contains { $0.0 == bigA && $0.2 == .screenRAW }
                && images.deliveries.contains { $0.0 == smallB && $0.2 == .screenRAW }
        }
        let (paneA, paneB) = try requirePanes(in: hosted.window)

        let displayScale = hosted.host.traitCollection.displayScale
        let nativeBig = DetailZoom.fullResolutionScale(
            nativePixels: bigSize, shownPixels: bigSize, viewSize: paneA.bounds.size,
            screenScale: displayScale)
        let nativeSmall = DetailZoom.fullResolutionScale(
            nativePixels: smallSize, shownPixels: smallSize, viewSize: paneB.bounds.size,
            screenScale: displayScale)
        let nativeLate = DetailZoom.fullResolutionScale(
            nativePixels: lateSize, shownPixels: lateSize, viewSize: paneB.bounds.size,
            screenScale: displayScale)

        // 1. Double-tap bigA to 100% -> smallB syncs to its own 100%, and stepping to lateRawC
        //    (whose preview lacks fullResolutionSize) opens zoomed and retargets when RAW arrives.
        paneA.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.65, y: 0.40)))
        try await waitUntil {
            paneA.isZoomed && paneB.isZoomed
                && images.deliveries.contains { $0.0 == bigA && $0.2 == .nativeRAW }
        }
        await flushMainRunLoop()
        let snapA = try #require(paneA.zoomSnapshot)
        let snapSmall = try #require(paneB.zoomSnapshot)
        #expect(abs(snapA.scale - nativeBig) < 0.03)
        #expect(abs(snapSmall.scale - nativeSmall) < 0.03)

        #expect(model.stepCompareChallenger(offset: 1))
        #expect(model.compareSession?.challenger == lateRawC)
        try await waitUntil {
            images.deliveries.contains { $0.0 == lateRawC && $0.2 == .nativeRAW }
                && paneB.isZoomed
        }
        await flushMainRunLoop()
        try await Task.sleep(for: .milliseconds(80))
        await flushMainRunLoop()

        let snapLate = try #require(paneB.zoomSnapshot)
        #expect(abs(snapLate.scale - nativeLate) < 0.03)
        #expect(abs(snapLate.anchor.x - snapA.anchor.x) < 0.02)
        #expect(abs(snapLate.anchor.y - snapA.anchor.y) < 0.02)

        // 2. Non-100% manual zoom on bigA converts via DetailZoom.convertedScale when stepping back to smallB.
        let manualScaleA = nativeBig * 0.5
        let manualAnchor = DetailZoomAnchor(x: 0.35, y: 0.62)
        applyUserZoom(to: paneA, scale: manualScaleA, anchor: manualAnchor)
        await flushMainRunLoop()

        #expect(model.stepCompareChallenger(offset: -1))
        #expect(model.compareSession?.challenger == smallB)
        await flushMainRunLoop()
        try await Task.sleep(for: .milliseconds(80))
        await flushMainRunLoop()

        let expectedConvertedSmall = DetailZoom.convertedScale(
            manualScaleA, fromNativeScale: nativeBig, toNativeScale: nativeSmall)
        let snapConvertedSmall = try #require(paneB.zoomSnapshot)
        #expect(abs(snapConvertedSmall.scale - expectedConvertedSmall) < 0.03)
        #expect(abs(snapConvertedSmall.anchor.x - manualAnchor.x) < 0.02)
        #expect(abs(snapConvertedSmall.anchor.y - manualAnchor.y) < 0.02)
    }

    @Test(
        "CompareFilmstrip raises only challenger B with full-opacity two-tone marker across activeSide switches and stepping"
    )
    func compareFilmstripPinsLiftAndTwoToneMarkerToChallengerOnly() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let folder = FolderIdentity(rawValue: "compare-filmstrip-marker")
        let p1 = GridPhoto(
            id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "CMP0001"),
            fileName: "CMP0001.ARW",
            time: .unavailable,
            marks: PhotoMarks())
        let p2 = GridPhoto(
            id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "CMP0002"),
            fileName: "CMP0002.ARW",
            time: .unavailable,
            marks: PhotoMarks(rating: .rejected))
        let p3 = GridPhoto(
            id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "CMP0003"),
            fileName: "CMP0003.ARW",
            time: .unavailable,
            marks: PhotoMarks())
        let photos = [p1, p2, p3]
        let whiteThumb = makeSolidCGImage(
            width: 32, height: 32, red: 1, green: 1, blue: 1)
        let thumbnails = CompareStaticThumbnails(image: whiteThumb)

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 140)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        func renderColor(
            _ style: CloveColour,
            referenceDimmedOverWhite: Bool = false,
            theme: CloveTheme
        ) throws -> (UInt8, UInt8, UInt8) {
            let swatch: AnyView =
                if referenceDimmedOverWhite {
                    AnyView(
                        ZStack {
                            Color.black
                            Color.white
                                .overlay {
                                    Rectangle().fill(style)
                                }
                                .opacity(0.78)
                        })
                } else {
                    AnyView(
                        ZStack {
                            Color.black
                            Rectangle().fill(style)
                        })
                }
            let renderer = ImageRenderer(
                content: swatch.frame(width: 8, height: 8).environment(\.cloveTheme, theme))
            renderer.scale = 1
            let cg = try #require(renderer.cgImage)
            let (r, g, b, _) = try pixelAt(x: 4, y: 4, in: cg)
            return (r, g, b)
        }

        func captureFilmstrip(
            challenger: PhotoIdentity,
            activeSide: CompareSide,
            theme: CloveTheme
        ) async throws -> CGImage {
            let strip = CompareFilmstrip(
                photos: photos,
                reference: p1.id,
                challenger: challenger,
                activeSide: activeSide,
                thumbnails: thumbnails,
                onSelectCandidate: { _ in }
            )
            .frame(width: 240, height: 56)
            .background(Color.black)
            .ignoresSafeArea()
            .environment(\.cloveTheme, theme)

            let host = UIHostingController(rootView: AnyView(strip))
            host.safeAreaRegions = []
            host.view.backgroundColor = .black
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            let region = CGRect(x: 40, y: (140 - 56) / 2.0, width: 240, height: 56)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let rendered = UIGraphicsImageRenderer(size: region.size, format: format).image { ctx in
                ctx.cgContext.translateBy(x: -region.minX, y: -region.minY)
                _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            return try #require(rendered.cgImage)
        }

        for theme in [CloveTheme.light, CloveTheme.dark] {
            let expectedCore = try renderColor(Color.clove.text.primary, theme: theme)
            let expectedEdge = try renderColor(Color.clove.bg.canvas, theme: theme)
            let expectedDimmedAccent = try renderColor(
                Color.clove.accent, referenceDimmedOverWhite: true, theme: theme)

            // 1. activeSide == .challenger: B (p2, rejected) is raised 6 pt and carries the marker.
            let bActiveImage = try await captureFilmstrip(
                challenger: p2.id, activeSide: .challenger, theme: theme)
            // 2. activeSide == .reference: B STILL carries the lift & marker; A gets accent badge only.
            let aActiveImage = try await captureFilmstrip(
                challenger: p2.id, activeSide: .reference, theme: theme)
            // 3. Stepping B to p3: lift & marker move to p3 while p2 drops back to baseline.
            let steppedImage = try await captureFilmstrip(
                challenger: p3.id, activeSide: .reference, theme: theme)

            // ScrollView starts flush-leading at x=0 (padding 4):
            // verify horizontal spans dynamically from mid-band pixels so center scrolling doesn't shift coordinates.
            let spans = try horizontalTileSpans(in: bActiveImage, y: 56)
            #expect(spans.count == 3)
            let xA = (spans[0].lowerBound + spans[0].upperBound) / 2
            let xB = (spans[1].lowerBound + spans[1].upperBound) / 2
            let x3 = (spans[2].lowerBound + spans[2].upperBound) / 2

            // Tile vertical bounds (sample away from top-left A/B badge and centered marker):
            let sampleA = xA + 20
            let sampleB = xB + 20
            let sample3 = x3 + 20

            let bActiveSpanA = try #require(try verticalLitSpan(in: bActiveImage, x: sampleA))
            let bActiveSpanB = try #require(try verticalLitSpan(in: bActiveImage, x: sampleB))
            let bActiveSpan3 = try #require(try verticalLitSpan(in: bActiveImage, x: sample3))
            #expect(bActiveSpanA.lowerBound - bActiveSpanB.lowerBound == 12)
            #expect(bActiveSpanA.upperBound - bActiveSpanB.upperBound == 12)
            #expect(bActiveSpanA == bActiveSpan3)

            // Marker sits at bottom of slot (y = 53 pt = 106 px bottom -> center 102 px, top edge 99 px).
            let markerTopPx = 106 - 8
            #expect(try pixelAt(x: xB, y: markerTopPx - 2, in: bActiveImage).0 < 20)
            try expectColorClose(
                pixelAt(x: xB, y: markerTopPx + 4, in: bActiveImage), expectedCore,
                "\(theme.rawValue) rejected B marker core")
            try expectColorClose(
                pixelAt(x: xB, y: markerTopPx + 1, in: bActiveImage), expectedEdge,
                "\(theme.rawValue) rejected B marker edge", tolerance: 30)
            // Unraised A occupies the baseline down to markerTopPx + 7 (no 2 pt gap, no marker).
            #expect(try pixelAt(x: xA, y: markerTopPx - 2, in: bActiveImage).0 > 120)
            #expect(try pixelAt(x: xA, y: markerTopPx + 9, in: bActiveImage).0 < 20)
            #expect(
                try !isColorClose(
                    pixelAt(x: xA, y: markerTopPx + 4, in: bActiveImage), expectedCore))

            // Switching activeSide to .reference leaves lift & marker strictly on B (not A!).
            let aActiveSpanA = try #require(try verticalLitSpan(in: aActiveImage, x: sampleA))
            let aActiveSpanB = try #require(try verticalLitSpan(in: aActiveImage, x: sampleB))
            #expect(aActiveSpanA.lowerBound - aActiveSpanB.lowerBound == 12)
            #expect(aActiveSpanA.upperBound - aActiveSpanB.upperBound == 12)
            #expect(try pixelAt(x: xB, y: markerTopPx - 2, in: aActiveImage).0 < 20)
            try expectColorClose(
                pixelAt(x: xB, y: markerTopPx + 4, in: aActiveImage), expectedCore,
                "\(theme.rawValue) A-active still keeps marker on B core")
            try expectColorClose(
                pixelAt(x: xB, y: markerTopPx + 1, in: aActiveImage), expectedEdge,
                "\(theme.rawValue) A-active still keeps marker on B edge", tolerance: 30)
            #expect(try pixelAt(x: xA, y: markerTopPx - 2, in: aActiveImage).0 > 120)
            #expect(try pixelAt(x: xA, y: markerTopPx + 9, in: aActiveImage).0 < 20)
            #expect(
                try !isColorClose(
                    pixelAt(x: xA, y: markerTopPx + 4, in: aActiveImage), expectedCore))

            // Badge A turns accent (within 0.78 reference frame opacity) when activeSide == .reference.
            let hasAccentOnBadgeA = { (image: CGImage) in
                (18..<48).contains { y in
                    (spans[0].lowerBound..<(spans[0].lowerBound + 34)).contains { x in
                        guard let px = try? pixelAt(x: x, y: y, in: image) else { return false }
                        return abs(Int(px.0) - Int(expectedDimmedAccent.0)) <= 16
                            && abs(Int(px.1) - Int(expectedDimmedAccent.1)) <= 16
                            && abs(Int(px.2) - Int(expectedDimmedAccent.2)) <= 16
                    }
                }
            }
            #expect(
                !hasAccentOnBadgeA(bActiveImage),
                "\(theme.rawValue) A badge quiet when challenger active")
            #expect(
                hasAccentOnBadgeA(aActiveImage),
                "\(theme.rawValue) A badge accent when reference active")

            // Stepping B to p3 moves lift and marker to p3 and drops p2 back to baseline.
            let steppedSpans = try horizontalTileSpans(in: steppedImage, y: 56)
            #expect(steppedSpans.count == 3)
            let sxA = (steppedSpans[0].lowerBound + steppedSpans[0].upperBound) / 2
            let sx2 = (steppedSpans[1].lowerBound + steppedSpans[1].upperBound) / 2
            let sx3 = (steppedSpans[2].lowerBound + steppedSpans[2].upperBound) / 2
            let steppedSpanA = try #require(try verticalLitSpan(in: steppedImage, x: sxA + 20))
            let steppedSpan2 = try #require(try verticalLitSpan(in: steppedImage, x: sx2 + 20))
            let steppedSpan3 = try #require(try verticalLitSpan(in: steppedImage, x: sx3 + 20))
            #expect(steppedSpanA == steppedSpan2)
            #expect(steppedSpan2.lowerBound - steppedSpan3.lowerBound == 12)
            #expect(try pixelAt(x: sx3, y: markerTopPx - 2, in: steppedImage).0 < 20)
            try expectColorClose(
                pixelAt(x: sx3, y: markerTopPx + 4, in: steppedImage), expectedCore,
                "\(theme.rawValue) stepped challenger p3 marker core")
            try expectColorClose(
                pixelAt(x: sx3, y: markerTopPx + 1, in: steppedImage), expectedEdge,
                "\(theme.rawValue) stepped challenger p3 marker edge", tolerance: 30)
            // Dropped p2 (rejected) returns to baseline down to markerTopPx + 7 (no marker gap above it).
            #expect(try pixelAt(x: sx2, y: markerTopPx - 2, in: steppedImage).0 > 40)
            #expect(try pixelAt(x: sx2, y: markerTopPx + 9, in: steppedImage).0 < 20)
            #expect(
                try !isColorClose(
                    pixelAt(x: sx2, y: markerTopPx + 4, in: steppedImage), expectedCore))
        }
    }

    private struct HostedCompare {
        let window: UIWindow
        let host: UIHostingController<AnyView>

        @MainActor
        func tearDown() {
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private func mountCompare(
        model: BrowsingModel, images: any DetailImageSource
    ) async throws -> HostedCompare {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let store = SettingsStore.sample
        let host = UIHostingController(
            rootView: AnyView(
                DetailScreen(browsing: model, images: images)
                    .environment(store)))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 852, height: 393)
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .compact
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitUntil { self.findPanes(in: window).count == 2 }
        return HostedCompare(window: window, host: host)
    }

    private func requirePanes(in window: UIWindow) throws -> (
        paneA: DetailZoomContainerView, paneB: DetailZoomContainerView
    ) {
        let panes = findPanes(in: window).sorted {
            $0.convert($0.bounds, to: window).minX < $1.convert($1.bounds, to: window).minX
        }
        #expect(panes.count == 2)
        return (panes[0], panes[1])
    }

    private func findPanes(in view: UIView) -> [DetailZoomContainerView] {
        var found: [DetailZoomContainerView] = []
        if let pane = view as? DetailZoomContainerView {
            found.append(pane)
        }
        for child in view.subviews {
            found.append(contentsOf: findPanes(in: child))
        }
        return found
    }

    private func applyUserZoom(
        to pane: DetailZoomContainerView, scale: CGFloat, anchor: DetailZoomAnchor
    ) {
        pane.applySyncedViewport(scale: scale, anchor: anchor)
        pane.onViewportChanged?(
            scale <= DetailFitScale.tolerance
                ? nil : DetailZoomSnapshot(scale: scale, anchor: anchor))
    }

    private func flushMainRunLoop() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func makeSolidCGImage(
        width: Int, height: Int, red: CGFloat = 0.4, green: CGFloat = 0.5, blue: CGFloat = 0.6
    ) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func pixelAt(x: Int, y: Int, in image: CGImage) throws -> (UInt8, UInt8, UInt8, UInt8) {
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
        let offset = (y * width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }

    private func expectColorClose(
        _ actual: (UInt8, UInt8, UInt8, UInt8),
        _ expected: (UInt8, UInt8, UInt8),
        _ label: String,
        tolerance: Int = 12,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            isColorClose(actual, expected, tolerance: tolerance),
            "\(label): actual \(actual) != expected \(expected)",
            sourceLocation: sourceLocation)
    }

    private func isColorClose(
        _ actual: (UInt8, UInt8, UInt8, UInt8),
        _ expected: (UInt8, UInt8, UInt8),
        tolerance: Int = 12
    ) -> Bool {
        abs(Int(actual.0) - Int(expected.0)) <= tolerance
            && abs(Int(actual.1) - Int(expected.1)) <= tolerance
            && abs(Int(actual.2) - Int(expected.2)) <= tolerance
            && actual.3 == 255
    }

    private func horizontalTileSpans(in image: CGImage, y: Int) throws -> [ClosedRange<Int>] {
        var spans: [ClosedRange<Int>] = []
        var start: Int?
        for x in 0..<image.width {
            let (r, g, b, _) = try pixelAt(x: x, y: y, in: image)
            let isLit = r > 20 || g > 20 || b > 20
            if isLit {
                if start == nil { start = x }
            } else if let openStart = start {
                spans.append(openStart...(x - 1))
                start = nil
            }
        }
        if let openStart = start {
            spans.append(openStart...(image.width - 1))
        }
        return spans
    }

    private func verticalLitSpan(in image: CGImage, x: Int) throws -> ClosedRange<Int>? {
        var minY: Int?
        var maxY: Int?
        for y in 0..<image.height {
            let (r, g, b, _) = try pixelAt(x: x, y: y, in: image)
            if r > 40 || g > 40 || b > 40 {
                if minY == nil { minY = y }
                maxY = y
            }
        }
        guard let minY, let maxY else { return nil }
        return minY...maxY
    }
}

@MainActor
private final class CompareStaticThumbnails: GridThumbnailSource {
    private let image: CGImage

    init(image: CGImage) {
        self.image = image
    }

    func cachedThumbnail(for photo: PhotoIdentity) -> GridThumbnailOutcome? { .image(image) }
    func companions(for photo: PhotoIdentity) -> GridCompanions { GridCompanions() }
    func thumbnail(for photo: PhotoIdentity, priority: GridThumbnailPriority) async
        -> GridThumbnailOutcome
    { .image(image) }
}

@MainActor
private final class CompareTestDetailImages: DetailImageSource {
    private let sample = SampleDetailImages()
    var warmPhotos: Set<PhotoIdentity> = []
    var delayedColdPhotos: [PhotoIdentity: Duration] = [:]
    var customFullSizes: [PhotoIdentity: CGSize] = [:]
    var unknownInitialFullSizePhotos: Set<PhotoIdentity> = []
    private(set) var requests: [(PhotoIdentity, DetailPixelRequest)] = []
    private(set) var deliveries: [(PhotoIdentity, DetailPixelRequest.Need, DetailQuality)] = []
    private var cachedPreviews: [PhotoIdentity: DetailImage] = [:]

    func warmImage(for photo: PhotoIdentity, request: DetailPixelRequest) -> DetailImage? {
        guard warmPhotos.contains(photo), request.need == .preview else { return nil }
        if let cached = cachedPreviews[photo] { return cached }
        let fullSize =
            unknownInitialFullSizePhotos.contains(photo)
            ? nil
            : (customFullSizes[photo] ?? CGSize(width: 3000, height: 2000))
        let image = makeImage(
            photo,
            size: CGSize(width: 1616, height: 1077),
            quality: .preview,
            fullSize: fullSize)
        cachedPreviews[photo] = image
        return image
    }

    func prepare(_ window: DetailPhotoWindow) async {
        await sample.prepare(window)
    }

    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        requests.append((photo, request))
        if let delay = delayedColdPhotos[photo], request.need == .preview {
            do { try await Task.sleep(for: delay) } catch { return .deferred }
        }
        if warmPhotos.contains(photo), request.need == .preview,
            let warm = warmImage(for: photo, request: request)
        {
            deliveries.append((photo, request.need, warm.quality))
            return .image(warm)
        }
        if let customSize = customFullSizes[photo] {
            let image: DetailImage
            switch request.need {
            case .preview:
                let includeSize = !unknownInitialFullSizePhotos.contains(photo)
                image = makeImage(
                    photo,
                    size: CGSize(width: 1616, height: 1077),
                    quality: .preview,
                    fullSize: includeSize ? customSize : nil)
            case .screenRender:
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return .deferred }
                image = makeImage(
                    photo,
                    size: CGSize(width: 2400, height: 1600),
                    quality: .screenRAW,
                    fullSize: customSize)
            case .morePixels, .fullResolution:
                image = makeImage(
                    photo,
                    size: customSize,
                    quality: .nativeRAW,
                    fullSize: customSize)
            }
            deliveries.append((photo, request.need, image.quality))
            return .image(image)
        }
        if request.need == .preview && unknownInitialFullSizePhotos.contains(photo) {
            let image = makeImage(
                photo,
                size: CGSize(width: 1616, height: 1077),
                quality: .preview,
                fullSize: nil)
            deliveries.append((photo, request.need, image.quality))
            return .image(image)
        }
        let outcome = await sample.image(for: photo, request: request)
        if case .image(let image) = outcome {
            if request.need == .preview {
                cachedPreviews[photo] = image
            }
            deliveries.append((photo, request.need, image.quality))
        }
        return outcome
    }

    func setCompareRetention(active: Bool, keeping photo: PhotoIdentity?) async {
        await sample.setCompareRetention(active: active, keeping: photo)
    }

    func releaseComparePhoto(_ photo: PhotoIdentity) async {
        await sample.releaseComparePhoto(photo)
    }

    func prefetchPreviews(_ window: DetailPhotoWindow) async {
        await sample.prefetchPreviews(window)
    }

    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
        await sample.prefetch(window, renderAhead: renderAhead)
    }

    func leave(window: UUID) async {
        await sample.leave(window: window)
    }

    private func makeImage(
        _ photo: PhotoIdentity, size: CGSize, quality: DetailQuality, fullSize: CGSize?
    ) -> DetailImage {
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.35, green: 0.45, blue: 0.55, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let source = DetailSource(
            url: URL(
                fileURLWithPath: "/clove.test-library/\(photo.relativeFolderPath)/\(photo.stem).ARW"
            ),
            revision: ThumbnailRevision(size: 0, modificationTime: .distantPast))
        return DetailImage(
            image: context.makeImage()!,
            source: source,
            quality: quality,
            hasRAW: true,
            fullResolutionSize: fullSize)
    }
}
