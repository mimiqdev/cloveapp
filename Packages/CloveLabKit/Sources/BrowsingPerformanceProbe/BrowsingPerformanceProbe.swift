import Foundation
import LabSupport

public struct BrowsingPerformanceConfiguration: Sendable {
    public var warmScanRepetitions: Int
    public var metadataSampleLimit: Int
    public var thumbnailLimit: Int
    public var thumbnailInFlight: Int
    public var detailSampleLimit: Int
    public var rawSampleLimit: Int
    public var featureSampleLimit: Int
    public var displayPixels: Int

    public init(
        warmScanRepetitions: Int = 4, metadataSampleLimit: Int = 240,
        thumbnailLimit: Int = 2_000, thumbnailInFlight: Int = 32,
        detailSampleLimit: Int = 24, rawSampleLimit: Int = 6,
        featureSampleLimit: Int = 240, displayPixels: Int = 1_320
    ) {
        self.warmScanRepetitions = max(0, warmScanRepetitions)
        self.metadataSampleLimit = max(0, metadataSampleLimit)
        self.thumbnailLimit = max(0, thumbnailLimit)
        self.thumbnailInFlight = max(1, thumbnailInFlight)
        self.detailSampleLimit = max(0, detailSampleLimit)
        self.rawSampleLimit = max(0, rawSampleLimit)
        self.featureSampleLimit = max(0, featureSampleLimit)
        self.displayPixels = max(1, displayPixels)
    }
}

public struct BrowsingPerformanceProgress: Sendable, Equatable {
    public let completed: Int
    public let total: Int
    public let message: String

    public init(completed: Int, total: Int, message: String) {
        self.completed = completed
        self.total = total
        self.message = message
    }
}

public enum BrowsingPerformanceError: Error, Sendable {
    case noPhotos
}

/// Measures the production CloveCore and CloveImaging paths used by the current browsing flow.
/// This is deliberately a Lab driver, not a second scan, pairing, preview or grouping algorithm.
public enum BrowsingPerformanceProbe {
    public static let descriptor = ProbeDescriptor(
        id: "Q3",
        question: "How do the current browsing pipelines perform on 2,000 photos?")

