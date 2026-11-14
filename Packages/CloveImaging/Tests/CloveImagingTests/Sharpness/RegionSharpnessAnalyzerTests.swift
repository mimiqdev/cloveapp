import CoreGraphics
import Foundation
import Synchronization
import Testing

@testable import CloveImaging

/// A recording reader for the analyzer tests: every read is counted and can be injected.
private final class RecordingReader: RegionSharpnessReading, @unchecked Sendable {
    private let lock = Mutex(Counts())
    private struct Counts {
        var propertiesCalls: [URL] = []
        var previewCalls = 0
        var highResolutionCalls = 0
    }
    var propertiesAnswer: ImageProperties?
    var previewImage: CGImage?
    var previewFailure: RegionImageFailure?
    var highResolutionImage: CGImage?
    var highResolutionFailure: RegionImageFailure?

    func properties(of url: URL) async -> ImageProperties? {
        lock.withLock { $0.propertiesCalls.append(url) }
        return propertiesAnswer
    }

    func preview(_ request: RegionSharpnessRequest) async -> Result<CGImage, RegionImageFailure> {
        lock.withLock { _ = $0.previewCalls += 1 }
        if let previewImage { return .success(previewImage) }
        return .failure(previewFailure ?? .noUsablePreview)
    }

    func highResolution(
        _ request: RegionSharpnessRequest
    ) async -> Result<CGImage, RegionImageFailure> {
        lock.withLock { _ = $0.highResolutionCalls += 1 }
        if let highResolutionImage { return .success(highResolutionImage) }
        return .failure(highResolutionFailure ?? .noUsablePreview)
    }

    var propertyReadCount: Int { lock.withLock { $0.propertiesCalls.count } }
    var previewReadCount: Int { lock.withLock { $0.previewCalls } }
    var highResolutionReadCount: Int { lock.withLock { $0.highResolutionCalls } }
}

private struct StubFaceDetector: FaceRegionDetecting {
    let outcome: FaceDetectionOutcome
    func detectFaces(on image: CGImage) async -> FaceDetectionOutcome { outcome }
}

private func afInfoProperties(_ values: [Any]) -> ImageProperties {
    ImageProperties(["{ExifAux}": ["AFInfo": values]])
}

@Suite(.imageWork) struct RegionSharpnessAnalyzerTests {
    let sharpImage = SharpnessScene.checkerboard(width: 256, height: 256, cell: 4)
    let previewImage = SharpnessScene.flat(width: 800, height: 600)

    private func request() throws -> RegionSharpnessRequest {
        RegionSharpnessRequest(
            raw: DetailSource(
                url: URL(fileURLWithPath: "/tmp/photo.arw"),
                revision: ThumbnailRevision(size: 1, modificationTime: Date())),
            locationIdentity: "test")
    }

    private func face(_ region: NormalizedRegion) -> DetectedFaceRegion {
        DetectedFaceRegion(
            face: region,
            leftEye: NormalizedRegion(
                x: region.x + region.width * 0.2, y: region.y + region.height * 0.2, width: 0.05,
                height: 0.05),
            rightEye: NormalizedRegion(
                x: region.x + region.width * 0.7, y: region.y + region.height * 0.2, width: 0.05,
                height: 0.05))
    }

