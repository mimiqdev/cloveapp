import CloveCore
import CloveImaging
import Foundation
import LabSupport

enum BrowsingPerformanceGrouping {
    static func measure(
        sets: [ScannedPhotoSet], photos: [GroupingPhoto],
        configuration: BrowsingPerformanceConfiguration,
        cacheRoot: URL, report: inout BrowsingPerformanceReportBuilder
    ) async throws {
        let candidates = GroupingFeatureCandidates.photos(in: photos)
        let setsByIdentity = Dictionary(uniqueKeysWithValues: sets.map { ($0.id, $0) })
        let requests = try candidates.map { photo -> ImageFeatureRequest in
            guard let set = setsByIdentity[photo.id] else {
                throw BrowsingPerformanceError.noPhotos
            }
            let source = set.photoSet.primary.url
            return ImageFeatureRequest(
                source: source, revision: try ThumbnailRevision.read(from: source),
                locationIdentity: BrowsingPerformanceScan.folderID.rawValue)
        }
        let photoByRequest = Dictionary(uniqueKeysWithValues: zip(requests, candidates.map(\.id)))
        report.value(
            "grouping-candidates", value: Double(candidates.count), unit: "count",
            tags: ["photoCount": String(photos.count)])
        try await measureFeatureLatency(
            requests: Array(requests.prefix(configuration.featureSampleLimit)),
            cacheRoot: cacheRoot, report: &report)

        let similarity = PhotoFeatureSimilarity<ImageFeatures> { left, right in
            switch left.distance(to: right) {
            case .visionPrint(let distance)?: .vision(distance: Float(distance))
            case .differenceHash(let bits)?: .differenceHash(distance: bits)
            case nil: nil
            }
        }
        let groupCache = SimilarGroupsCache(
            directory: cacheRoot.appendingPathComponent("groups", isDirectory: true))
        let grouping = SimilarGrouping(similarity: similarity, cache: groupCache)
        let revision = GroupingInputRevision.scanned(sets, feature: "preview:400|feature:2")
        let totalWatch = Stopwatch()
        let timeWatch = Stopwatch()
        await grouping.run(photos: photos, revision: revision, reuseCache: true)
        let timeMilliseconds = timeWatch.milliseconds
        report.distribution("grouping-time-stage", cache: "cold", samples: [timeMilliseconds])

        await similarity.start(photos: candidates.map(\.id))
        let featureResult = try await runFeatures(
            requests: requests, directory: cacheRoot.appendingPathComponent("features-cold"),
            thumbnailDirectory: cacheRoot.appendingPathComponent("feature-thumbnails-cold"),
            memoryBytes: 64 * 1_024 * 1_024, similarity: similarity,
            photoByRequest: photoByRequest)
        report.distribution(
            "grouping-feature-completion", cache: "cold", samples: featureResult.samples,
            failureCount: featureResult.failures.values.reduce(0, +))
        report.failureReasons(
            "grouping-feature-completion", cache: "cold", reasons: featureResult.failures)
        report.value(
            "grouping-feature-throughput", value: featureResult.throughput, unit: "photos/s",
            tags: ["cache": "cold", "sampleCount": String(featureResult.samples.count)])

        let refineWatch = Stopwatch()
        await grouping.refine()
        report.distribution(
            "grouping-refine", cache: "cold", samples: [refineWatch.milliseconds])
        let coldGroups = await grouping.current
        report.distribution("grouping-total", cache: "cold", samples: [totalWatch.milliseconds])
        report.value(
            "grouping-groups", value: Double(coldGroups.groups.count), unit: "count",
            tags: ["cache": "cold", "analysis": coldGroups.analysis.description])
        report.context["visionStatus"] = featureResult.visionStatus

        // Diagnostic disk-warm feature pass. A warm app open normally uses the finished group
        // cache below and does not request these features again.
        let diskFeatures = try await runFeatures(
            requests: requests, directory: cacheRoot.appendingPathComponent("features-cold"),
            thumbnailDirectory: cacheRoot.appendingPathComponent("feature-thumbnails-cold"),
            memoryBytes: 0, similarity: nil, photoByRequest: photoByRequest)
        report.distribution(
            "grouping-feature-completion", cache: "disk", samples: diskFeatures.samples,
            failureCount: diskFeatures.failures.values.reduce(0, +))
        report.failureReasons(
            "grouping-feature-completion", cache: "disk", reasons: diskFeatures.failures)
        report.value(
            "grouping-feature-throughput", value: diskFeatures.throughput, unit: "photos/s",
            tags: ["cache": "disk", "sampleCount": String(diskFeatures.samples.count)])

        let warmGrouping = SimilarGrouping(similarity: similarity, cache: groupCache)
        let warmWatch = Stopwatch()
        await warmGrouping.run(photos: photos, revision: revision, reuseCache: true)
        let warmMilliseconds = warmWatch.milliseconds
        let warmGroups = await warmGrouping.current
        report.distribution("grouping-time-stage", cache: "warm", samples: [warmMilliseconds])
        report.distribution("grouping-total", cache: "warm", samples: [warmMilliseconds])
        let warmCacheHit = candidates.count > 1 && warmGroups.analysis == .analyzed
        report.value(
            "grouping-cache-hit", value: warmCacheHit ? 1 : 0, unit: "count",
            tags: ["cache": "warm", "analysis": warmGroups.analysis.description])
        if !warmCacheHit {
            report.unavailable(
                "grouping-cache-hit", cache: "warm",
                reason: "The persisted analyzed grouping was not available on the warm run.")
        }
    }

