import CloveCore
import CloveImaging
import CoreGraphics
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
@Suite("Compare flow")
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

    private func makeSolidCGImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