    public static func run(
        folder: URL, configuration: BrowsingPerformanceConfiguration = .init(),
        app: LabApp = .current(),
        progress: @Sendable (BrowsingPerformanceProgress) async -> Void = { _ in }
    ) async throws -> LabReport {
        let sampler = LabResidentSampler()
        var report = BrowsingPerformanceReportBuilder()
        let buildIdentity = "\(app.bundleIdentifier) \(app.version) (\(app.build))"
        let hasBuildIdentity =
            !app.bundleIdentifier.isEmpty && !app.version.isEmpty
            && !app.build.isEmpty
        report.context = [
            "folder": folder.lastPathComponent,
            "buildIdentity": hasBuildIdentity
                ? buildIdentity : "unavailable: the runner has no CFBundle identity",
            "execution": "production CloveCore/CloveImaging pipelines driven by Clove Lab",
            "thumbnailWorkers": "4",
            "thumbnailInFlight": String(configuration.thumbnailInFlight),
            "detailDisplayPixels": String(configuration.displayPixels),
        ]
        if !hasBuildIdentity {
            report.unavailable(
                "build-identity",
                reason:
                    "CFBundleIdentifier, CFBundleShortVersionString and CFBundleVersion are not all available in this runner."
            )
        }
        report.notes = [
            "Measurement only. No target pass or physical-device result is inferred from another host.",
            "Cold means fresh Lab-owned cache directories and first touch in this run. iOS/macOS OS caches are not flushed; this is not a reboot-cold measurement.",
            "Disk-warm thumbnail and feature passes recreate the production caches with zero memory capacity over the cold run's disk entries. Warm detail uses its in-memory cache. Warm grouping uses the finished group cache and normally does no feature work.",
            "Percentiles are nearest-rank over successful samples. Each statistic and sample count carries the cache state; failures and unavailable stages have separate entries.",
            "Thumbnail latency includes bounded queueing behind at most \(configuration.thumbnailInFlight) in-flight requests. Throughput counts materialized successful previews over the whole pass.",
            "First detail preview uses the production raw-first request at \(configuration.displayPixels) display pixels. RAW focus cancels the first native render after 100 ms and measures the production close drain, then measures a second native render in a fresh pipeline. The combined distribution adds those two measured spans only when cancellation was observed.",
            "Memory is process RSS sampled every 5 ms. Peaks are cumulative lower bounds, not per-stage or per-allocation attribution.",
            "The generated set repeats pinned sources under unique paths. Shared capture metadata and pixels provide repeatable load, not realistic burst-grouping accuracy evidence.",
            "The measured folder and its photo files are never modified. Lab caches use a temporary directory removed after the run.",
        ]

        do {
            let identity = try FixtureIdentity.read(from: folder)
            report.context["fixtureSet"] = identity.set
            report.context["fixtureDefinitionSHA256"] = identity.definitionSHA256
            report.context["fixtureSourceSHA256"] = identity.sourceDigestJSON
            report.context["fixtureDeclaredFileCount"] = String(identity.fileCount)
        } catch {
            report.unavailable(
                "fixture-identity",
                reason:
                    "The selected folder has no readable generated .clove-fixture.json identity: \(error.localizedDescription)"
            )
        }

        await progress(.init(completed: 0, total: 6, message: "Scan and metadata"))
        var scanned: BrowsingScanResult?
        do {
            scanned = try await BrowsingPerformanceScan.measure(
                folder: folder, configuration: configuration, report: &report)
        } catch {
            try record(error, stage: "scan", report: &report)
        }
        report.memoryPeak(sampler.peak, stage: "scan")

        if let scanned {
            if let declared = report.context["fixtureDeclaredFileCount"].flatMap(Int.init) {
                let matches = declared == scanned.imageFileCount
                report.value(
                    "fixture-file-count-match", value: matches ? 1 : 0, unit: "count",
                    tags: ["declared": String(declared), "actual": String(scanned.imageFileCount)])
                if !matches {
                    report.notes.append(
                        "Fixture identity declares \(declared) files but the scan paired \(scanned.imageFileCount); regenerate the standard set before comparing runs."
                    )
                }
            }

            await progress(.init(completed: 1, total: 6, message: "Cold and disk-warm thumbnails"))
            do {
                let cacheRoot = try temporaryCacheRoot()
                defer { try? FileManager.default.removeItem(at: cacheRoot) }
                try await BrowsingPerformanceImages.measureThumbnails(
                    sets: scanned.sets, configuration: configuration, cacheRoot: cacheRoot,
                    report: &report)
                report.memoryPeak(sampler.peak, stage: "thumbnails")

                await progress(
                    .init(completed: 2, total: 6, message: "Detail previews and RAW focus"))
                do {
                    try await BrowsingPerformanceImages.measureDetails(
                        sets: scanned.sets, configuration: configuration, report: &report)
                } catch {
                    try record(error, stage: "detail-preview", report: &report)
                }
                report.memoryPeak(sampler.peak, stage: "detail")

                await progress(.init(completed: 3, total: 6, message: "Grouping and features"))
                do {
                    try await BrowsingPerformanceGrouping.measure(
                        sets: scanned.sets, photos: scanned.groupingPhotos,
                        configuration: configuration, cacheRoot: cacheRoot, report: &report)
                } catch {
                    try record(error, stage: "grouping", report: &report)
                }
                report.memoryPeak(sampler.peak, stage: "grouping")
            } catch {
                try record(error, stage: "thumbnails", report: &report)
                report.unavailable(
                    "detail-preview",
                    reason: "The temporary measurement cache could not be prepared.")
                report.unavailable(
                    "grouping", reason: "The temporary measurement cache could not be prepared.")
            }
        } else {
            report.unavailable(
                "thumbnail", reason: "No completed production scan supplied photo sets.")
            report.unavailable(
                "detail-preview", reason: "No completed production scan supplied photo sets.")
            report.unavailable(
                "grouping", reason: "No completed production scan supplied photo sets.")
        }

        report.unavailable(
            "grid-scroll-presentation",
            reason:
                "Clove Lab drives the production thumbnail pipeline without Clove's UICollectionView; decode latency is not an on-screen scroll frame-rate measurement."
        )
        report.value(
            "memory-resident-start", value: Double(sampler.baseline), unit: "bytes",
            tags: ["basis": "process RSS"])
        report.memoryPeak(sampler.finish(), stage: "overall")
        await progress(.init(completed: 6, total: 6, message: "Finished"))
        return report.report(app: app)
    }

    private static func temporaryCacheRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "clove-browsing-performance-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func record(
        _ error: any Error, stage: String,
        report: inout BrowsingPerformanceReportBuilder
    ) throws {
        if error is CancellationError { throw error }
        report.unavailable(stage, reason: String(describing: error))
    }
}
