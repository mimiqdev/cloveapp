import Foundation
import LabSupport
import Vision

public struct GroupingRun: Sendable {
    public var report: LabReport
    public var photos: [GroupingPhoto]
    public var thumbnails: [String: Data]
    public var boundaries: [GroupingBoundary]
    public var groups: [[String]]

    public func labeledReport() -> LabReport {
        var result = report
        for boundary in boundaries {
            var tags = [
                "left": boundary.left, "right": boundary.right,
                "proposedSplit": String(boundary.proposedSplit),
                "expectedSplit": boundary.expectedSplit.map(String.init) ?? "unreviewed",
            ]
            if let distance = boundary.distance { tags["distance"] = String(distance) }
            result.measurements.append(
                .init(name: "boundary", value: boundary.gap, unit: "s", tags: tags))
        }
        result.measurements += Self.sweepMeasurements(
            Grouping.sweep(boundaries), sample: "reviewed-folder")
        result.context["reviewedBoundaries"] = String(
            boundaries.filter { $0.expectedSplit != nil }.count)
        return result
    }

    static func sweepMeasurements(_ sweep: [SweepResult], sample: String) -> [LabMeasurement] {
        sweep.flatMap { row in
            let tags = [
                "sample": sample, "timeGap": String(row.timeGap), "distance": String(row.distance),
                "reviewed": String(row.reviewed),
            ]
            return [
                LabMeasurement(
                    name: "wrong-splits", value: Double(row.wrongSplits), unit: "count", tags: tags),
                LabMeasurement(
                    name: "wrong-merges", value: Double(row.wrongMerges), unit: "count", tags: tags),
            ]
        }
    }
}

public enum GroupingSuite {
    static let rasterExtensions: Set<String> = Set(["jpg", "jpeg", "png"]).union(
        PhotoExtensions.heif)
    private static let pairedExtensions: Set<String> = Set(["jpg", "jpeg"]).union(
        PhotoExtensions.heif)

