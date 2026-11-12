import CoreGraphics
import Foundation

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

/// The analysis engine: camera-AF regions and Vision face/eye regions, each scored by the
/// shared ``RegionSharpnessScorer`` over one shared high-resolution acquisition (#208).
///
/// The two paths are independent by construction: the AF regions are located from metadata
/// before face detection is awaited, and either path can produce regions while the other
/// reports unavailable. One detection request runs per analysis, and the single acquisition
/// supplies every region, so there is no per-region decode at this boundary.
///
/// This type holds no state between calls and adds no scheduler of its own; later slices own
/// prioritization and caching (#114).
public struct RegionSharpnessAnalyzer: Sendable {
    /// The preview long edge face detection runs on. Large enough for Vision on a 24 MP
    /// photo's subject, small enough that detection stays cheap on the shared executor.
    public static let previewPixels = 800

    private let reader: any RegionSharpnessReading
    private let faceDetector: any FaceRegionDetecting
    private let scorer: RegionSharpnessScorer
    private let metadataReader: AutofocusMetadataReader

    public init(reader: any RegionSharpnessReading) {
        self.init(reader: reader, faces: VisionFaceRegionDetector())
    }

    init(
        reader: any RegionSharpnessReading, faces: any FaceRegionDetecting,
        scorer: RegionSharpnessScorer = RegionSharpnessScorer(),
        metadataReader: AutofocusMetadataReader = AutofocusMetadataReader()
    ) {
        self.reader = reader
        self.faceDetector = faces
        self.scorer = scorer
        self.metadataReader = metadataReader
    }

    public func analyze(_ request: RegionSharpnessRequest) async -> RegionSharpnessAnalysis {
        // Stage 1 — AF metadata. The AF regions are located before the face path is awaited,
        // so an AF answer never waits on detection (#208).
        let metadata = await measure { await self.reader.properties(of: request.primaryURL) }
        let autofocus = Self.locateAutofocus(properties: metadata.value, reader: metadataReader)

        // Stage 2 — face detection on a preview, independent of the AF answer.
        let preview = await measure { await self.reader.preview(request) }
        let detection = await measure { () -> FaceDetectionOutcome? in
            guard case .success(let preview) = preview.value else { return nil }
            return await self.faceDetector.detectFaces(on: preview)
        }
        let faces = Self.detectedFaces(of: detection.value)

        // Stage 3 — the one acquisition shared by every region the two paths located.
        let acquisition = await measure { await self.reader.highResolution(request) }
        let pixels: CGImage?
        let acquisitionFailure: RegionImageFailure?
        switch acquisition.value {
        case .success(let image):
            pixels = image
            acquisitionFailure = nil
        case .failure(let failure):
            pixels = nil
            acquisitionFailure = failure
        }

        // Stage 4 — score every located region against that one acquisition. A failed
        // acquisition leaves every region located but unscored, with the shared failure on
        // the analysis itself (#208).
        var regions = Self.unscored(autofocus: autofocus, faces: faces)
        let scoring = await measure {
            guard let pixels else {
                for index in regions.indices where regions[index].unavailableBecause == nil {
                    regions[index] = Self.unavailable(
                        regions[index], because: .pixelsUnavailable)
                }
                return
            }
            for index in regions.indices {
                regions[index] = Self.scored(regions[index], in: pixels, scorer: self.scorer)
            }
        }

        return RegionSharpnessAnalysis(
            autofocus: Self.autofocusPath(
                located: autofocus, evidence: regions.filter { $0.kind == .cameraAutofocus },
                pixelsFailed: acquisitionFailure != nil),
            faces: Self.facePath(
                detection: detection.value, faces: faces, preview: preview.value,
                evidence: regions.filter { $0.kind != .cameraAutofocus }),
            acquisitionFailure: acquisitionFailure,
            timings: RegionSharpnessTimings(
                metadataRead: metadata.duration, previewRead: preview.duration,
                faceDetection: detection.duration, pixelAcquisition: acquisition.duration,
                regionScoring: scoring.duration))
    }

    // MARK: - Region location

