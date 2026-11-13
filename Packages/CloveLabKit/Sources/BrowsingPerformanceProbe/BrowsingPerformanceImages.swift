import CloveCore
import CloveImaging
import CoreGraphics
import Foundation
import LabSupport

private struct ImageRequestOutcome: Sendable {
    let milliseconds: Double
    let decodedBytes: Int
    let failure: String?

    static func success(_ milliseconds: Double, _ decodedBytes: Int) -> ImageRequestOutcome {
        ImageRequestOutcome(milliseconds: milliseconds, decodedBytes: decodedBytes, failure: nil)
    }

    static func failed(_ milliseconds: Double, _ reason: String) -> ImageRequestOutcome {
        ImageRequestOutcome(
            milliseconds: milliseconds, decodedBytes: 0, failure: reason)
    }
}

private struct ThumbnailRun: Sendable {
    let samples: [Double]
    let failures: [String: Int]
    let throughput: Double
    let attempted: Int
    let diskEntries: Int
}

enum BrowsingPerformanceImages {
    static func measureThumbnails(
        sets: [ScannedPhotoSet], configuration: BrowsingPerformanceConfiguration,
        cacheRoot: URL, report: inout BrowsingPerformanceReportBuilder
    ) async throws {
        let requests = try sets.prefix(configuration.thumbnailLimit).map(thumbnailRequest)
        guard !requests.isEmpty else { throw BrowsingPerformanceError.noPhotos }
        let directory = cacheRoot.appendingPathComponent("thumbnails", isDirectory: true)
        let cold = try await thumbnailRun(
            requests: requests, directory: directory, memoryBytes: 64 * 1_024 * 1_024,
            inFlight: configuration.thumbnailInFlight)
        append(cold, cache: "cold", report: &report)

        // A new cache with no memory tier forces the production disk read path while retaining
        // exactly the entries written by the cold run. OS file caches are not flushed.
        let disk = try await thumbnailRun(
            requests: requests, directory: directory, memoryBytes: 0,
            inFlight: configuration.thumbnailInFlight)
        append(disk, cache: "disk", report: &report)
    }

    static func measureDetails(
        sets: [ScannedPhotoSet], configuration: BrowsingPerformanceConfiguration,
        report: inout BrowsingPerformanceReportBuilder
    ) async throws {
        let requests = try sets.prefix(configuration.detailSampleLimit).map {
            try detailRequest(set: $0, configuration: configuration, native: false)
        }
        guard !requests.isEmpty else { throw BrowsingPerformanceError.noPhotos }
        let pipeline = DetailPipeline()
        var cold: [Double] = []
        var coldFailures: [String: Int] = [:]
        var warm: [Double] = []
        var warmFailures: [String: Int] = [:]
        do {
            for request in requests {
                try Task.checkCancellation()
                let watch = Stopwatch()
                let result = try await pipeline.preview(for: request)
                if decodedBytes(result) != nil {
                    cold.append(watch.milliseconds)
                } else {
                    coldFailures[failureReason(result), default: 0] += 1
                }
            }
            for request in requests {
                try Task.checkCancellation()
                let watch = Stopwatch()
                let result = try await pipeline.preview(for: request)
                if decodedBytes(result) != nil {
                    warm.append(watch.milliseconds)
                } else {
                    warmFailures[failureReason(result), default: 0] += 1
                }
            }
        } catch {
            await pipeline.close()
            throw error
        }
        await pipeline.close()
        report.distribution(
            "detail-first-preview", cache: "cold", samples: cold,
            failureCount: coldFailures.values.reduce(0, +))
        report.failureReasons("detail-first-preview", cache: "cold", reasons: coldFailures)
        report.distribution(
            "detail-first-preview", cache: "warm", samples: warm,
            failureCount: warmFailures.values.reduce(0, +))
        report.failureReasons("detail-first-preview", cache: "warm", reasons: warmFailures)

        try await measureRAWFocus(sets: sets, configuration: configuration, report: &report)
    }

