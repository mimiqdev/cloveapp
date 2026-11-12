import CoreGraphics
import Foundation

/// Computes one photo's features from a single preview read.
///
/// PRD P0-11 groups photos by similarity while the grid is already reading previews, so both
/// kinds come from the same pixels: the hash is always computed because it is cheap, and the
/// Vision print is attempted once when the session still allows it (G1 "Grouping (C9/I3)").
/// A Vision failure never fails the photo: the hash is returned with the reason attached.
struct ImageFeatureExtractor: Sendable {
    let prints: any FeaturePrintReading
    let session: FeaturePrintSession
    private let hashes = DifferenceHashReader()

    func features(from image: CGImage) async -> ImageFeatures {
        await withTaskExecutorPreference(ImageWorkExecutor.utility) {
            let hash = hashes.hash(of: image)
            guard session.permitsAttempt else {
                // The session already gave up: no attempt, no retry loop, and the reason is kept.
                return ImageFeatures(differenceHash: hash, visionFailure: session.lastFailure)
            }
            switch await prints.featurePrint(of: image) {
            case .success(let print):
                session.recordSuccess()
                return ImageFeatures(print: print, differenceHash: hash)
            case .failure(let failure):
                session.recordFailure(failure)
                return ImageFeatures(differenceHash: hash, visionFailure: failure)
            }
        }
    }
}
