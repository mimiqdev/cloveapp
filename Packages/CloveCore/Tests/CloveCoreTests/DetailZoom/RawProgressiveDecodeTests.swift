import CloveCore
import Foundation
import Testing

@Suite("RawProgressiveDecode")
struct RawProgressiveDecodeTests {
    private static let folder = FolderIdentity(rawValue: "raw-progressive-test-folder")
    private static let rawPhotoA = PhotoIdentity(
        folderID: folder, relativeFolderPath: "", stem: "RAW_A")
    private static let rawPhotoB = PhotoIdentity(
        folderID: folder, relativeFolderPath: "", stem: "RAW_B")

    private actor ControlledSleep {
        private var waiters:
            [(id: UUID, duration: Duration, continuation: CheckedContinuation<Void, any Error>)] =
                []

        var pendingCount: Int { waiters.count }
        var lastRequestedDuration: Duration? { waiters.last?.duration }

        func wait(for duration: Duration) async throws {
            let waiterID = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    waiters.append((id: waiterID, duration: duration, continuation: continuation))
                }
            } onCancel: {
                Task { await self.cancel(id: waiterID) }
            }
        }

        func advanceNext() -> Bool {
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

    @Test("Default gate delay matches 250 ms")
    func defaultGateDelay() {
        #expect(RawProgressiveDecodeController.defaultGateDelay == .milliseconds(250))
    }

    @Test("Fast decode before 250 ms gate settles cleanly without showing spinner or Preview")
    @MainActor
    func fastDecodeNeverRevealsPreview() async {
        let clock = ControlledSleep()
        let controller = RawProgressiveDecodeController(
            sleep: { try await clock.wait(for: $0) }
        )

        #expect(controller.phase == .idle)
        let token = controller.beginUpgrade(for: Self.rawPhotoA)
        #expect(controller.phase == .gating)
        #expect(!controller.phase.showsSpinner)
        #expect(!controller.phase.isPreviewOnly)

        await Task.yield()
        #expect(await clock.lastRequestedDuration == .milliseconds(250))
        #expect(await clock.pendingCount == 1)

        controller.complete(token: token)
        #expect(controller.phase == .idle)
        #expect(!controller.phase.showsSpinner)

        // Even after yielding, the cancelled delay task must not surface `.decodingPreview`.
        await Task.yield()
        #expect(await clock.pendingCount == 0)
        #expect(controller.phase == .idle)
    }

    @Test("Slow decode crossing 250 ms reveals spinner and Preview then clears on completion")
    @MainActor
    func slowDecodeRevealsThenClears() async {
        let clock = ControlledSleep()
        let controller = RawProgressiveDecodeController(
            sleep: { try await clock.wait(for: $0) }
        )

        let token = controller.beginUpgrade(for: Self.rawPhotoA)
        await Task.yield()
        #expect(controller.phase == .gating)

        #expect(await clock.advanceNext())
        await Task.yield()
        #expect(controller.phase == .decodingPreview)
        #expect(controller.phase.showsSpinner)
        #expect(!controller.phase.isPreviewOnly)

        controller.complete(token: token)
        #expect(controller.phase == .idle)
        #expect(!controller.phase.showsSpinner)
        #expect(!controller.phase.isPreviewOnly)
    }

    @Test("Decode failure or storage disconnect stops spinner into Preview only immediately")
    @MainActor
    func failureAndLocationLossStopSpinnerIntoPreviewOnly() async {
        let clock = ControlledSleep()
        let controller = RawProgressiveDecodeController(
            sleep: { try await clock.wait(for: $0) }
        )

        let token = controller.beginUpgrade(for: Self.rawPhotoA)
        await Task.yield()
        #expect(await clock.advanceNext())
        await Task.yield()
        #expect(controller.phase == .decodingPreview)

        controller.fail(token: token)
        #expect(controller.phase == .previewOnly)
        #expect(!controller.phase.showsSpinner)
        #expect(controller.phase.isPreviewOnly)

        // Subsequent location loss path while gating also halts spinner into `.previewOnly`.
        controller.reset()
        #expect(controller.phase == .idle)

        _ = controller.beginUpgrade(for: Self.rawPhotoB)
        await Task.yield()
        controller.enterPreviewOnly()
        await Task.yield()
        #expect(await clock.pendingCount == 0)
        #expect(controller.phase == .previewOnly)
        #expect(!controller.phase.showsSpinner)
    }

    @Test("Photo change or Fit zoom resets immediately and ignores stale tokens")
    @MainActor
    func resetCancelsGateAndIgnoresStaleTokens() async {
        let clock = ControlledSleep()
        let controller = RawProgressiveDecodeController(
            sleep: { try await clock.wait(for: $0) }
        )

        let staleToken = controller.beginUpgrade(for: Self.rawPhotoA)
        await Task.yield()
        controller.reset()
        await Task.yield()

        #expect(controller.phase == .idle)
        #expect(await clock.pendingCount == 0)

        let freshToken = controller.beginUpgrade(for: Self.rawPhotoB)
        await Task.yield()

        // Stale completion or failure from photo A must not affect photo B's active gate.
        controller.fail(token: staleToken)
        #expect(controller.phase == .gating)
        controller.complete(token: staleToken)
        #expect(controller.phase == .gating)

        #expect(await clock.advanceNext())
        await Task.yield()
        #expect(controller.phase == .decodingPreview)

        // Switching away again resets immediately (no linger).
        controller.reset()
        #expect(controller.phase == .idle)
        #expect(controller.activeToken == nil)
        controller.complete(token: freshToken)
        #expect(controller.phase == .idle)
    }

    @Test("Re-calling beginUpgrade for the same in-flight photo preserves the existing gate")
    @MainActor
    func repeatedBeginForSamePhotoPreservesGate() async {
        let clock = ControlledSleep()
        let controller = RawProgressiveDecodeController(
            sleep: { try await clock.wait(for: $0) }
        )

        let first = controller.beginUpgrade(for: Self.rawPhotoA)
        let second = controller.beginUpgrade(for: Self.rawPhotoA)
        #expect(first == second)

        await Task.yield()
        #expect(await clock.pendingCount == 1)
    }

    @Test("Deferred cancellation clears active token to idle instead of Preview only")
    @MainActor
    func deferredCancelReturnsToIdle() async {
        let clock = ControlledSleep()
        let controller = RawProgressiveDecodeController(
            sleep: { try await clock.wait(for: $0) }
        )

        let token = controller.beginUpgrade(for: Self.rawPhotoA)
        await Task.yield()
        _ = await clock.advanceNext()
        await Task.yield()
        #expect(controller.phase == .decodingPreview)

        controller.cancel(token: token)
        #expect(controller.phase == .idle)
        #expect(!controller.phase.isPreviewOnly)
    }

    @Test("Eligibility distinguishes RAW upgrade candidates from non-RAW and companion modes")
    func eligibilityRules() {
        let rawFirstCandidate = RawProgressiveDecodeEligibility(
            primaryFormat: .raw,
            hasCameraCompanion: true,
            displayMode: .rawFirst,
            shownHasRAW: true,
            shownIsNativeRAW: false,
            shownIsScreenRAW: false,
            shownIsBestAvailable: false,
            isPreviewOnly: false,
            isLocationLost: false
        )
        #expect(rawFirstCandidate.shouldTrackFullResolutionUpgrade)
        #expect(!rawFirstCandidate.shouldShowStaticPreviewOnly)

        let cameraFirstWithCompanion = RawProgressiveDecodeEligibility(
            primaryFormat: .raw,
            hasCameraCompanion: true,
            displayMode: .cameraPreviewFirst,
            shownHasRAW: true,
            shownIsNativeRAW: false,
            shownIsScreenRAW: false,
            shownIsBestAvailable: false,
            isPreviewOnly: false,
            isLocationLost: false
        )
        #expect(!cameraFirstWithCompanion.shouldTrackFullResolutionUpgrade)

        let cameraFirstCompanionFellBackToScreenRAW = RawProgressiveDecodeEligibility(
            primaryFormat: .raw,
            hasCameraCompanion: true,
            displayMode: .cameraPreviewFirst,
            shownHasRAW: true,
            shownIsNativeRAW: false,
            shownIsScreenRAW: true,
            shownIsBestAvailable: false,
            isPreviewOnly: false,
            isLocationLost: false
        )
        #expect(cameraFirstCompanionFellBackToScreenRAW.shouldTrackFullResolutionUpgrade)

        let cameraFirstRawOnly = RawProgressiveDecodeEligibility(
            primaryFormat: .raw,
            hasCameraCompanion: false,
            displayMode: .cameraPreviewFirst,
            shownHasRAW: true,
            shownIsNativeRAW: false,
            shownIsScreenRAW: false,
            shownIsBestAvailable: false,
            isPreviewOnly: false,
            isLocationLost: false
        )
        #expect(cameraFirstRawOnly.shouldTrackFullResolutionUpgrade)

        for nonRawFormat in [PhotoFormat.jpeg, .heif] {
            let standalone = RawProgressiveDecodeEligibility(
                primaryFormat: nonRawFormat,
                hasCameraCompanion: false,
                displayMode: .rawFirst,
                shownHasRAW: true,  // Guards against mock detail sources setting hasRAW=true
                shownIsNativeRAW: false,
                shownIsScreenRAW: false,
                shownIsBestAvailable: false,
                isPreviewOnly: false,
                isLocationLost: false
            )
            #expect(!standalone.shouldTrackFullResolutionUpgrade)
            #expect(!standalone.shouldShowStaticPreviewOnly)
        }

        let alreadyDecoded = RawProgressiveDecodeEligibility(
            primaryFormat: .raw,
            hasCameraCompanion: false,
            displayMode: .rawFirst,
            shownHasRAW: true,
            shownIsNativeRAW: true,
            shownIsScreenRAW: false,
            shownIsBestAvailable: true,
            isPreviewOnly: false,
            isLocationLost: false
        )
        #expect(!alreadyDecoded.shouldTrackFullResolutionUpgrade)
        #expect(!alreadyDecoded.shouldShowStaticPreviewOnly)

        let previewOnlyRAW = RawProgressiveDecodeEligibility(
            primaryFormat: .raw,
            hasCameraCompanion: false,
            displayMode: .rawFirst,
            shownHasRAW: true,
            shownIsNativeRAW: false,
            shownIsScreenRAW: false,
            shownIsBestAvailable: false,
            isPreviewOnly: true,
            isLocationLost: false
        )
        #expect(!previewOnlyRAW.shouldTrackFullResolutionUpgrade)
        #expect(previewOnlyRAW.shouldShowStaticPreviewOnly)
    }
}