    public static func files(in folder: URL) throws -> [URL] {
        let manager = FileManager.default
        var enumerationError: Error?
        guard
            let enumerator = manager.enumerator(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, error in
                    enumerationError = error; return false
                })
        else { throw CocoaError(.fileReadUnknown) }
        let raw = ["cr3", "cr2", "nef", "arw", "raf", "orf", "rw2", "dng"]
        let extensions = Set(raw).union(pairedExtensions)
        var files: [URL] = []
        for case let file as URL in enumerator {
            if file.lastPathComponent == "_Rejected" { enumerator.skipDescendants(); continue }
            guard
                extensions.contains(file.pathExtension.lowercased()),
                try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            else { continue }
            files.append(file)
        }
        if let enumerationError { throw enumerationError }
        let rawStems = Set(
            files.filter { raw.contains($0.pathExtension.lowercased()) }.map {
                $0.deletingPathExtension().path
            })
        return files.filter {
            !(pairedExtensions.contains($0.pathExtension.lowercased())
                && rawStems.contains($0.deletingPathExtension().path))
        }.sorted { $0.path < $1.path }
    }

    public static func run(
        folder: URL, includeSyntheticFixtures: Bool = false,
        progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async throws -> GroupingRun {
        let all = try files(in: folder)
        let files = Array(all.prefix(600))
        var measurements: [LabMeasurement] = []
        var photos: [GroupingPhoto] = []
        var thumbnails: [String: Data] = [:]
        var prints: [String: [Int: VNFeaturePrintObservation]] = [:]
        var hashes: [String: UInt64] = [:]
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let id = String(file.path.dropFirst(folder.path.count + 1))
            let metadata = GroupingMetadataReader.read(url: file, id: id)
            photos.append(metadata.photo)
            let tags = ["file": id, "format": file.pathExtension.uppercased()]
            measurements.append(
                .init(name: "metadata-read", value: metadata.milliseconds, unit: "ms", tags: tags))
            measurements.append(
                .init(
                    name: "metadata", value: metadata.photo.captureTime?.timeIntervalSince1970 ?? 0,
                    unit: "epoch-s",
                    tags: tags.merging([
                        "hasTime": String(metadata.photo.captureTime != nil),
                        "model": metadata.photo.model ?? "missing",
                        "serial": metadata.photo.serial ?? "missing",
                        "paths": json(metadata.selectedPaths),
                        "properties": json(metadata.properties),
                        "error": metadata.error ?? "none",
                    ]) { _, new in new }))
            for size in [400, 2_000] {
                try Task.checkCancellation()
                autoreleasepool {
                    var featureTags = tags.merging(["maxPixel": String(size), "revision": "2"]) {
                        _, new in new
                    }
                    do {
                        let extractionStart = ContinuousClock.now
                        let image = try GroupingFeatures.preview(url: file, maxPixel: size)
                        featureTags["pixels"] = "\(image.width)x\(image.height)"
                        measurements.append(
                            .init(
                                name: "preview-read",
                                value: GroupingMetadataReader.elapsed(extractionStart), unit: "ms",
                                tags: featureTags))
                        if size == 400 {
                            thumbnails[id] = GroupingFeatures.thumbnail(image)
                            let hashStart = ContinuousClock.now
                            hashes[id] = try GroupingFeatures.differenceHash(image)
                            measurements.append(
                                .init(
                                    name: "dhash", value: GroupingMetadataReader.elapsed(hashStart),
                                    unit: "ms", tags: featureTags))
                        }
                        let start = ContinuousClock.now
                        let print = try GroupingFeatures.feature(image)
                        prints[id, default: [:]][size] = print
                        measurements.append(
                            .init(
                                name: "vision-feature",
                                value: GroupingMetadataReader.elapsed(start), unit: "ms",
                                tags: featureTags))
                    } catch {
                        featureTags["error"] = String(describing: error)
                        measurements.append(
                            .init(
                                name: "feature-failure", value: 1, unit: "count", tags: featureTags)
                        )
                    }
                }
            }
            await progress(index + 1, files.count)
        }
        func distance(_ left: String, _ right: String, size: Int = 400) -> Double? {
            guard let a = prints[left]?[size], let b = prints[right]?[size] else { return nil }
            var value: Float = 0
            do { try a.computeDistance(&value, to: b); return Double(value) } catch { return nil }
        }
        var boundaries: [GroupingBoundary] = []
        for body in Grouping.orderedBodies(photos) {
            for (left, right) in zip(body, body.dropFirst()) {
                guard let rightTime = right.captureTime, let leftTime = left.captureTime else {
                    continue
                }
                let gap = rightTime.timeIntervalSince(leftTime)
                let value = distance(left.id, right.id)
                for size in [400, 2_000] {
                    if let value = distance(left.id, right.id, size: size) {
                        measurements.append(
                            .init(
                                name: "body-adjacent-distance", value: value,
                                unit: "vision-distance",
                                tags: [
                                    "left": left.id, "right": right.id, "maxPixel": String(size),
                                ]))
                    }
                }
                if let a = hashes[left.id], let b = hashes[right.id] {
                    measurements.append(
                        .init(
                            name: "body-adjacent-distance", value: Double((a ^ b).nonzeroBitCount),
                            unit: "hash-bits", tags: ["left": left.id, "right": right.id]))
                }
                boundaries.append(
                    .init(
                        left: left.id, right: right.id, gap: gap, distance: value,
                        proposedSplit: Grouping.shouldSplit(
                            gap: gap, distance: value, parameters: .init())))
            }
        }
        // Diagnostic path pairs are not human labels and need not share a body.
        for (left, right) in zip(photos, photos.dropFirst()) {
            for size in [400, 2_000] {
                if let value = distance(left.id, right.id, size: size) {
                    measurements.append(
                        .init(
                            name: "path-adjacent-distance", value: value, unit: "vision-distance",
                            tags: ["left": left.id, "right": right.id, "maxPixel": String(size)]))
                }
            }
            if let a = hashes[left.id], let b = hashes[right.id] {
                measurements.append(
                    .init(
                        name: "path-adjacent-distance", value: Double((a ^ b).nonzeroBitCount),
                        unit: "hash-bits", tags: ["left": left.id, "right": right.id]))
            }
        }
        let groups = Grouping.groups(photos) { distance($0, $1) }
        for (index, group) in groups.enumerated() {
            for member in group {
                measurements.append(
                    .init(
                        name: "group-member", value: Double(index), unit: "group-index",
                        tags: ["file": member]))
            }
        }
        var seenStems: Set<String> = []
        let syntheticIDs = photos.map(\.id).filter {
            prints[$0]?[400] != nil
                && seenStems.insert(($0 as NSString).deletingPathExtension).inserted
        }
        let synthetic = syntheticBoundaries(
            ids: includeSyntheticFixtures ? syntheticIDs : []
        ) {
            distance($0, $1)
        }
        measurements += GroupingRun.sweepMeasurements(
            Grouping.sweep(synthetic), sample: "synthetic-fixture-duplicates")
        for boundary in synthetic {
            measurements.append(
                .init(
                    name: "synthetic-boundary", value: boundary.gap, unit: "s",
                    tags: [
                        "left": boundary.left, "right": boundary.right,
                        "distance": boundary.distance.map { String($0) } ?? "missing",
                        "expectedSplit": boundary.expectedSplit.map { String($0) } ?? "unreviewed",
                    ]))
        }
        return GroupingRun(
            report: LabReport(
                spike: "S5",
                context: [
                    "folder": folder.lastPathComponent, "filesFound": String(all.count),
                    "filesTested": String(files.count),
                    "timeGap": "2", "visionDistance": "0.5", "featureRevision": "2",
                    "maxPixels": "400,2000",
                    "ordering":
                        "body, capture time, numeric relative path; serial processing; caches not flushed",
                ], measurements: measurements,
                notes: [
                    "RAW uses embedded-only ImageIO thumbnail requests; no full RAW decode fallback. Raster images use image thumbnails. ImageIO preview provenance is not guaranteed.",
                    "Preview read includes extraction; Vision/dHash timings exclude extraction. Grid thumbnails retained for boundary review; feature observations discarded at end of run.",
                    "Missing capture times excluded; missing serial falls back to model; unknown model/serial can mix unidentified bodies. No offset uses camera wall time in a UTC surrogate zone.",
                    "Synthetic fixture duplicates are not real bursts: exact repeats at 0.2s, same scene after 3s (split), unrelated scenes at 0.8s (split). No accuracy claim.",
                    "Only explicitly reviewed boundaries are labels. Unreviewed entries are excluded from the labeled sweep. No photo or XMP is modified.",
                    "At most 600 primary photos; RAW+JPEG or RAW+HEIF in the same folder use RAW only, including when both companions exist. Missing feature conservatively splits. Device calibration pending.",
                ]), photos: photos, thumbnails: thumbnails, boundaries: boundaries, groups: groups)
    }

    public static func syntheticBoundaries(
        ids: [String], distance: (String, String) -> Double?
    ) -> [GroupingBoundary] {
        var result: [GroupingBoundary] = []
        for (index, id) in ids.enumerated() {
            for (suffix, gap, split) in [("repeat", 0.2, false), ("pause", 3.0, true)] {
                result.append(
                    .init(
                        left: "\(id)#\(suffix)-a", right: "\(id)#\(suffix)-b", gap: gap,
                        distance: distance(id, id), proposedSplit: split, expectedSplit: split))
            }
            if index > 0 {
                result.append(
                    .init(
                        left: ids[index - 1], right: id, gap: 0.8,
                        distance: distance(ids[index - 1], id), proposedSplit: true,
                        expectedSplit: true))
            }
        }
        return result
    }

    private static func json(_ dictionary: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(dictionary) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
