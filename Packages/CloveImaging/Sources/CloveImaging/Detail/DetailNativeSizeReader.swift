import CoreGraphics
import Dispatch

/// Reads the size a photo's 100% means, from the route its pixels come from (PRD P0-04;
/// G1 "Preview, detail (I2)").
///
/// The pipeline takes this as a dependency so a test can supply a size that describes the
/// embedded preview instead of the sensor, which is the shape of the device bug this replaced
/// (#111).
protocol DetailNativeSizeReading: Sendable {
    /// The oriented native size of the photo's reference file, or nil when it is unknown.
    ///
    /// - Parameters:
    ///   - reference: The photo's RAW when it has one, otherwise its JPEG primary.
    ///   - isRAW: Whether `reference` is the photo's RAW.
    func nativeSize(of reference: DetailSource, isRAW: Bool) -> CGSize?
}

extension DetailNativeSizeReading {
    /// ImageIO and RAW size discovery may block; a detached task still uses the cooperative pool.
    func readNativeSize(of reference: DetailSource, isRAW: Bool) async -> CGSize? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: nativeSize(of: reference, isRAW: isRAW))
            }
        }
    }
}

/// The system readers: the RAW decoder for a RAW, the ImageIO header otherwise (PRD P0-04).
struct DetailNativeSizeReader: DetailNativeSizeReading {
    func nativeSize(of reference: DetailSource, isRAW: Bool) -> CGSize? {
        // The render's own decoder answers for a RAW, so the 100% target and the pixels that
        // replace the preview cannot disagree. The header is only the fallback for a RAW the
        // decoder cannot open (G1 "Preview, detail (I2)").
        if isRAW, let size = DetailNativeSize.raw(reference) { return size }
        return DetailNativeSize.header(reference)
    }
}
