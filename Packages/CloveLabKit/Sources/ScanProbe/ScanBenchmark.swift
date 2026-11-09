import Foundation
import LabSupport

/// Progress for the Clove Lab status line.
public struct ScanProgress: Sendable, Hashable {
    /// Steps finished.
    public var completed: Int
    /// Steps the suite runs.
    public var total: Int
    /// What is running now.
    public var message: String

    public init(completed: Int, total: Int, message: String) {
        self.completed = completed
        self.total = total
        self.message = message
    }
}

/// Runs the Scan comparison: three listing methods, every key set, three passes,
/// pairing, the rejects-folder variants, and streamed batches.
///
/// All times are one observation per cell, with no percentile. The first pass is
/// the first touch of the tree in this process; the OS caches were not flushed,
/// because iOS and macOS offer no unprivileged way to do that.
public enum ScanBenchmark {
    /// Passes over the whole matrix.
    public static let defaultRepetitions = 3

    /// Files per streamed batch, matching a grid page.
    public static let defaultBatchSize = 64

    /// Measures `folder` and returns the report Clove Lab exports.
    ///
    /// - Parameters:
    ///   - folder: Root of the generated tree, or a camera folder on a card.
    ///   - options: Filters and rejects folder name.
    ///   - repetitions: Passes over the matrix; the suite uses three.
    ///   - progress: Called before each step, for the status line.
    public static func run(
        folder: URL,
        options: ScanOptions = ScanOptions(),
        repetitions: Int = ScanBenchmark.defaultRepetitions,
        progress: @Sendable (ScanProgress) async -> Void = { _ in }
    ) async throws -> LabReport {
        let repetitions = max(1, repetitions)
        let methods = ScanMethod.allCases
        let keySets = ScanKeySet.allCases
        let perPass =
            methods.count * keySets.count + methods.count * 4  // pairing, rejects, lazy, stream
        let total = perPass * repetitions
        var completed = 0
        var measurements: [LabMeasurement] = []

        for pass in 1...repetitions {
            // Rotate the method order so the first touch of the tree is not
            // always paid by the same method.
            let offset = (pass - 1) % methods.count
            var order = Array(methods[offset...])
            order.append(contentsOf: methods[..<offset])
            var namesElapsed: [ScanMethod: Double] = [:]
            var allEntries: [ScanMethod: [ScanEntry]] = [:]
            for method in order {
                for keySet in keySets {
                    try Task.checkCancellation()
                    await progress(
                        .init(
                            completed: completed, total: total,
                            message: "Pass \(pass)/\(repetitions): \(method.displayName), "
                                + keySet.rawValue))
                    let start = ContinuousClock.now
                    let listing = try ScanLister.list(
                        folder: folder, method: method, keySet: keySet, options: options)
                    let elapsed = ScanClock.milliseconds(from: start)
                    var tags = baseTags(method: method, pass: pass)
                    tags["keys"] = keySet.rawValue
                    tags["mode"] = "skip-rejected"
                    if keySet == .names { namesElapsed[method] = elapsed }
                    if keySet == .all { allEntries[method] = listing.entries }
                    measurements += scanMeasurements(
                        listing, elapsed: elapsed, tags: tags, includeCounts: pass == 1)
                    completed += 1
                }

                if let entries = allEntries[method] {
                    try Task.checkCancellation()
                    await progress(
                        .init(
                            completed: completed, total: total,
                            message: "Pass \(pass)/\(repetitions): pairing, \(method.displayName)"))
                    measurements += pairingMeasurements(
                        entries, method: method, pass: pass)
                    completed += 1
                }

                try Task.checkCancellation()
                await progress(
                    .init(
                        completed: completed, total: total,
                        message: "Pass \(pass)/\(repetitions): rejects folder, "
                            + method.displayName))
                measurements += try rejectsMeasurements(
                    folder: folder, method: method, options: options, pass: pass)
                completed += 1

                if let names = namesElapsed[method] {
                    try Task.checkCancellation()
                    await progress(
                        .init(
                            completed: completed, total: total,
                            message: "Pass \(pass)/\(repetitions): lazy stats, "
                                + method.displayName))
                    measurements += try lazyStatMeasurements(
                        folder: folder, method: method, options: options, namesElapsed: names,
                        pass: pass)
                    completed += 1
                }

                try Task.checkCancellation()
                await progress(
                    .init(
                        completed: completed, total: total,
                        message: "Pass \(pass)/\(repetitions): streamed batches, "
                            + method.displayName))
                measurements += try await streamMeasurements(
                    folder: folder, method: method, options: options, pass: pass)
                completed += 1
            }
        }

        await progress(.init(completed: total, total: total, message: "Finished"))
        var context = ScanVolume.describe(folder)
        context["folder"] = folder.lastPathComponent
        context["repetitions"] = String(repetitions)
        context["keySets"] = keySets.map(\.rawValue).joined(separator: ",")
        context["batchSize"] = String(options.batchSize)
        context["rejectsFolder"] = options.rejectsFolderName
        context["cache"] =
            "OS caches not flushed; pass 1 is the first touch in this process and later passes are warm"
        context["ordering"] =
            "methods rotated per pass; key sets in fixed order; one observation per cell"
        return LabReport(
            spike: "S6",
            context: context,
            measurements: measurements,
            notes: notes(options: options, repetitions: repetitions))
    }

