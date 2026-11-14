import CoreGraphics
import Foundation
import os

/// One photo's sharpness-analysis request: the photo set's files, named the way a detail
/// request names them (#208). `CloveImaging` does not depend on `CloveCore`, so this mirrors
/// ``DetailRequest``'s raw/jpeg/heif roles instead of a C1 photo set.
public struct RegionSharpnessRequest: Hashable, Sendable {
    public let raw: DetailSource?
    public let jpeg: DetailSource?
    public let heif: DetailSource?
    public let locationIdentity: String

    public init(
        raw: DetailSource? = nil, jpeg: DetailSource? = nil, heif: DetailSource? = nil,
        locationIdentity: String
    ) {
        precondition(raw != nil || jpeg != nil || heif != nil, "An analysis request needs a file")
        self.raw = raw
        self.jpeg = jpeg
        self.heif = heif
        self.locationIdentity = locationIdentity
    }

    /// The primary file whose metadata an analysis reads: the RAW of a RAW set, else the
    /// JPEG, else the HIF, matching the detail pipeline's precedence (G1 decision 1).
    public var primaryURL: URL {
        if let raw { return raw.url }
        if let jpeg { return jpeg.url }
        if let heif { return heif.url }
        preconditionFailure("An analysis request needs a file")
    }

    /// Every file of the set, standardized, so both sides of an invalidation comparison use
    /// the same spelling however the caller wrote the path (#216).
    public var fileURLs: [URL] {
        [raw?.url, jpeg?.url, heif?.url].compactMap { $0 }.map { $0.standardizedFileURL }
    }
}

/// The ImageIO property dictionary of one file, wrapped so it can cross an await.
///
/// ImageIO's dictionaries are freshly created read-only snapshots; this wrapper only moves
/// the reference from the read to its synchronous consumer inside one analysis.
public struct ImageProperties: @unchecked Sendable {
    public let values: [String: Any]

    public init(_ values: [String: Any]) {
        self.values = values
    }

    public subscript(path: String) -> Any? { values[path] }
}

/// Reads the metadata and pixels one sharpness analysis needs.
///
/// The seams exist so tests can count acquisitions and inject detections without real files;
/// production uses ``DetailRegionSharpnessReading``, which delegates every pixel read to the
/// app's existing ``DetailPipeline`` so the analysis adds no decode route of its own (#208).
public protocol RegionSharpnessReading: Sendable {
    /// The primary file's full ImageIO property dictionary, or nil when it cannot be read.
    func properties(of url: URL) async -> ImageProperties?
    /// One preview for face detection, orientation applied, or the reason there is none.
    func preview(_ request: RegionSharpnessRequest) async -> Result<CGImage, RegionImageFailure>
    /// The one high-resolution acquisition every region shares, orientation applied.
    func highResolution(_ request: RegionSharpnessRequest) async -> Result<
        CGImage, RegionImageFailure
    >
}

/// The analysis engine: camera-AF regions from metadata and Vision face/eye regions from
/// the bounded preview (#208, #278).
///
/// The AF path needs no decoded pixels and is delivered to ``analyze(_:onAutofocus:)``'s
/// callback immediately after the metadata read for both located regions and unavailability —
/// before face detection runs. The callback fires exactly once per analysis; the returned
/// ``RegionSharpnessAnalysis`` carries the same AF result again for callers that read only the
/// combined value.
///
/// This type holds no state between calls; prioritization and caching live in the scheduler
/// (#216).
public struct RegionSharpnessAnalyzer: Sendable {
    private static let signposter = OSSignposter(
        subsystem: "com.mimiqdev.clove", category: "Sharpness")

    /// The preview long edge face detection runs on. Large enough for Vision on a 24 MP
    /// photo's subject, small enough that detection stays cheap on the shared executor.
    public static let previewPixels = 800

    private let reader: any RegionSharpnessReading
    private let faceDetector: any FaceRegionDetecting
    private let metadataReader: AutofocusMetadataReader
    private let stages: any RegionSharpnessStageGate

    public init(reader: any RegionSharpnessReading) {
        self.init(reader: reader, faces: VisionFaceRegionDetector())
    }

    init(
        reader: any RegionSharpnessReading, faces: any FaceRegionDetecting,
        metadataReader: AutofocusMetadataReader = AutofocusMetadataReader(),
        stages: any RegionSharpnessStageGate = UngatedSharpnessStage()
    ) {
        self.reader = reader
        self.faceDetector = faces
        self.metadataReader = metadataReader
        self.stages = stages
    }

