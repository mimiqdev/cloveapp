import Foundation
import ImageIO
import LabSupport
import UniformTypeIdentifiers

public struct PreviewProgress: Sendable {
    public var completed: Int
    public var total: Int
    public var message: String
}

public enum PreviewSuite {
    /// Bound expensive decoding on large cards. Run formats separately so every
    /// fixture receives detailed measurements. Throughput uses up to 240 files.
    public static func run(
        folder: URL,
        includeFullRAW: Bool = true,
        progress: @Sendable (PreviewProgress) async -> Void = { _ in }
    ) async throws -> LabReport {
        let files = try PreviewMeasurement.files(in: folder)
        let grid = Array(files.prefix(240))
        let detailed = Array(files.prefix(12))
        let requests =
            [400, 2_000].flatMap { size in
                [PreviewMethod.embeddedOnly, .ifAbsent, .always].map {
                    PreviewRequest(method: $0, maxPixel: size)
                }
            } + [
                PreviewRequest(method: .embeddedOnly, maxPixel: 20_000),
                PreviewRequest(method: .ifAbsent, maxPixel: 400, transform: false),
                PreviewRequest(method: .raw, maxPixel: 2_000),
            ] + (includeFullRAW ? [PreviewRequest(method: .raw, maxPixel: 0)] : [])
        let total =
            detailed.count * requests.count + 4 + detailed.count + 1 + (files.isEmpty ? 0 : 1)
        var completed = 0
        var measurements: [LabMeasurement] = []
        for file in detailed {
            for request in requests {
                try Task.checkCancellation()
                await progress(
                    .init(completed: completed, total: total, message: file.lastPathComponent))
                var result = try PreviewMeasurement.measure(url: file, request: request)
                result.file = relativePath(file, in: folder)
                measurements += result.measurements
                completed += 1
            }
        }
        for concurrency in [1, 2, 4, 8] {
            try Task.checkCancellation()
            await progress(
                .init(
                    completed: completed, total: total, message: "Grid concurrency \(concurrency)"))
            measurements += try await throughput(files: grid, concurrency: concurrency)
            completed += 1
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "clove-previews-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for file in detailed {
            try Task.checkCancellation()
            measurements += try autoreleasepool {
                try cacheMeasurements(file: file, directory: directory).map { measurement in
                    var measurement = measurement
                    measurement.tags["file"] = relativePath(file, in: folder)
                    return measurement
                }
            }
            completed += 1
            await progress(
                .init(
                    completed: completed, total: total, message: "Cache: \(file.lastPathComponent)")
            )
        }
        let control = try PreviewControl.writeNoThumbnailJPEG(in: directory)
        for method in [PreviewMethod.embeddedOnly, .ifAbsent, .always] {
            for transform in [false, true] {
                measurements += try PreviewMeasurement.measure(
                    url: control,
                    request: .init(method: method, maxPixel: 400, transform: transform)
                ).measurements
            }
        }
        completed += 1
        if let file = detailed.first {
            measurements += await cancellationProbe(file: file).map { measurement in
                var measurement = measurement
                measurement.tags["file"] = relativePath(file, in: folder)
                return measurement
            }
            completed += 1
        }
        await progress(.init(completed: completed, total: total, message: "Finished"))
        return LabReport(
            spike: "S2",
            context: [
                "folder": folder.lastPathComponent, "filesFound": String(files.count),
                "detailedFiles": String(detailed.count), "gridFiles": String(grid.count),
                "fullRAW": String(includeFullRAW), "memory": "5ms process RSS samples; lower bound",
                "volume": (try? folder.resourceValues(forKeys: [.volumeNameKey]).volumeName)
                    ?? "unknown",
                "order": "sorted path; methods serial; concurrency 1,2,4,8; OS caches not flushed",
            ],
            measurements: measurements,
            notes: [
                "First pixel means CPU bitmap materialized, not on-screen presentation. One observation per variant.",
                "embeddedOnly sets both creation flags false. ImageIO may expose only one of several embedded previews; provenance is not guaranteed.",
                "RAW uses CIRAWFilter plus CIContext RGBA8 sRGB render, with optional output scaling. Not draft decoding.",
                "Peak RSS is sampled, process-wide, includes framework caches and concurrent activity; it is not RAW-only memory.",
                "Detailed methods and cache sample first 12 files; grid throughput uses first 240. No original bytes are written.",
                "Cache disk read is warm OS-cache JPEG decode; NSCache is a warmed lookup. Temp cache removed after run.",
                "control-no-thumbnail.jpg is a synthetic 2400x1600 JPEG without a thumbnail, orientation 6, created only in temporary storage.",
                "Physical-device results must be collected on iPhone 17 Pro Max and iPad Pro; simulator is not device performance.",
            ])
    }

    private static func relativePath(_ file: URL, in folder: URL) -> String {
        let root = folder.standardizedFileURL.path + "/"
        let path = file.standardizedFileURL.path
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : file.lastPathComponent
    }

