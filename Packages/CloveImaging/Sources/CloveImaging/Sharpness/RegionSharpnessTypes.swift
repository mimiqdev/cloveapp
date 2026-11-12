import CoreGraphics
import Foundation

/// A rectangle in a photo's displayed orientation, normalized so that 0…1 spans the visible
/// image with the origin at its top-left.
///
/// Everything CloveImaging delivers — previews, renders and full decodes — already has EXIF
/// orientation applied, so a region in this space maps onto delivered pixels by scaling alone.
/// Camera metadata is recorded in the file's unrotated storage space and is converted into this
/// space by the metadata reader before anything else sees it (#208).
public struct NormalizedRegion: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var centerX: Double { x + width / 2 }
    public var centerY: Double { y + height / 2 }

    /// The same rectangle after the file's EXIF orientation is applied for display.
    ///
    /// Metadata rectangles live in the unrotated storage space. EXIF orientations 2–4 mirror or
    /// rotate by half a turn, and 5–8 rotate by a quarter turn (5 and 7 mirror as well), which
    /// swaps the rectangle's axes. Mapping the four corners and taking their bounds is exact
    /// because every orientation is an axis-aligned isometry.
    public func oriented(forExifOrientation orientation: Int) -> NormalizedRegion {
        guard (2...8).contains(orientation) else { return self }
        let corners = [
            (x, y), (x + width, y), (x, y + height), (x + width, y + height),
        ].map { Self.displayPoint(x: $0.0, y: $0.1, orientation: orientation) }
        let xs = corners.map(\.0)
        let ys = corners.map(\.1)
        return NormalizedRegion(
            x: xs.min() ?? 0, y: ys.min() ?? 0,
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0))
    }

    /// Where this rectangle lands in delivered pixels, or nil when none of it is inside.
    public func pixelRect(in size: CGSize) -> CGRect? {
        guard size.width > 0, size.height > 0 else { return nil }
        let rect = CGRect(
            x: x * Double(size.width), y: y * Double(size.height),
            width: width * Double(size.width), height: height * Double(size.height))
        let clipped = rect.integral.intersection(CGRect(origin: .zero, size: size))
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return clipped
    }

    /// One point of the storage-to-display map for each EXIF orientation. Inputs and outputs
    /// are top-left-origin normalized coordinates.
    static func displayPoint(x: Double, y: Double, orientation: Int) -> (Double, Double) {
        switch orientation {
        case 2: return (1 - x, y)
        case 3: return (1 - x, 1 - y)
        case 4: return (x, 1 - y)
        case 5: return (y, x)
        case 6: return (1 - y, x)
        case 7: return (1 - y, 1 - x)
        case 8: return (y, 1 - x)
        default: return (x, y)
        }
    }
}

/// Which input produced a region: the camera's own autofocus record, or on-device face and eye
/// localization (#208). Regions stay separate per face and per eye; they are never collapsed.
public enum SharpnessRegionKind: String, Sendable {
    case cameraAutofocus
    case face
    case eye
}

/// Sharpness evidence for one region: a measurement over its pixels, never a calibrated focus
/// percentage or a verdict (#114, #208).
public struct RegionSharpnessScore: Hashable, Sendable {
    /// Mean of the squared Sobel gradient magnitude over the region's luminance, the Tenengrad
    /// measure. Larger means more local contrast; it is only comparable between regions scored
    /// by the same version of the scorer.
    public let tenengradMeanSquare: Double
    /// Interior pixels the measure averaged over.
    public let sampledPixels: Int
    public let sampledWidth: Int
    public let sampledHeight: Int

    public init(
        tenengradMeanSquare: Double, sampledPixels: Int, sampledWidth: Int, sampledHeight: Int
    ) {
        self.tenengradMeanSquare = tenengradMeanSquare
        self.sampledPixels = sampledPixels
        self.sampledWidth = sampledWidth
        self.sampledHeight = sampledHeight
    }
}

