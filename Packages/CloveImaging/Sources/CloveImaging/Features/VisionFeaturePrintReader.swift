import CoreGraphics
import Dispatch
import Foundation
import Vision

/// Produces one photo's Vision feature print, or the reason it could not.
///
/// This is the seam the feature tests inject a failure through, so P0-11's fallback and G1
/// "Grouping (C9/I3)"'s give-up rule are tested without depending on whether the host can run
/// Vision. The revision is part of the contract because G1 keys cached features by it.
protocol FeaturePrintReading: Sendable {
    /// The `VNGenerateImageFeaturePrintRequest` revision this reader produces, which G1
    /// "Grouping (C9/I3)" also uses as part of the cache identity.
    var revision: Int { get }

    /// Computes the print for orientation-applied preview pixels. Never retries: a failure is
    /// reported once and the caller decides whether the session should keep asking.
    func featurePrint(of image: CGImage) async -> Result<VisionFeaturePrint, FeatureFailure>
}

/// G1 "Vision feature per photo": `VNGenerateImageFeaturePrintRequest` revision 2 with
/// `scaleFit`, on the roughly 400 px orientation-applied preview.
///
/// The request is built per call and the observation is copied into plain elements before it
/// leaves this type, so nothing `Sendable`-unsafe crosses an await. Vision fails at runtime on
/// some hosts (S5 recorded `NSOSStatusErrorDomain -1` on the iOS Simulator), which arrives as a
/// ``FeatureFailure`` rather than a crash.
///
/// The synchronous request runs on its own serial queue rather than the caller's task. Vision
/// schedules the request's work on its own queue and then waits for it, so running it inside a
/// Swift concurrency task blocks one of the cooperative pool's threads until that work is
/// scheduled; with the pool busy, a 3 ms request can turn into a multi-second stall. S5 measured
/// requests one at a time on device, and Vision serialises feature prints internally, so a
/// serial queue costs nothing and keeps the app's pool free.
struct VisionFeaturePrintReader: FeaturePrintReading {
    /// Revision 2 is what G1 and S5 measured; bumping it invalidates every cached print.
    static let requestRevision = Int(VNGenerateImageFeaturePrintRequestRevision2)

    /// One queue for every feature print in the process: Vision's own capacity queue is serial
    /// too, so this only moves the wait off the cooperative pool.
    private static let queue = DispatchQueue(
        label: "com.mimiqdev.clove.image-feature-print", qos: .utility)

    var revision: Int { Self.requestRevision }

    func featurePrint(of image: CGImage) async -> Result<VisionFeaturePrint, FeatureFailure> {
        await withCheckedContinuation { continuation in
            Self.queue.async {
                continuation.resume(returning: Self.requestPrint(of: image))
            }
        }
    }

    /// One request, synchronously, the way S5 measured it.
    ///
    /// The pipeline only calls this through ``featurePrint(of:)``; the timing test calls it
    /// directly so a reported Vision time is the request and not the serial queue's wait.
    static func requestPrint(of image: CGImage) -> Result<VisionFeaturePrint, FeatureFailure> {
        autoreleasepool {
            let request = VNGenerateImageFeaturePrintRequest()
            request.revision = requestRevision
            request.imageCropAndScaleOption = .scaleFit
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                return .failure(FeatureFailure(error))
            }
            guard let observation = request.results?.first else {
                return .failure(FeatureFailure(missingObservation))
            }
            guard
                let elements = elements(of: observation, expectedCount: observation.elementCount)
            else {
                return .failure(FeatureFailure(unreadableElements))
            }
            return .success(VisionFeaturePrint(revision: request.revision, elements: elements))
        }
    }

    private static var missingObservation: NSError {
        NSError(
            domain: "CloveImaging.FeaturePrint", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Vision returned no feature print."])
    }

    private static var unreadableElements: NSError {
        NSError(
            domain: "CloveImaging.FeaturePrint", code: 2,
            userInfo: [
                NSLocalizedDescriptionKey: "Vision returned a feature print without float elements."
            ])
    }

    /// Copies a float revision 2 observation into plain scalars, rejecting anything else rather
    /// than guessing at an element layout the distance would then compare wrongly.
    private static func elements(
        of observation: VNFeaturePrintObservation, expectedCount: Int
    ) -> [Float]? {
        guard observation.elementType == .float, expectedCount > 0,
            observation.data.count == expectedCount * MemoryLayout<Float>.size
        else { return nil }
        return observation.data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self).prefix(expectedCount))
        }
    }
}
