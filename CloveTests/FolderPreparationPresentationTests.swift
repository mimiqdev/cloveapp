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
            FolderPreparationAccessibility.detailsHeading() == "Preparing folder")
        #expect(
            FolderPreparationAccessibility.headerSummaryText(
                folderName: "Coastal light", status: enumerating)
                == "Coastal light · Scanning folder…")
        #expect(
            FolderPreparationAccessibility.readyForBothText(for: enumerating)
                == "Scanning folder…")
        #expect(
            FolderPreparationAccessibility.analysisRowTitle() == "Face & focus analysis")
        #expect(
            FolderPreparationAccessibility.previewsRowTitle() == "Preview optimization")
        #expect(
            FolderPreparationAccessibility.reassuranceFooterText()
                == "You can keep browsing. The current photo is prioritized. Originals are unchanged."
        )
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
            FolderPreparationAccessibility.headerSummaryText(
                folderName: "Coastal light", status: preparing)
                == "Coastal light · 36 photos")
        #expect(
            FolderPreparationAccessibility.readyForBothText(for: preparing)
                == "15 photos ready for both")
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

        var pausedWithIssues = withIssues
        pausedWithIssues.waitingReason = .memoryPressure
        #expect(pausedWithIssues.hasRetryableIssues)
        #expect(!FolderPreparationAccessibility.canRetryIssues(for: pausedWithIssues))

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

        // Grouping reflects determinate, active, and paused VoiceOver states when prep is .complete or .idle.
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(
                for: .idle, isFindingSimilarShots: true) == "Finding similar shots")
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(
                for: .idle, isFindingSimilarShots: true,
                groupingProgress: .analyzing(completed: 12, total: 24))
                == "Finding similar shots, 12 of 24 analyzed")
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(
                for: complete, isFindingSimilarShots: true) == "Finding similar shots")
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(
                for: complete, isFindingSimilarShots: true,
                groupingProgress: .analyzing(completed: 5, total: 10))
                == "Finding similar shots, 5 of 10 analyzed")
        var pausedComplete = complete
        pausedComplete.waitingReason = .memoryPressure
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(
                for: pausedComplete, isFindingSimilarShots: true,
                groupingProgress: .analyzing(completed: 5, total: 10)) == "Paused for memory")
        var disconnectedComplete = complete
        disconnectedComplete.waitingReason = .folderUnavailable(.externalVolumeDisconnected)
        #expect(
            FolderPreparationAccessibility.indicatorAccessibilityValue(
                for: disconnectedComplete, isFindingSimilarShots: true,
                groupingProgress: .analyzing(completed: 5, total: 10))
                == "Paused · drive disconnected")

        // Grouping status text covers scanning/.idle, determinate analyzing, paused, and complete.
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: enumerating, progress: .idle, groupCount: 0, isScanning: true)
                == "Waiting for photo count")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: complete, progress: .idle, groupCount: 0, isScanning: false)
                == "Waiting for photo count")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: complete, progress: .analyzing(completed: 12, total: 24))
                == "12 of 24 analyzed")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: complete, progress: .analyzing(completed: 0, total: 0))
                == "Finding similar shots…")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: pausedComplete, progress: .analyzing(completed: 12, total: 24))
                == "Paused")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: complete, progress: .complete, groupCount: 0) == "0 groups")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: complete, progress: .complete, groupCount: 1) == "1 group")
        #expect(
            FolderPreparationAccessibility.groupingStatusText(
                for: complete, progress: .complete, groupCount: 3) == "3 groups")

        // FolderGroupingProgress helpers report active state and clamped fractions cleanly.
        #expect(!FolderGroupingProgress.idle.isAnalyzing)
        #expect(FolderGroupingProgress.idle.fraction == nil)
        #expect(!FolderGroupingProgress.complete.isAnalyzing)
        #expect(FolderGroupingProgress.complete.fraction == nil)
        #expect(FolderGroupingProgress.analyzing(completed: 0, total: 0).isAnalyzing)
        #expect(FolderGroupingProgress.analyzing(completed: 0, total: 0).fraction == nil)
        #expect(FolderGroupingProgress.analyzing(completed: 6, total: 24).fraction == 0.25)
        #expect(FolderGroupingProgress.analyzing(completed: -2, total: 10).fraction == 0)
        #expect(FolderGroupingProgress.analyzing(completed: 15, total: 10).fraction == 1)
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

    @Test func groupingProgressKeepsPreparationIndicatorVisibleAndReflectsPauseInDetails()
        async throws
    {
        let library = GroupingPresentationStubLibrary()
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        try await waitFor("stub folder completed initial preparation") {
            browsing.preparationStatus.phase == .complete
        }

        // Dismiss completion first, as happens after the initial open finishes.
        browsing.dismissPreparationCompletion(
            folder: browsing.preparationStatus.folder,
            generation: browsing.preparationStatus.generation)
        #expect(!browsing.showsPreparationIndicator)

        // Running grouping again re-shows the indicator even while prep status is .complete.
        library.emit(.groupingProgress(.analyzing(completed: 2, total: 10)))
        try await waitFor("grouping progress started on browsing model") {
            browsing.isGroupingInProgress && browsing.groupingFraction == 0.2
        }
        #expect(browsing.showsPreparationIndicator)

        // Completion dismissal must not hide the indicator while grouping is running.
        browsing.dismissPreparationCompletion(
            folder: browsing.preparationStatus.folder,
            generation: browsing.preparationStatus.generation)
        #expect(browsing.showsPreparationIndicator)

        // Also stays visible when preparationStatus is .idle and grouping is active.
        let idleLibrary = GroupingPresentationStubLibrary(initialPhaseIdle: true)
        let idleModel = BrowsingModel(library: idleLibrary)
        idleModel.openFolder()
        #expect(idleModel.preparationStatus.phase == .idle)
        #expect(!idleModel.showsPreparationIndicator)
        idleLibrary.emit(.groupingProgress(.analyzing(completed: 1, total: 4)))
        try await waitFor("idle folder shows indicator during grouping") {
            idleModel.isGroupingInProgress && idleModel.showsPreparationIndicator
        }

        // Turning off similarGroupsEnabled stops showing grouping progress immediately.
        await idleModel.setSimilarGroupsEnabled(false)
        #expect(!idleModel.isGroupingInProgress)
        #expect(idleModel.groupingProgress == .idle)
        #expect(!idleModel.showsPreparationIndicator)

        // scanStarted resets groupingProgress back to .idle.
        idleLibrary.emit(.groupingProgress(.analyzing(completed: 2, total: 4)))
        await idleModel.setSimilarGroupsEnabled(true)
        try await waitFor("re-enabled grouping progress observed") {
            idleModel.isGroupingInProgress
        }
        idleLibrary.emit(.scanStarted)
        try await waitFor("scanStarted cleared grouping progress") {
            idleModel.groupingProgress == .idle && !idleModel.isGroupingInProgress
        }

        // Render FolderPreparationDetails across determinate progress, paused grouping, and complete states.
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let detailsWindow = UIWindow(windowScene: scene)
        detailsWindow.frame = CGRect(x: 0, y: 0, width: 420, height: 640)
        let detailsHost = UIHostingController(
            rootView: FolderPreparationDetails(browsing: browsing, showsDoneButton: false)
                .environment(\.cloveTheme, .light))
        detailsWindow.rootViewController = detailsHost
        detailsWindow.makeKeyAndVisible()
        detailsWindow.layoutIfNeeded()
        defer {
            detailsWindow.isHidden = true
            detailsWindow.rootViewController = nil
        }

        try await Task.sleep(for: .milliseconds(80))
        let earlyDetailsPixels = try #require(findRenderedPixels(in: detailsWindow))

        library.emit(.groupingProgress(.analyzing(completed: 8, total: 10)))
        try await waitFor("grouping progress advanced to 8 of 10") {
            browsing.groupingProgress == .analyzing(completed: 8, total: 10)
                && browsing.groupingFraction == 0.8
        }
        try await Task.sleep(for: .milliseconds(80))
        let lateDetailsPixels = try #require(findRenderedPixels(in: detailsWindow))
        #expect(lateDetailsPixels != earlyDetailsPixels)

        var pausedStatus = browsing.preparationStatus
        pausedStatus.waitingReason = .memoryPressure
        library.emit(.preparation(pausedStatus))
        try await waitFor("waiting reason applied to browsing model") {
            browsing.preparationStatus.waitingReason == .memoryPressure
        }
        try await Task.sleep(for: .milliseconds(80))
        let pausedDetailsPixels = try #require(findRenderedPixels(in: detailsWindow))
        #expect(pausedDetailsPixels != lateDetailsPixels)

        // Indicator stays mounted past the 2s completion window while grouping is running,
        // advances determinate ring as progress updates, pauses/resumes, and auto-dismisses at .complete.
        pausedStatus.waitingReason = nil
        library.emit(.preparation(pausedStatus))
        try await waitFor("waiting reason cleared") {
            browsing.preparationStatus.waitingReason == nil
        }

        let frameBox = FrameStoreBox()
        let indicatorWindow = UIWindow(windowScene: scene)
        indicatorWindow.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let indicatorHost = UIHostingController(
            rootView: FolderPreparationIndicator(
                browsing: browsing, identifierPrefix: "clove.grid.preparation"
            )
            .environment(\.cloveTheme, .light)
            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                frameBox.frames = frames
            })
        indicatorWindow.rootViewController = indicatorHost
        indicatorWindow.makeKeyAndVisible()
        defer {
            indicatorWindow.isHidden = true
            indicatorWindow.rootViewController = nil
        }

        try await waitFor("indicator mounted while grouping") {
            frameBox.frames["clove.grid.preparation"] != nil
        }
        // Wait past the 2s completion auto-dismiss interval to verify grouping keeps it visible.
        try await Task.sleep(for: .milliseconds(2200))
        #expect(browsing.showsPreparationIndicator)
        #expect(frameBox.frames["clove.grid.preparation"] != nil)

        let eightTenthsIndicatorPixels = try #require(findRenderedPixels(in: indicatorWindow))
        library.emit(.groupingProgress(.analyzing(completed: 2, total: 10)))
        try await waitFor("indicator progress updated to 2 of 10") {
            browsing.groupingFraction == 0.2
        }
        try await Task.sleep(for: .milliseconds(80))
        let twoTenthsIndicatorPixels = try #require(findRenderedPixels(in: indicatorWindow))
        #expect(twoTenthsIndicatorPixels != eightTenthsIndicatorPixels)

        pausedStatus.waitingReason = .memoryPressure
        library.emit(.preparation(pausedStatus))
        try await waitFor("indicator saw paused status") {
            browsing.preparationStatus.waitingReason == .memoryPressure
        }
        try await Task.sleep(for: .milliseconds(80))
        let pausedIndicatorPixels = try #require(findRenderedPixels(in: indicatorWindow))
        #expect(pausedIndicatorPixels != twoTenthsIndicatorPixels)

        // Clearing pause and completing grouping keeps the persistent row in details and auto-dismisses indicator.
        pausedStatus.waitingReason = nil
        library.emit(.preparation(pausedStatus))
        library.emit(.groupingProgress(.complete))
        try await waitFor("grouping finished") {
            !browsing.isGroupingInProgress
                && browsing.groupingProgress == .complete
                && browsing.preparationStatus.waitingReason == nil
        }
        try await Task.sleep(for: .milliseconds(80))
        let finishedDetailsPixels = try #require(findRenderedPixels(in: detailsWindow))
        #expect(finishedDetailsPixels != earlyDetailsPixels)
        #expect(finishedDetailsPixels != lateDetailsPixels)

        try await waitFor("indicator auto-dismissed after grouping finished", timeout: .seconds(4))
        {
            !browsing.showsPreparationIndicator && frameBox.frames["clove.grid.preparation"] == nil
        }

        // Hiding similar groups removes the persistent Similar groups row from details.
        await browsing.setSimilarGroupsEnabled(false)
        try await Task.sleep(for: .milliseconds(80))
        let disabledDetailsPixels = try #require(findRenderedPixels(in: detailsWindow))
        #expect(disabledDetailsPixels != finishedDetailsPixels)

        // Leaving the folder resets groupingProgress to .idle.
        library.emit(.groupingProgress(.analyzing(completed: 1, total: 4)))
        await browsing.setSimilarGroupsEnabled(true)
        try await waitFor("grouping active before leaveFolder") {
            browsing.isGroupingInProgress
        }
        browsing.back()
        #expect(browsing.groupingProgress == .idle)
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

    @Test
    func preparationPopoverAndSheetShowAlignedHeadingLabelsReadyCountFooterAndPreservedStates()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let library = GroupingPresentationStubLibrary(initialPhaseIdle: false)
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        try await waitFor("stub folder opened") {
            browsing.preparationStatus.totalPhotos == 12
        }

        let issue = FolderPreparationIssue(
            photo: PhotoIdentity(
                folderID: library.folder, relativeFolderPath: "", stem: "MMQ02700"),
            fileName: "MMQ02700.ARW",
            task: .analysis,
            reason: "The RAW render failed.")
        let detailedStatus = FolderPreparationStatus(
            folder: library.folder,
            folderName: "Coastal light",
            generation: 1,
            isEnumerating: false,
            isPartialScan: false,
            waitingReason: .memoryPressure,
            totalPhotos: 12,
            analysis: FolderPreparationTaskCounts(completed: 9, failed: 1),
            previews: FolderPreparationTaskCounts(completed: 10),
            readyForBothCount: 8,
            bothSettledCount: 9,
            issues: [issue])
        library.emit(.preparation(detailedStatus))
        library.emit(.groupingProgress(.analyzing(completed: 4, total: 12)))
        try await waitFor("detailed preparation state applied") {
            browsing.preparationStatus.issues.count == 1
                && browsing.preparationStatus.waitingReason == .memoryPressure
                && browsing.groupingProgress == .analyzing(completed: 4, total: 12)
        }

        for showsDoneButton in [false, true] {
            let presentation = FolderPreparationDetails.Presentation(
                browsing: browsing, showsDoneButton: showsDoneButton)
            #expect(presentation.heading == "Preparing folder")
            #expect(presentation.showsPopoverHeading == !showsDoneButton)
            #expect(presentation.headerSummary == "Coastal light · 12 photos")
            #expect(presentation.analysisTitle == "Face & focus analysis")
            #expect(presentation.previewsTitle == "Preview optimization")
            #expect(presentation.groupingTitle == "Similar groups")
            #expect(presentation.groupingStatus == "Paused")
            #expect(presentation.readyForBothText == "8 photos ready for both")
            #expect(presentation.waitingTitle == "Paused for memory")
            #expect(presentation.showsIssues)
            #expect(!presentation.canRetryIssues)
            #expect(
                presentation.reassuranceFooter
                    == "You can keep browsing. The current photo is prioritized. Originals are unchanged."
            )

            let frameBox = FrameStoreBox()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 420, height: 760)
            let host = UIHostingController(
                rootView: FolderPreparationDetails(
                    browsing: browsing, showsDoneButton: showsDoneButton
                )
                .environment(\.cloveTheme, .light)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                    frameBox.frames = frames
                })
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("preparation details elements laid out (done=\(showsDoneButton))") {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                let hasSharedFrames =
                    frameBox.frames["clove.preparation.folderName"] != nil
                    && frameBox.frames["clove.preparation.waiting"] != nil
                    && frameBox.frames["clove.preparation.analysis.title"] != nil
                    && frameBox.frames["clove.preparation.previews.title"] != nil
                    && frameBox.frames["clove.preparation.summary"] != nil
                    && frameBox.frames["clove.preparation.issues"] != nil
                    && frameBox.frames["clove.preparation.retry"] != nil
                    && frameBox.frames["clove.preparation.footer"] != nil
                if showsDoneButton {
                    let navBar = self.findNavigationBar(in: window)
                    return hasSharedFrames
                        && navBar != nil
                        && (navBar?.topItem?.title == "Preparing folder"
                            || navBar?.topItem?.titleView != nil)
                } else {
                    return hasSharedFrames
                        && frameBox.frames["clove.preparation.title"] != nil
                }
            }

            let folderFrame = try #require(frameBox.frames["clove.preparation.folderName"])
            let waitingFrame = try #require(frameBox.frames["clove.preparation.waiting"])
            let analysisFrame = try #require(frameBox.frames["clove.preparation.analysis.title"])
            let previewsFrame = try #require(frameBox.frames["clove.preparation.previews.title"])
            let summaryFrame = try #require(frameBox.frames["clove.preparation.summary"])
            let issuesFrame = try #require(frameBox.frames["clove.preparation.issues"])
            let footerFrame = try #require(frameBox.frames["clove.preparation.footer"])

            if showsDoneButton {
                let navBar = try #require(findNavigationBar(in: window))
                let navBarFrame = navBar.convert(navBar.bounds, to: window)
                #expect(
                    navBar.topItem?.title == "Preparing folder" || navBar.topItem?.titleView != nil
                )
                if let reportedTitle = frameBox.frames["clove.preparation.title"] {
                    #expect(reportedTitle.maxY <= folderFrame.minY + 1)
                } else if let titleView = navBar.topItem?.titleView {
                    let titleRect = titleView.convert(titleView.bounds, to: window)
                    #expect(titleRect.maxY <= folderFrame.minY + 1)
                } else {
                    #expect(navBarFrame.minY < folderFrame.minY)
                }
            } else {
                let titleFrame = try #require(frameBox.frames["clove.preparation.title"])
                #expect(titleFrame.maxY <= folderFrame.minY + 1)
            }
            #expect(folderFrame.maxY <= waitingFrame.minY + 1)
            #expect(waitingFrame.maxY <= analysisFrame.minY + 1)
            #expect(analysisFrame.maxY <= previewsFrame.minY + 1)
            #expect(previewsFrame.maxY <= summaryFrame.minY + 1)
            #expect(summaryFrame.maxY <= issuesFrame.minY + 1)
            #expect(issuesFrame.maxY <= footerFrame.minY + 1)
            #expect(try #require(findRenderedPixels(in: window)).isEmpty == false)
        }
    }

    @Test func inlineDetailProgressBarDoesNotCollideWithDuoFocusToggleAndHidesWhenComplete()
        async throws
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
                            showsGrid: true))
                }
                .environment(SettingsStore.sample)
                .environment(\.isDuoExpanded, true)
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

        try await waitFor("Duo viewport inline preparation bar and identity laid out") {
            frameBox.frames["clove.detail.preparation.progress"] != nil
                && frameBox.frames["clove.detail.info"] != nil
                && frameBox.frames["clove.detail.focusToggle"] != nil
                && frameBox.frames["clove.detail.photoCornerOverlay"] != nil
                && frameBox.frames["clove.detail.fileName"] != nil
                && frameBox.frames["clove.detail.zoom"] != nil
                && self.findPreview(in: window) != nil
        }

        let preview = try #require(findPreview(in: window))
        let previewRect = preview.convert(preview.bounds, to: window)
        let overlay = try #require(frameBox.frames["clove.detail.photoCornerOverlay"])
        let infoButton = try #require(frameBox.frames["clove.detail.info"])
        let prepBar = try #require(frameBox.frames["clove.detail.preparation.progress"])
        let focus = try #require(frameBox.frames["clove.detail.focusToggle"])
        let fileName = try #require(frameBox.frames["clove.detail.fileName"])
        let zoom = try #require(frameBox.frames["clove.detail.zoom"])

        #expect(frameBox.frames["clove.detail.photoHeader"] == nil)
        #expect(frameBox.frames["clove.detail.preparation"] == nil)
        #expect(infoButton.width >= 44 && infoButton.height >= 44)
        #expect(prepBar.width >= 28 && prepBar.width <= 40)
        #expect(abs(prepBar.height - 3) <= 0.5)
        #expect(prepBar.minY >= fileName.maxY - 1)
        #expect(prepBar.minX >= zoom.maxX)
        #expect(prepBar.maxX <= overlay.maxX)
        #expect(!overlay.intersects(focus))
        #expect(!prepBar.intersects(focus))
        #expect(abs(overlay.minX - (previewRect.minX + 16)) <= 1.5)
        #expect(abs(overlay.minY - (previewRect.minY + 12)) <= 1.5)
        #expect(focus.minY > overlay.maxY)
        #expect(fileName.maxY <= zoom.minY + 1)
        #expect(abs(fileName.minX - zoom.minX) <= 2)
        #expect(frameBox.frames["clove.detail.saveState"] == nil)

        // Tappable identity badge intercepts hits cleanly over the viewport.
        let infoHit = window.hitTest(CGPoint(x: overlay.midX, y: overlay.midY), with: nil)
        #expect(infoHit != nil)
        #expect(infoHit?.isDescendant(of: preview) == false)

        // Switching to Focus View preserves the inline preparation bar and tappable badge.
        presentationBox.value = .focus
        let photoPreviewOverlayMinX = overlay.minX
        try await waitFor("Focus View viewport overlay did not lay out") {
            guard let preview = self.findPreview(in: window),
                let focusOverlay = frameBox.frames["clove.detail.photoCornerOverlay"]
            else {
                return false
            }
            let stageRect = preview.convert(preview.bounds, to: window)
            return self.findCollectionView(in: window) == nil
                && focusOverlay.minX < photoPreviewOverlayMinX - 40
                && abs(focusOverlay.minX - (stageRect.minX + 16)) <= 1.5
                && abs(focusOverlay.minY - (stageRect.minY + 12)) <= 1.5
        }
        let previewInFocus = try #require(findPreview(in: window))
        let focusPreviewRect = previewInFocus.convert(previewInFocus.bounds, to: window)
        let overlayInFocus = try #require(frameBox.frames["clove.detail.photoCornerOverlay"])
        let prepBarInFocus = try #require(frameBox.frames["clove.detail.preparation.progress"])
        let focusInFocus = try #require(frameBox.frames["clove.detail.focusToggle"])
        let fileInFocus = try #require(frameBox.frames["clove.detail.fileName"])
        let zoomInFocus = try #require(frameBox.frames["clove.detail.zoom"])

        #expect(frameBox.frames["clove.detail.photoHeader"] == nil)
        #expect(frameBox.frames["clove.detail.preparation"] == nil)
        #expect(!overlayInFocus.intersects(focusInFocus))
        #expect(prepBarInFocus.minY >= fileInFocus.maxY - 1)
        #expect(prepBarInFocus.minX >= zoomInFocus.maxX)
        #expect(focusInFocus.minY > overlayInFocus.maxY)
        #expect(abs(overlayInFocus.minX - (focusPreviewRect.minX + 16)) <= 1.5)
        #expect(abs(overlayInFocus.minY - (focusPreviewRect.minY + 12)) <= 1.5)

        // Completing preparation removes the transient inline bar automatically without resizing stage.
        let stageBeforeComplete = previewInFocus.convert(previewInFocus.bounds, to: window)
        let fitBeforeComplete = previewInFocus.imageRectAtFit()
        let stageAfter = previewInFocus.convert(previewInFocus.bounds, to: window)
        let fitAfter = previewInFocus.imageRectAtFit()
        #expect(abs(stageAfter.minY - stageBeforeComplete.minY) <= 0.5)
        #expect(abs(stageAfter.height - stageBeforeComplete.height) <= 0.5)
        #expect(abs(fitAfter.width - fitBeforeComplete.width) <= 0.5)
        #expect(abs(fitAfter.height - fitBeforeComplete.height) <= 0.5)
    }

    @Test func inlineProgressBarShowsDuringGroupingAndHidesWhenPreparationFinishesOnPhoneHeader()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let stubLibrary = GroupingPresentationStubLibrary(initialPhaseIdle: false)
        let browsing = BrowsingModel(library: stubLibrary)
        browsing.openFolder()
        try await waitFor("stub folder opened") {
            browsing.preparationStatus.totalPhotos == 12
        }
        let sampleLibrary = TestLibrary.sample()
        let stubPhoto = try #require(sampleLibrary.photos.first)
        var initialPreparing = FolderPreparationStatus(
            folder: stubLibrary.folder,
            folderName: "Coastal light",
            generation: 1,
            isEnumerating: false,
            isPartialScan: false,
            waitingReason: nil,
            totalPhotos: 12,
            analysis: FolderPreparationTaskCounts(completed: 6),
            previews: FolderPreparationTaskCounts(completed: 6),
            readyForBothCount: 6,
            bothSettledCount: 6,
            issues: [])
        stubLibrary.emit(.preparation(initialPreparing))
        try await waitFor("stub folder entered preparing phase") {
            browsing.preparationStatus.phase == .preparing
        }

        let frameBox = FrameStoreBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let timeline = DetailTimeline(photos: [stubPhoto], groups: [], groupsEnabled: false)
        let host = UIHostingController(
            rootView: NavigationStack {
                DetailMarkingView(
                    browsing: browsing,
                    photo: stubPhoto,
                    settings: SettingsStore.sample.settings,
                    images: SampleDetailImages(),
                    timeline: timeline,
                    expandedGroup: nil,
                    order: [stubPhoto],
                    actions: DetailMarkingActions(
                        apply: { _, _ in }, marked: { _, _, _ in }, step: { _ in },
                        markingSwipeBegan: {})
                )
            }
            .environment(SettingsStore.sample)
            .environment(\.cloveUserInterfaceIdiom, .phone)
            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frameBox.frames = $0 })
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("phone detail header inline progress bar laid out") {
            let hasFilterItem =
                self.findNavigationBar(in: window)?.topItem?.trailingItemGroups
                .flatMap(\.barButtonItems)
                .contains {
                    $0.accessibilityIdentifier == "clove.detail.filter"
                        || $0.accessibilityLabel == "Filter"
                        || $0.title == "Filter"
                        || $0.customView != nil
                } ?? false
            return frameBox.frames["clove.detail.preparation.progress"] != nil
                && frameBox.frames["clove.detail.info"] != nil
                && frameBox.frames["clove.detail.zoom"] != nil
                && hasFilterItem
        }
        #expect(frameBox.frames["clove.detail.preparation"] == nil)
        let info = try #require(frameBox.frames["clove.detail.info"])
        let zoom = try #require(frameBox.frames["clove.detail.zoom"])
        let progress = try #require(frameBox.frames["clove.detail.preparation.progress"])
        #expect(info.width >= 44 && info.height >= 44)
        #expect(progress.minX >= zoom.maxX)
        #expect(abs(progress.height - 3) <= 0.5)

        // Finishing preparation removes the transient Row 2 progress bar immediately.
        initialPreparing.analysis.completed = 12
        initialPreparing.previews.completed = 12
        initialPreparing.readyForBothCount = 12
        initialPreparing.bothSettledCount = 12
        stubLibrary.emit(.preparation(initialPreparing))
        try await waitFor("inline progress bar did not disappear upon completion") {
            browsing.preparationStatus.phase == .complete
                && frameBox.frames["clove.detail.preparation.progress"] == nil
        }
    }

    @Test func preparationAccessibilityHelpersMatchActivePausedAndIssueStates() {
        let idle = FolderPreparationStatus.idle
        #expect(!FolderPreparationAccessibility.isActive(for: idle, isGroupingInProgress: false))
        #expect(
            !FolderPreparationAccessibility.shouldShowInfoSheetPreparationRow(
                for: idle, isGroupingInProgress: false))
        #expect(FolderPreparationAccessibility.isActive(for: idle, isGroupingInProgress: true))
        #expect(
            FolderPreparationAccessibility.shouldShowInfoSheetPreparationRow(
                for: idle, isGroupingInProgress: true))

        var preparing = FolderPreparationStatus.idle
        preparing.totalPhotos = 10
        preparing.readyForBothCount = 4
        #expect(
            FolderPreparationAccessibility.isActive(for: preparing, isGroupingInProgress: false))
        #expect(
            FolderPreparationAccessibility.inlineProgressFraction(
                for: preparing, isGroupingInProgress: false, groupingProgress: .idle) == 0.4)
        #expect(
            FolderPreparationAccessibility.infoSheetSummaryText(
                for: preparing, isGroupingInProgress: false, groupingProgress: .idle)
                == "4 of 10 ready")

        var paused = preparing
        paused.waitingReason = .memoryPressure
        #expect(!FolderPreparationAccessibility.isActive(for: paused, isGroupingInProgress: false))
        #expect(
            FolderPreparationAccessibility.shouldShowInfoSheetPreparationRow(
                for: paused, isGroupingInProgress: false))
        #expect(
            FolderPreparationAccessibility.infoSheetSummaryText(
                for: paused, isGroupingInProgress: false, groupingProgress: .idle)
                == "Paused for memory")

        var complete = FolderPreparationStatus.idle
        complete.totalPhotos = 10
        complete.readyForBothCount = 10
        complete.bothSettledCount = 10
        #expect(
            !FolderPreparationAccessibility.isActive(for: complete, isGroupingInProgress: false))
        #expect(
            !FolderPreparationAccessibility.shouldShowInfoSheetPreparationRow(
                for: complete, isGroupingInProgress: false))

        var completeWithIssues = complete
        completeWithIssues.analysis.failed = 2
        completeWithIssues.issues = [
            FolderPreparationIssue(
                photo: PhotoIdentity(
                    folderID: FolderIdentity(rawValue: "f"), relativeFolderPath: "", stem: "a"),
                fileName: "a.ARW",
                task: .analysis,
                reason: "Failed")
        ]
        #expect(
            !FolderPreparationAccessibility.isActive(
                for: completeWithIssues, isGroupingInProgress: false))
        #expect(
            FolderPreparationAccessibility.shouldShowInfoSheetPreparationRow(
                for: completeWithIssues, isGroupingInProgress: false))
        #expect(
            FolderPreparationAccessibility.infoSheetSummaryText(
                for: completeWithIssues, isGroupingInProgress: false, groupingProgress: .idle)
                == "2 issues")
    }

    @Test func floatingDuoPreparationRingOpensPopoverAndHidingItDoesNotResizeStage() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let library = TestLibrary.forLaunch(
            environment: [
                TestLibrary.launchVariable: "1",
                TestLibrary.preparationVariable: "complete",
            ])
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        let first = try #require(browsing.photos.first?.id)
        browsing.openPhoto(first)

        let envBox = PreparationEnvironmentBox()
        envBox.isDuoExpanded = true
        let frameBox = FrameStoreBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 600)

        struct FloatingPopoverHost: View {
            let browsing: BrowsingModel
            let envBox: PreparationEnvironmentBox
            let frameBox: FrameStoreBox

            var body: some View {
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.clove.bg.stage)
                    HStack(spacing: 8) {
                        DetailPhotoCornerOverlay(
                            fileName: "MMQ02680.ARW",
                            positionText: "1 / 36",
                            isGroupFocus: false,
                            zoomText: nil,
                            language: .english)
                        FolderPreparationIndicator(
                            browsing: browsing,
                            identifierPrefix: "clove.detail.preparation",
                            usesCompactLayoutPadding: false,
                            usesFloatingBackdrop: true,
                            presentTrigger: envBox.presentTrigger)
                    }
                    .padding(.top, 12)
                    .padding(.leading, 16)
                }
                .environment(\.isDuoExpanded, true)
                .environment(\.scenePhase, envBox.scenePhase)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                    frameBox.frames = $0
                }
            }
        }

        let host = UIHostingController(
            rootView: FloatingPopoverHost(
                browsing: browsing, envBox: envBox, frameBox: frameBox))
        host.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("floating preparation indicator laid out") {
            frameBox.frames["clove.detail.preparation"] != nil
        }
        try await Task.sleep(for: .milliseconds(60))
        envBox.presentTrigger += 1
        try await waitFor("floating preparation popover did not present") {
            self.topPresentedViewController(from: host) != nil
        }
        host.dismiss(animated: false)
        try await waitFor("floating preparation popover did not dismiss") {
            self.topPresentedViewController(from: host) == nil
        }
        browsing.dismissPreparationCompletion(
            folder: browsing.preparationStatus.folder,
            generation: browsing.preparationStatus.generation)
        try await waitFor("floating preparation ring did not hide after completion dismissal") {
            frameBox.frames["clove.detail.preparation"] == nil
        }
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

    private func findPreview(in view: UIView) -> DetailZoomContainerView? {
        if let preview = view as? DetailZoomContainerView { return preview }
        for child in view.subviews {
            if let found = findPreview(in: child) { return found }
        }
        return nil
    }

    private func findCollectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        for child in view.subviews {
            if let found = findCollectionView(in: child) { return found }
        }
        return nil
    }

    private func findNavigationBar(in view: UIView) -> UINavigationBar? {
        if let navBar = view as? UINavigationBar { return navBar }
        for child in view.subviews {
            if let found = findNavigationBar(in: child) { return found }
        }
        return nil
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

@MainActor
private final class GroupingPresentationStubLibrary: FolderLibrary {
    let folder = FolderIdentity(rawValue: "stub-grouping-prep")
    let openGeneration = 1
    let photos: [GridPhoto] = []
    let groups: [BrowsingGroup] = []
    private(set) var preparationStatus: FolderPreparationStatus
    let updates: AsyncStream<FolderLibraryUpdate>
    private let continuation: AsyncStream<FolderLibraryUpdate>.Continuation

    init(initialPhaseIdle: Bool = false) {
        (updates, continuation) = AsyncStream.makeStream(of: FolderLibraryUpdate.self)
        if initialPhaseIdle {
            preparationStatus = .idle
        } else {
            preparationStatus = FolderPreparationStatus(
                folder: folder,
                folderName: "Coastal light",
                generation: 1,
                isEnumerating: false,
                isPartialScan: false,
                waitingReason: nil,
                totalPhotos: 12,
                analysis: FolderPreparationTaskCounts(completed: 12),
                previews: FolderPreparationTaskCounts(completed: 12),
                readyForBothCount: 12,
                bothSettledCount: 12,
                issues: [])
        }
        continuation.yield(.scanStarted)
        continuation.yield(.preparation(preparationStatus))
        continuation.yield(.scanFinished(FolderScanSummary(photoCount: 12, status: .complete)))
    }

    func emit(_ update: FolderLibraryUpdate) {
        if case .preparation(let status) = update {
            preparationStatus = status
        }
        continuation.yield(update)
    }
}
