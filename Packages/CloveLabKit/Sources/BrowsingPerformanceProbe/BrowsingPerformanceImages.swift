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
                let elapsed = watch.milliseconds
                if decodedBytes(result) != nil {
                    cold.append(elapsed)
                } else {
                    coldFailures[failureReason(result), default: 0] += 1
                }
            }
            for request in requests {
                try Task.checkCancellation()
                let watch = Stopwatch()
                let result = try await pipeline.preview(for: request)
                let elapsed = watch.milliseconds
                if decodedBytes(result) != nil {
                    warm.append(elapsed)
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
            failureCount: coldFailures.values.reduce(0, +),
            extraTags: ["displayPixels": String(configuration.displayPixels)])
        report.failureReasons(
            "detail-first-preview", cache: "cold", reasons: coldFailures,
            extraTags: ["displayPixels": String(configuration.displayPixels)])
        report.distribution(
            "detail-first-preview", cache: "warm", samples: warm,
            failureCount: warmFailures.values.reduce(0, +),
            extraTags: ["displayPixels": String(configuration.displayPixels)])
        report.failureReasons(
            "detail-first-preview", cache: "warm", reasons: warmFailures,
            extraTags: ["displayPixels": String(configuration.displayPixels)])

        try await measureDetailScreen(sets: sets, configuration: configuration, report: &report)
        try await measureRAWFocus(sets: sets, configuration: configuration, report: &report)
        try await measureMultiFormatDetails(
            sets: sets, configuration: configuration, report: &report)
    }

    private static func measureDetailScreen(
        sets: [ScannedPhotoSet], configuration: BrowsingPerformanceConfiguration,
        report: inout BrowsingPerformanceReportBuilder
    ) async throws {
        let rawSets = sets.filter { $0.photoSet.primary.format == .raw }
            .prefix(configuration.detailSampleLimit)
        let requests = try rawSets.map {
            try detailRequest(set: $0, configuration: configuration, native: false)
        }
        guard !requests.isEmpty else {
            report.unavailable(
                "detail-screen",
                reason: "The folder has no RAW photos for screenRAW measurement.")
            return
        }
        let pipeline = DetailPipeline()
        var cold: [Double] = []
        var coldFailures: [String: Int] = [:]
        var warm: [Double] = []
        var warmFailures: [String: Int] = [:]
        do {
            for request in requests {
                try Task.checkCancellation()
                // Warm preview first so DetailNativeSizeReader is populated, matching real arrival.
                _ = try await pipeline.preview(for: request)
                let watch = Stopwatch()
                let result = try await pipeline.screen(for: request)
                let elapsed = watch.milliseconds
                if screenRAWBytes(result) != nil {
                    cold.append(elapsed)
                } else {
                    coldFailures[screenFailureReason(result), default: 0] += 1
                }
            }
            for request in requests {
                try Task.checkCancellation()
                let watch = Stopwatch()
                let result = try await pipeline.screen(for: request)
                let elapsed = watch.milliseconds
                if screenRAWBytes(result) != nil {
                    warm.append(elapsed)
                } else {
                    warmFailures[screenFailureReason(result), default: 0] += 1
                }
            }
        } catch {
            await pipeline.close()
            throw error
        }
        await pipeline.close()
        let extraTags = ["screenPixels": String(configuration.screenPixels)]
        report.distribution(
            "detail-screen", cache: "cold", samples: cold,
            failureCount: coldFailures.values.reduce(0, +), extraTags: extraTags)
        report.failureReasons(
            "detail-screen", cache: "cold", reasons: coldFailures, extraTags: extraTags)
        report.distribution(
            "detail-screen", cache: "warm", samples: warm,
            failureCount: warmFailures.values.reduce(0, +), extraTags: extraTags)
        report.failureReasons(
            "detail-screen", cache: "warm", reasons: warmFailures, extraTags: extraTags)
    }

    private static func measureMultiFormatDetails(
        sets: [ScannedPhotoSet], configuration: BrowsingPerformanceConfiguration,
        report: inout BrowsingPerformanceReportBuilder
    ) async throws {
        guard configuration.detailFormatLimit > 0, configuration.detailFormatRepetitions > 0 else {
            return
        }
        let formatFolder = configuration.detailFormatFolder ?? Fixtures.set("formats")
        let folderSets: [ScannedPhotoSet]
        if let formatFolder {
            folderSets = try await scanSets(
                in: formatFolder, folderID: FolderIdentity(rawValue: "clove.lab.detail-formats"))
        } else {
            folderSets = sets
        }
        let orderedRAW = orderedFormatRAWSets(folderSets)
        let selectedSets = Array(orderedRAW.prefix(configuration.detailFormatLimit))
        report.context["detailFormatFolder"] =
            formatFolder?.lastPathComponent
            ?? sets.first?.photoSet.primary.url.deletingLastPathComponent().lastPathComponent
            ?? "none"
        report.context["detailFormatSampleCount"] = String(selectedSets.count)

        guard !selectedSets.isEmpty else {
            report.unavailable(
                "detail-20mp-raw",
                reason: "No RAW fixtures were found for multi-format detail benchmarks.")
            return
        }

        let repetitions = configuration.detailFormatRepetitions
        let includeWarmup = repetitions > 1
        var twentyPlusSets: [ScannedPhotoSet] = []
        var twentyPlusPreviewCold: [Double] = []
        var twentyPlusPreviewWarm: [Double] = []
        var twentyPlusScreenCold: [Double] = []
        var twentyPlusScreenWarm: [Double] = []
        var twentyPlusNativeCold: [Double] = []
        var twentyPlusNativeWarm: [Double] = []
        var twentyPlusPreviewColdFailures: [String: Int] = [:]
        var twentyPlusPreviewWarmFailures: [String: Int] = [:]
        var twentyPlusScreenColdFailures: [String: Int] = [:]
        var twentyPlusScreenWarmFailures: [String: Int] = [:]
        var twentyPlusNativeColdFailures: [String: Int] = [:]
        var twentyPlusNativeWarmFailures: [String: Int] = [:]

        for set in selectedSets {
            try Task.checkCancellation()
            let folderID = FolderIdentity(rawValue: "clove.lab.detail-formats")
            let previewReq = try detailRequest(
                set: set, configuration: configuration, native: false,
                locationIdentity: folderID.rawValue)
            let nativeReq = try detailRequest(
                set: set, configuration: configuration, native: true,
                locationIdentity: folderID.rawValue)

            var previewCold: [Double] = []
            var previewWarm: [Double] = []
            var screenCold: [Double] = []
            var screenWarm: [Double] = []
            var nativeCold: [Double] = []
            var nativeWarm: [Double] = []
            var previewColdFailures: [String: Int] = [:]
            var previewWarmFailures: [String: Int] = [:]
            var screenColdFailures: [String: Int] = [:]
            var screenWarmFailures: [String: Int] = [:]
            var nativeColdFailures: [String: Int] = [:]
            var nativeWarmFailures: [String: Int] = [:]
            var detectedMegapixels: Double = 0

            let totalPasses = repetitions + (includeWarmup ? 1 : 0)
            for pass in 0..<totalPasses {
                try Task.checkCancellation()
                let isWarmup = includeWarmup && pass == 0
                let pipeline = DetailPipeline()
                do {
                    let previewWatch = Stopwatch()
                    let previewResult = try await pipeline.preview(for: previewReq)
                    let previewElapsed = previewWatch.milliseconds
                    let previewOK = decodedBytes(previewResult) != nil

                    let warmPreviewWatch = Stopwatch()
                    let warmPreviewResult = try await pipeline.preview(for: previewReq)
                    let warmPreviewElapsed = warmPreviewWatch.milliseconds
                    let warmPreviewOK = decodedBytes(warmPreviewResult) != nil

                    let screenWatch = Stopwatch()
                    let screenResult = try await pipeline.screen(for: previewReq)
                    let screenElapsed = screenWatch.milliseconds
                    let screenOK = screenRAWBytes(screenResult) != nil

                    let warmScreenWatch = Stopwatch()
                    let warmScreenResult = try await pipeline.screen(for: previewReq)
                    let warmScreenElapsed = warmScreenWatch.milliseconds
                    let warmScreenOK = screenRAWBytes(warmScreenResult) != nil

                    let nativeWatch = Stopwatch()
                    let nativeResult = try await pipeline.image(for: nativeReq)
                    let nativeElapsed = nativeWatch.milliseconds
                    let nativeOK = nativeRAWBytes(nativeResult) != nil
                    if nativeOK, case .available(let image) = nativeResult {
                        let mp = Double(image.image.width * image.image.height) / 1_000_000
                        if mp > detectedMegapixels { detectedMegapixels = mp }
                    }

                    let warmNativeWatch = Stopwatch()
                    let warmNativeResult = try await pipeline.image(for: nativeReq)
                    let warmNativeElapsed = warmNativeWatch.milliseconds
                    let warmNativeOK = nativeRAWBytes(warmNativeResult) != nil

                    if !isWarmup {
                        if previewOK {
                            previewCold.append(previewElapsed)
                        } else {
                            previewColdFailures[failureReason(previewResult), default: 0] += 1
                        }
                        if warmPreviewOK {
                            previewWarm.append(warmPreviewElapsed)
                        } else {
                            previewWarmFailures[failureReason(warmPreviewResult), default: 0] += 1
                        }
                        if screenOK {
                            screenCold.append(screenElapsed)
                        } else {
                            screenColdFailures[screenFailureReason(screenResult), default: 0] += 1
                        }
                        if warmScreenOK {
                            screenWarm.append(warmScreenElapsed)
                        } else {
                            screenWarmFailures[screenFailureReason(warmScreenResult), default: 0] +=
                                1
                        }
                        if nativeOK {
                            nativeCold.append(nativeElapsed)
                        } else {
                            nativeColdFailures[rawFocusFailureReason(nativeResult), default: 0] += 1
                        }
                        if warmNativeOK {
                            nativeWarm.append(warmNativeElapsed)
                        } else {
                            nativeWarmFailures[
                                rawFocusFailureReason(warmNativeResult), default: 0] += 1
                        }
                    }
                } catch {
                    await pipeline.close()
                    throw error
                }
                await pipeline.close()
            }

            let formatName = set.photoSet.primary.url.lastPathComponent
            let mpTag = String(format: "%.1f", detectedMegapixels)
            let formatTags: [String: String] = [
                "format": formatName,
                "megapixels": mpTag,
                "displayPixels": String(configuration.displayPixels),
            ]
            let screenFormatTags: [String: String] = [
                "format": formatName,
                "megapixels": mpTag,
                "screenPixels": String(configuration.screenPixels),
            ]
            let nativeFormatTags: [String: String] = [
                "format": formatName,
                "megapixels": mpTag,
            ]
            report.distribution(
                "detail-format-preview", cache: "cold", samples: previewCold,
                failureCount: previewColdFailures.values.reduce(0, +), extraTags: formatTags)
            report.distribution(
                "detail-format-preview", cache: "warm", samples: previewWarm,
                failureCount: previewWarmFailures.values.reduce(0, +), extraTags: formatTags)
            report.distribution(
                "detail-format-screen", cache: "cold", samples: screenCold,
                failureCount: screenColdFailures.values.reduce(0, +), extraTags: screenFormatTags)
            report.distribution(
                "detail-format-screen", cache: "warm", samples: screenWarm,
                failureCount: screenWarmFailures.values.reduce(0, +), extraTags: screenFormatTags)
            report.distribution(
                "detail-format-native", cache: "cold", samples: nativeCold,
                failureCount: nativeColdFailures.values.reduce(0, +), extraTags: nativeFormatTags)
            report.distribution(
                "detail-format-native", cache: "warm", samples: nativeWarm,
                failureCount: nativeWarmFailures.values.reduce(0, +), extraTags: nativeFormatTags)

            // Treat >= 19.9 MP as 20+ MP class so 5472x3648 (19.96 MP Canon R6 CR3) is included.
            if detectedMegapixels >= 19.9 {
                twentyPlusSets.append(set)
                twentyPlusPreviewCold.append(contentsOf: previewCold)
                twentyPlusPreviewWarm.append(contentsOf: previewWarm)
                twentyPlusScreenCold.append(contentsOf: screenCold)
                twentyPlusScreenWarm.append(contentsOf: screenWarm)
                twentyPlusNativeCold.append(contentsOf: nativeCold)
                twentyPlusNativeWarm.append(contentsOf: nativeWarm)
                for (k, v) in previewColdFailures {
                    twentyPlusPreviewColdFailures[k, default: 0] += v
                }
                for (k, v) in previewWarmFailures {
                    twentyPlusPreviewWarmFailures[k, default: 0] += v
                }
                for (k, v) in screenColdFailures {
                    twentyPlusScreenColdFailures[k, default: 0] += v
                }
                for (k, v) in screenWarmFailures {
                    twentyPlusScreenWarmFailures[k, default: 0] += v
                }
                for (k, v) in nativeColdFailures {
                    twentyPlusNativeColdFailures[k, default: 0] += v
                }
                for (k, v) in nativeWarmFailures {
                    twentyPlusNativeWarmFailures[k, default: 0] += v
                }
            }
        }

        report.context["detail20MPFormatCount"] = String(twentyPlusSets.count)
        guard !twentyPlusSets.isEmpty else {
            report.unavailable(
                "detail-20mp-raw",
                reason: "No 20+ MP RAW fixtures were present in the detail-formats set.")
            return
        }

        let displayTags = ["displayPixels": String(configuration.displayPixels)]
        let screenTags = ["screenPixels": String(configuration.screenPixels)]
        report.distribution(
            "detail-20mp-preview", cache: "cold", samples: twentyPlusPreviewCold,
            failureCount: twentyPlusPreviewColdFailures.values.reduce(0, +),
            extraTags: displayTags)
        report.distribution(
            "detail-20mp-preview", cache: "warm", samples: twentyPlusPreviewWarm,
            failureCount: twentyPlusPreviewWarmFailures.values.reduce(0, +),
            extraTags: displayTags)
        report.distribution(
            "detail-20mp-screen", cache: "cold", samples: twentyPlusScreenCold,
            failureCount: twentyPlusScreenColdFailures.values.reduce(0, +),
            extraTags: screenTags)
        report.distribution(
            "detail-20mp-screen", cache: "warm", samples: twentyPlusScreenWarm,
            failureCount: twentyPlusScreenWarmFailures.values.reduce(0, +),
            extraTags: screenTags)
        report.distribution(
            "detail-20mp-native", cache: "cold", samples: twentyPlusNativeCold,
            failureCount: twentyPlusNativeColdFailures.values.reduce(0, +))
        report.distribution(
            "detail-20mp-native", cache: "warm", samples: twentyPlusNativeWarm,
            failureCount: twentyPlusNativeWarmFailures.values.reduce(0, +))

        if twentyPlusSets.count >= 2 {
            try await measureRAWFocusSeries(
                rawSets: twentyPlusSets, prefix: "raw-focus-20mp",
                limit: configuration.rawSampleLimit, configuration: configuration,
                locationIdentity: "clove.lab.detail-formats", report: &report)
        }
    }

    private static func orderedFormatRAWSets(_ sets: [ScannedPhotoSet]) -> [ScannedPhotoSet] {
        let priority: [String: Int] = [
            "sony-ilce-7s.ARW": 0,
            "canon-eos-r6.CR3": 1,
            "nikon-d500.NEF": 2,
            "olympus-e-m1markii.ORF": 3,
            "fujifilm-x-s10.RAF": 4,
            "apple-iphone-12-pro.DNG": 5,
            "pentax-k-5-ii-s.DNG": 6,
            "panasonic-dmc-gh4.RW2": 7,
        ]
        return sets.filter { $0.photoSet.primary.format == .raw }.sorted { lhs, rhs in
            let lName = lhs.photoSet.primary.url.lastPathComponent
            let rName = rhs.photoSet.primary.url.lastPathComponent
            let lRank = priority[lName] ?? Int.max
            let rRank = priority[rName] ?? Int.max
            if lRank != rRank { return lRank < rRank }
            return lName < rName
        }
    }

    private static func scanSets(
        in folder: URL, folderID: FolderIdentity
    ) async throws -> [ScannedPhotoSet] {
        let scan = FolderScan(folderURL: folder, folderID: folderID)
        var sets: [ScannedPhotoSet] = []
        do {
            for try await batch in scan {
                for item in batch.items {
                    if case .photo(let set) = item {
                        sets.append(set)
                    }
                }
            }
            _ = try await scan.summary()
            return sets
        } catch {
            scan.cancel()
            _ = try? await scan.summary()
            throw error
        }
    }

    private static func measureRAWFocus(
        sets: [ScannedPhotoSet], configuration: BrowsingPerformanceConfiguration,
        report: inout BrowsingPerformanceReportBuilder
    ) async throws {
        let rawSets = sets.filter { $0.photoSet.primary.format == .raw }
        try await measureRAWFocusSeries(
            rawSets: rawSets, prefix: "raw-focus", limit: configuration.rawSampleLimit,
            configuration: configuration,
            locationIdentity: BrowsingPerformanceScan.folderID.rawValue, report: &report)
    }

    private struct CancelNextOutcome: Sendable {
        let drainMilliseconds: Double
        let cancelObserved: Bool
        let secondMilliseconds: Double
        let secondSucceeded: Bool
        let secondFailureReason: String?
        let warmMilliseconds: Double
        let warmSucceeded: Bool
        let warmFailureReason: String?
    }

    private static func measureRAWFocusSeries(
        rawSets: [ScannedPhotoSet], prefix: String, limit: Int,
        configuration: BrowsingPerformanceConfiguration, locationIdentity: String,
        report: inout BrowsingPerformanceReportBuilder
    ) async throws {
        var raw: [Double] = []
        var includingCancel: [Double] = []
        var cancelDrain: [Double] = []
        var warm: [Double] = []
        var failures: [String: Int] = [:]
        var warmFailures: [String: Int] = [:]
        var combinedFailures: [String: Int] = [:]
        var cancelNotObserved = 0
        var pairsMeasured = 0
        for index in stride(from: 0, to: rawSets.count - 1, by: 2) {
            guard pairsMeasured < limit else { break }
            try Task.checkCancellation()
            let first = try detailRequest(
                set: rawSets[index], configuration: configuration, native: true,
                locationIdentity: locationIdentity)
            let second = try detailRequest(
                set: rawSets[index + 1], configuration: configuration, native: true,
                locationIdentity: locationIdentity)
            let outcome = try await measureCancelNextPair(first: first, second: second)
            if outcome.secondSucceeded {
                raw.append(outcome.secondMilliseconds)
            } else if let reason = outcome.secondFailureReason {
                failures[reason, default: 0] += 1
            }
            if outcome.cancelObserved {
                // The first render's drain is valid independently of the next render.
                cancelDrain.append(outcome.drainMilliseconds)
                if outcome.secondSucceeded {
                    includingCancel.append(outcome.drainMilliseconds + outcome.secondMilliseconds)
                } else if let reason = outcome.secondFailureReason {
                    combinedFailures["Second native render: \(reason)", default: 0] += 1
                }
            } else {
                cancelNotObserved += 1
                combinedFailures[
                    "Native render admission or cancellation was not observed", default: 0] += 1
            }
            if outcome.secondSucceeded {
                if outcome.warmSucceeded {
                    warm.append(outcome.warmMilliseconds)
                } else if let reason = outcome.warmFailureReason {
                    warmFailures[reason, default: 0] += 1
                }
            }
            pairsMeasured += 1
        }
        guard pairsMeasured > 0 else {
            report.unavailable(
                prefix,
                reason: "The folder has fewer than two RAW photos for a cancel/next pair.")
            return
        }
        report.distribution(
            prefix, cache: "cold", samples: raw,
            failureCount: failures.values.reduce(0, +))
        report.failureReasons(prefix, cache: "cold", reasons: failures)
        report.distribution(
            prefix, cache: "warm", samples: warm,
            failureCount: warmFailures.values.reduce(0, +))
        report.failureReasons(prefix, cache: "warm", reasons: warmFailures)
        report.value(
            "\(prefix)-native-results", value: Double(raw.count), unit: "count",
            tags: ["attempted": String(pairsMeasured), "quality": "nativeRAW"])
        report.distribution(
            "\(prefix)-cancel-drain", cache: "cold", samples: cancelDrain,
            failureCount: cancelNotObserved)
        if cancelNotObserved > 0 {
            report.failureReasons(
                "\(prefix)-cancel-drain", cache: "cold",
                reasons: [
                    "Native render admission or cancellation was not observed": cancelNotObserved
                ])
        }
        report.distribution(
            "\(prefix)-including-cancel", cache: "cold", samples: includingCancel,
            failureCount: combinedFailures.values.reduce(0, +))
        report.failureReasons(
            "\(prefix)-including-cancel", cache: "cold", reasons: combinedFailures)
        report.value(
            "\(prefix)-cancel-observed", value: Double(cancelDrain.count), unit: "count",
            tags: ["attempted": String(pairsMeasured), "trigger": "nativeRAWRenderCount"])
    }

    private static func measureCancelNextPair(
        first: DetailRequest, second: DetailRequest
    ) async throws -> CancelNextOutcome {
        let firstPipeline = DetailPipeline()
        let firstTask = Task { try await firstPipeline.image(for: first) }
        let admissionWatch = Stopwatch()
        let initialNativeCount = await firstPipeline.nativeRAWRenderCount
        var nativeStarted = false
        do {
            while !nativeStarted && admissionWatch.seconds < 5 {
                try Task.checkCancellation()
                nativeStarted =
                    await firstPipeline.nativeRAWRenderCount > initialNativeCount
                if !nativeStarted { await Task.yield() }
            }
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
            let secondSucceeded = nativeRAWBytes(result) != nil
            let secondFailureReason = secondSucceeded ? nil : rawFocusFailureReason(result)

            var firstWasCancelled = false
            do {
                _ = try await firstTask.value
            } catch is CancellationError {
                firstWasCancelled = true
            } catch {
                // A failed first render did not establish a cancelled-render wait.
            }

            var warmElapsed: Double = 0
            var warmSucceeded = false
            var warmFailureReason: String?
            if secondSucceeded {
                let warmWatch = Stopwatch()
                let cached = try await secondPipeline.image(for: second)
                warmElapsed = warmWatch.milliseconds
                warmSucceeded = nativeRAWBytes(cached) != nil
                if !warmSucceeded {
                    warmFailureReason = rawFocusFailureReason(cached)
                }
            }
            await secondPipeline.close()
            return CancelNextOutcome(
                drainMilliseconds: drainMilliseconds,
                cancelObserved: nativeStarted && firstWasCancelled,
                secondMilliseconds: elapsed,
                secondSucceeded: secondSucceeded,
                secondFailureReason: secondFailureReason,
                warmMilliseconds: warmElapsed,
                warmSucceeded: warmSucceeded,
                warmFailureReason: warmFailureReason)
        } catch {
            await secondPipeline.close()
            throw error
        }
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
                            let elapsed = watch.milliseconds
                            switch result {
                            case .available(let thumbnail):
                                guard let bytes = decodedBytes(thumbnail.image), bytes > 0 else {
                                    return .failed(elapsed, "No materialized pixels.")
                                }
                                return .success(elapsed, bytes)
                            case .unavailable(let reason):
                                return .failed(elapsed, reason.rawValue)
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
        set: ScannedPhotoSet, configuration: BrowsingPerformanceConfiguration, native: Bool,
        locationIdentity: String = BrowsingPerformanceScan.folderID.rawValue
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
            locationIdentity: locationIdentity, mode: .rawFirst,
            screenPixels: configuration.screenPixels)
    }

    private static func failureReason(_ result: DetailResult) -> String {
        guard case .unavailable(let reason) = result else { return "No materialized pixels." }
        return reason.rawValue
    }

    private static func screenRAWBytes(_ result: DetailResult) -> Int? {
        guard case .available(let image) = result,
            image.quality == .screenRAW, image.limitation != .rawRenderFailed
        else { return nil }
        return decodedBytes(image.image)
    }

    private static func screenFailureReason(_ result: DetailResult) -> String {
        guard case .available(let image) = result else { return failureReason(result) }
        if image.limitation == .rawRenderFailed { return DetailLimitation.rawRenderFailed.rawValue }
        if image.quality != .screenRAW {
            return "Expected screenRAW, got \(image.quality.rawValue)"
        }
        return "No materialized screen RAW pixels."
    }

    private static func nativeRAWBytes(_ result: DetailResult) -> Int? {
        guard case .available(let image) = result,
            image.quality == .nativeRAW, image.limitation != .rawRenderFailed
        else { return nil }
        return decodedBytes(image.image)
    }

    private static func rawFocusFailureReason(_ result: DetailResult) -> String {
        guard case .available(let image) = result else { return failureReason(result) }
        if image.limitation == .rawRenderFailed { return DetailLimitation.rawRenderFailed.rawValue }
        if image.quality != .nativeRAW {
            return "Expected nativeRAW, got \(image.quality.rawValue)"
        }
        return "No materialized native RAW pixels."
    }

    private static func decodedBytes(_ result: DetailResult) -> Int? {
        guard case .available(let image) = result else { return nil }
        return decodedBytes(image.image)
    }

    private static func decodedBytes(_ image: CGImage) -> Int? {
        guard image.width > 0, image.height > 0, image.bytesPerRow > 0 else { return nil }
        return image.bytesPerRow * image.height
    }
}
