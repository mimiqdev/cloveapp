import CloveCore
import CloveImaging
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Clove

@Suite(.serialized)
@MainActor
struct WorkflowPresentationTests {
    @Test func moveRejectsToastShowsOnlyDetailsOnPartialFailureAndUndoOnSuccess() throws {
        let library = ControlledPhotoLibrary(rejected: ["a", "b"], stems: ["a", "b"])
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        let a = library.identity("a")
        let b = library.identity("b")

        let fileA = RejectMoveFilePlan(
            role: .primary,
            source: URL(fileURLWithPath: "/Library/a.ARW"),
            destination: URL(fileURLWithPath: "/Library/_Rejected/a.ARW"))
        let fileB = RejectMoveFilePlan(
            role: .primary,
            source: URL(fileURLWithPath: "/Library/b.ARW"),
            destination: URL(fileURLWithPath: "/Library/_Rejected/b.ARW"))

        // 1. Full success: shows Undo action and no Details action.
        let successCompleted = CompletedRejectMove(
            result: RejectMoveResult(
                id: RejectMoveBatchID(),
                outcomes: [
                    .moved(
                        RejectMoveMovedSet(
                            identity: a, files: [fileA], removedStoredReject: true,
                            staleRejectRecord: nil)),
                    .moved(
                        RejectMoveMovedSet(
                            identity: b, files: [fileB], removedStoredReject: true,
                            staleRejectRecord: nil)),
                ]),
            rejectsFolderName: .defaultFolderName,
            folder: browsing.state.folder,
            openGeneration: browsing.openGeneration)

        let successPresentation = MoveRejectsToast.presentation(
            for: successCompleted, canUndo: true, language: .english)
        #expect(successPresentation.message == "Moved 2 to _Rejected")
        #expect(successPresentation.detail == nil)
        #expect(successPresentation.actionTitle == "Undo")
        #expect(successPresentation.actionKind == .undo)

        let disabledUndoPresentation = MoveRejectsToast.presentation(
            for: successCompleted, canUndo: false, language: .english)
        #expect(disabledUndoPresentation.actionTitle == nil)
        #expect(disabledUndoPresentation.actionKind == nil)

        for theme in [CloveTheme.light, .dark] {
            let actual = try renderPNG(
                MoveRejectsToast(browsing: browsing, completed: successCompleted) {},
                theme: theme)
            let expectedUndoOnly = try renderPNG(
                Toast(
                    message: "Moved 2 to _Rejected",
                    actionTitle: "Undo",
                    identifier: "clove.moves.toast",
                    onAction: {}),
                theme: theme)
            #expect(actual == expectedUndoOnly)
        }

        // 2. Partial failure: shows only Details action and never Undo in the toast.
        let partialCompleted = CompletedRejectMove(
            result: RejectMoveResult(
                id: RejectMoveBatchID(),
                outcomes: [
                    .moved(
                        RejectMoveMovedSet(
                            identity: a, files: [fileA], removedStoredReject: true,
                            staleRejectRecord: nil)),
                    .failed(
                        RejectMoveFailedSet(
                            identity: b,
                            failure: RejectMoveFailure(
                                reason: .permissionLost, message: "Permission denied"),
                            files: [fileB])),
                ]),
            rejectsFolderName: .defaultFolderName,
            folder: browsing.state.folder,
            openGeneration: browsing.openGeneration)

        let partialPresentation = MoveRejectsToast.presentation(
            for: partialCompleted, canUndo: true, language: .english)
        #expect(partialPresentation.message == "Moved 1 to _Rejected")
        #expect(partialPresentation.detail == "1 couldn't be moved")
        #expect(partialPresentation.actionTitle == "Details")
        #expect(partialPresentation.actionKind == .details)

        for theme in [CloveTheme.light, .dark] {
            let actual = try renderPNG(
                MoveRejectsToast(browsing: browsing, completed: partialCompleted) {},
                theme: theme)
            let expectedDetailsOnly = try renderPNG(
                Toast(
                    message: "Moved 1 to _Rejected",
                    detail: "1 couldn't be moved",
                    actionTitle: "Details",
                    identifier: "clove.moves.toast",
                    onAction: {}),
                theme: theme)
            let oldBothButtons = try renderPNG(
                Toast(
                    message: "Moved 1 to _Rejected",
                    detail: "1 couldn't be moved",
                    actionTitle: "Undo",
                    secondaryActionTitle: "Details",
                    onSecondaryAction: {},
                    identifier: "clove.moves.toast",
                    onAction: {}),
                theme: theme)
            #expect(actual == expectedDetailsOnly)
            #expect(actual != oldBothButtons)
        }
    }

