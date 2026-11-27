import CloveCore
import CloveImaging
import CoreGraphics
import Foundation
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

        func sleep(for _: Duration) async throws {
            let waiterID = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    waiters.append((id: waiterID, continuation: continuation))
                }
            } onCancel: {
                Task { await self.cancel(id: waiterID) }
            }
        }

        func advance() -> Bool {
            guard !waiters.isEmpty else { return false }
            let next = waiters.removeFirst()
            next.continuation.resume(returning: ())
            return true
        }

        private func cancel(id: UUID) {
            guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
            let removed = waiters.remove(at: index)
            removed.continuation.resume(throwing: CancellationError())
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
        await Task.yield()
        #expect(controller.phase == .gating)
        #expect(await clock.advance())
        await Task.yield()
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
}
