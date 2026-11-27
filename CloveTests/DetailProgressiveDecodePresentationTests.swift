import CloveCore
import CloveImaging
import CoreGraphics
import Foundation
import Observation
import SwiftUI
import Testing

@testable import Clove

@MainActor
struct DetailProgressiveDecodePresentationTests {
    private static let folderID = FolderIdentity(rawValue: "detail-progressive-presentation")
    private static let photoID = PhotoIdentity(
        folderID: folderID, relativeFolderPath: "", stem: "DSC0001")

    private actor GateClock {
        private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []
        private var countObservers:
            [(id: UUID, targetCount: Int, continuation: CheckedContinuation<Void, Never>)] = []

        func sleep(for _: Duration) async throws {
            let waiterID = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    waiters.append((id: waiterID, continuation: continuation))
                    notifyCountObservers()
                }
            } onCancel: {
                Task { await self.cancel(id: waiterID) }
            }
        }

        func waitUntilPendingCount(equals targetCount: Int) async {
            if waiters.count == targetCount { return }
            let observerID = UUID()
            await withCheckedContinuation { continuation in
                countObservers.append(
                    (id: observerID, targetCount: targetCount, continuation: continuation))
            }
        }

        func advance() -> Bool {
            guard !waiters.isEmpty else { return false }
            let next = waiters.removeFirst()
            notifyCountObservers()
            next.continuation.resume(returning: ())
            return true
        }

        private func cancel(id: UUID) {
            guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
            let removed = waiters.remove(at: index)
            notifyCountObservers()
            removed.continuation.resume(throwing: CancellationError())
        }

        private func notifyCountObservers() {
            var remaining:
                [(id: UUID, targetCount: Int, continuation: CheckedContinuation<Void, Never>)] = []
            for observer in countObservers {
                if waiters.count == observer.targetCount {
                    observer.continuation.resume()
                } else {
                    remaining.append(observer)
                }
            }
            countObservers = remaining
        }
    }

    private func waitForPhase(
        _ expected: RawProgressiveDecodePhase,
        on controller: RawProgressiveDecodeController
    ) async {
        while controller.phase != expected {
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = controller.phase
                } onChange: {
                    Task { @MainActor in
                        continuation.resume()
                    }
                }
            }
        }
    }

    private static let dummyCGImage: CGImage = {
        let context = CGContext(
            data: nil, width: 16, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()

    private func makeDetailImage(
        fileName: String,
        quality: DetailQuality,
        hasRAW: Bool,
        limitation: DetailLimitation? = nil
    ) -> DetailImage {
        let url = URL(fileURLWithPath: "/tmp/\(fileName)")
        let source = DetailSource(
            url: url, revision: ThumbnailRevision(size: 1_024, modificationTime: .distantPast))
        return DetailImage(
            image: Self.dummyCGImage,
            source: source,
            quality: quality,
            hasRAW: hasRAW,
            limitation: limitation,
            fullResolutionSize: CGSize(width: 6_000, height: 4_000)
        )
    }

    @Test func detailHeaderPresentationCoversAllFourStatesAndLanguages() {
        // State 1 & State 3: clean `1 / 11 · 100%` (`.gating` collapses visibly to `.idle`).
        for phase in [RawProgressiveDecodePhase.idle, .gating] {
            let readout = DetailZoomReadoutPresentation(
                prefixText: "1 / 11",
                zoomText: "100%",
                showsProgressiveState: true,
                phase: phase,
                language: .english
            )
            #expect(readout.visualPhase == .idle)
            #expect(!readout.showsSpinner)
            #expect(readout.combinedVisibleText == "1 / 11 · 100%")
            #expect(readout.accessibilityLabel == "1 / 11 · 100%")
            #expect(readout.accessibilityValue == nil)
        }

        // State 2: > 250 ms reveals spinner + `Preview` while keeping accessibilityLabel compatible.
        let enPreview = DetailZoomReadoutPresentation(
            prefixText: "2 / 32",
            zoomText: "100%",
            showsProgressiveState: true,
            phase: .decodingPreview,
            language: .english
        )
        #expect(enPreview.visualPhase == .decodingPreview)
        #expect(enPreview.showsSpinner)
        #expect(enPreview.combinedVisibleText == "2 / 32 · 100% · Preview")
        #expect(enPreview.accessibilityLabel == "2 / 32 · 100%")
        #expect(enPreview.accessibilityValue == "Preview")

        let hansPreview = DetailZoomReadoutPresentation(
            prefixText: "1 / 11",
            zoomText: "100%",
            showsProgressiveState: true,
            phase: .decodingPreview,
            language: .simplifiedChinese
        )
        #expect(hansPreview.combinedVisibleText == "1 / 11 · 100% · 预览")
        #expect(hansPreview.accessibilityValue == "预览")

        let hantPreview = DetailZoomReadoutPresentation(
            prefixText: "1 / 11",
            zoomText: "100%",
            showsProgressiveState: true,
            phase: .decodingPreview,
            language: .traditionalChinese
        )
        #expect(hantPreview.combinedVisibleText == "1 / 11 · 100% · 預覽")
        #expect(hantPreview.accessibilityValue == "預覽")

        // State 4: failed / disconnected RAW settles on muted `Preview only` without spinner.
        let enPreviewOnly = DetailZoomReadoutPresentation(
            prefixText: "1 / 11",
            zoomText: "100%",
            showsProgressiveState: true,
            phase: .previewOnly,
            language: .english
        )
        #expect(enPreviewOnly.visualPhase == .previewOnly)
        #expect(!enPreviewOnly.showsSpinner)
        #expect(enPreviewOnly.combinedVisibleText == "1 / 11 · Preview only")
        #expect(enPreviewOnly.accessibilityLabel == "1 / 11 · Preview only")
        #expect(enPreviewOnly.accessibilityValue == nil)

        let hansPreviewOnly = DetailZoomReadoutPresentation(
            prefixText: "1 / 11",
            zoomText: "100%",
            showsProgressiveState: true,
            phase: .previewOnly,
            language: .simplifiedChinese
        )
        #expect(hansPreviewOnly.combinedVisibleText == "1 / 11 · 仅预览")

        let hantPreviewOnly = DetailZoomReadoutPresentation(
            prefixText: "1 / 11",
            zoomText: "100%",
            showsProgressiveState: true,
            phase: .previewOnly,
            language: .traditionalChinese
        )
        #expect(hantPreviewOnly.combinedVisibleText == "1 / 11 · 僅預覽")

        // Zoomed below 100% (or at Fit) suppresses any progressive suffix even if phase lingers.
        let clamped = DetailZoomReadoutPresentation(
            prefixText: "1 / 11",
            zoomText: "150%",
            showsProgressiveState: false,
            phase: .decodingPreview,
            language: .english
        )
        #expect(clamped.visualPhase == .idle)
        #expect(!clamped.showsSpinner)
        #expect(clamped.combinedVisibleText == "1 / 11 · 150%")
        #expect(clamped.accessibilityValue == nil)
    }

    @Test func comparePaneHeaderPresentationStaysIndependentAndOmitsIndexPrefix() {
        let paneAClean = DetailZoomReadoutPresentation(
            prefixText: nil,
            zoomText: "100%",
            showsProgressiveState: true,
            phase: .idle,
            language: .english
        )
        #expect(paneAClean.combinedVisibleText == "100%")
        #expect(!paneAClean.showsSpinner)

        let paneBPreview = DetailZoomReadoutPresentation(
            prefixText: nil,
            zoomText: "100%",
            showsProgressiveState: true,
            phase: .decodingPreview,
            language: .english
        )
        #expect(paneBPreview.combinedVisibleText == "100% · Preview")
        #expect(paneBPreview.showsSpinner)
        #expect(paneBPreview.accessibilityLabel == "100%")
        #expect(paneBPreview.accessibilityValue == "Preview")

        let paneBPreviewOnly = DetailZoomReadoutPresentation(
            prefixText: nil,
            zoomText: "100%",
            showsProgressiveState: true,
            phase: .previewOnly,
            language: .english
        )
        #expect(paneBPreviewOnly.combinedVisibleText == "Preview only")
        #expect(!paneBPreviewOnly.showsSpinner)
        #expect(paneBPreviewOnly.accessibilityLabel == "Preview only")
    }

    @Test func cornerOverlayMetadataStringsIncludeGroupFocusAndProgressiveStates() {
        let slowGroup = DetailPhotoCornerOverlay.metadataStrings(
            positionText: "3 / 5",
            isGroupFocus: true,
            zoomText: "100%",
            showsProgressiveState: true,
            progressiveDecodePhase: .decodingPreview,
            language: .english
        )
        #expect(slowGroup.visible == "3 / 5 · 100% · Preview")
        #expect(slowGroup.accessible == "Group · 3 / 5 · 100%")

        let previewOnlyGroup = DetailPhotoCornerOverlay.metadataStrings(
            positionText: "3 / 5",
            isGroupFocus: true,
            zoomText: "100%",
            showsProgressiveState: true,
            progressiveDecodePhase: .previewOnly,
            language: .simplifiedChinese
        )
        #expect(previewOnlyGroup.visible == "3 / 5 · 仅预览")
        #expect(previewOnlyGroup.accessible == "分组 · 3 / 5 · 仅预览")
    }

    @Test func supportBridgeHandlesSlowDecodeFastDecodeJpegAndFailure() async throws {
        let clock = GateClock()
        let controller = RawProgressiveDecodeController(sleep: { try await clock.sleep(for: $0) })

        let rawURL = URL(fileURLWithPath: "/tmp/DSC0001.ARW")
        let jpegURL = URL(fileURLWithPath: "/tmp/DSC0001.JPG")
        let rawWithCompanion = try PhotoSet(
            folderID: Self.folderID,
            relativeFolderPath: "",
            rawURL: rawURL,
            jpegURL: jpegURL
        )

        let embeddedPreview = makeDetailImage(
            fileName: "DSC0001.ARW", quality: .preview, hasRAW: true)
        let nativeRAW = makeDetailImage(
            fileName: "DSC0001.ARW", quality: .nativeRAW, hasRAW: true)
        let failedRAW = makeDetailImage(
            fileName: "DSC0001.ARW", quality: .preview, hasRAW: true, limitation: .rawRenderFailed)

        // Standalone JPEG stays invisible even if a test mock flags hasRAW=true.
        let jpegToken = DetailProgressiveDecodeSupport.syncAtFullResolution(
            controller: controller,
            photoID: Self.photoID,
            fileName: "MMQ02714.JPG",
            photoSet: nil,
            displayMode: .rawFirst,
            shown: embeddedPreview,
            isPreviewOnly: false,
            isLocationLost: false,
            startingUpgrade: true
        )
        #expect(jpegToken == nil)
        #expect(controller.phase == .idle)

        // RAW + companion in cameraPreviewFirst skips RAW gate when preview comes from companion.
        let companionToken = DetailProgressiveDecodeSupport.syncAtFullResolution(
            controller: controller,
            photoID: Self.photoID,
            fileName: "DSC0001.ARW",
            photoSet: rawWithCompanion,
            displayMode: .cameraPreviewFirst,
            shown: embeddedPreview,
            isPreviewOnly: false,
            isLocationLost: false,
            startingUpgrade: true
        )
        #expect(companionToken == nil)
        #expect(controller.phase == .idle)

        // RAW-first slow path crosses 250 ms gate, shows Preview, then settles cleanly on nativeRAW.
        let rawToken = try #require(
            DetailProgressiveDecodeSupport.syncAtFullResolution(
                controller: controller,
                photoID: Self.photoID,
                fileName: "DSC0001.ARW",
                photoSet: rawWithCompanion,
                displayMode: .rawFirst,
                shown: embeddedPreview,
                isPreviewOnly: false,
                isLocationLost: false,
                startingUpgrade: true
            )
        )
        await clock.waitUntilPendingCount(equals: 1)
        #expect(controller.phase == .gating)
        #expect(await clock.advance())
        await waitForPhase(.decodingPreview, on: controller)
        #expect(controller.phase == .decodingPreview)

        DetailProgressiveDecodeSupport.settle(
            controller: controller,
            token: rawToken,
            outcome: .image(nativeRAW),
            photoID: Self.photoID,
            fileName: "DSC0001.ARW",
            photoSet: rawWithCompanion,
            isLocationLost: false
        )
        #expect(controller.phase == .idle)

        // Failed RAW stops into `.previewOnly` and does not re-spin when inspected again.
        let retryToken = try #require(
            DetailProgressiveDecodeSupport.syncAtFullResolution(
                controller: controller,
                photoID: Self.photoID,
                fileName: "DSC0001.ARW",
                photoSet: rawWithCompanion,
                displayMode: .rawFirst,
                shown: embeddedPreview,
                isPreviewOnly: false,
                isLocationLost: false,
                startingUpgrade: true
            )
        )
        DetailProgressiveDecodeSupport.settle(
            controller: controller,
            token: retryToken,
            outcome: .image(failedRAW),
            photoID: Self.photoID,
            fileName: "DSC0001.ARW",
            photoSet: rawWithCompanion,
            isLocationLost: false
        )
        #expect(controller.phase == .previewOnly)
        #expect(!controller.phase.showsSpinner)
    }

    @Test func unknownNativeDimensionsSurfacesDecodeAndPreviewOnlyAtFitScale() async throws {
        let clock = GateClock()
        let controller = RawProgressiveDecodeController(sleep: { try await clock.sleep(for: $0) })

        let url = URL(fileURLWithPath: "/tmp/DSC0002.ARW")
        let source = DetailSource(
            url: url, revision: ThumbnailRevision(size: 1_024, modificationTime: .distantPast))
        let unknownSizePreview = DetailImage(
            image: Self.dummyCGImage,
            source: source,
            quality: .preview,
            hasRAW: true,
            fullResolutionSize: nil
        )
        let photoSet = try PhotoSet(folderID: Self.folderID, relativeFolderPath: "", rawURL: url)
        let viewSize = CGSize(width: 400, height: 600)

        let token = try #require(
            DetailProgressiveDecodeSupport.syncAtFullResolution(
                controller: controller,
                photoID: Self.photoID,
                fileName: "DSC0002.ARW",
                photoSet: photoSet,
                displayMode: .rawFirst,
                shown: unknownSizePreview,
                isPreviewOnly: false,
                isLocationLost: false,
                startingUpgrade: true
            )
        )
        await clock.waitUntilPendingCount(equals: 1)

        // While waiting at scale 1.0 with unknown native size, explicit zoomMode = .fullResolution
        // keeps progressive state eligible and resolves label `"100%"` in both Detail and Compare.
        let showsGating = DetailProgressiveDecodeSupport.showsProgressiveState(
            scale: 1.0,
            zoomModeIsFullResolution: true,
            fullResolutionPixels: nil,
            viewSize: viewSize,
            screenScale: 3,
            isFullResolutionUpgradeInFlight: true,
            phase: controller.phase
        )
        #expect(showsGating)
        let gatingDetailZoom = DetailProgressiveDecodeSupport.zoomLabelText(
            scale: 1.0,
            scaledZoomText: "Fit",
            fitText: nil,
            zoomModeIsFullResolution: true,
            isFullResolutionUpgradeInFlight: true,
            phase: controller.phase,
            language: .english
        )
        #expect(gatingDetailZoom == "100%")

        // Crossing 250 ms surfaces `100% · Preview` even while scale remains at 1.0.
        #expect(await clock.advance())
        await waitForPhase(.decodingPreview, on: controller)

        let showsDecoding = DetailProgressiveDecodeSupport.showsProgressiveState(
            scale: 1.0,
            zoomModeIsFullResolution: true,
            fullResolutionPixels: nil,
            viewSize: viewSize,
            screenScale: 3,
            isFullResolutionUpgradeInFlight: true,
            phase: controller.phase
        )
        #expect(showsDecoding)
        let decodingDetailZoom = try #require(
            DetailProgressiveDecodeSupport.zoomLabelText(
                scale: 1.0,
                scaledZoomText: "Fit",
                fitText: nil,
                zoomModeIsFullResolution: true,
                isFullResolutionUpgradeInFlight: true,
                phase: controller.phase,
                language: .english
            )
        )
        let decodingCompareZoom = try #require(
            DetailProgressiveDecodeSupport.zoomLabelText(
                scale: 1.0,
                scaledZoomText: "Fit",
                fitText: "Fit",
                zoomModeIsFullResolution: true,
                isFullResolutionUpgradeInFlight: true,
                phase: controller.phase,
                language: .english
            )
        )
        let detailPreviewReadout = DetailZoomReadoutPresentation(
            prefixText: "1 / 11",
            zoomText: decodingDetailZoom,
            showsProgressiveState: showsDecoding,
            phase: controller.phase,
            language: .english
        )
        let comparePreviewReadout = DetailZoomReadoutPresentation(
            prefixText: nil,
            zoomText: decodingCompareZoom,
            showsProgressiveState: showsDecoding,
            phase: controller.phase,
            language: .english
        )
        #expect(detailPreviewReadout.combinedVisibleText == "1 / 11 · 100% · Preview")
        #expect(detailPreviewReadout.showsSpinner)
        #expect(comparePreviewReadout.combinedVisibleText == "100% · Preview")
        #expect(comparePreviewReadout.showsSpinner)

        // Failing / unavailable decode at scale 1.0 still surfaces `Preview only`.
        DetailProgressiveDecodeSupport.settle(
            controller: controller,
            token: token,
            outcome: .unavailable(.cannotOpen),
            photoID: Self.photoID,
            fileName: "DSC0002.ARW",
            photoSet: photoSet,
            isLocationLost: false
        )
        #expect(controller.phase == .previewOnly)

        let showsPreviewOnly = DetailProgressiveDecodeSupport.showsProgressiveState(
            scale: 1.0,
            zoomModeIsFullResolution: true,
            fullResolutionPixels: nil,
            viewSize: viewSize,
            screenScale: 3,
            isFullResolutionUpgradeInFlight: false,
            phase: controller.phase
        )
        #expect(showsPreviewOnly)
        let failedDetailZoom = try #require(
            DetailProgressiveDecodeSupport.zoomLabelText(
                scale: 1.0,
                scaledZoomText: "Fit",
                fitText: nil,
                zoomModeIsFullResolution: true,
                isFullResolutionUpgradeInFlight: false,
                phase: controller.phase,
                language: .english
            )
        )
        let detailFailedReadout = DetailZoomReadoutPresentation(
            prefixText: "1 / 11",
            zoomText: failedDetailZoom,
            showsProgressiveState: showsPreviewOnly,
            phase: controller.phase,
            language: .english
        )
        let compareFailedReadout = DetailZoomReadoutPresentation(
            prefixText: nil,
            zoomText: DetailProgressiveDecodeSupport.zoomLabelText(
                scale: 1.0,
                scaledZoomText: "Fit",
                fitText: "Fit",
                zoomModeIsFullResolution: true,
                isFullResolutionUpgradeInFlight: false,
                phase: controller.phase,
                language: .english
            ),
            showsProgressiveState: showsPreviewOnly,
            phase: controller.phase,
            language: .english
        )
        #expect(detailFailedReadout.combinedVisibleText == "1 / 11 · Preview only")
        #expect(!detailFailedReadout.showsSpinner)
        #expect(compareFailedReadout.combinedVisibleText == "Preview only")
        #expect(!compareFailedReadout.showsSpinner)
    }

    @Test func pinchingAboveFullResolutionAndBackRetainsInFlightDecodeCue() async throws {
        let clock = GateClock()
        let controller = RawProgressiveDecodeController(sleep: { try await clock.sleep(for: $0) })

        let url = URL(fileURLWithPath: "/tmp/DSC0003.ARW")
        let photoSet = try PhotoSet(folderID: Self.folderID, relativeFolderPath: "", rawURL: url)
        let nativePixels = CGSize(width: 6_000, height: 4_000)
        let viewSize = CGSize(width: 393, height: 852)
        let screenScale: CGFloat = 3
        let fullResScale = DetailZoom.fullResolutionScale(
            nativePixels: nativePixels,
            shownPixels: nativePixels,
            viewSize: viewSize,
            screenScale: screenScale
        )
        let embeddedPreview = makeDetailImage(
            fileName: "DSC0003.ARW", quality: .preview, hasRAW: true)

        let token = try #require(
            DetailProgressiveDecodeSupport.syncAtFullResolution(
                controller: controller,
                photoID: Self.photoID,
                fileName: "DSC0003.ARW",
                photoSet: photoSet,
                displayMode: .rawFirst,
                shown: embeddedPreview,
                isPreviewOnly: false,
                isLocationLost: false,
                startingUpgrade: true
            )
        )
        await clock.waitUntilPendingCount(equals: 1)
        #expect(await clock.advance())
        await waitForPhase(.decodingPreview, on: controller)

        // Manual pinch slightly past 100% stays eligible and retains the active decode gate.
        let scaleAbove100 = fullResScale * 1.35
        #expect(
            DetailProgressiveDecodeSupport.isAtOrAboveFullResolution(
                scale: scaleAbove100,
                zoomModeIsFullResolution: false,
                fullResolutionPixels: nativePixels,
                viewSize: viewSize,
                screenScale: screenScale
            ))
        #expect(
            DetailProgressiveDecodeSupport.shouldRetainProgressiveDecodeAboveFit(
                scale: scaleAbove100,
                zoomModeIsFullResolution: false,
                fullResolutionPixels: nativePixels,
                viewSize: viewSize,
                screenScale: screenScale,
                isFullResolutionUpgradeInFlight: true
            ))
        #expect(
            DetailProgressiveDecodeSupport.showsProgressiveState(
                scale: scaleAbove100,
                zoomModeIsFullResolution: false,
                fullResolutionPixels: nativePixels,
                viewSize: viewSize,
                screenScale: screenScale,
                isFullResolutionUpgradeInFlight: true,
                phase: controller.phase
            ))

        // Even dipping momentarily below 100% above Fit retains an active `.fullResolution` decode.
        let scaleBelow100 = fullResScale * 0.8
        #expect(
            DetailProgressiveDecodeSupport.shouldRetainProgressiveDecodeAboveFit(
                scale: scaleBelow100,
                zoomModeIsFullResolution: false,
                fullResolutionPixels: nativePixels,
                viewSize: viewSize,
                screenScale: screenScale,
                isFullResolutionUpgradeInFlight: true
            ))
        #expect(controller.phase == .decodingPreview)

        // Returning to 100% still displays `100% · Preview` until the in-flight decode completes.
        let returnedReadout = DetailZoomReadoutPresentation(
            prefixText: "1 / 11",
            zoomText: "100%",
            showsProgressiveState: DetailProgressiveDecodeSupport.showsProgressiveState(
                scale: fullResScale,
                zoomModeIsFullResolution: false,
                fullResolutionPixels: nativePixels,
                viewSize: viewSize,
                screenScale: screenScale,
                isFullResolutionUpgradeInFlight: true,
                phase: controller.phase
            ),
            phase: controller.phase,
            language: .english
        )
        #expect(returnedReadout.combinedVisibleText == "1 / 11 · 100% · Preview")
        #expect(returnedReadout.showsSpinner)

        // Once no `.fullResolution` upgrade runs, zooming below 100% or to Fit clears retention.
        controller.complete(token: token)
        #expect(controller.phase == .idle)
        #expect(
            !DetailProgressiveDecodeSupport.shouldRetainProgressiveDecodeAboveFit(
                scale: scaleBelow100,
                zoomModeIsFullResolution: false,
                fullResolutionPixels: nativePixels,
                viewSize: viewSize,
                screenScale: screenScale,
                isFullResolutionUpgradeInFlight: false
            ))
        #expect(
            !DetailProgressiveDecodeSupport.shouldRetainProgressiveDecodeAboveFit(
                scale: 1.0,
                zoomModeIsFullResolution: false,
                fullResolutionPixels: nativePixels,
                viewSize: viewSize,
                screenScale: screenScale,
                isFullResolutionUpgradeInFlight: false
            ))
    }
}
