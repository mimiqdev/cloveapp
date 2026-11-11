import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// JPEG bytes and the image's presentation facts, without retaining decoded pixels.
/// Encoding and decoding are called only from detail workers.
struct DetailCompressedImage: Sendable {
    let data: Data
    let longEdge: Int
    private let source: DetailSource
    private let quality: DetailQuality
    private let hasRAW: Bool
    private let limitation: DetailLimitation?
    private let fullResolutionSize: CGSize?

    init?(_ image: DetailImage) {
        let bytes = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                bytes, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image.image,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        data = bytes as Data
        longEdge = image.longEdge
        source = image.source
        quality = image.quality
        hasRAW = image.hasRAW
        limitation = image.limitation
        fullResolutionSize = image.fullResolutionSize
    }

    func decoded() -> DetailImage? {
        autoreleasepool {
            guard
                let encoded = CGImageSourceCreateWithData(
                    data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                let pixels = CGImageSourceCreateImageAtIndex(
                    encoded, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                let bytes = pixels.dataProvider?.data, CFDataGetLength(bytes) > 0
            else { return nil }
            return DetailImage(
                image: pixels, source: source, quality: quality, hasRAW: hasRAW,
                limitation: limitation, fullResolutionSize: fullResolutionSize)
        }
    }
}
