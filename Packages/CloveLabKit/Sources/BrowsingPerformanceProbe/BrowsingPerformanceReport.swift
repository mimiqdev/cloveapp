import Foundation
import LabSupport

struct FixtureRecipe: Codable, Sendable {
    let id: String
    let format: String
    let `extension`: String
    let tool: String
    let args: [String]
    let notes: String
}

/// Identity written by `make-fixture-sets` beside a generated measurement folder.
struct FixtureIdentity: Decodable, Sendable {
    let schemaVersion: Int
    let set: String
    let fileCount: Int
    let definitionSHA256: String
    let sources: [String: String]
    let recipes: [String: FixtureRecipe]
    let generated: [String: String]

    static func read(from folder: URL) throws -> FixtureIdentity {
        let url = folder.appendingPathComponent(".clove-fixture.json")
        return try JSONDecoder().decode(FixtureIdentity.self, from: Data(contentsOf: url))
    }

    var sourceDigestJSON: String { sortedJSON(sources) }
    var recipeJSON: String { sortedJSON(recipes) }
    var generatedDigestJSON: String { sortedJSON(generated) }

    private func sortedJSON<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder.sorted.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// Nearest-rank distribution statistics over successful observations only.
struct Distribution: Sendable, Equatable {
    let samples: [Double]

    var count: Int { samples.count }

    func percentile(_ fraction: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let rank = max(1, Int((fraction * Double(sorted.count)).rounded(.up)))
        return sorted[min(sorted.count, rank) - 1]
    }
}

/// Collects the normal Lab measurements for one run. No report-schema extension is needed:
/// statistic, cache state, sample count and unavailable reasons travel as measurement tags.
struct BrowsingPerformanceReportBuilder: Sendable {
    var context: [String: String] = [:]
    var measurements: [LabMeasurement] = []
    var notes: [String] = []

    mutating func distribution(
        _ stage: String, cache: String, samples: [Double], unit: String = "ms",
        failureCount: Int = 0
    ) {
        let distribution = Distribution(samples: samples)
        var tags = ["cache": cache, "sampleCount": String(distribution.count)]
        measurements.append(
            LabMeasurement(
                name: "\(stage)-sample-count", value: Double(distribution.count), unit: "count",
                tags: ["cache": cache]))
        if failureCount > 0 {
            measurements.append(
                LabMeasurement(
                    name: "\(stage)-failure-count", value: Double(failureCount), unit: "count",
                    tags: ["cache": cache]))
        }
        guard distribution.count > 0 else {
            unavailable(stage, cache: cache, reason: "No successful samples.")
            return
        }
        for (name, fraction) in [("p50", 0.5), ("p95", 0.95)] {
            tags["statistic"] = name
            measurements.append(
                LabMeasurement(
                    name: stage, value: distribution.percentile(fraction) ?? 0, unit: unit,
                    tags: tags))
        }
    }

    mutating func value(
        _ name: String, value: Double, unit: String, tags: [String: String] = [:]
    ) {
        measurements.append(LabMeasurement(name: name, value: value, unit: unit, tags: tags))
    }

    mutating func failureReasons(
        _ stage: String, cache: String, reasons: [String: Int]
    ) {
        for (reason, count) in reasons.sorted(by: { $0.key < $1.key }) {
            value(
                "\(stage)-failure-reason", value: Double(count), unit: "count",
                tags: ["cache": cache, "reason": reason])
        }
    }

    mutating func unavailable(_ stage: String, cache: String = "none", reason: String) {
        measurements.append(
            LabMeasurement(
                name: "metric-unavailable", value: 1, unit: "count",
                tags: ["stage": stage, "cache": cache, "reason": reason]))
    }

    mutating func memoryPeak(_ bytes: UInt64, stage: String) {
        value(
            "memory-peak", value: Double(bytes), unit: "bytes",
            tags: ["stage": stage, "basis": "5ms process RSS samples; cumulative lower bound"])
    }

    func report(createdAt: Date = Date(), app: LabApp = .current()) -> LabReport {
        LabReport(
            spike: "Q3", createdAt: createdAt, app: app, context: context,
            measurements: measurements, notes: notes)
    }
}

extension Stopwatch {
    var milliseconds: Double { seconds * 1_000 }
}