/// Why one located region carries no score. An explicit reason is always reported instead of a
/// misleading measurement (#208).
public enum RegionScoreUnavailable: String, Sendable {
    /// The region maps to fewer pixels than the scorer can measure.
    case regionTooSmall
    /// The region does not overlap the delivered pixels at all.
    case regionOutsideImage
    /// The photo's high-resolution pixels could not be acquired; see
    /// ``RegionSharpnessAnalysis/acquisitionFailure`` for why.
    case pixelsUnavailable
    /// The file changed while the analysis ran, so the pixels no longer match the request.
    case staleSource
}

/// The failure of an image read the analysis depends on. A `staleSource` read is mapped
/// through to every region as ``RegionScoreUnavailable/staleSource``.
public enum RegionImageFailure: Error, Sendable {
    case cannotOpen
    case noUsablePreview
    case queueFull
    case closed
    case staleSource
}

/// One region's outcome: where it is, and either its sharpness evidence or the explicit reason
/// there is none.
public struct RegionSharpnessEvidence: Sendable {
    public let kind: SharpnessRegionKind
    /// The face a face or eye region belongs to, so results stay separate per face (#114).
    public let groupIndex: Int?
    /// The region in displayed-image space, the same space an overlay would draw in.
    public let region: NormalizedRegion
    public let score: RegionSharpnessScore?
    public let unavailableBecause: RegionScoreUnavailable?
}

/// What one analysis path concluded when it produced no regions at all.
public enum RegionPathUnavailable: Sendable {
    /// No usable camera AF coordinates. The evidence records every path that was checked.
    case noAutofocusMetadata(AutofocusMetadataEvidence)
    /// Detection ran and found no face.
    case noFacesDetected
    /// The detection request itself failed; the message is Vision's own description.
    case faceDetectionFailed(String)
    /// No preview pixels to detect faces on.
    case previewFailed(RegionImageFailure)
}

public enum RegionSharpnessPathResult: Sendable {
    case regions([RegionSharpnessEvidence])
    case unavailable(RegionPathUnavailable)
}

/// Per-stage wall-clock measurements for later device benchmarking (#208). They are exposed as
/// recorded facts; no performance claim is derived from them here.
public struct RegionSharpnessTimings: Sendable {
    /// Reading the photo's AF metadata properties.
    public let metadataRead: ContinuousClock.Duration?
    /// Reading the preview the face detection ran on.
    public let previewRead: ContinuousClock.Duration?
    /// The one Vision face and eye localization request.
    public let faceDetection: ContinuousClock.Duration?
    /// The single high-resolution acquisition shared by every region.
    public let pixelAcquisition: ContinuousClock.Duration?
    /// All region scoring combined.
    public let regionScoring: ContinuousClock.Duration?

    public init(
        metadataRead: ContinuousClock.Duration? = nil,
        previewRead: ContinuousClock.Duration? = nil,
        faceDetection: ContinuousClock.Duration? = nil,
        pixelAcquisition: ContinuousClock.Duration? = nil,
        regionScoring: ContinuousClock.Duration? = nil
    ) {
        self.metadataRead = metadataRead
        self.previewRead = previewRead
        self.faceDetection = faceDetection
        self.pixelAcquisition = pixelAcquisition
        self.regionScoring = regionScoring
    }

    /// Milliseconds, for reporting only.
    public static func milliseconds(_ duration: ContinuousClock.Duration?) -> Double? {
        duration.map {
            Double($0.components.seconds) * 1_000 + Double($0.components.attoseconds) / 1e15
        }
    }
}

/// One photo's local sharpness analysis: the camera-AF path and the face/eye path, each with its
/// own regions and its own explicit unavailability (#208).
public struct RegionSharpnessAnalysis: Sendable {
    public let autofocus: RegionSharpnessPathResult
    public let faces: RegionSharpnessPathResult
    /// Why the shared high-resolution acquisition failed, when it did; every region of that
    /// analysis then reports ``RegionScoreUnavailable/pixelsUnavailable``.
    public let acquisitionFailure: RegionImageFailure?
    public let timings: RegionSharpnessTimings

    public init(
        autofocus: RegionSharpnessPathResult, faces: RegionSharpnessPathResult,
        acquisitionFailure: RegionImageFailure?, timings: RegionSharpnessTimings
    ) {
        self.autofocus = autofocus
        self.faces = faces
        self.acquisitionFailure = acquisitionFailure
        self.timings = timings
    }
}
