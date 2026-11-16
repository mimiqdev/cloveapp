import CloveCore
import CloveImaging
import Foundation
import Testing

@testable import Clove

@MainActor
struct FolderPreparationAccountingTests {
    @Test func readyForBothCountsExactIntersectionOfDisjointSets() throws {
        let folder = FolderIdentity(rawValue: "folder-disjoint")
        let setA = try makeScannedSet(folder: folder, stem: "IMG_0001")
        let setB = try makeScannedSet(folder: folder, stem: "IMG_0002")
        let setC = try makeScannedSet(folder: folder, stem: "IMG_0003")
        let setD = try makeScannedSet(folder: folder, stem: "IMG_0004")

        var accountant = FolderPreparationAccountant(
            folder: folder, folderName: "Shoot", generation: 1, parametersVersion: 2)
        accountant.registerDiscovered([setA, setB, setC, setD])
        accountant.finishScan(isPartial: false)

        // Analysis completes on {A, B}; previews complete on {C, D}. Intersection must be 0,
        // never min(2, 2) or average(2, 2).
        let changedAAnalysis = accountant.recordAnalysisClassification(.completed, for: setA.id)
        let changedBAnalysis = accountant.recordAnalysisClassification(.completed, for: setB.id)
        let changedCPreview = accountant.recordPreviewClassification(.completed, for: setC.id)
        let changedDPreview = accountant.recordPreviewClassification(.completed, for: setD.id)
        #expect(changedAAnalysis && changedBAnalysis && changedCPreview && changedDPreview)

        let disjointStatus = accountant.status
        #expect(disjointStatus.totalPhotos == 4)
        #expect(disjointStatus.analysis.completed == 2)
        #expect(disjointStatus.previews.completed == 2)
        #expect(disjointStatus.readyForBothCount == 0)
        #expect(disjointStatus.bothSettledCount == 0)
        #expect(disjointStatus.readyFraction == 0)
        #expect(disjointStatus.analysisFraction == 0.5)
        #expect(disjointStatus.previewFraction == 0.5)
        #expect(disjointStatus.phase == .preparing)

        // Now overlap at A and C -> intersection is 2, not 3.
        let changedAPreview = accountant.recordPreviewClassification(.completed, for: setA.id)
        let changedCAnalysis = accountant.recordAnalysisClassification(.completed, for: setC.id)
        #expect(changedAPreview && changedCAnalysis)

        let overlappedStatus = accountant.status
        #expect(overlappedStatus.analysis.completed == 3)
        #expect(overlappedStatus.previews.completed == 3)
        #expect(overlappedStatus.readyForBothCount == 2)
        #expect(overlappedStatus.bothSettledCount == 2)
        #expect(overlappedStatus.readyFraction == 0.5)
        #expect(overlappedStatus.phase == .preparing)
    }