    private static func measureRAWFocus(
        sets: [ScannedPhotoSet], configuration: BrowsingPerformanceConfiguration,
        report: inout BrowsingPerformanceReportBuilder
    ) async throws {
        let rawSets = sets.filter { $0.photoSet.primary.format == .raw }
        var raw: [Double] = []
        var includingCancel: [Double] = []
        var cancelDrain: [Double] = []
        var warm: [Double] = []
        var failures: [String: Int] = [:]
        var cancelNotObserved = 0
        var pairsMeasured = 0
        for index in stride(from: 0, to: rawSets.count - 1, by: 2) {
            guard pairsMeasured < configuration.rawSampleLimit else { break }
            try Task.checkCancellation()
            let first = try detailRequest(
                set: rawSets[index], configuration: configuration, native: true)
            let second = try detailRequest(
                set: rawSets[index + 1], configuration: configuration, native: true)
            let firstPipeline = DetailPipeline()
            let firstTask = Task { try await firstPipeline.image(for: first) }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                firstTask.cancel()
                await firstPipeline.close()
                throw error
            }
            let drainWatch = Stopwatch()
            firstTask.cancel()
            // Closing waits for an uncancellable native read that already started. This is
            // the cancelled-render drain, measured directly rather than inferred from a delay.
            await firstPipeline.close()
            let drainMilliseconds = drainWatch.milliseconds

            let secondPipeline = DetailPipeline()
            do {
                let watch = Stopwatch()
                let result = try await secondPipeline.image(for: second)
                let elapsed = watch.milliseconds
                let secondSucceeded = decodedBytes(result) != nil
                if secondSucceeded {
                    raw.append(elapsed)
                } else {
                    failures[failureReason(result), default: 0] += 1
                }

                var firstWasCancelled = false
                do {
                    _ = try await firstTask.value
                } catch is CancellationError {
                    firstWasCancelled = true
                } catch {
                    // A failed first render did not establish a cancelled-render wait.
                }
                if secondSucceeded && firstWasCancelled {
                    cancelDrain.append(drainMilliseconds)
                    includingCancel.append(drainMilliseconds + elapsed)
                } else if !firstWasCancelled {
                    cancelNotObserved += 1
                }

                if secondSucceeded {
                    let warmWatch = Stopwatch()
                    let cached = try await secondPipeline.image(for: second)
                    if decodedBytes(cached) != nil {
                        warm.append(warmWatch.milliseconds)
                    }
                }
            } catch {
                await secondPipeline.close()
                throw error
            }
            await secondPipeline.close()
            pairsMeasured += 1
        }
        guard pairsMeasured > 0 else {
            report.unavailable(
                "raw-focus",
                reason: "The folder has fewer than two RAW photos for a cancel/next pair.")
            return
        }
        report.distribution(
            "raw-focus", cache: "cold", samples: raw,
            failureCount: failures.values.reduce(0, +))
        report.failureReasons("raw-focus", cache: "cold", reasons: failures)
        report.distribution("raw-focus", cache: "warm", samples: warm)
        report.distribution("raw-focus-cancel-drain", cache: "cold", samples: cancelDrain)
        report.distribution(
            "raw-focus-including-cancel", cache: "cold", samples: includingCancel,
            failureCount: cancelNotObserved)
        if cancelNotObserved > 0 {
            report.failureReasons(
                "raw-focus-including-cancel", cache: "cold",
                reasons: [
                    "First render completed or failed before cancellation was observed":
                        cancelNotObserved
                ])
        }
        report.value(
            "raw-focus-cancel-observed", value: Double(includingCancel.count), unit: "count",
            tags: ["attempted": String(pairsMeasured), "cancelSignalDelayMs": "100"])
    }

    private static func thumbnailRun(
        requests: [ThumbnailRequest], directory: URL, memoryBytes: Int, inFlight: Int
    ) async throws -> ThumbnailRun {
        var configuration = ThumbnailCache.Configuration()
        configuration.memoryBytes = memoryBytes
        let cache = try ThumbnailCache(directory: directory, configuration: configuration)
        let pipeline = ThumbnailPipeline(cache: cache)
        let totalWatch = Stopwatch()
        var outcomes: [ImageRequestOutcome] = []
        do {
            try await withThrowingTaskGroup(of: ImageRequestOutcome.self) { group in
                var next = 0
                func admit() {
                    let request = requests[next]
                    next += 1
                    group.addTask {
                        let watch = Stopwatch()
                        do {
                            let result = try await pipeline.thumbnail(for: request)
                            switch result {
                            case .available(let thumbnail):
                                guard let bytes = decodedBytes(thumbnail.image), bytes > 0 else {
                                    return .failed(watch.milliseconds, "No materialized pixels.")
                                }
                                return .success(watch.milliseconds, bytes)
                            case .unavailable(let reason):
                                return .failed(watch.milliseconds, reason.rawValue)
                            }
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            return .failed(watch.milliseconds, String(describing: error))
                        }
                    }
                }
                for _ in 0..<min(max(1, inFlight), requests.count) { admit() }
                while let outcome = try await group.next() {
                    outcomes.append(outcome)
                    if next < requests.count { admit() }
                }
            }
        } catch {
            await pipeline.close()
            throw error
        }
        await pipeline.close()
        let elapsed = totalWatch.milliseconds
        let successes = outcomes.filter { $0.failure == nil }
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
        let failures = outcomes.compactMap(\.failure).reduce(into: [String: Int]()) {
            $0[$1, default: 0] += 1
        }
        return ThumbnailRun(
            samples: successes.map(\.milliseconds), failures: failures,
            throughput: Double(successes.count) * 1_000 / max(elapsed, 0.001),
            attempted: outcomes.count,
            diskEntries: files.filter { $0.pathExtension == "jpg" }.count)
    }

    private static func append(
        _ run: ThumbnailRun, cache: String,
        report: inout BrowsingPerformanceReportBuilder
    ) {
        report.distribution(
            "thumbnail", cache: cache, samples: run.samples,
            failureCount: run.failures.values.reduce(0, +))
        report.failureReasons("thumbnail", cache: cache, reasons: run.failures)
        report.value(
            "thumbnail-throughput", value: run.throughput, unit: "photos/s",
            tags: [
                "cache": cache, "sampleCount": String(run.samples.count),
                "attempted": String(run.attempted), "workers": "4",
            ])
        report.value(
            "thumbnail-disk-entries", value: Double(run.diskEntries), unit: "count",
            tags: ["cache": cache])
    }

    private static func thumbnailRequest(set: ScannedPhotoSet) throws -> ThumbnailRequest {
        let source = set.photoSet.primary.url
        return ThumbnailRequest(
            source: source, revision: try ThumbnailRevision.read(from: source), targetPixels: 400,
            locationIdentity: BrowsingPerformanceScan.folderID.rawValue)
    }

    private static func detailRequest(
        set: ScannedPhotoSet, configuration: BrowsingPerformanceConfiguration, native: Bool
    ) throws -> DetailRequest {
        let photo = set.photoSet
        var raw: DetailSource?
        var jpeg: DetailSource?
        var heif: DetailSource?
        switch photo.primary.format {
        case .raw:
            raw = try DetailSource.read(photo.primary.url)
            jpeg = try photo.jpegCompanion.map { try DetailSource.read($0.url) }
            heif = try photo.heifCompanion.map { try DetailSource.read($0.url) }
        case .jpeg:
            jpeg = try DetailSource.read(photo.primary.url)
            heif = try photo.heifCompanion.map { try DetailSource.read($0.url) }
        case .heif:
            heif = try DetailSource.read(photo.primary.url)
        }
        return DetailRequest(
            raw: raw, jpeg: jpeg, heif: heif,
            displayPixels: configuration.displayPixels, wantsNativeResolution: native,
            locationIdentity: BrowsingPerformanceScan.folderID.rawValue, mode: .rawFirst,
            screenPixels: configuration.displayPixels)
    }

    private static func failureReason(_ result: DetailResult) -> String {
        guard case .unavailable(let reason) = result else { return "No materialized pixels." }
        return reason.rawValue
    }

    private static func decodedBytes(_ result: DetailResult) -> Int? {
        guard case .available(let image) = result else { return nil }
        return decodedBytes(image.image)
    }

    private static func decodedBytes(_ image: CGImage) -> Int? {
        guard let data = image.dataProvider?.data, CFDataGetLength(data) > 0 else { return nil }
        return image.bytesPerRow * image.height
    }
}