    @Test func renameOrderTilesShowMarkBadgesAndUpdatedOrderFooterCopy() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let fourStars = try #require(Rating(rawValue: 4))
        let unmarked = PhotoMarks()
        let marked = PhotoMarks(rating: fourStars, label: ColourLabel(colour: .red))

        // Shared tile badge overlays produce distinct pixels matching GridPhotoCell tokens.
        let bareTile = Color.gray.frame(width: 120, height: 120)
            .overlay(alignment: .bottomLeading) { PhotoTileRatingBadge(rating: unmarked.rating) }
            .overlay(alignment: .bottomTrailing) { PhotoTileLabelDot(label: unmarked.label) }
        let badgedTile = Color.gray.frame(width: 120, height: 120)
            .overlay(alignment: .bottomLeading) { PhotoTileRatingBadge(rating: marked.rating) }
            .overlay(alignment: .bottomTrailing) { PhotoTileLabelDot(label: marked.label) }
        #expect(try renderPNG(bareTile, theme: .light) != renderPNG(badgedTile, theme: .light))

        #expect(BatchRenameOrderScreen.footerText() == "Cancel discards changes to the order.")

        // RenameOrderGrid renders existing rating pills and colour label dots on reorder tiles.
        let library = TestLibrary.sample()
        let browsing = BrowsingModel(library: library, similarGroupsEnabled: false)
        browsing.openFolder()
        let photos = Array(browsing.photos.prefix(2))
        browsing.apply(.rating(fourStars), to: photos[0].id)
        browsing.apply(.label(ColourLabel(colour: .green)), to: photos[0].id)
        browsing.apply(.rating(.unrated), to: photos[1].id)
        browsing.apply(.label(.clear), to: photos[1].id)
        for photo in photos { browsing.toggleSelection(photo.id) }

