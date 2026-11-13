import Foundation
import LabSupport
import Testing

@testable import BrowsingPerformanceProbe

@Test func nearestRankPercentilesIncludeTheirSampleCount() {
    let distribution = Distribution(samples: Array(1...100).map(Double.init))
    #expect(distribution.count == 100)
    #expect(distribution.percentile(0.5) == 50)
    #expect(distribution.percentile(0.95) == 95)
    #expect(Distribution(samples: []).percentile(0.5) == nil)
    #expect(Distribution(samples: [2, 1]).percentile(0.95) == 2)
}

@Test func reportDistinguishesColdAndDiskSamples() {
    var builder = BrowsingPerformanceReportBuilder()
    builder.distribution("thumbnail", cache: "cold", samples: [4, 1, 3, 2])
    builder.distribution("thumbnail", cache: "disk", samples: [2, 1])

    let cold = builder.measurements.filter {
        $0.name == "thumbnail" && $0.tags["cache"] == "cold"
    }
    #expect(cold.count == 2)
    #expect(cold.first { $0.tags["statistic"] == "p50" }?.value == 2)
    #expect(cold.first { $0.tags["statistic"] == "p95" }?.value == 4)
    #expect(cold.allSatisfy { $0.tags["sampleCount"] == "4" })
    #expect(
        builder.measurements.contains {
            $0.name == "thumbnail-sample-count" && $0.tags["cache"] == "disk" && $0.value == 2
        })
}

@Test func emptyDistributionHasAnExplicitUnavailableReason() {
    var builder = BrowsingPerformanceReportBuilder()
    builder.distribution("raw-focus", cache: "cold", samples: [], failureCount: 2)
    builder.failureReasons("raw-focus", cache: "cold", reasons: ["noUsablePreview": 2])
    #expect(
        builder.measurements.contains {
            $0.name == "metric-unavailable" && $0.tags["stage"] == "raw-focus"
                && $0.tags["reason"] == "No successful samples."
        })
    #expect(
        builder.measurements.contains {
            $0.name == "raw-focus-failure-count" && $0.value == 2
        })
    #expect(
        builder.measurements.contains {
            $0.name == "raw-focus-failure-reason" && $0.value == 2
                && $0.tags["reason"] == "noUsablePreview"
        })
}

@Test func generatedFixtureIdentityRoundTripsIntoReportContext() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let document: [String: Any] = [
        "schemaVersion": 1,
        "set": "browsing-2000",
        "fileCount": 4_000,
        "definitionSHA256": String(repeating: "a", count: 64),
        "sources": ["source-b": "bbb", "source-a": "aaa"],
    ]
    let data = try JSONSerialization.data(withJSONObject: document)
    try data.write(to: folder.appendingPathComponent(".clove-fixture.json"))

    let identity = try FixtureIdentity.read(from: folder)
    #expect(identity.set == "browsing-2000")
    #expect(identity.fileCount == 4_000)
    #expect(identity.sourceDigestJSON == #"{"source-a":"aaa","source-b":"bbb"}"#)
}

@Test func browsingReportUsesTheNormalLabSchema() throws {
    let builder = BrowsingPerformanceReportBuilder()
    let report = builder.report(createdAt: Date(timeIntervalSince1970: 0))
    #expect(report.schemaVersion == LabReport.currentSchemaVersion)
    #expect(report.spike == "Q3")
    #expect(try LabReport(jsonData: report.encoded()) == report)
}