    @Test func companionPhotoSetCountsAsOneLogicalPhotoAndCompanionInvalidationTargetsAnalysis()
        throws
    {
        let folder = FolderIdentity(rawValue: "folder-companions")
        let dir = URL(fileURLWithPath: "/tmp/prep-companions", isDirectory: true)
        let rawURL = dir.appendingPathComponent("DSC00100.ARW")
        let jpegURL = dir.appendingPathComponent("DSC00100.JPG")
        let heifURL = dir.appendingPathComponent("DSC00100.HIF")
        let revision = ThumbnailRevision(
            size: 4096, modificationTime: Date(timeIntervalSince1970: 1))
        let photoSet = try PhotoSet(
            folderID: folder, relativeFolderPath: "", rawURL: rawURL, jpegURL: jpegURL,
            heifURL: heifURL)
        let scanned = ScannedPhotoSet(
            photoSet: photoSet, sidecar: .absent,
            imageFiles: [
                ScannedImageFile(
                    file: photoSet.primary, size: 4096,
                    modificationDate: revision.modificationTime),
                ScannedImageFile(
                    file: try #require(photoSet.jpegCompanion), size: 1024,
                    modificationDate: revision.modificationTime),
                ScannedImageFile(
                    file: try #require(photoSet.heifCompanion), size: 1024,
                    modificationDate: revision.modificationTime),
            ])

        var accountant = FolderPreparationAccountant(
            folder: folder, folderName: "Companions", generation: 3, parametersVersion: 2)
        accountant.registerDiscovered([scanned])
        accountant.finishScan(isPartial: false)

        let thumbReq = try #require(
            FolderPreparationAccountant.makeThumbnailRequest(for: scanned, folder: folder))
        let regionReq = try #require(
            FolderPreparationAccountant.makeRegionRequest(for: scanned, folder: folder))
        #expect(regionReq.raw?.url == rawURL)
        #expect(regionReq.jpeg?.url == jpegURL)
        #expect(regionReq.heif?.url == heifURL)

        let key = SharpnessResultKey(
            folderSession: folder.rawValue,
            photo: rawURL,
            revision: revision,
            parametersVersion: 2)
        let analysis = RegionSharpnessAnalysis(
            autofocus: .unavailable(.noAutofocusMetadata(emptyAFEvidence)),
            faces: .unavailable(.noFacesDetected),
            acquisitionFailure: nil,
            timings: RegionSharpnessTimings())

        let thumbRecorded = accountant.recordPreviewOutcome(.completed, for: thumbReq)
        let analysisRecorded = accountant.recordAnalysisSettlement(
            key: key, request: regionReq, analysis: analysis)
        #expect(thumbRecorded && analysisRecorded)

        #expect(accountant.status.totalPhotos == 1)
        #expect(accountant.status.readyForBothCount == 1)
        #expect(accountant.status.phase == .complete)

        // Invalidating companion JPEG resets analysis for the logical PhotoSet while preserving
        // its already-prepared primary thumbnail.
        let companionInvalidated = accountant.invalidate(sources: [jpegURL])
        #expect(companionInvalidated == [scanned.id])
        #expect(accountant.status.previews.completed == 1)
        #expect(accountant.status.analysis.completed == 0)
        #expect(accountant.status.readyForBothCount == 0)
        #expect(accountant.status.phase == .preparing)

        // Re-settling completes again, then invalidating primary resets both.
        accountant.setResolvedRequests(
            for: scanned.id, thumbnailRequest: thumbReq, regionRequest: regionReq)
        let reRecorded = accountant.recordAnalysisSettlement(
            key: key, request: regionReq, analysis: analysis)
        #expect(reRecorded)
        #expect(accountant.status.phase == .complete)

        let primaryInvalidated = accountant.invalidate(sources: [rawURL])
        #expect(primaryInvalidated == [scanned.id])
        #expect(accountant.status.previews.completed == 0)
        #expect(accountant.status.analysis.completed == 0)
        #expect(accountant.status.readyForBothCount == 0)
    }

    @Test func duplicateRequestsAndWrongSessionOrParametersAreNotCounted() throws {
        let folder = FolderIdentity(rawValue: "folder-dedup")
        let otherFolder = FolderIdentity(rawValue: "folder-other")
        let scanned = try makeScannedSet(folder: folder, stem: "IMG_0007")
        let thumbReq = try #require(
            FolderPreparationAccountant.makeThumbnailRequest(for: scanned, folder: folder))
        let regionReq = try #require(
            FolderPreparationAccountant.makeRegionRequest(for: scanned, folder: folder))
        let revision = try #require(scanned.imageFiles.first?.modificationDate)
        let key = SharpnessResultKey(
            folderSession: folder.rawValue,
            photo: scanned.photoSet.primary.url,
            revision: ThumbnailRevision(size: 2048, modificationTime: revision),
            parametersVersion: 2)
        let analysis = RegionSharpnessAnalysis(
            autofocus: .unavailable(.noAutofocusMetadata(emptyAFEvidence)),
            faces: .unavailable(.noFacesDetected),
            acquisitionFailure: nil,
            timings: RegionSharpnessTimings())

        var accountant = FolderPreparationAccountant(
            folder: folder, folderName: "Dedup", generation: 1, parametersVersion: 2)
        accountant.registerDiscovered([scanned, scanned])
        #expect(accountant.status.totalPhotos == 1)

        // Wrong folder / wrong pixels / wrong parametersVersion must be ignored.
        let wrongFolderThumb = ThumbnailRequest(
            source: thumbReq.source, revision: thumbReq.revision,
            targetPixels: thumbReq.targetPixels, locationIdentity: otherFolder.rawValue)
        let wrongSizeThumb = ThumbnailRequest(
            source: thumbReq.source, revision: thumbReq.revision,
            targetPixels: 800, locationIdentity: folder.rawValue)
        let wrongVersionKey = SharpnessResultKey(
            folderSession: folder.rawValue, photo: scanned.photoSet.primary.url,
            revision: key.revision, parametersVersion: 99)
        let wrongFolderKey = SharpnessResultKey(
            folderSession: otherFolder.rawValue, photo: scanned.photoSet.primary.url,
            revision: key.revision, parametersVersion: 2)

        let ignoredWrongFolder = accountant.recordPreviewOutcome(.completed, for: wrongFolderThumb)
        let ignoredWrongSize = accountant.recordPreviewOutcome(.completed, for: wrongSizeThumb)
        let ignoredWrongVersion = accountant.recordAnalysisSettlement(
            key: wrongVersionKey, request: regionReq, analysis: analysis)
        let ignoredWrongSession = accountant.recordAnalysisSettlement(
            key: wrongFolderKey, request: regionReq, analysis: analysis)
        #expect(!ignoredWrongFolder && !ignoredWrongSize && !ignoredWrongVersion)
        #expect(!ignoredWrongSession)

        // First completion counts once; repeated coalesced completions return false.
        let firstPreview = accountant.recordPreviewOutcome(.completed, for: thumbReq)
        let dupPreview = accountant.recordPreviewOutcome(.completed, for: thumbReq)
        let firstAnalysis = accountant.recordAnalysisSettlement(
            key: key, request: regionReq, analysis: analysis)
        let dupAnalysis = accountant.recordAnalysisSettlement(
            key: key, request: regionReq, analysis: analysis)
        #expect(firstPreview && !dupPreview)
        #expect(firstAnalysis && !dupAnalysis)

        // Transient deferral after completion does not regress completed state.
        let regressed = accountant.recordAnalysisClassification(
            .retryableDeferral("cancelled"), for: scanned.id)
        #expect(!regressed)

        #expect(accountant.status.analysis.completed == 1)
        #expect(accountant.status.previews.completed == 1)
        #expect(accountant.status.readyForBothCount == 1)
    }

    @Test func dynamicTotalsAndRemovalsReflectHonestDenominators() throws {
        let folder = FolderIdentity(rawValue: "folder-dynamic")
        let set1 = try makeScannedSet(folder: folder, stem: "IMG_0001")
        let set2 = try makeScannedSet(folder: folder, stem: "IMG_0002")
        let set3 = try makeScannedSet(folder: folder, stem: "IMG_0003")
        let set4 = try makeScannedSet(folder: folder, stem: "IMG_0004")

        var accountant = FolderPreparationAccountant(
            folder: folder, folderName: "Dynamic", generation: 1, parametersVersion: 2)
        #expect(accountant.status.phase == .enumeratingUnknown)
        #expect(accountant.status.isVisibleInHeader)
        #expect(accountant.status.readyFraction == nil)

        accountant.registerDiscovered([set1, set2])
        let s1A = accountant.recordAnalysisClassification(.completed, for: set1.id)
        let s1P = accountant.recordPreviewClassification(.completed, for: set1.id)
        let s2A = accountant.recordAnalysisClassification(.completed, for: set2.id)
        let s2P = accountant.recordPreviewClassification(.completed, for: set2.id)
        #expect(s1A && s1P && s2A && s2P)

        // While enumerating, even 2/2 must remain .preparing rather than premature .complete.
        #expect(accountant.status.totalPhotos == 2)
        #expect(accountant.status.readyForBothCount == 2)
        #expect(accountant.status.phase == .preparing)

        // New batch increases denominator honestly: 2/2 -> 2/4.
        accountant.registerDiscovered([set3, set4])
        accountant.finishScan(isPartial: true)
        #expect(accountant.status.isPartialScan)
        #expect(accountant.status.totalPhotos == 4)
        #expect(accountant.status.readyForBothCount == 2)
        #expect(accountant.status.readyFraction == 0.5)

        // Removing a completed photo and a pending photo adjusts numerator and denominator cleanly.
        accountant.removePhotos([set1.id, set3.id])
        #expect(accountant.status.totalPhotos == 2)
        #expect(accountant.status.readyForBothCount == 1)
        #expect(accountant.status.analysis.completed == 1)
        #expect(accountant.status.previews.completed == 1)

        let s4A = accountant.recordAnalysisClassification(.completed, for: set4.id)
        let s4P = accountant.recordPreviewClassification(.completed, for: set4.id)
        #expect(s4A && s4P)
        #expect(accountant.status.phase == .complete)
    }

    @Test func classificationsAndBoundedRetriesHandleNoFacesFailuresAndSupersedingResults() throws {
        let noFacesAndNoAF = RegionSharpnessAnalysis(
            autofocus: .unavailable(.noAutofocusMetadata(emptyAFEvidence)),
            faces: .unavailable(.noFacesDetected),
            acquisitionFailure: nil,
            timings: RegionSharpnessTimings())
        #expect(FolderPreparationClassification.classifyAnalysis(noFacesAndNoAF) == .completed)

        let faceFailed = RegionSharpnessAnalysis(
            autofocus: .unavailable(.noAutofocusMetadata(emptyAFEvidence)),
            faces: .unavailable(.faceDetectionFailed("Vision request error")),
            acquisitionFailure: nil,
            timings: RegionSharpnessTimings())
        #expect(
            FolderPreparationClassification.classifyAnalysis(faceFailed)
                == .failed("Vision request error"))

        let acqNoPreview = RegionSharpnessAnalysis(
            autofocus: .unavailable(.noAutofocusMetadata(emptyAFEvidence)),
            faces: .unavailable(.noFacesDetected),
            acquisitionFailure: .noUsablePreview,
            timings: RegionSharpnessTimings())
        #expect(
            FolderPreparationClassification.classifyAnalysis(acqNoPreview)
                == .failed("No usable preview for focus analysis."))

        #expect(
            FolderPreparationClassification.classifyPreviewOutcome(.unavailable(.cannotOpen))
                == .failed("Couldn't open photo for preview."))
        #expect(
            FolderPreparationClassification.classifyPreviewError(ThumbnailPipelineError.queueFull)
                == .retryableDeferral("Preview queue is busy."))
        #expect(
            FolderPreparationClassification.classifyPreviewError(CancellationError())
                == .retryableDeferral("Preview request was cancelled before finishing."))

        let folder = FolderIdentity(rawValue: "folder-outcomes")
        let okPhoto = try makeScannedSet(folder: folder, stem: "OK_0001")
        let failedPhoto = try makeScannedSet(folder: folder, stem: "BAD_0002")
        let deferredPhoto = try makeScannedSet(folder: folder, stem: "DEF_0003")

        var accountant = FolderPreparationAccountant(
            folder: folder, folderName: "Outcomes", generation: 1, parametersVersion: 2,
            maxTransientRetries: 2)
        accountant.registerDiscovered([okPhoto, failedPhoto, deferredPhoto])
        accountant.finishScan(isPartial: false)

        // Photo 1 completes normally.
        let okA = accountant.recordAnalysisClassification(.completed, for: okPhoto.id)
        let okP = accountant.recordPreviewClassification(.completed, for: okPhoto.id)
        #expect(okA && okP)

        // Photo 2 fails preview and analysis explicitly.
        let badP = accountant.recordPreviewClassification(
            .failed("No usable embedded preview."), for: failedPhoto.id)
        let badA = accountant.recordAnalysisClassification(
            .failed("Couldn't open photo for focus analysis."), for: failedPhoto.id)
        #expect(badP && badA)

        // Photo 3 hits transient deferral twice (retries 1 and 2 stay pending), 3rd becomes .deferred.
        let retry1 = accountant.recordAnalysisClassification(
            .retryableDeferral("Analysis queue is busy."), for: deferredPhoto.id)
        let retry2 = accountant.recordAnalysisClassification(
            .retryableDeferral("Analysis queue is busy."), for: deferredPhoto.id)
        #expect(!retry1 && !retry2)
        #expect(accountant.status.analysis.deferred == 0)

        let retry3 = accountant.recordAnalysisClassification(
            .retryableDeferral("Analysis queue is busy."), for: deferredPhoto.id)
        let defPreview = accountant.recordPreviewClassification(.completed, for: deferredPhoto.id)
        #expect(retry3 && defPreview)
        #expect(accountant.status.analysis.deferred == 1)

        let statusWithIssues = accountant.status
        #expect(statusWithIssues.totalPhotos == 3)
        #expect(statusWithIssues.readyForBothCount == 1)
        #expect(statusWithIssues.bothSettledCount == 3)
        #expect(statusWithIssues.phase == .completeWithIssues)
        #expect(statusWithIssues.issues.count == 3)

        // A later real completion on deferredPhoto supersedes its deferral and removes that issue.
        let superseded = accountant.recordAnalysisClassification(.completed, for: deferredPhoto.id)
        #expect(superseded)
        #expect(accountant.status.readyForBothCount == 2)
        #expect(accountant.status.analysis.deferred == 0)
        #expect(accountant.status.issues.count == 2)
        #expect(accountant.status.phase == .completeWithIssues)
    }

    @Test func waitingReasonAndEmptyFolderTransitionsAreAccurate() throws {
        let folder = FolderIdentity(rawValue: "folder-waiting")
        let photo = try makeScannedSet(folder: folder, stem: "IMG_0001")
        var accountant = FolderPreparationAccountant(
            folder: folder, folderName: "Wait", generation: 1, parametersVersion: 2)
        accountant.registerDiscovered([photo])
        accountant.finishScan(isPartial: false)

        let setPressure = accountant.setWaitingReason(.memoryPressure)
        #expect(setPressure)
        #expect(accountant.status.phase == .waiting(.memoryPressure))

        let setDisconnected = accountant.setWaitingReason(
            .folderUnavailable(.externalVolumeDisconnected))
        #expect(setDisconnected)
        #expect(
            accountant.status.phase
                == .waiting(.folderUnavailable(.externalVolumeDisconnected)))

        let cleared = accountant.setWaitingReason(nil)
        #expect(cleared)
        #expect(accountant.status.phase == .preparing)

        // Empty finished folder returns to .idle (not visible in header).
        var emptyAccountant = FolderPreparationAccountant(
            folder: folder, folderName: "Empty", generation: 1, parametersVersion: 2)
        #expect(emptyAccountant.status.phase == .enumeratingUnknown)
        emptyAccountant.finishScan(isPartial: false)
        #expect(emptyAccountant.status.phase == .idle)
        #expect(!emptyAccountant.status.isVisibleInHeader)
    }

    @Test func testLibraryPreparationModesPublishExpectedStatuses() async throws {
        let preparing = TestLibrary.forLaunch(environment: [
            TestLibrary.launchVariable: "1",
            TestLibrary.preparationVariable: "preparing",
        ])
        let modelPreparing = BrowsingModel(library: preparing)
        #expect(modelPreparing.preparationStatus.phase == .preparing)
        #expect(modelPreparing.preparationStatus.totalPhotos == 36)
        #expect(modelPreparing.preparationStatus.readyForBothCount > 0)
        #expect(modelPreparing.preparationStatus.readyForBothCount < 36)

        let waiting = TestLibrary.forLaunch(environment: [
            TestLibrary.launchVariable: "1",
            TestLibrary.preparationVariable: "waiting_pressure",
        ])
        #expect(waiting.preparationStatus.phase == .waiting(.memoryPressure))

        let disconnected = TestLibrary.forLaunch(environment: [
            TestLibrary.launchVariable: "1",
            TestLibrary.preparationVariable: "waiting_disconnected",
        ])
        #expect(
            disconnected.preparationStatus.phase
                == .waiting(.folderUnavailable(.externalVolumeDisconnected)))

        let issues = TestLibrary.forLaunch(environment: [
            TestLibrary.launchVariable: "1",
            TestLibrary.preparationVariable: "issues",
        ])
        #expect(issues.preparationStatus.phase == .completeWithIssues)
        #expect(!issues.preparationStatus.issues.isEmpty)

        let enumerating = TestLibrary.forLaunch(environment: [
            TestLibrary.launchVariable: "1",
            TestLibrary.preparationVariable: "enumerating",
        ])
        #expect(enumerating.preparationStatus.phase == .enumeratingUnknown)
    }

    private var emptyAFEvidence: AutofocusMetadataEvidence {
        AutofocusMetadataEvidence(inspected: [], cameraMake: nil, exifOrientation: 1)
    }

    private func makeScannedSet(
        folder: FolderIdentity,
        stem: String,
        modificationTime: Date = Date(timeIntervalSince1970: 1_760_000_000)
    ) throws -> ScannedPhotoSet {
        let url = URL(fileURLWithPath: "/tmp/prep-tests/\(stem).ARW")
        let photoSet = try PhotoSet(folderID: folder, relativeFolderPath: "", rawURL: url)
        return ScannedPhotoSet(
            photoSet: photoSet,
            sidecar: .absent,
            imageFiles: [
                ScannedImageFile(
                    file: photoSet.primary, size: 2048, modificationDate: modificationTime)
            ])
    }
}