        let flow = BatchRenameFlow(browsing: browsing)
        let framesBox = WorkflowFrameStore()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 844)
        let host = UIHostingController(
            rootView: BatchRenameOrderScreen(flow: flow)
                .environment(SettingsStore.sample)
                .environment(\.cloveTheme, .light)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                    framesBox.frames = $0
                })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        var collectionView: UICollectionView?
        try await waitFor("rename order screen did not lay out") {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            collectionView = self.findCollectionView(in: window)
            return collectionView?.visibleCells.count == 2
                && framesBox.frames["clove.rename.order.footer"] != nil
        }

        let grid = try #require(collectionView)
        let firstCell = try #require(grid.cellForItem(at: IndexPath(item: 0, section: 0)))
        let secondCell = try #require(grid.cellForItem(at: IndexPath(item: 1, section: 0)))
        let firstCellPNG = try renderViewPNG(firstCell)
        let secondCellPNG = try renderViewPNG(secondCell)
        #expect(!firstCellPNG.isEmpty && !secondCellPNG.isEmpty)
        #expect(firstCellPNG != secondCellPNG)

        let footerFrame = try #require(framesBox.frames["clove.rename.order.footer"])
        #expect(footerFrame.height > 0)
        #expect(footerFrame.minY >= grid.convert(grid.bounds, to: window).maxY - 1)
    }

    @Test func batchRenameNameSheetOrdersFieldsAddsCopyUsesAccentCTAAndOrdersRunningFooter()
        async throws
    {
        #expect(BatchRenameNameSheet.subtitleText() == "Preview names before applying changes.")
        #expect(
            BatchRenameNameSheet.previewNoteText() == "Replacements are flagged in the preview.")
        #expect(
            BatchRenameNameSheet.confirmTitle(totalCount: 2, replacementCount: 1)
                == "Rename 2 · Replace 1")
        #expect(
            BatchRenameNameSheet.confirmTitle(totalCount: 3, replacementCount: 0)
                == "Rename 3 photos")

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let library = TestLibrary.forLaunch(
            environment: [
                TestLibrary.launchVariable: "1",
                "CLOVE_TEST_LIBRARY_RENAME_PREVIEW": "1",
            ])
        let browsing = BrowsingModel(library: library, similarGroupsEnabled: false)
        browsing.openFolder()
        // Select first two photos so mmq02678 triggers replacement without mmq02680's problem.
        for photo in browsing.photos.prefix(2) { browsing.toggleSelection(photo.id) }
        let flow = BatchRenameFlow(
            browsing: browsing, defaults: BatchRenameDefaults(storage: SampleSettingsStorage()))
        flow.options.prefix = "Test_"
        await flow.prepare(rejectsFolderName: .defaultFolderName)
        #expect((flow.preview?.replacementCount ?? 0) == 1)
        #expect(flow.canRename)

        let framesBox = WorkflowFrameStore()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 420, height: 844)
        let host = UIHostingController(
            rootView: BatchRenameNameSheet(flow: flow, completion: {})
                .environment(SettingsStore.sample)
                .environment(\.cloveTheme, .light)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                    framesBox.frames = $0
                })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let orderedFieldIDs = [
            "clove.rename.prefix",
            "clove.rename.captureDate",
            "clove.rename.separator",
            "clove.rename.startInput",
            "clove.rename.digits",
        ]

        try await waitFor("rename name sheet did not lay out") {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let hasCopy =
                framesBox.frames["clove.rename.subtitle"] != nil
                && framesBox.frames["clove.rename.previewNote"] != nil
                && framesBox.frames["clove.rename.confirm"] != nil
            let hasFields = orderedFieldIDs.allSatisfy { framesBox.frames[$0] != nil }
            return flow.canRename && flow.preview != nil && hasCopy && hasFields
        }
        // Let SwiftUI flush the enabled CTA opacity (1.0) after .task prepare completes.
        try await Task.sleep(for: .milliseconds(60))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let fieldFrames = try orderedFieldIDs.map { try #require(framesBox.frames[$0]) }
        for idx in 0..<(fieldFrames.count - 1) {
            #expect(fieldFrames[idx].minY < fieldFrames[idx + 1].minY)
        }

        // Replacement CTA uses non-destructive accent fill rather than red reject fill.
        let confirmFrame = try #require(framesBox.frames["clove.rename.confirm"])
        let windowImage = try renderWindowImage(window)
        let confirmCenterPixel = try pixelRGBA(
            in: windowImage, at: CGPoint(x: confirmFrame.minX + 32, y: confirmFrame.midY))
        let expectedAccent = try renderedRGBA(CloveTheme.light.tokens.accent.color)
        let unexpectedReject = try renderedRGBA(CloveTheme.light.tokens.reject.color)
        #expect(rgbaDistance(confirmCenterPixel, expectedAccent) < 24)
        #expect(rgbaDistance(confirmCenterPixel, unexpectedReject) > 60)

        // Running footer orders progress text above undo warning above progress bar.
        let heldLibrary = HeldRunningRenameLibrary()
        let heldBrowsing = BrowsingModel(library: heldLibrary, similarGroupsEnabled: false)
        heldBrowsing.openFolder()
        for photo in heldBrowsing.photos.prefix(2) { heldBrowsing.toggleSelection(photo.id) }
        let runningFlow = BatchRenameFlow(
            browsing: heldBrowsing, defaults: BatchRenameDefaults(storage: SampleSettingsStorage()))
        runningFlow.options.prefix = "Run_"
        await runningFlow.prepare(rejectsFolderName: .defaultFolderName)

        let runningFrames = WorkflowFrameStore()
        let runningWindow = UIWindow(windowScene: scene)
        runningWindow.frame = CGRect(x: 0, y: 0, width: 420, height: 844)
        let runningHost = UIHostingController(
            rootView: BatchRenameNameSheet(flow: runningFlow, completion: {})
                .environment(SettingsStore.sample)
                .environment(\.cloveTheme, .light)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                    runningFrames.frames = $0
                })
        runningWindow.rootViewController = runningHost
        runningWindow.makeKeyAndVisible()
        defer {
            heldLibrary.releaseRename?.resume()
            heldLibrary.releaseRename = nil
            runningWindow.isHidden = true
            runningWindow.rootViewController = nil
        }

        // Let BatchRenameNameSheet's initial `.task(id: flow.options)` settle before starting rename.
        try await waitFor("running rename sheet did not prepare") {
            runningHost.view.setNeedsLayout()
            runningHost.view.layoutIfNeeded()
            return runningFlow.canRename
                && runningFlow.preview != nil
                && runningFrames.frames["clove.rename.confirm"] != nil
        }

        let renameTask = Task { await runningFlow.rename {} }
        try await waitFor("running footer did not lay out") {
            runningHost.view.setNeedsLayout()
            runningHost.view.layoutIfNeeded()
            return runningFlow.isRunning
                && runningFrames.frames["clove.rename.progress"] != nil
                && runningFrames.frames["clove.rename.warning"] != nil
                && runningFrames.frames["clove.rename.progressBar"] != nil
        }

        let progressFrame = try #require(runningFrames.frames["clove.rename.progress"])
        let warningFrame = try #require(runningFrames.frames["clove.rename.warning"])
        let barFrame = try #require(runningFrames.frames["clove.rename.progressBar"])
        #expect(progressFrame.maxY <= warningFrame.minY + 1)
        #expect(warningFrame.maxY <= barFrame.minY + 1)

        heldLibrary.releaseRename?.resume()
        heldLibrary.releaseRename = nil
        await renameTask.value
    }

    @Test func errorBannerFloatsOverDimmedGridAndDetailWithoutVerticalLayoutShift() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        // 1. GridScreen: floating FolderSaveBanner never shifts UICollectionView downward.
        do {
            let library = ControlledPhotoLibrary(
                rejected: [], stems: ["a", "b", "c", "d", "e", "f"])
            let browsing = BrowsingModel(library: library, similarGroupsEnabled: false)
            browsing.openFolder()
            library.reportScanFinished()
            try await waitFor("grid folder finished opening") { !browsing.isFolderOpening }

            let framesBox = WorkflowFrameStore()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 844)
            let host = UIHostingController(
                rootView: GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
                    .environment(SettingsStore.sample)
                    .environment(\.cloveUserInterfaceIdiom, .phone)
                    .environment(\.cloveTheme, .light)
                    .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                        framesBox.frames = $0
                    })
            host.traitOverrides.horizontalSizeClass = .compact
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            var collectionView: UICollectionView?
            try await waitFor("grid collection did not lay out") {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                collectionView = self.findCollectionView(in: window)
                return collectionView?.visibleCells.isEmpty == false
            }
            let grid = try #require(collectionView)
            let beforeRect = grid.convert(grid.bounds, to: window)
            let beforePNG = try renderViewPNG(window)
            #expect(framesBox.frames["clove.grid.saveState.failure"] == nil)

            library.reportDriveLoss()
            try await waitFor("grid ErrorBanner did not appear") {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                return framesBox.frames["clove.grid.saveState.failure"] != nil
                    && framesBox.frames["clove.grid.saveState.failure.action"] != nil
            }
            let afterRect = grid.convert(grid.bounds, to: window)
            let afterPNG = try renderViewPNG(window)
            let bannerFrame = try #require(framesBox.frames["clove.grid.saveState.failure"])
            let actionFrame = try #require(framesBox.frames["clove.grid.saveState.failure.action"])
            #expect(abs(afterRect.minY - beforeRect.minY) <= 0.5)
            #expect(abs(afterRect.height - beforeRect.height) <= 0.5)
            #expect(bannerFrame.minY >= afterRect.minY - 1)
            #expect(bannerFrame.maxY <= afterRect.maxY + 1)
            #expect(bannerFrame.intersects(actionFrame))
            #expect(afterPNG != beforePNG)
        }

        // 2. DetailMarkingView (standard layout): floating FolderSaveBanner never shifts stage downward.
        do {
            let library = TestLibrary.sample()
            let browsing = BrowsingModel(library: library, similarGroupsEnabled: false)
            browsing.openFolder()
            try await waitFor("detail folder finished opening") { !browsing.isFolderOpening }
            let photo = try #require(browsing.photos.first)
            browsing.openPhoto(photo.id)

            let store = SettingsStore.sample
            store.markGestureGuideSeen()
            let framesBox = WorkflowFrameStore()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 844)
            let host = UIHostingController(
                rootView: DetailMarkingView(
                    browsing: browsing,
                    photo: photo,
                    settings: store.settings,
                    images: SampleDetailImages(),
                    order: browsing.photos,
                    actions: DetailMarkingActions(
                        apply: { _, _ in },
                        marked: { _, _, _ in },
                        step: { _ in },
                        markingSwipeBegan: {})
                )
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.cloveTheme, .light)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                    framesBox.frames = $0
                })
            host.traitOverrides.horizontalSizeClass = .compact
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            var preview: DetailZoomContainerView?
            try await waitFor("detail stage did not lay out") {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                preview = self.findPreview(in: window)
                return preview != nil
            }
            let stage = try #require(preview)
            let beforeStageRect = stage.convert(stage.bounds, to: window)
            let beforePNG = try renderViewPNG(window)
            #expect(framesBox.frames["clove.detail.saveStatus.failure"] == nil)

            library.reportLocationLoss(.locationUnavailable)
            try await waitFor("detail ErrorBanner did not appear") {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                guard let banner = framesBox.frames["clove.detail.saveStatus.failure"],
                    framesBox.frames["clove.detail.saveStatus.failure.action"] != nil
                else {
                    return false
                }
                let currentStage = stage.convert(stage.bounds, to: window)
                return abs(banner.minY - currentStage.minY) <= 1
            }
            let afterStageRect = stage.convert(stage.bounds, to: window)
            let afterPNG = try renderViewPNG(window)
            let bannerFrame = try #require(framesBox.frames["clove.detail.saveStatus.failure"])
            let actionFrame = try #require(
                framesBox.frames["clove.detail.saveStatus.failure.action"])
            #expect(abs(afterStageRect.minY - beforeStageRect.minY) <= 0.5)
            #expect(abs(afterStageRect.height - beforeStageRect.height) <= 0.5)
            #expect(bannerFrame.minY >= afterStageRect.minY - 1)
            #expect(bannerFrame.maxY <= afterStageRect.maxY + 1)
            #expect(bannerFrame.intersects(actionFrame))
            #expect(afterPNG != beforePNG)
        }
    }

    private func waitFor(
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

    private func findCollectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        for child in view.subviews {
            if let found = findCollectionView(in: child) { return found }
        }
        return nil
    }

    private func findPreview(in view: UIView) -> DetailZoomContainerView? {
        if let preview = view as? DetailZoomContainerView { return preview }
        for child in view.subviews {
            if let found = findPreview(in: child) { return found }
        }
        return nil
    }

    private func renderPNG<V: View>(_ view: V, theme: CloveTheme) throws -> Data {
        let renderer = ImageRenderer(
            content:
                view
                .environment(\.cloveTheme, theme)
                .environment(\.appLanguage, .english))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        return try #require(UIImage(cgImage: image).pngData())
    }

    private func renderViewPNG(_ view: UIView) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var didDraw = false
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
            didDraw = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        #expect(didDraw)
        return try #require(image.pngData())
    }

    private func renderWindowImage(_ window: UIWindow) throws -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var didDraw = false
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        #expect(didDraw)
        return try #require(image.cgImage)
    }

    private func renderedRGBA(_ color: Color) throws -> (Int, Int, Int, Int) {
        let renderer = ImageRenderer(content: Rectangle().fill(color).frame(width: 4, height: 4))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        return try pixelRGBA(in: image, at: CGPoint(x: 2, y: 2))
    }

    private func pixelRGBA(in image: CGImage, at point: CGPoint) throws -> (Int, Int, Int, Int) {
        let width = image.width
        let height = image.height
        let x = min(max(Int(point.x.rounded()), 0), max(width - 1, 0))
        let y = min(max(Int(point.y.rounded()), 0), max(height - 1, 0))
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
        return (
            Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]),
            Int(bytes[offset + 3])
        )
    }

    private func rgbaDistance(_ lhs: (Int, Int, Int, Int), _ rhs: (Int, Int, Int, Int)) -> Int {
        abs(lhs.0 - rhs.0) + abs(lhs.1 - rhs.1) + abs(lhs.2 - rhs.2) + abs(lhs.3 - rhs.3)
    }
}

@MainActor
private final class WorkflowFrameStore {
    var frames: [String: CGRect] = [:]
}

@MainActor
private final class HeldRunningRenameLibrary: FolderLibrary {
    let sample = TestLibrary.sample
    var releaseRename: CheckedContinuation<Void, Never>?
    var folder: FolderIdentity { sample.folder }
    var photos: [GridPhoto] { sample.photos }
    var groups: [BrowsingGroup] { [] }
    var updates: AsyncStream<FolderLibraryUpdate> { sample.updates }

    func planBatchRename(
        order: [PhotoIdentity], template: RenameTemplate, destination: RenameDestination,
        rejectsFolderName: RejectsFolderName
    ) async throws -> BatchRenamePlan {
        try await sample.planBatchRename(
            order: order, template: template, destination: destination,
            rejectsFolderName: rejectsFolderName)
    }

    func runBatchRename(
        _ plan: BatchRenamePlan,
        progress: @escaping @MainActor @Sendable (BatchRenameProgress) -> Void
    ) async throws -> BatchRenameResult {
        await withCheckedContinuation { releaseRename = $0 }
        return try await sample.runBatchRename(plan, progress: progress)
    }
}
