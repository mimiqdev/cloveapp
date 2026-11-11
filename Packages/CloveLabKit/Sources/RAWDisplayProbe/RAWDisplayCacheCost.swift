import CoreGraphics
import Foundation
import ImageIO
import LabSupport
import UniformTypeIdentifiers

/// What one screen-size render costs to keep: an encode to HEIC and JPEG at quality
/// 0.9, the bytes those files take, their decode time, and the RAM of six decoded
/// renders held at once.
public enum RAWDisplayCacheCost {
    /// Encodes and holds at most this many renders; the brief fixes the memory sample
    /// at six.
    public static let heldImageLimit = 6

    /// Runs the cache measurements into a temporary directory owned by the caller.
    public static func measurements(
        files: [URL], folder: URL, variant: RAWDisplayVariant,
        measuring: any RAWDisplayMeasuring, directory: URL,
        step: (String) async -> Void = { _ in }
    ) async throws -> [LabMeasurement] {
        var held: [(file: URL, image: CGImage)] = []
        var measurements: [LabMeasurement] = []
        let sampler = RAWDisplayResidentSampler()
        let start = ContinuousClock.now
        for file in files.prefix(heldImageLimit) {
            try Task.checkCancellation()
            await step("Cache: \(file.lastPathComponent)")
            do {
                let image = try measuring.rawImage(url: file, variant: variant)
                held.append((file, image))
                measurements.append(
                    LabMeasurement(
                        name: "cache-screen-decoded-memory",
                        value: Double(image.bytesPerRow * image.height), unit: "bytes",
                        tags: ["file": RAWDisplayFiles.relativePath(file, in: folder)]))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                measurements.append(failure(file: file, folder: folder, error: error))
            }
        }
        let heldBytes = held.reduce(0) { $0 + $1.image.bytesPerRow * $1.image.height }
        let heldTags: [String: String] = [
            "count": String(held.count), "variant": variant.name,
            "note": "screen-size renders held decoded at the same time",
        ]
        measurements += [
            LabMeasurement(
                name: "cache-held-images", value: Double(held.count), unit: "count", tags: heldTags),
            LabMeasurement(
                name: "cache-held-decoded-memory", value: Double(heldBytes), unit: "bytes",
                tags: heldTags),
            LabMeasurement(
                name: "cache-held-resident", value: Double(sampler.finish()), unit: "bytes",
                tags: heldTags),
            LabMeasurement(
                name: "cache-held-duration", value: displayMilliseconds(since: start), unit: "ms",
                tags: heldTags),
        ]
        for entry in held {
            try Task.checkCancellation()
            for format in [UTType.heic, UTType.jpeg] {
                measurements += encodeMeasurements(
                    entry.image, format: format, file: entry.file, folder: folder,
                    directory: directory)
            }
        }
        // Release the held bitmaps before returning so the next phase starts clean.
        held.removeAll()
        return measurements
    }

    private static func encodeMeasurements(
        _ image: CGImage, format: UTType, file: URL, folder: URL, directory: URL
    ) -> [LabMeasurement] {
        let name = format == .heic ? "heic" : "jpeg"
        let tags: [String: String] = [
            "file": RAWDisplayFiles.relativePath(file, in: folder), "format": name,
            "quality": "0.9",
        ]
        let url = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(name == "heic" ? "heic" : "jpg")
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, format.identifier as CFString, 1, nil)
        else {
            return [
                LabMeasurement(name: "cache-encode-failure", value: 1, unit: "count", tags: tags)
            ]
        }
        let encodeStart = ContinuousClock.now
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return [
                LabMeasurement(name: "cache-encode-failure", value: 1, unit: "count", tags: tags)
            ]
        }
        let encodeMS = displayMilliseconds(since: encodeStart)
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let decodeStart = ContinuousClock.now
        var decodedBytes = 0
        var decodeError = "ok"
        if let source = CGImageSourceCreateWithURL(
            url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let decoded = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
            let data = decoded.dataProvider?.data, CFDataGetLength(data) > 0
        {
            decodedBytes = decoded.bytesPerRow * decoded.height
        } else {
            decodeError = "cannotDecode"
        }
        let decodeMS = displayMilliseconds(since: decodeStart)
        try? FileManager.default.removeItem(at: url)
        return [
            LabMeasurement(
                name: "cache-encode", value: encodeMS, unit: "ms",
                tags: tags.merging(["status": "ok"]) { _, new in new }),
            LabMeasurement(name: "cache-bytes", value: Double(bytes), unit: "bytes", tags: tags),
            LabMeasurement(
                name: "cache-decode", value: decodeMS, unit: "ms",
                tags: tags.merging(["status": decodeError]) { _, new in new }),
            LabMeasurement(
                name: "cache-decoded-memory", value: Double(decodedBytes), unit: "bytes",
                tags: tags.merging(["status": decodeError]) { _, new in new }),
        ]
    }

    private static func failure(file: URL, folder: URL, error: any Error) -> LabMeasurement {
        LabMeasurement(
            name: "cache-failure", value: 1, unit: "count",
            tags: [
                "file": RAWDisplayFiles.relativePath(file, in: folder),
                "status": String(describing: error),
            ])
    }
}

/// Projects the measured 400 px render time to a folder of the brief's size.
///
/// This is arithmetic on one measured per-photo time, not a concurrent run: the
/// concurrency-2 row assumes two renders divide the work perfectly, which neither the
/// decoder nor the device promises.
public enum RAWDisplayGridEstimate {
    public static func measurements(
        perPhotoMilliseconds: Double, variantName: String, folderPhotos: Int
    ) -> [LabMeasurement] {
        let tags: [String: String] = [
            "variant": variantName, "photos": String(folderPhotos),
            "basis": "per-photo render time from this run; arithmetic projection",
        ]
        return [
            LabMeasurement(
                name: "grid-per-photo", value: perPhotoMilliseconds, unit: "ms", tags: tags),
            LabMeasurement(
                name: "grid-folder-projection",
                value: perPhotoMilliseconds * Double(folderPhotos) / 1_000,
                unit: "s", tags: tags.merging(["concurrency": "1"]) { _, new in new }),
            LabMeasurement(
                name: "grid-folder-projection",
                value: perPhotoMilliseconds * Double(folderPhotos) / 2_000, unit: "s",
                tags: tags.merging(["concurrency": "2"]) { _, new in new }),
        ]
    }
}