    // MARK: - Per-scan measurements

    private static func baseTags(method: ScanMethod, pass: Int) -> [String: String] {
        ["method": method.tag, "pass": String(pass)]
    }

    private static func scanMeasurements(
        _ listing: ScanListing,
        elapsed: Double,
        tags: [String: String],
        includeCounts: Bool
    ) -> [LabMeasurement] {
        var measurements: [LabMeasurement] = [
            .init(name: "list-elapsed", value: elapsed, unit: "ms", tags: tags)
        ]
        if let firstHundred = listing.firstHundredMilliseconds {
            measurements.append(
                .init(name: "first-100", value: firstHundred, unit: "ms", tags: tags))
        }
        if let firstBatch = listing.firstBatchMilliseconds {
            measurements.append(
                .init(name: "first-batch", value: firstBatch, unit: "ms", tags: tags))
        }
        guard includeCounts else { return measurements }
        let countTags = tags.filter { $0.key != "pass" }
        for (name, value) in [
            ("entries", listing.entries.count),
            ("directories", listing.directories),
            ("seen", listing.entriesSeen),
            ("skipped-hidden", listing.hiddenSkipped),
            ("skipped-unsupported", listing.unsupportedSkipped),
            ("skipped-rejects", listing.rejectedSkipped),
            ("stat-fallbacks", listing.statFallbacks),
            ("errors", listing.errors),
            ("batches", listing.batches),
        ] {
            measurements.append(
                .init(name: name, value: Double(value), unit: "count", tags: countTags))
        }
        if !listing.entries.isEmpty {
            measurements.append(
                .init(
                    name: "per-file", value: elapsed * 1_000 / Double(listing.entries.count),
                    unit: "µs", tags: countTags))
        }
        return measurements
    }

    // MARK: - Pairing

    private static func pairingMeasurements(
        _ entries: [ScanEntry],
        method: ScanMethod,
        pass: Int
    ) -> [LabMeasurement] {
        let tags = baseTags(method: method, pass: pass).merging(["keys": "all"]) { _, new in new }
        let sortStart = ContinuousClock.now
        let sorted = entries.sorted { $0.relativePath < $1.relativePath }
        let sortElapsed = ScanClock.milliseconds(from: sortStart)
        let pairingStart = ContinuousClock.now
        let photos = ScanPairing.photos(from: sorted)
        let pairingElapsed = ScanClock.milliseconds(from: pairingStart)
        let pairs = photos.filter(\.isPaired).count
        return [
            .init(name: "sort-elapsed", value: sortElapsed, unit: "ms", tags: tags),
            .init(name: "pairing-elapsed", value: pairingElapsed, unit: "ms", tags: tags),
            .init(name: "photos", value: Double(photos.count), unit: "count", tags: tags),
            .init(name: "pairs", value: Double(pairs), unit: "count", tags: tags),
            .init(name: "files", value: Double(entries.count), unit: "count", tags: tags),
        ]
    }

    // MARK: - Rejects folder and lazy stats

    private static func rejectsMeasurements(
        folder: URL,
        method: ScanMethod,
        options: ScanOptions,
        pass: Int
    ) throws -> [LabMeasurement] {
        var includeRejected = options
        includeRejected.includeRejected = true
        let start = ContinuousClock.now
        let listing = try ScanLister.list(
            folder: folder, method: method, keySet: .all, options: includeRejected)
        let scanElapsed = ScanClock.milliseconds(from: start)
        let filterStart = ContinuousClock.now
        let kept = ScanPairing.removingRejected(
            listing.entries, folderName: options.rejectsFolderName)
        let filterElapsed = ScanClock.milliseconds(from: filterStart)
        let tags = baseTags(method: method, pass: pass).merging([
            "keys": "all", "mode": "post-filter",
        ]) { _, new in new }
        return [
            .init(name: "list-elapsed", value: scanElapsed, unit: "ms", tags: tags),
            .init(name: "filter-elapsed", value: filterElapsed, unit: "ms", tags: tags),
            .init(
                name: "total-elapsed", value: scanElapsed + filterElapsed, unit: "ms", tags: tags),
            .init(
                name: "rejected-entries", value: Double(listing.entries.count - kept.count),
                unit: "count", tags: tags),
        ]
    }

