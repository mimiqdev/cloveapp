import CoreImage
import CryptoKit
import Darwin
import Foundation
import ImageIO
import LabSupport

public enum PreviewMethod: String, CaseIterable, Sendable {
    /// Both creation flags false: diagnostic for what ImageIO exposes, not proof of provenance.
    case embeddedOnly, ifAbsent, always, raw
}

public struct PreviewRequest: Sendable {
    public var method: PreviewMethod
    /// Zero means native resolution (RAW only).
    public var maxPixel: Int
    public var transform: Bool

    public init(method: PreviewMethod, maxPixel: Int, transform: Bool = true) {
        self.method = method
        self.maxPixel = maxPixel
        self.transform = transform
    }
}

public struct PreviewResult: Sendable {
    public var file: String
    public var request: PreviewRequest
    public var milliseconds: Double
    public var width: Int = 0
    public var height: Int = 0
    public var sourceWidth: Int = 0
    public var sourceHeight: Int = 0
    public var orientation: Int = 1
    public var decodedBytes: Int = 0
    public var residentBefore: UInt64 = 0
    public var sampledPeakResident: UInt64 = 0
    public var error: String?

    public var measurements: [LabMeasurement] {
        let tags = [
            "file": file, "format": (file as NSString).pathExtension.uppercased(),
            "method": request.method.rawValue, "maxPixel": String(request.maxPixel),
            "transform": String(request.transform), "status": error ?? "ok",
        ]
        return [
            ("first-pixel", milliseconds, "ms"),
            ("width", Double(width), "px"), ("height", Double(height), "px"),
            ("source-width", Double(sourceWidth), "px"),
            ("source-height", Double(sourceHeight), "px"),
            ("source-orientation", Double(orientation), "exif"),
            ("decoded-memory", Double(decodedBytes), "bytes"),
            ("resident-before", Double(residentBefore), "bytes"),
            ("sampled-peak-resident", Double(sampledPeakResident), "bytes"),
        ].map { LabMeasurement(name: $0.0, value: $0.1, unit: $0.2, tags: tags) }
    }
}

public enum PreviewFailure: Error {
    case cannotOpen, noThumbnail, rawUnsupported, rawNoOutput, cannotRender
}

/// Process RSS, sampled every 5 ms during one synchronous decode. A lower bound,
/// not an isolated allocation count; other tasks and framework caches contribute.
private final class ResidentSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64
    private let timer: DispatchSourceTimer
    let baseline: UInt64

    init() {
        baseline = Self.resident()
        peak = baseline
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "clove.previews.memory"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
    }

    func finish() -> UInt64 {
        timer.cancel()
        sample()
        return lock.withLock { peak }
    }

    private func sample() {
        let value = Self.resident()
        lock.withLock { peak = max(peak, value) }
    }

    private static func resident() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.resident_size : 0
    }
}

public enum PreviewMeasurement {
    public static let extensions: Set<String> = Set([
        "cr3", "nef", "arw", "raf", "orf", "rw2", "dng", "jpg", "jpeg",
    ]).union(PhotoExtensions.heif)

    /// Deterministic recursive list, excluding hidden files and the default rejects folder.
    public static func files(in folder: URL) throws -> [URL] {
        var enumerationError: (any Error)?
        guard
            let enumerator = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                }
            )
        else { throw PreviewFailure.cannotOpen }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == "_Rejected" {
                enumerator.skipDescendants()
            } else if extensions.contains(url.pathExtension.lowercased()),
                try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            {
                files.append(url)
            }
        }
        if let enumerationError { throw enumerationError }
        return files.sorted { $0.path < $1.path }
    }

    /// A fresh source per request with ImageIO caching disabled. Timing includes
    /// opening, properties, decode and touching the bitmap provider (CPU pixels).
    /// Native synchronous calls cannot be interrupted; cancelled results are discarded.
    public static func measure(
        url: URL, request: PreviewRequest, willRender: @Sendable () -> Void = {}
    ) throws -> PreviewResult {
        try Task.checkCancellation()
        return try autoreleasepool {
            let sampler = ResidentSampler()
            let start = ContinuousClock.now
            var result = PreviewResult(
                file: url.lastPathComponent, request: request, milliseconds: 0)
            result.residentBefore = sampler.baseline
            do {
                if let source = CGImageSourceCreateWithURL(
                    url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
                {
                    let properties =
                        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                    result.sourceWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
                    result.sourceHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
                    result.orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
                }
                let image = try image(url: url, request: request, willRender: willRender)
                // Forces provider materialization rather than timing a lazy CIImage graph.
                guard let pixels = image.dataProvider?.data, CFDataGetLength(pixels) > 0 else {
                    throw PreviewFailure.cannotRender
                }
                result.width = image.width
                result.height = image.height
                result.decodedBytes = image.bytesPerRow * image.height
            } catch {
                result.error = String(describing: error)
            }
            result.milliseconds = milliseconds(since: start)
            result.sampledPeakResident = sampler.finish()
            try Task.checkCancellation()
            return result
        }
    }

    public static func image(
        url: URL, request: PreviewRequest, willRender: @Sendable () -> Void = {}
    ) throws -> CGImage {
        try Task.checkCancellation()
        if request.method == .raw {
            guard let filter = CIRAWFilter(imageURL: url) else {
                throw PreviewFailure.rawUnsupported
            }
            guard var output = filter.outputImage else { throw PreviewFailure.rawNoOutput }
            if request.maxPixel > 0 {
                let scale = min(
                    1, CGFloat(request.maxPixel) / max(output.extent.width, output.extent.height))
                // Deliberately render then downscale; do not claim this measures RAW draft decoding.
                output = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
            let context = CIContext(options: [.cacheIntermediates: false])
            willRender()
            guard
                let rendered = context.createCGImage(
                    output, from: output.extent, format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            else { throw PreviewFailure.cannotRender }
            try Task.checkCancellation()
            return rendered
        }
        guard
            let source = CGImageSourceCreateWithURL(
                url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw PreviewFailure.cannotOpen }
        var options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: max(1, request.maxPixel),
            kCGImageSourceCreateThumbnailWithTransform: request.transform,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
        ]
        switch request.method {
        case .ifAbsent: options[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
        case .always: options[kCGImageSourceCreateThumbnailFromImageAlways] = true
        case .embeddedOnly, .raw: break
        }
        willRender()
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            throw PreviewFailure.noThumbnail
        }
        try Task.checkCancellation()
        return image
    }

    public static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
    }
}

/// Invalidation identity for the cache experiment. Size, exact modification time,
/// render variant and standardized path are included; no original is changed.
public enum PreviewCacheKey {
    public static func make(url: URL, request: PreviewRequest) throws -> String {
        var freshURL = url
        freshURL.removeAllCachedResourceValues()
        let values = try freshURL.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey,
        ])
        let identity = [
            url.standardizedFileURL.path, String(values.fileSize ?? 0),
            String((values.contentModificationDate ?? .distantPast).timeIntervalSince1970),
            request.method.rawValue, String(request.maxPixel), String(request.transform),
            "previews-v1-srgb",
        ]
        let bytes = try JSONEncoder().encode(identity)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