    /// Bounded task group; never queues the entire folder into native decoders.
    public static func throughput(files: [URL], concurrency: Int) async throws -> [LabMeasurement] {
        let start = ContinuousClock.now
        let request = PreviewRequest(method: .ifAbsent, maxPixel: 400)
        let successes = try await withThrowingTaskGroup(of: Bool.self) { group in
            var next = 0
            var successes = 0
            for _ in 0..<min(max(1, concurrency), files.count) {
                let file = files[next]
                next += 1
                group.addTask {
                    try PreviewMeasurement.measure(url: file, request: request).error == nil
                }
            }
            while let success = try await group.next() {
                if success { successes += 1 }
                try Task.checkCancellation()
                if next < files.count {
                    let file = files[next]
                    next += 1
                    group.addTask {
                        try PreviewMeasurement.measure(url: file, request: request).error == nil
                    }
                }
            }
            return successes
        }
        let elapsed = PreviewMeasurement.milliseconds(since: start)
        let tags = [
            "concurrency": String(concurrency), "attempted": String(files.count),
            "method": "ifAbsent-400",
        ]
        return [
            LabMeasurement(name: "grid-elapsed", value: elapsed, unit: "ms", tags: tags),
            LabMeasurement(
                name: "grid-success", value: Double(successes), unit: "count", tags: tags),
            LabMeasurement(
                name: "grid-throughput", value: Double(successes) * 1_000 / max(elapsed, 0.001),
                unit: "images/s", tags: tags),
        ]
    }

    /// Signal immediately before the synchronous render call, then cancel from
    /// the awaiting task. Scheduling can race completion; record that outcome too.
    public static func cancellationProbe(file: URL) async -> [LabMeasurement] {
        var measurements: [LabMeasurement] = []
        for request in [
            PreviewRequest(method: .ifAbsent, maxPixel: 400), .init(method: .raw, maxPixel: 2_000),
        ] {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            let task = Task.detached {
                defer { continuation.finish() }
                do {
                    let result = try PreviewMeasurement.measure(url: file, request: request) {
                        continuation.yield(())
                    }
                    return result.error ?? "completed-before-cancel-observed"
                } catch is CancellationError {
                    return "cancelled-result-discarded"
                } catch { return String(describing: error) }
            }
            var reachedRender = false
            for await _ in stream { reachedRender = true; break }
            let start = ContinuousClock.now
            task.cancel()
            let outcome = await task.value
            measurements.append(
                LabMeasurement(
                    name: "cancel-drain", value: PreviewMeasurement.milliseconds(since: start),
                    unit: "ms",
                    tags: [
                        "file": file.lastPathComponent, "status": outcome,
                        "method": request.method.rawValue, "maxPixel": String(request.maxPixel),
                        "trigger": reachedRender ? "native render boundary" : "no render available",
                    ]))
        }
        return measurements
    }

    public static func cacheMeasurements(file: URL, directory: URL) throws -> [LabMeasurement] {
        let request = PreviewRequest(method: .ifAbsent, maxPixel: 400)
        let tags = ["file": file.lastPathComponent, "maxPixel": "400"]
        do {
            let image = try PreviewMeasurement.image(url: file, request: request)
            let memory = NSCache<NSString, CGImage>()
            memory.totalCostLimit = 64 * 1_024 * 1_024
            let key = try PreviewCacheKey.make(url: file, request: request)
            memory.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height)
            let start = ContinuousClock.now
            let hit = memory.object(forKey: key as NSString)
            let hitMS = PreviewMeasurement.milliseconds(since: start)
            let diskURL = directory.appendingPathComponent(key).appendingPathExtension("jpg")
            let writeStart = ContinuousClock.now
            guard
                let destination = CGImageDestinationCreateWithURL(
                    diskURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
            else {
                throw PreviewFailure.cannotRender
            }
            CGImageDestinationAddImage(
                destination, image,
                [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw PreviewFailure.cannotRender }
            let writeMS = PreviewMeasurement.milliseconds(since: writeStart)
            let readStart = ContinuousClock.now
            let decoded = try PreviewMeasurement.image(
                url: diskURL, request: .init(method: .always, maxPixel: 400))
            guard let data = decoded.dataProvider?.data, CFDataGetLength(data) > 0 else {
                throw PreviewFailure.cannotRender
            }
            let readMS = PreviewMeasurement.milliseconds(since: readStart)
            let bytes = try diskURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return [
                LabMeasurement(name: "cache-memory-hit", value: hitMS, unit: "ms", tags: tags),
                LabMeasurement(
                    name: "cache-hit", value: hit == nil ? 0 : 1, unit: "count", tags: tags),
                LabMeasurement(name: "cache-encode-write", value: writeMS, unit: "ms", tags: tags),
                LabMeasurement(name: "cache-read-decode", value: readMS, unit: "ms", tags: tags),
                LabMeasurement(
                    name: "cache-disk-size", value: Double(bytes), unit: "bytes", tags: tags),
                LabMeasurement(
                    name: "cache-decoded-size", value: Double(image.bytesPerRow * image.height),
                    unit: "bytes", tags: tags),
            ]
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return [
                LabMeasurement(
                    name: "cache-failure", value: 1, unit: "count",
                    tags: tags.merging(["status": String(describing: error)]) { _, new in new })
            ]
        }
    }
}