    /// The AF region located from one file's properties, or the evidence that none could be.
    private static func locateAutofocus(
        properties: ImageProperties?, reader: AutofocusMetadataReader
    ) -> Result<AutofocusRegion, AutofocusMetadataEvidence> {
        guard let properties else {
            return .failure(
                AutofocusMetadataEvidence(
                    inspected: [
                        .init(path: "<properties>", finding: .missing)
                    ],
                    cameraMake: nil, exifOrientation: 1))
        }
        return reader.regions(of: URL(fileURLWithPath: "/"), properties: properties.values)
    }

    /// A detection's faces; a failed or skipped detection has none.
    private static func detectedFaces(of detection: FaceDetectionOutcome?) -> [DetectedFaceRegion] {
        guard case .faces(let faces)? = detection else { return [] }
        return faces
    }

    /// Every region the two paths located, before scoring. Faces and eyes stay separate, and
    /// each carries its face's index (#114).
    private static func unscored(
        autofocus: Result<AutofocusRegion, AutofocusMetadataEvidence>,
        faces: [DetectedFaceRegion]
    ) -> [RegionSharpnessEvidence] {
        var regions: [RegionSharpnessEvidence] = []
        if case .success(let located) = autofocus {
            regions.append(
                RegionSharpnessEvidence(
                    kind: .cameraAutofocus, groupIndex: nil, region: located.region,
                    score: nil, unavailableBecause: nil))
        }
        for (index, face) in faces.enumerated() {
            regions.append(
                RegionSharpnessEvidence(
                    kind: .face, groupIndex: index, region: face.face, score: nil,
                    unavailableBecause: nil))
            for eye in [face.leftEye, face.rightEye].compactMap({ $0 }) {
                regions.append(
                    RegionSharpnessEvidence(
                        kind: .eye, groupIndex: index, region: eye, score: nil,
                        unavailableBecause: nil))
            }
        }
        return regions
    }

    /// One region marked unscored for an explicit reason.
    private static func unavailable(
        _ evidence: RegionSharpnessEvidence, because reason: RegionScoreUnavailable
    ) -> RegionSharpnessEvidence {
        RegionSharpnessEvidence(
            kind: evidence.kind, groupIndex: evidence.groupIndex, region: evidence.region,
            score: nil, unavailableBecause: reason)
    }

    /// One region scored against the shared pixels, or the explicit reason it cannot be.
    private static func scored(
        _ evidence: RegionSharpnessEvidence, in pixels: CGImage, scorer: RegionSharpnessScorer
    ) -> RegionSharpnessEvidence {
        func replaced(
            score: RegionSharpnessScore? = nil,
            unavailable: RegionScoreUnavailable? = nil
        ) -> RegionSharpnessEvidence {
            RegionSharpnessEvidence(
                kind: evidence.kind, groupIndex: evidence.groupIndex, region: evidence.region,
                score: score, unavailableBecause: unavailable)
        }
        let size = CGSize(width: pixels.width, height: pixels.height)
        guard let rect = evidence.region.pixelRect(in: size) else {
            return replaced(unavailable: .regionOutsideImage)
        }
        guard rect.width >= CGFloat(RegionSharpnessScorer.minimumEdge),
            rect.height >= CGFloat(RegionSharpnessScorer.minimumEdge)
        else { return replaced(unavailable: .regionTooSmall) }
        guard let score = scorer.score(image: pixels, region: evidence.region) else {
            return replaced(unavailable: .regionTooSmall)
        }
        return replaced(score: score)
    }

    // MARK: - Path results

    private static func autofocusPath(
        located: Result<AutofocusRegion, AutofocusMetadataEvidence>,
        evidence: [RegionSharpnessEvidence], pixelsFailed: Bool
    ) -> RegionSharpnessPathResult {
        switch located {
        case .failure(let missing):
            return .unavailable(.noAutofocusMetadata(missing))
        case .success:
            return .regions(evidence)
        }
    }

    private static func facePath(
        detection: FaceDetectionOutcome?, faces: [DetectedFaceRegion],
        preview: Result<CGImage, RegionImageFailure>, evidence: [RegionSharpnessEvidence]
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