    /// What the prefetched six keys cost compared with listing names and then
    /// asking for each file's values one by one.
    private static func lazyStatMeasurements(
        folder: URL,
        method: ScanMethod,
        options: ScanOptions,
        namesElapsed: Double,
        pass: Int
    ) throws -> [LabMeasurement] {
        let listing = try ScanLister.list(
            folder: folder, method: method, keySet: .names, options: options)
        let reader = ScanKeyReader(.all)
        let start = ContinuousClock.now
        var inspected = 0
        for entry in listing.entries {
            var copy = entry
            do {
                try reader.apply(to: entry.url, entry: &copy)
                inspected += 1
            } catch {
                continue
            }
        }
        let statElapsed = ScanClock.milliseconds(from: start)
        let tags = baseTags(method: method, pass: pass).merging([
            "keys": "all", "mode": "lazy-stat",
        ]) { _, new in new }
        return [
            .init(name: "stat-elapsed", value: statElapsed, unit: "ms", tags: tags),
            .init(name: "total-elapsed", value: namesElapsed + statElapsed, unit: "ms", tags: tags),
            .init(name: "stat-files", value: Double(inspected), unit: "count", tags: tags),
        ]
    }

    // MARK: - Streaming

    private static func streamMeasurements(
        folder: URL,
        method: ScanMethod,
        options: ScanOptions,
        pass: Int
    ) async throws -> [LabMeasurement] {
        let start = ContinuousClock.now
        let result = try await ScanStream.run(
            folder: folder, method: method, keySet: .all, options: options)
        let total = ScanClock.milliseconds(from: start)
        let tags = baseTags(method: method, pass: pass).merging([
            "keys": "all", "mode": "stream", "batchSize": String(options.batchSize),
        ]) { _, new in new }
        var measurements: [LabMeasurement] = [
            .init(name: "stream-total", value: total, unit: "ms", tags: tags),
            .init(
                name: "stream-batches", value: Double(result.report.batches), unit: "count",
                tags: tags),
            .init(
                name: "stream-files", value: Double(result.report.files), unit: "count",
                tags: tags),
        ]
        if let value = result.report.firstBatchProducedMilliseconds {
            measurements.append(
                .init(
                    name: "stream-first-batch", value: value, unit: "ms",
                    tags: tags))
        }
        if let value = result.report.firstBatchReceivedMilliseconds {
            measurements.append(
                .init(
                    name: "stream-first-batch-received", value: value,
                    unit: "ms", tags: tags))
        }
        if let value = result.report.lastBatchReceivedMilliseconds {
            measurements.append(
                .init(
                    name: "stream-last-batch", value: value, unit: "ms",
                    tags: tags))
        }
        if let value = result.listing.firstHundredMilliseconds {
            measurements.append(
                .init(
                    name: "stream-first-100", value: value, unit: "ms",
                    tags: tags))
        }
        return measurements
    }

    private static func notes(options: ScanOptions, repetitions: Int) -> [String] {
        [
            "Times are single observations from ContinuousClock in one process; no percentile is claimed.",
            "\(repetitions) passes rotate the method order. The first pass is the first touch of the tree in this process; the OS page cache is not flushed, because that needs admin rights on macOS and is not available on iOS.",
            "Key-set names isolate one key; the ladder adds keys one at a time and ends in all. Entries, directories, and skip counts are written on pass 1 only.",
            "first-100 is the time until the walk accepted its 100th file, in traversal order, before sorting.",
            "The rejects comparison walks the rejects folder (post-filter) and then filters by path; skip-rejected is the same scan with the folder excluded.",
            "lazy-stat lists names, then asks each file for all six keys; its total adds that to the names scan. Compare with the all-key scan.",
            "Streaming pairs inside each batch of \(options.batchSize) files, so a RAW+JPEG/HEIF pair split across two batches is not paired until the grid repairs it.",
            "Proposal for the production decision: pair a same-name RAW+HEIF in the same folder. When both JPEG and HEIF exist, keep RAW+JPEG and leave HEIF as a standalone item. JPEG preference requires complete-folder pairing or later grid repair.",
            "File content is placeholder bytes unless the tree was built with realistic sizes; a listing reads names and metadata, not pixels.",
        ]
    }
}