    @Test func afResultIsDeliveredBeforeFaceDetectionCompletes() async throws {
        // A detector that parks until the test releases it. The early-AF callback must fire
        // straight after metadataRead while detection is still running.
        final class GatedDetector: FaceRegionDetecting, @unchecked Sendable {
            let gate = Mutex<[CheckedContinuation<FaceDetectionOutcome, Never>]>([])
            func detectFaces(on image: CGImage) async -> FaceDetectionOutcome {
                await withCheckedContinuation { continuation in
                    gate.withLock { $0.append(continuation) }
                }
                return .faces([])
            }
        }
        let detector = GatedDetector()
        let reader = RecordingReader()
        reader.propertiesAnswer = afInfoProperties([0.2, 0.2, 0.1, 0.1, "f"])
        reader.previewImage = previewImage
        reader.highResolutionImage = sharpImage
        let analyzer = RegionSharpnessAnalyzer(reader: reader, faces: detector)

        let delivered = Mutex<RegionSharpnessPathResult?>(nil)
        let analysisTask = Task {
            await analyzer.analyze(try request()) { early in
                delivered.withLock { $0 = early }
            }
        }

        // The AF result arrives while the detector is still parked: no release has happened.
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var early: RegionSharpnessPathResult?
        while ContinuousClock.now < deadline {
            early = delivered.withLock { $0 }
            if early != nil { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let waiting = detector.gate.withLock { !$0.isEmpty }
        try #require(early != nil, "AF result must arrive before detection completes")
        #expect(waiting, "the detector must still be parked when the AF result arrives")
        guard case .regions(let afRegions) = early else {
            Issue.record("Expected the located AF region, got \(String(describing: early))")
            analysisTask.cancel()
            return
        }
        #expect(afRegions.count == 1)
        #expect(afRegions[0].kind == .cameraAutofocus)
        #expect(afRegions[0].score == nil)
        #expect(afRegions[0].unavailableBecause == nil)

        // Releasing the detector lets the analysis finish; its combined result carries the
        // same AF answer plus the (empty) face path.
        let waiters = detector.gate.withLock { $0 }
        detector.gate.withLock { $0.removeAll() }
        for waiter in waiters { waiter.resume(returning: .faces([])) }
        let analysis = try await analysisTask.value
        guard
            case .regions(let combinedAutofocus) = analysis.autofocus,
            case .regions(let earlyRegions) = early
        else {
            Issue.record("The combined result must carry the same located AF regions")
            return
        }
        #expect(combinedAutofocus.map(\.region) == earlyRegions.map(\.region))
        #expect(
            combinedAutofocus.map(\.unavailableBecause) == earlyRegions.map(\.unavailableBecause))
        guard case .unavailable(.noFacesDetected) = analysis.faces else {
            Issue.record("Expected the released detection's answer on the face path")
            return
        }
        #expect(reader.highResolutionReadCount == 0)
    }

    @Test func unavailableAFIsDeliveredEarlyToo() async throws {
        // Metadata unavailable needs no pixels, so the early callback fires straight after
        // the metadata read — even with a parked detector and no acquisition.
        final class ParkedDetector: FaceRegionDetecting, @unchecked Sendable {
            let parked = Mutex<[CheckedContinuation<FaceDetectionOutcome, Never>]>([])
            func detectFaces(on image: CGImage) async -> FaceDetectionOutcome {
                // Parked until the test's task is cancelled; the continuation is leaked by
                // design for the lifetime of this short-lived test.
                return await withCheckedContinuation { continuation in
                    parked.withLock { $0.append(continuation) }
                }
            }
        }
        let reader = RecordingReader()
        reader.propertiesAnswer = ImageProperties(["{TIFF}": ["Make": "SONY"]])
        reader.previewImage = previewImage
        let analyzer = RegionSharpnessAnalyzer(reader: reader, faces: ParkedDetector())

        let delivered = Mutex<RegionSharpnessPathResult?>(nil)
        let analysisTask = Task {
            await analyzer.analyze(try request()) { early in
                delivered.withLock { $0 = early }
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var early: RegionSharpnessPathResult?
        while ContinuousClock.now < deadline {
            early = delivered.withLock { $0 }
            if early != nil { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        analysisTask.cancel()
        try #require(early != nil, "AF unavailability must arrive before detection completes")
        guard case .unavailable(.noAutofocusMetadata(let evidence)) = early else {
            Issue.record("Expected early AF unavailability with evidence")
            return
        }
        #expect(evidence.cameraMake == "SONY")
    }

    @Test func missingAutofocusMetadataReportsEvidenceNotAnEmptyRegion() async throws {
        let reader = RecordingReader()
        reader.propertiesAnswer = ImageProperties([
            "{TIFF}": ["Make": "SONY"], "{Exif}": ["PixelXDimension": 2768],
        ])
        reader.previewImage = previewImage
        reader.highResolutionImage = sharpImage
        let analyzer = RegionSharpnessAnalyzer(
            reader: reader, faces: StubFaceDetector(outcome: .faces([])))

        let analysis = await analyzer.analyze(try request())

        guard case .unavailable(.noAutofocusMetadata(let evidence)) = analysis.autofocus else {
            Issue.record("Expected AF unavailable with evidence")
            return
        }
        #expect(evidence.cameraMake == "SONY")
        #expect(!evidence.inspected.isEmpty)
        // The face path is unaffected by the AF path's answer.
        guard case .unavailable(.noFacesDetected) = analysis.faces else {
            Issue.record("Expected no-faces for the face path")
            return
        }
        // Presentation analysis never decodes a native RAW.
        #expect(reader.previewReadCount == 1)
        #expect(reader.highResolutionReadCount == 0)
        #expect(analysis.acquisitionFailure == nil)
        #expect(analysis.timings.pixelAcquisition == nil)
        #expect(analysis.timings.regionScoring == nil)
    }

    /// A Sony file the focusmeta fallback can read (#238): the region is located off the main
    /// actor without scoring or acquiring high-res pixels, and the synthetic container never
    /// touches the app's fixtures.
    @Test func sonyRegionThroughTheMetadataFallbackIsLocatedWithoutScoring() async throws {
        let reader = RecordingReader()
        reader.propertiesAnswer = ImageProperties([
            "{TIFF}": ["Make": "SONY"], "{Exif}": ["PixelXDimension": 80, "PixelYDimension": 60],
        ])
        reader.previewImage = previewImage
        reader.highResolutionImage = sharpImage
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clove-sony-\(UUID().uuidString).arw")
        try SyntheticSonyContainer.arw(orientation: 1).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let sonyRequest = RegionSharpnessRequest(
            raw: DetailSource(
                url: url, revision: ThumbnailRevision(size: 1, modificationTime: Date())),
            locationIdentity: "sony-test")
        let analyzer = RegionSharpnessAnalyzer(
            reader: reader, faces: StubFaceDetector(outcome: .faces([])))

        let analysis = await analyzer.analyze(sonyRequest)

        guard case .regions(let afRegions) = analysis.autofocus else {
            Issue.record("The Sony record must locate through the fallback")
            return
        }
        #expect(afRegions.count == 1)
        #expect(afRegions[0].kind == .cameraAutofocus)
        // The synthetic record's region, in display space at orientation 1.
        #expect(abs(afRegions[0].region.centerX - 17.0 / 80.0) < 1e-9)
        #expect(abs(afRegions[0].region.centerY - 31.0 / 60.0) < 1e-9)
        #expect(afRegions[0].score == nil)
        #expect(afRegions[0].unavailableBecause == nil)
        #expect(reader.highResolutionReadCount == 0)
    }

    @Test func failedPreviewFailsOnlyTheFacePath() async throws {
        let reader = RecordingReader()
        reader.propertiesAnswer = afInfoProperties([0.2, 0.2, 0.1, 0.1, "f"])
        reader.previewFailure = .cannotOpen
        reader.highResolutionImage = sharpImage
        let analyzer = RegionSharpnessAnalyzer(
            reader: reader, faces: StubFaceDetector(outcome: .faces([])))

        let analysis = await analyzer.analyze(try request())

        guard case .unavailable(.previewFailed(let failure)) = analysis.faces else {
            Issue.record("Expected preview failure on the face path")
            return
        }
        #expect(failure == .cannotOpen)
        // The AF path still produced its located region.
        guard case .regions(let afRegions) = analysis.autofocus else {
            Issue.record("Expected AF regions despite preview failure")
            return
        }
        #expect(afRegions.first?.score == nil)
        #expect(afRegions.first?.unavailableBecause == nil)
    }

    @Test func tinyDetectedFacesReportTooSmallRatherThanAScore() async throws {
        let reader = RecordingReader()
        reader.previewImage = previewImage
        reader.highResolutionImage = sharpImage
        let tinyFace = DetectedFaceRegion(
            face: NormalizedRegion(x: 0.5, y: 0.5, width: 0.002, height: 0.002),
            leftEye: nil, rightEye: nil)
        let outsideFace = DetectedFaceRegion(
            face: NormalizedRegion(x: 1.5, y: 0.5, width: 0.2, height: 0.2),
            leftEye: nil, rightEye: nil)
        let analyzer = RegionSharpnessAnalyzer(
            reader: reader, faces: StubFaceDetector(outcome: .faces([tinyFace, outsideFace])))

        let analysis = await analyzer.analyze(try request())

        guard case .regions(let faceRegions) = analysis.faces else {
            Issue.record("A detected face is a located region, not an empty path")
            return
        }
        #expect(faceRegions.count == 2)
        #expect(faceRegions[0].score == nil)
        #expect(faceRegions[0].unavailableBecause == .regionTooSmall)
        #expect(faceRegions[1].score == nil)
        #expect(faceRegions[1].unavailableBecause == .regionOutsideImage)
    }

    @Test func detectionFailureCarriesVisionMessage() async throws {
        let reader = RecordingReader()
        reader.propertiesAnswer = nil
        reader.previewImage = previewImage
        reader.highResolutionImage = sharpImage
        let analyzer = RegionSharpnessAnalyzer(
            reader: reader, faces: StubFaceDetector(outcome: .failed("Vision unavailable")))

        let analysis = await analyzer.analyze(try request())

        guard case .unavailable(.faceDetectionFailed(let message)) = analysis.faces else {
            Issue.record("Expected the detection failure to be reported")
            return
        }
        #expect(message == "Vision unavailable")
        // Unreadable properties still leave explicit AF evidence.
        guard case .unavailable(.noAutofocusMetadata) = analysis.autofocus else {
            Issue.record("Expected AF unavailable when properties cannot be read")
            return
        }
    }

    @Test func timingsRecordEveryStageRan() async throws {
        let reader = RecordingReader()
        reader.propertiesAnswer = afInfoProperties([0.2, 0.2, 0.1, 0.1, "f"])
        reader.previewImage = previewImage
        reader.highResolutionImage = sharpImage
        let analyzer = RegionSharpnessAnalyzer(
            reader: reader,
            faces: StubFaceDetector(
                outcome: .faces([face(NormalizedRegion(x: 0.3, y: 0.3, width: 0.3, height: 0.3))])))

        let analysis = await analyzer.analyze(try request())

        guard case .regions(let afRegions) = analysis.autofocus,
            case .regions(let faceRegions) = analysis.faces
        else {
            Issue.record("Expected located AF and face regions")
            return
        }
        #expect(afRegions.count == 1)
        #expect(afRegions[0].score == nil)
        #expect(afRegions[0].unavailableBecause == nil)
        #expect(faceRegions.count == 3)
        #expect(faceRegions.allSatisfy { $0.score == nil && $0.unavailableBecause == nil })
        #expect(reader.highResolutionReadCount == 0)

        // Measurements are exposed as facts; only metadataRead, previewRead, and faceDetection run.
        #expect(analysis.timings.metadataRead != nil)
        #expect(analysis.timings.previewRead != nil)
        #expect(analysis.timings.faceDetection != nil)
        #expect(analysis.timings.pixelAcquisition == nil)
        #expect(analysis.timings.regionScoring == nil)
    }
}
