import CoreGraphics
import Dispatch
import Foundation
import Vision

/// One detected face with its eyes, located on a preview, in the preview's normalized space
/// (top-left origin, orientation already applied by the preview's pixels).
public struct DetectedFaceRegion: Sendable {
    public let face: NormalizedRegion
    public let leftEye: NormalizedRegion?
    public let rightEye: NormalizedRegion?

    public init(face: NormalizedRegion, leftEye: NormalizedRegion?, rightEye: NormalizedRegion?) {
        self.face = face
        self.leftEye = leftEye
        self.rightEye = rightEye
    }
}

/// What a face-detection pass concluded.
public enum FaceDetectionOutcome: Sendable {
    case faces([DetectedFaceRegion])
    case failed(String)
}

/// The seam the sharpness tests use to replace Vision, matching how the feature-print tests
/// inject theirs. Production uses ``VisionFaceRegionDetector``.
protocol FaceRegionDetecting: Sendable {
    func detectFaces(on image: CGImage) async -> FaceDetectionOutcome
}

/// On-device Vision face and eye localization over an existing preview (#208).
///
/// `VNDetectFaceLandmarksRequest` locates faces on its own — no separate rectangles pass — and
/// its `VNFaceObservation` results carry the face box plus pupil landmark points, so one
/// request supplies both. Landmark points are normalized within the face's own box; Vision's
/// coordinate origin is bottom-left, and the analysis's normalized space is top-left, so the
/// pupil conversion flips the y axis.
///
/// The request runs on its own serial queue for the same reason the feature-print reader's
/// does: Vision schedules the request's work on its own queue and then waits for it, so a
/// serial queue costs nothing and keeps the cooperative pool free.
struct VisionFaceRegionDetector: FaceRegionDetecting {
    private static let queue = DispatchQueue(
        label: "com.mimiqdev.clove.face-region-detection", qos: .utility)

    func detectFaces(on image: CGImage) async -> FaceDetectionOutcome {
        await withCheckedContinuation { continuation in
            Self.queue.async {
                continuation.resume(returning: Self.requestFaces(of: image))
            }
        }
    }

    static func requestFaces(of image: CGImage) -> FaceDetectionOutcome {
        autoreleasepool {
            let request = VNDetectFaceLandmarksRequest()
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                return .failed(error.localizedDescription)
            }
            guard let observations = request.results else { return .faces([]) }
            let faces = observations.map { observation in
                DetectedFaceRegion(
                    face: Self.region(of: observation.boundingBox),
                    leftEye: Self.eye(of: observation, selecting: { $0?.leftPupil }),
                    rightEye: Self.eye(of: observation, selecting: { $0?.rightPupil }))
            }
            return .faces(faces)
        }
    }

    /// A measurable eye box from a pupil landmark: two-fifths of the face's smaller side,
    /// centered on the pupil point. The floor keeps the box measurable on small faces.
    private static func eye(
        of observation: VNFaceObservation,
        selecting landmark: (VNFaceLandmarks2D?) -> VNFaceLandmarkRegion2D?
    ) -> NormalizedRegion? {
        guard let region = landmark(observation.landmarks), region.pointCount > 0,
            let point = region.normalizedPoints.first
        else { return nil }
        let box = observation.boundingBox
        // The pupil point is in the face's unit box; the face box is in the image's normalized
        // space with a bottom-left origin.
        let centerX = Double(box.origin.x + point.x * box.width)
        let centerY = Double(box.origin.y + point.y * box.height)
        let side = max(0.4 * Double(min(box.width, box.height)), 0.02)
        return NormalizedRegion(
            x: centerX - side / 2, y: (1 - centerY) - side / 2, width: side, height: side)
    }

    /// Converts a Vision bottom-left normalized box to the analysis's top-left space.
    private static func region(of box: CGRect) -> NormalizedRegion {
        NormalizedRegion(
            x: Double(box.origin.x), y: 1 - Double(box.origin.y + box.height),
            width: Double(box.width), height: Double(box.height))
    }
}