    private struct FeatureRun: Sendable {
        let samples: [Double]
        let failures: [String: Int]
        let throughput: Double
        let visionStatus: String
    }

    private static func runFeatures(
        requests: [ImageFeatureRequest], directory: URL, thumbnailDirectory: URL,
        memoryBytes: Int, similarity: PhotoFeatureSimilarity<ImageFeatures>?,
        photoByRequest: [ImageFeatureRequest: PhotoIdentity]
    ) async throws -> FeatureRun {
        var featureConfiguration = ImageFeatureCache.Configuration()
        featureConfiguration.memoryBytes = memoryBytes
        let featureCache = try ImageFeatureCache(
            directory: directory, configuration: featureConfiguration)
        var thumbnailConfiguration = ThumbnailCache.Configuration()
        thumbnailConfiguration.memoryBytes = memoryBytes
        let thumbnailCache = try ThumbnailCache(
            directory: thumbnailDirectory, configuration: thumbnailConfiguration)
        let pipeline = ImageFeaturePipeline(
            cache: featureCache, sharedPreviewCache: thumbnailCache)
        let watch = Stopwatch()
        var samples: [Double] = []
        var failures: [String: Int] = [:]
        var visionCount = 0
        var hashOnlyCount = 0
        for await result in await pipeline.run(requests) {
            switch result.outcome {
            case .features(let features):
                samples.append(watch.milliseconds)
                if features.print != nil {
                    visionCount += 1
                } else if features.differenceHash != nil {
                    hashOnlyCount += 1
                }
                if let photo = photoByRequest[result.request] {
                    await similarity?.settle(.features(features), for: photo)
                }
            case .unavailable(let reason):
                failures[reason.rawValue, default: 0] += 1
                if let photo = photoByRequest[result.request] {
                    await similarity?.settle(.unavailable, for: photo)
                }
            }
        }
        await pipeline.close()
        let status = await pipeline.featurePrintStatus
        return FeatureRun(
            samples: samples, failures: failures,
            throughput: Double(samples.count) * 1_000 / max(watch.milliseconds, 0.001),
            visionStatus: describe(status, visionCount: visionCount, hashOnlyCount: hashOnlyCount))
    }

    /// One-at-a-time production feature requests, excluding the queueing seen in a folder pass.
    /// Each value includes preview reading, Vision and dHash work, and cache publication.
    private static func measureFeatureLatency(
        requests: [ImageFeatureRequest], cacheRoot: URL,
        report: inout BrowsingPerformanceReportBuilder
    ) async throws {
        let featureCache = try ImageFeatureCache(
            directory: cacheRoot.appendingPathComponent("feature-latency", isDirectory: true))
        let thumbnailCache = try ThumbnailCache(
            directory: cacheRoot.appendingPathComponent(
                "feature-latency-thumbnails", isDirectory: true))
        let pipeline = ImageFeaturePipeline(
            cache: featureCache, sharedPreviewCache: thumbnailCache)
        var samples: [Double] = []
        var failures: [String: Int] = [:]
        for request in requests {
            try Task.checkCancellation()
            let watch = Stopwatch()
            guard let result = await pipeline.features(for: request) else {
                failures["no result", default: 0] += 1
                continue
            }
            switch result.outcome {
            case .features: samples.append(watch.milliseconds)
            case .unavailable(let reason): failures[reason.rawValue, default: 0] += 1
            }
        }
        await pipeline.close()
        report.distribution(
            "feature-read-and-compute", cache: "cold", samples: samples,
            failureCount: failures.values.reduce(0, +))
        report.failureReasons("feature-read-and-compute", cache: "cold", reasons: failures)
    }

    private static func describe(
        _ status: FeaturePrintStatus, visionCount: Int, hashOnlyCount: Int
    ) -> String {
        let base: String
        switch status {
        case .available: base = "available"
        case .failing(let failure): base = "failing: \(failure)"
        case .givenUp(let failure, let count):
            base = "given up after \(count) failures: \(failure)"
        }
        return "\(base); vision=\(visionCount), hashOnly=\(hashOnlyCount)"
    }
}

extension GroupAnalysis {
    fileprivate var description: String {
        switch self {
        case .off: "off"
        case .timeOnly: "timeOnly"
        case .refining(let decided, let total): "refining-\(decided)-of-\(total)"
        case .analyzed: "analyzed"
        }
    }
}