    /// The same engine admitting its stages through another gate (#216).
    func gated(by stages: any RegionSharpnessStageGate) -> RegionSharpnessAnalyzer {
        RegionSharpnessAnalyzer(
            reader: reader, faces: faceDetector,
            metadataReader: metadataReader, stages: stages)
    }

    /// Runs one photo's analysis and returns both paths' results.
    ///
    /// `onAutofocus`, when supplied, receives the AF path's finished result straight after the
    /// metadata read without waiting for face detection to finish.
    public func analyze(
        _ request: RegionSharpnessRequest,
        onAutofocus: ((RegionSharpnessPathResult) -> Void)? = nil
    ) async -> RegionSharpnessAnalysis {
        guard
            let analysis = try? await analyzeGated(request, onAutofocus: onAutofocus)
        else { preconditionFailure("The ungated analysis path admits every stage") }
        return analysis
    }

    /// ``analyze(_:onAutofocus:)`` with a stage gate: each bounded stage's admission can stop
    /// an analysis that became obsolete before its work started (#216). A refused analysis
    /// throws `CancellationError` instead of returning a result a caller could publish.
    public func analyzeGated(
        _ request: RegionSharpnessRequest,
        onAutofocus: ((RegionSharpnessPathResult) -> Void)? = nil
    ) async throws -> RegionSharpnessAnalysis {
        let analysisInterval = Self.signposter.beginInterval(
            "SharpnessAnalysis", id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval("SharpnessAnalysis", analysisInterval) }

        // Stage 1 — AF metadata, admitted through its own bound so a folder-wide background
        // submit does not fan out one ImageIO read per photo at once (#216). Both located
        // regions and missing-metadata answers are final here, before face detection starts.
        try await stages.enter(.metadataRead)
        let metadataInterval = Self.signposter.beginInterval(
            "SharpnessMetadataRead", id: Self.signposter.makeSignpostID())
        let metadata = await measure { await self.reader.properties(of: request.primaryURL) }
        let autofocus = await Self.locateAutofocus(
            properties: metadata.value, url: request.primaryURL, reader: metadataReader)
        Self.signposter.endInterval("SharpnessMetadataRead", metadataInterval)
        await stages.exit(.metadataRead)

        let autofocusResult = Self.autofocusPath(located: autofocus)
        onAutofocus?(autofocusResult)

        // Stage 2 — preview read and Vision face/eye localization. Presentation analysis skips
        // pixel acquisition and scoring, validating regions directly in normalized coordinates.
        let detectionStage = try await Self.runDetection(
            reader: reader, detector: faceDetector, request: request, stages: stages)
        let faces = Self.detectedFaces(of: detectionStage.outcome)
        let faceEvidence = Self.validatedFaces(faces)

        return RegionSharpnessAnalysis(
            autofocus: autofocusResult,
            faces: Self.facePath(
                detection: detectionStage.outcome, faces: faces,
                preview: detectionStage.preview, evidence: faceEvidence),
            acquisitionFailure: nil,
            timings: RegionSharpnessTimings(
                metadataRead: metadata.duration,
                previewRead: detectionStage.previewDuration,
                faceDetection: detectionStage.detectionDuration,
                pixelAcquisition: nil,
                regionScoring: nil))
    }

    // MARK: - Stages

    /// One detection stage's recorded facts: the preview it read, the detection outcome, and
    /// each read's duration.
    private struct DetectionStage {
        let preview: Result<CGImage, RegionImageFailure>?
        let previewDuration: ContinuousClock.Duration?
        let outcome: FaceDetectionOutcome?
        let detectionDuration: ContinuousClock.Duration?
    }

