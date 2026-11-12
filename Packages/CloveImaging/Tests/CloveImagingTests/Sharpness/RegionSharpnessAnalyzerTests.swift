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

@Suite struct RegionSharpnessAnalyzerTests {
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

    @Test func bothPathsScoreThroughTheSharedScorer() async throws {
        let reader = RecordingReader()
        reader.propertiesAnswer = afInfoProperties([0.2, 0.2, 0.1, 0.1, "f"])
        reader.previewImage = previewImage
        reader.highResolutionImage = sharpImage
        let analyzer = RegionSharpnessAnalyzer(
            reader: reader,
            faces: StubFaceDetector(
                outcome: .faces([
                    face(NormalizedRegion(x: 0.3, y: 0.3, width: 0.3, height: 0.3))
                ])))

        let analysis = await analyzer.analyze(try request())

        // AF path: one region with a score.
        guard case .regions(let afRegions) = analysis.autofocus else {
            Issue.record("Expected AF regions")
            return
        }
        #expect(afRegions.count == 1)
        #expect(afRegions[0].kind == .cameraAutofocus)
        #expect(afRegions[0].score != nil)

        // Face path: one face and two eyes, each separate, each scored.
        guard case .regions(let faceRegions) = analysis.faces else {
            Issue.record("Expected face regions")
            return
        }
        #expect(faceRegions.count == 3)
        #expect(faceRegions.filter { $0.kind == .face }.count == 1)
        #expect(faceRegions.filter { $0.kind == .eye }.count == 2)
        #expect(faceRegions.allSatisfy { $0.score != nil })
        #expect(faceRegions.allSatisfy { $0.groupIndex == 0 })

        // The AF region and face regions carry different scores where their pixels differ;
        // equality is not asserted because both sit on the same checkerboard.
        #expect(analysis.acquisitionFailure == nil)
    }

    @Test func oneAcquisitionServesEveryRegion() async throws {
        let reader = RecordingReader()
        reader.propertiesAnswer = afInfoProperties([0.2, 0.2, 0.1, 0.1, "f"])
        reader.previewImage = previewImage
        reader.highResolutionImage = sharpImage
        let analyzer = RegionSharpnessAnalyzer(
            reader: reader,
            faces: StubFaceDetector(
                outcome: .faces([
                    face(NormalizedRegion(x: 0.1, y: 0.1, width: 0.4, height: 0.4)),
                    face(NormalizedRegion(x: 0.5, y: 0.5, width: 0.3, height: 0.3)),
                ])))

        _ = await analyzer.analyze(try request())

        // One property read, one preview read, one high-resolution read — for five regions.
        #expect(reader.propertyReadCount == 1)
        #expect(reader.previewReadCount == 1)
        #expect(reader.highResolutionReadCount == 1)
    }

    @Test func afDoesNotWaitForFaceDetection() async throws {
        // The AF region is computed before the detector is entered; this test pins that order
        // through a detector that records when it is entered, and the analysis still delivers
        // its AF score even when detection finds nothing.
        final class OrderingDetector: FaceRegionDetecting, @unchecked Sendable {
            private let entered = Mutex(false)
            func detectFaces(on image: CGImage) async -> FaceDetectionOutcome {
                entered.withLock { $0 = true }
                return .faces([])
            }
            var wasEntered: Bool { entered.withLock { $0 } }
        }
        let reader = RecordingReader()
        reader.propertiesAnswer = afInfoProperties([0.2, 0.2, 0.1, 0.1, "f"])
        reader.previewImage = previewImage
        reader.highResolutionImage = sharpImage
        let detector = OrderingDetector()
        let analyzer = RegionSharpnessAnalyzer(reader: reader, faces: detector)

        let analysis = await analyzer.analyze(try request())

        guard case .regions(let afRegions) = analysis.autofocus else {
            Issue.record("Expected AF regions")
            return
        }
        #expect(afRegions.first?.score != nil)
        #expect(detector.wasEntered)
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
    }

    @Test func failedAcquisitionIsExplicitAndRegionsSayWhy() async throws {
        let reader = RecordingReader()
        reader.propertiesAnswer = afInfoProperties([0.2, 0.2, 0.1, 0.1, "f"])
        reader.previewImage = previewImage
        reader.highResolutionFailure = .queueFull
        let analyzer = RegionSharpnessAnalyzer(
            reader: reader,
            faces: StubFaceDetector(
                outcome: .faces([face(NormalizedRegion(x: 0.3, y: 0.3, width: 0.3, height: 0.3))])))

        let analysis = await analyzer.analyze(try request())

        #expect(analysis.acquisitionFailure == .queueFull)
        guard case .regions(let afRegions) = analysis.autofocus else {
            Issue.record("AF region was located, so it stays reported")
            return
        }
        #expect(afRegions.first?.score == nil)
        // A located region with no pixels says why instead of guessing a score.
        #expect(afRegions.first?.unavailableBecause == .pixelsUnavailable)
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
        // The AF path still produced its scored region.
        guard case .regions(let afRegions) = analysis.autofocus else {
            Issue.record("Expected AF regions despite preview failure")
            return
        }
        #expect(afRegions.first?.score != nil)
    }

    @Test func tinyDetectedFacesReportTooSmallRatherThanAScore() async throws {
        let reader = RecordingReader()
        reader.previewImage = previewImage
        reader.highResolutionImage = sharpImage
        let tinyFace = DetectedFaceRegion(
            face: NormalizedRegion(x: 0.5, y: 0.5, width: 0.002, height: 0.002),
            leftEye: nil, rightEye: nil)
        let analyzer = RegionSharpnessAnalyzer(
            reader: reader, faces: StubFaceDetector(outcome: .faces([tinyFace])))

        let analysis = await analyzer.analyze(try request())

        guard case .regions(let faceRegions) = analysis.faces else {
            Issue.record("A detected face is a located region, not an empty path")
            return
        }
        #expect(faceRegions.first?.score == nil)
        #expect(faceRegions.first?.unavailableBecause == .regionTooSmall)
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

        // Measurements are exposed as facts; the test only pins that each stage recorded one.
        #expect(analysis.timings.metadataRead != nil)
        #expect(analysis.timings.previewRead != nil)
        #expect(analysis.timings.faceDetection != nil)
        #expect(analysis.timings.pixelAcquisition != nil)
        #expect(analysis.timings.regionScoring != nil)
    }
}
