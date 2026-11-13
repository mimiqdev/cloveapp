import CloveCore
import CloveImaging
import Foundation
import LabSupport

struct BrowsingScanResult: Sendable {
    let sets: [ScannedPhotoSet]
    let groupingPhotos: [GroupingPhoto]
    let imageFileCount: Int
    let status: ScanStatus
}

enum BrowsingPerformanceScan {
    static let folderID = FolderIdentity(rawValue: "clove.lab.browsing-performance")

    static func measure(
        folder: URL, configuration: BrowsingPerformanceConfiguration,
        report: inout BrowsingPerformanceReportBuilder
    ) async throws -> BrowsingScanResult {
        let cold = try await scan(folder: folder)
        report.distribution("scan-first-photos", cache: "cold", samples: [cold.firstPhotos])
        report.distribution("scan-complete", cache: "cold", samples: [cold.total])

        var warm: [Double] = []
        var warmFirst: [Double] = []
        for _ in 0..<configuration.warmScanRepetitions {
            try Task.checkCancellation()
            let pass = try await scan(folder: folder)
            warm.append(pass.total)
            warmFirst.append(pass.firstPhotos)
        }
        report.distribution("scan-first-photos", cache: "warm", samples: warmFirst)
        report.distribution("scan-complete", cache: "warm", samples: warm)

        let sets = cold.sets
        let imageFileCount = sets.reduce(0) { $0 + $1.imageFiles.count }
        report.context["actualPhotoCount"] = String(sets.count)
        report.context["actualImageFileCount"] = String(imageFileCount)
        report.context["scanStatus"] = cold.summary.status.rawValue
        report.value(
            "scan-image-files", value: Double(imageFileCount), unit: "count",
            tags: ["cache": "cold"])
        report.value(
            "scan-ambiguous-items", value: Double(cold.summary.ambiguousCount), unit: "count",
            tags: ["cache": "cold"])
        if cold.summary.status != .complete {
            report.unavailable(
                "scan-complete-folder", cache: "cold",
                reason:
                    "\(cold.summary.issues.count) folder or file read issue(s); the scan is partial."
            )
        }

        let reader = MetadataReader()
        var serialSamples: [Double] = []
        var serialFailures = 0
        var serialFailureReasons: [String: Int] = [:]
        for set in sets.prefix(configuration.metadataSampleLimit) {
            try Task.checkCancellation()
            let watch = Stopwatch()
            let result = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: reader.read(url: set.photoSet.primary.url))
                }
            }
            if case .success = result.outcome {
                serialSamples.append(watch.milliseconds)
            } else {
                serialFailures += 1
                if case .failure(let reason) = result.outcome {
                    serialFailureReasons[String(describing: reason), default: 0] += 1
                }
            }
        }
        report.distribution(
            "capture-time-read", cache: "cold", samples: serialSamples,
            failureCount: serialFailures)
        report.failureReasons(
            "capture-time-read", cache: "cold", reasons: serialFailureReasons)

        var groupingByIdentity: [PhotoIdentity: GroupingPhoto] = [:]
        var batchSamples: [Double] = []
        var metadataFailures = 0
        for start in stride(from: 0, to: sets.count, by: ScanConfiguration().batchSize) {
            try Task.checkCancellation()
            let batch = Array(sets[start..<min(start + ScanConfiguration().batchSize, sets.count)])
            let watch = Stopwatch()
            let reads = await reader.read(urls: batch.map { $0.photoSet.primary.url })
            batchSamples.append(watch.milliseconds)
            for (set, read) in zip(batch, reads) {
                if case .failure = read.outcome { metadataFailures += 1 }
                groupingByIdentity[set.id] = groupingPhoto(set: set, read: read)
            }
        }
        report.distribution("capture-time-batch", cache: "warm", samples: batchSamples)
        report.value(
            "capture-time-failure-count", value: Double(metadataFailures), unit: "count",
            tags: ["cache": "warm", "basis": "individual metadata reads in the batches"])
        report.value(
            "capture-time-total", value: batchSamples.reduce(0, +), unit: "ms",
            tags: ["cache": "warm", "batchSize": String(ScanConfiguration().batchSize)])

        let groupingPhotos = sets.compactMap { groupingByIdentity[$0.id] }
        if groupingPhotos.count != sets.count {
            report.unavailable(
                "grouping-input",
                reason: "Metadata results were missing for one or more scanned photos.")
        }
        return BrowsingScanResult(
            sets: sets, groupingPhotos: groupingPhotos, imageFileCount: imageFileCount,
            status: cold.summary.status)
    }

    private struct ScanPass: Sendable {
        let firstPhotos: Double
        let total: Double
        let sets: [ScannedPhotoSet]
        let summary: ScanSummary
    }

    private static func scan(folder: URL) async throws -> ScanPass {
        let scan = FolderScan(folderURL: folder, folderID: folderID)
        let watch = Stopwatch()
        var firstPhotos: Double?
        var sets: [ScannedPhotoSet] = []
        for try await batch in scan {
            for item in batch.items {
                guard case .photo(let set) = item else { continue }
                if firstPhotos == nil { firstPhotos = watch.milliseconds }
                sets.append(set)
            }
        }
        let summary = try await scan.summary()
        guard let firstPhotos else {
            throw BrowsingPerformanceError.noPhotos
        }
        return ScanPass(
            firstPhotos: firstPhotos, total: watch.milliseconds, sets: sets, summary: summary)
    }

    private static func groupingPhoto(
        set: ScannedPhotoSet, read: MetadataFileResult
    ) -> GroupingPhoto {
        var time = PhotoTimeState.unavailable
        var body: CameraBody?
        if case .success(let metadata) = read.outcome {
            switch metadata.time {
            case .captureMetadata(let capture):
                time = .known(
                    PhotoTime(
                        captureWallTime: capture.wallTime,
                        utcOffsetSeconds: capture.utcOffsetSeconds, in: .current))
            case .fileCreation(let date): time = .known(PhotoTime(fileCreation: date))
            case .fileModification(let date): time = .known(PhotoTime(fileModification: date))
            case .unavailable: break
            }
            body = CameraBody(model: metadata.model.value, serial: metadata.bodySerial.value)
        }
        return GroupingPhoto(
            id: set.id, fileName: set.photoSet.primary.url.lastPathComponent, time: time,
            body: body)
    }
}