    /// Reads the preview and runs Vision over it, admitted as one stage (#216): the slot
    /// bounds the preview decode and the localization request together, which is what a
    /// detection budget has to bound. A refused admission cancels the whole analysis; a
    /// failed preview read means no request, so no detection duration is recorded (#208).
    private static func runDetection(
        reader: any RegionSharpnessReading, detector: any FaceRegionDetecting,
        request: RegionSharpnessRequest, stages: any RegionSharpnessStageGate
    ) async throws -> DetectionStage {
        try await stages.enter(.faceDetection)
        let detectionInterval = Self.signposter.beginInterval(
            "SharpnessFaceDetection", id: Self.signposter.makeSignpostID())
        let preview = await measure { await reader.preview(request) }
        guard case .success(let image) = preview.value else {
            Self.signposter.endInterval("SharpnessFaceDetection", detectionInterval)
            await stages.exit(.faceDetection)
            return DetectionStage(
                preview: preview.value, previewDuration: preview.duration, outcome: nil,
                detectionDuration: nil)
        }
        let start = ContinuousClock.now
        let outcome = await detector.detectFaces(on: image)
        Self.signposter.endInterval("SharpnessFaceDetection", detectionInterval)
        await stages.exit(.faceDetection)
        return DetectionStage(
            preview: preview.value, previewDuration: preview.duration, outcome: outcome,
            detectionDuration: start.duration(to: .now))
    }

    // MARK: - Region location

    /// The AF region located from one file's properties, or the evidence that none could be.
    /// The focusmeta file read happens only when the property paths all report missing, and
    /// runs inside the metadata stage so the ImageIO read and the focusmeta read share one
    /// admission slot and no synchronous file I/O ever lands on the main actor.
    private static func locateAutofocus(
        properties: ImageProperties?, url: URL, reader: AutofocusMetadataReader
    ) async -> Result<AutofocusRegion, AutofocusMetadataEvidence> {
        guard let properties else {
            return .failure(
                AutofocusMetadataEvidence(
                    inspected: [
                        .init(path: "<properties>", finding: .missing)
                    ],
                    cameraMake: nil, exifOrientation: 1))
        }
        return await withTaskExecutorPreference(ImageWorkExecutor.current) {
            reader.regions(of: url, properties: properties.values)
        }
    }

    /// A detection's faces; a failed or skipped detection has none.
    private static func detectedFaces(of detection: FaceDetectionOutcome?) -> [DetectedFaceRegion] {
        guard case .faces(let faces)? = detection else { return [] }
        return faces
    }

    /// The face path's located regions, validated in normalized coordinates. Faces and eyes
    /// stay separate, and each carries its face's index (#114).
    private static func validatedFaces(_ faces: [DetectedFaceRegion]) -> [RegionSharpnessEvidence] {
        var regions: [RegionSharpnessEvidence] = []
        for (index, face) in faces.enumerated() {
            regions.append(validatedEvidence(kind: .face, groupIndex: index, region: face.face))
            for eye in [face.leftEye, face.rightEye].compactMap({ $0 }) {
                regions.append(validatedEvidence(kind: .eye, groupIndex: index, region: eye))
            }
        }
        return regions
    }

    private static func validatedEvidence(
        kind: SharpnessRegionKind, groupIndex: Int?, region: NormalizedRegion
    ) -> RegionSharpnessEvidence {
        RegionSharpnessEvidence(
            kind: kind,
            groupIndex: groupIndex,
            region: region,
            score: nil,
            unavailableBecause: region.normalizedUnavailability)
    }

    // MARK: - Path results

    private static func autofocusPath(
        located: Result<AutofocusRegion, AutofocusMetadataEvidence>
    ) -> RegionSharpnessPathResult {
        switch located {
        case .failure(let missing):
            return .unavailable(.noAutofocusMetadata(missing))
        case .success(let region):
            return .regions([
                validatedEvidence(
                    kind: .cameraAutofocus, groupIndex: nil, region: region.region)
            ])
        }
    }

    private static func facePath(
        detection: FaceDetectionOutcome?, faces: [DetectedFaceRegion],
        preview: Result<CGImage, RegionImageFailure>?, evidence: [RegionSharpnessEvidence]
    ) -> RegionSharpnessPathResult {
        switch detection {
        case .faces(let detected):
            return detected.isEmpty ? .unavailable(.noFacesDetected) : .regions(evidence)
        case .failed(let message):
            return .unavailable(.faceDetectionFailed(message))
        case nil:
            switch preview {
            case .success:
                return .unavailable(.faceDetectionFailed("detection did not run"))
            case .failure(let failure):
                return .unavailable(.previewFailed(failure))
            case nil:
                return .unavailable(.faceDetectionFailed("detection did not run"))
            }
        }
    }
}

/// Wall-clock around one stage, recorded without interpreting it (#208).
private func measure<T: Sendable>(_ body: () async -> T) async -> (
    value: T, duration: ContinuousClock.Duration?
) {
    let start = ContinuousClock.now
    let value = await body()
    return (value, start.duration(to: .now))
}
