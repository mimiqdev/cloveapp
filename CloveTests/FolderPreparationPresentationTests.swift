import CloveCore
import CloveImaging
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Clove

@Suite(.serialized)
@MainActor
struct FolderPreparationPresentationTests {
    @Test func presentationModeAdaptsToRegularPopoverAndCompactSheet() {
        #expect(
            FolderPreparationPresentationMode.resolved(horizontalSizeClass: .regular) == .popover)
        #expect(FolderPreparationPresentationMode.resolved(horizontalSizeClass: .compact) == .sheet)
        #expect(FolderPreparationPresentationMode.resolved(horizontalSizeClass: nil) == .sheet)
    }

    @Test func accessibilityAndSummaryTextReportHonestCountsAndStates() {
        let folder = FolderIdentity(rawValue: "presentation-states")

        let enumerating = FolderPreparationStatus(
            folder: folder,
            folderName: "Coastal light",
            generation: 1,
            isEnumerating: true,
            isPartialScan: false,
            waitingReason: nil,
            totalPhotos: 0,
            analysis: FolderPreparationTaskCounts(),
            previews: FolderPreparationTaskCounts(),
            readyForBothCount: 0,
            bothSettledCount: 0,
            issues: [])
        #expect(enumerating.phase == .enumeratingUnknown)
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(for: enumerating)
                == "Scanning folder")
        #expect(FolderPreparationAccessibility.summaryText(for: enumerating) == "Scanning folder…")
        #expect(
            FolderPreparationAccessibility.analysisCountText(for: enumerating)
                == "Waiting for photo count")
        #expect(
            FolderPreparationAccessibility.previewsCountText(for: enumerating)
                == "Waiting for photo count")

        let preparing = FolderPreparationStatus(
            folder: folder,
            folderName: "Coastal light",
            generation: 1,
            isEnumerating: false,
            isPartialScan: false,
            waitingReason: nil,
            totalPhotos: 36,
            analysis: FolderPreparationTaskCounts(completed: 18),
            previews: FolderPreparationTaskCounts(completed: 29),
            readyForBothCount: 15,
            bothSettledCount: 15,
            issues: [])
        #expect(preparing.phase == .preparing)
        #expect(FolderPreparationAccessibility.summaryText(for: preparing) == "15 of 36 ready")
        #expect(
            FolderPreparationAccessibility.analysisCountText(for: preparing) == "18 of 36 analyzed")
        #expect(
            FolderPreparationAccessibility.previewsCountText(for: preparing) == "29 of 36 prepared")

        let waitingMemory = FolderPreparationStatus(
            folder: folder,
            folderName: "Coastal light",
            generation: 1,
            isEnumerating: false,
            isPartialScan: false,
            waitingReason: .memoryPressure,
            totalPhotos: 36,
            analysis: FolderPreparationTaskCounts(completed: 18),
            previews: FolderPreparationTaskCounts(completed: 29),
            readyForBothCount: 15,
            bothSettledCount: 15,
            issues: [])
        #expect(waitingMemory.phase == .waiting(.memoryPressure))
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(for: waitingMemory)
                == "Paused for memory, 15 of 36 ready")

        let waitingDisconnected = FolderPreparationStatus(
            folder: folder,
            folderName: "Coastal light",
            generation: 1,
            isEnumerating: false,
            isPartialScan: false,
            waitingReason: .folderUnavailable(.externalVolumeDisconnected),
            totalPhotos: 0,
            analysis: FolderPreparationTaskCounts(),
            previews: FolderPreparationTaskCounts(),
            readyForBothCount: 0,
            bothSettledCount: 0,
            issues: [])
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(for: waitingDisconnected)
                == "Paused · drive disconnected")

        let complete = FolderPreparationStatus(
            folder: folder,
            folderName: "Coastal light",
            generation: 1,
            isEnumerating: false,
            isPartialScan: false,
            waitingReason: nil,
            totalPhotos: 36,
            analysis: FolderPreparationTaskCounts(completed: 36),
            previews: FolderPreparationTaskCounts(completed: 36),
            readyForBothCount: 36,
            bothSettledCount: 36,
            issues: [])
        #expect(complete.phase == .complete)
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(for: complete)
                == "Complete, 36 of 36 ready")

        let withIssues = FolderPreparationStatus(
            folder: folder,
            folderName: "Coastal light",
            generation: 1,
            isEnumerating: false,
            isPartialScan: false,
            waitingReason: nil,
            totalPhotos: 36,
            analysis: FolderPreparationTaskCounts(completed: 34, failed: 1, deferred: 1),
            previews: FolderPreparationTaskCounts(completed: 35, unsupported: 1),
            readyForBothCount: 34,
            bothSettledCount: 36,
            issues: [])
        #expect(withIssues.phase == .completeWithIssues)
        #expect(
            FolderPreparationAccessibility.taskIssueSummary(withIssues.analysis)
                == "1 failed · 1 deferred")
        #expect(
            FolderPreparationAccessibility.taskIssueSummary(withIssues.previews) == "1 unsupported")
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(for: withIssues).contains(
                "34 of 36 ready"))
        #expect(FolderPreparationAccessibility.canRetryIssues(for: withIssues))
        #expect(
            FolderPreparationAccessibility.retryButtonAccessibilityHint(for: withIssues)
                == "Retries failed or deferred analysis and preview tasks.")

        var pausedWithIssues = withIssues
        pausedWithIssues.waitingReason = .memoryPressure
        #expect(pausedWithIssues.hasRetryableIssues)
        #expect(!FolderPreparationAccessibility.canRetryIssues(for: pausedWithIssues))
        #expect(
            FolderPreparationAccessibility.retryButtonAccessibilityHint(for: pausedWithIssues)
                == "Unavailable while folder preparation is paused.")

        var disconnectedWithIssues = withIssues
        disconnectedWithIssues.waitingReason = .folderUnavailable(.externalVolumeDisconnected)
        #expect(!FolderPreparationAccessibility.canRetryIssues(for: disconnectedWithIssues))

        let unsupportedOnly = FolderPreparationStatus(
            folder: folder,
            folderName: "Coastal light",
            generation: 1,
            isEnumerating: false,
            isPartialScan: false,
            waitingReason: nil,
            totalPhotos: 36,
            analysis: FolderPreparationTaskCounts(completed: 36),
            previews: FolderPreparationTaskCounts(completed: 35, unsupported: 1),
            readyForBothCount: 35,
            bothSettledCount: 36,
            issues: [])
        #expect(!unsupportedOnly.hasRetryableIssues)
        #expect(!FolderPreparationAccessibility.canRetryIssues(for: unsupportedOnly))
    }

    @Test func browsingModelRetryPreparationIssuesResolvesSampleIssuesAndBlocksWhenDisconnected()
        async throws
    {
        let library = try #require(
            TestLibrary.forLaunch(
                environment: [
                    TestLibrary.launchVariable: "1",
                    TestLibrary.preparationVariable: "issues",
                ]) as? TestLibrary)
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        #expect(browsing.preparationStatus.phase == .completeWithIssues)
        #expect(browsing.preparationStatus.canRetryIssues)
        #expect(library.preparationRetryCount == 0)

        await browsing.retryPreparationIssues()
        try await waitFor("preparation issues resolved after retry") {
            browsing.preparationStatus.phase == .complete
                && browsing.preparationStatus.issues.isEmpty
        }
        #expect(library.preparationRetryCount == 1)
        #expect(!browsing.preparationStatus.canRetryIssues)

        // Disconnected library blocks retry even if issues exist.
        let disconnectedLibrary = try #require(
            TestLibrary.forLaunch(
                environment: [
                    TestLibrary.launchVariable: "1",
                    TestLibrary.preparationVariable: "issues",
                ]) as? TestLibrary)
        let disconnectedModel = BrowsingModel(library: disconnectedLibrary)
        disconnectedModel.openFolder()
        disconnectedLibrary.reportLocationLoss(.externalVolumeDisconnected)
        try await waitFor("location loss applied to browsing model") {
            disconnectedModel.folderLocationLoss != nil
        }
        await disconnectedModel.retryPreparationIssues()
        #expect(disconnectedLibrary.preparationRetryCount == 0)
    }

    @Test func completionDismissalSharedOnBrowsingModelAndResetsWhenNoLongerComplete() {
        let library = TestLibrary.forLaunch(
            environment: [
                TestLibrary.launchVariable: "1",
                TestLibrary.preparationVariable: "complete",
            ])
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        #expect(browsing.preparationStatus.phase == .complete)
        #expect(browsing.showsPreparationIndicator)

        // Mismatched folder or generation cannot dismiss the active folder's indicator.
        browsing.dismissPreparationCompletion(
            folder: FolderIdentity(rawValue: "wrong"),
            generation: browsing.preparationStatus.generation)
        #expect(browsing.showsPreparationIndicator)

        browsing.dismissPreparationCompletion(
            folder: browsing.preparationStatus.folder,
            generation: browsing.preparationStatus.generation + 1)
        #expect(browsing.showsPreparationIndicator)

        // Matching dismissal withdraws indicator for both Grid and Detail.
        browsing.dismissPreparationCompletion(
            folder: browsing.preparationStatus.folder,
            generation: browsing.preparationStatus.generation)
        #expect(!browsing.showsPreparationIndicator)
    }

    @Test func detailsViewRendersHonestMetricsWithoutPauseOrCancelControlsAcrossThemes()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let library = TestLibrary.forLaunch(
            environment: [
                TestLibrary.launchVariable: "1",
                TestLibrary.preparationVariable: "issues",
            ])
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()

        let status = browsing.preparationStatus
        #expect(FolderPreparationAccessibility.summaryText(for: status) == "35 of 36 ready")
        #expect(
            FolderPreparationAccessibility.analysisCountText(for: status) == "35 of 36 analyzed")
        #expect(
            FolderPreparationAccessibility.previewsCountText(for: status) == "35 of 36 prepared")
        #expect(status.issues.contains { $0.fileName == "MMQ02700.ARW" })
        #expect(
            !FolderPreparationAccessibility.summaryText(for: status)
                .localizedCaseInsensitiveContains("cancel"))

        let themes: [CloveTheme] = [.light, .dark, .nord]
        var renderedImages: [Data] = []
        for theme in themes {
            for showsDoneButton in [false, true] {
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 420, height: 640)
                let host = UIHostingController(
                    rootView: FolderPreparationDetails(
                        browsing: browsing, showsDoneButton: showsDoneButton
                    )
                    .environment(\.cloveTheme, theme))
                window.rootViewController = host
                window.makeKeyAndVisible()
                window.layoutIfNeeded()
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                }

                try await Task.sleep(for: .milliseconds(50))
                let pixels = try #require(findRenderedPixels(in: window))
                #expect(!pixels.isEmpty)
                if !showsDoneButton {
                    renderedImages.append(pixels)
                }
            }
        }
        // Light, Dark, and Nord popover cards should produce distinct rendered outputs.
        #expect(renderedImages.count == 3)
        #expect(renderedImages[0] != renderedImages[1])
        #expect(renderedImages[1] != renderedImages[2])
    }

    @Test func inlineDetailRingDoesNotCollideWithDuoFocusToggleAndKeeps44PtHitTarget() async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let library = TestLibrary.forLaunch(
            environment: [
                TestLibrary.launchVariable: "1",
                TestLibrary.preparationVariable: "preparing",
            ])
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        let first = try #require(browsing.photos.first?.id)
        browsing.openPhoto(first)

        let presentationBox = PresentationBox(value: .photoPreview)
        let frameBox = FrameStoreBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 600)

        struct HostedDuoDetail: View {
            let browsing: BrowsingModel
            @Bindable var presentation: PresentationBox
            let frameBox: FrameStoreBox

            var body: some View {
                NavigationStack {
                    DetailScreen(
                        browsing: browsing,
                        images: SampleDetailImages(),
                        duo: DuoDetailLayout(
                            presentation: $presentation.value,
                            filter: AnyView(EmptyView()),
                            more: AnyView(EmptyView()),
                            bottom: AnyView(EmptyView()),
                            showsGrid: true))
                }
                .environment(SettingsStore.sample)
                .environment(\.isDuoExpanded, true)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, true)
                .environment(\.hasFoldRegion, true)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                    frameBox.frames = frames
                }
            }
        }

        let host = UIHostingController(
            rootView: HostedDuoDetail(
                browsing: browsing, presentation: presentationBox, frameBox: frameBox))
        host.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("Duo header preparation and focus controls laid out") {
            frameBox.frames["clove.detail.preparation"] != nil
                && frameBox.frames["clove.detail.focusToggle"] != nil
                && frameBox.frames["clove.detail.fileName"] != nil
                && frameBox.frames["clove.detail.zoom"] != nil
        }

        let prep = try #require(frameBox.frames["clove.detail.preparation"])
        let focus = try #require(frameBox.frames["clove.detail.focusToggle"])
        let fileName = try #require(frameBox.frames["clove.detail.fileName"])
        let zoom = try #require(frameBox.frames["clove.detail.zoom"])
        let header = try #require(frameBox.frames["clove.detail.photoHeader"])

        #expect(abs(header.height - 48) <= 1.0)
        #expect(prep.width >= 43)
        #expect(prep.height >= 43)
        #expect(!prep.intersects(focus))
        #expect(focus.maxX < prep.minX)
        #expect(prep.minY >= header.minY - 1)
        #expect(prep.maxY <= header.maxY + 1)
        #expect(fileName.minY >= header.maxY + 9)
        #expect(fileName.maxY <= zoom.minY + 1)
        #expect(abs(fileName.minX - zoom.minX) <= 2)
        #expect(frameBox.frames["clove.detail.saveState"] == nil)

        // Switching to Focus View preserves the icon-only leading preparation ring without collision
        // and keeps the filename/position corner overlay inside the photo stage.
        presentationBox.value = .focus
        let photoPreviewHeaderMinX = header.minX
        try await waitFor("Focus View preparation header did not lay out") {
            guard let focusHeader = frameBox.frames["clove.detail.photoHeader"] else {
                return false
            }
            return focusHeader.minX < photoPreviewHeaderMinX - 40
        }
        let prepInFocus = try #require(frameBox.frames["clove.detail.preparation"])
        let focusInFocus = try #require(frameBox.frames["clove.detail.focusToggle"])
        let fileInFocus = try #require(frameBox.frames["clove.detail.fileName"])
        let zoomInFocus = try #require(frameBox.frames["clove.detail.zoom"])
        let headerInFocus = try #require(frameBox.frames["clove.detail.photoHeader"])

        #expect(abs(headerInFocus.height - 48) <= 1.0)
        #expect(prepInFocus.width >= 43)
        #expect(prepInFocus.height >= 43)
        #expect(!prepInFocus.intersects(focusInFocus))
        #expect(focusInFocus.maxX < prepInFocus.minX)
        #expect(fileInFocus.minY >= headerInFocus.maxY + 9)
        #expect(fileInFocus.maxY <= zoomInFocus.minY + 1)
    }

    @Test func preparationDetailsDismissOnModeRoutePostureAndInactiveSceneTransitions()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let library = TestLibrary.forLaunch(
            environment: [
                TestLibrary.launchVariable: "1",
                TestLibrary.preparationVariable: "preparing",
            ])

        // 1. Compact sheet -> regular popover transition dismisses cleanly without colliding.
        do {
            let browsing = BrowsingModel(library: library)
            browsing.openFolder()
            let envBox = PreparationEnvironmentBox()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
            let host = makePreparationHost(browsing: browsing, envBox: envBox)
            host.traitOverrides.horizontalSizeClass = .compact
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await Task.sleep(for: .milliseconds(80))
            window.layoutIfNeeded()
            envBox.presentTrigger += 1
            try await waitFor("compact preparation sheet presented") {
                self.topPresentedViewController(from: host) != nil
            }
            host.traitOverrides.horizontalSizeClass = .regular
            UIView.performWithoutAnimation {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                _ = window.snapshotView(afterScreenUpdates: true)
            }
            try await waitFor("preparation sheet dismissed on size-class flip") {
                self.topPresentedViewController(from: host) == nil
            }
        }

        // 2. Regular popover -> route change dismisses cleanly.
        do {
            let browsing = BrowsingModel(library: library)
            browsing.openFolder()
            let firstPhoto = try #require(browsing.photos.first?.id)
            let envBox = PreparationEnvironmentBox()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
            let host = makePreparationHost(browsing: browsing, envBox: envBox)
            host.traitOverrides.horizontalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await Task.sleep(for: .milliseconds(80))
            window.layoutIfNeeded()
            envBox.presentTrigger += 1
            try await waitFor("regular preparation popover presented") {
                self.topPresentedViewController(from: host) != nil
            }
            browsing.openPhoto(firstPhoto)
            try await waitFor("preparation popover dismissed on route change") {
                self.topPresentedViewController(from: host) == nil
            }
        }

        // 3. Regular popover -> inactive scene + snapshot dismisses cleanly.
        do {
            let browsing = BrowsingModel(library: library)
            browsing.openFolder()
            let envBox = PreparationEnvironmentBox()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
            let host = makePreparationHost(browsing: browsing, envBox: envBox)
            host.traitOverrides.horizontalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await Task.sleep(for: .milliseconds(80))
            window.layoutIfNeeded()
            envBox.presentTrigger += 1
            try await waitFor("preparation popover re-presented") {
                self.topPresentedViewController(from: host) != nil
            }
            envBox.scenePhase = .inactive
            UIView.performWithoutAnimation {
                _ = window.snapshotView(afterScreenUpdates: true)
            }
            try await waitFor("preparation popover dismissed on inactive scene") {
                self.topPresentedViewController(from: host) == nil
            }
        }
    }

    private func makePreparationHost(
        browsing: BrowsingModel,
        envBox: PreparationEnvironmentBox
    ) -> UIHostingController<AnyView> {
        struct HostView: View {
            let browsing: BrowsingModel
            let envBox: PreparationEnvironmentBox
            var body: some View {
                NavigationStack {
                    Text("Grid")
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                FolderPreparationIndicator(
                                    browsing: browsing,
                                    identifierPrefix: "clove.grid.preparation",
                                    presentTrigger: envBox.presentTrigger)
                            }
                        }
                }
                .environment(\.isDuoExpanded, envBox.isDuoExpanded)
                .environment(\.isDuoCover, envBox.isDuoCover)
                .environment(\.scenePhase, envBox.scenePhase)
            }
        }
        return UIHostingController(rootView: AnyView(HostView(browsing: browsing, envBox: envBox)))
    }

    private func topPresentedViewController(from controller: UIViewController) -> UIViewController?
    {
        if let presented = controller.presentedViewController { return presented }
        for child in controller.children {
            if let presented = topPresentedViewController(from: child) { return presented }
        }
        return nil
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

    private func findRenderedPixels(in window: UIWindow) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var didDraw = false
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard didDraw else { return nil }
        return image.pngData()
    }
}

@MainActor
@Observable
private final class PreparationEnvironmentBox {
    var isDuoExpanded = false
    var isDuoCover = false
    var scenePhase: ScenePhase = .active
    var presentTrigger = 0
}

@MainActor
@Observable
private final class PresentationBox {
    var value: DetailPresentation
    init(value: DetailPresentation) { self.value = value }
}

@MainActor
private final class FrameStoreBox {
    var frames: [String: CGRect] = [:]
}
