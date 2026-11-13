import Foundation
import LabSupport
import Testing

@testable import BrowsingPerformanceProbe

@Test(.enabled(if: Fixtures.set("browsing-2000") != nil), .timeLimit(.minutes(5)))
func smallRealFolderProducesEveryCurrentPipelineStage() async throws {
    let standard = try #require(Fixtures.set("browsing-2000"))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
        "clove-browsing-test-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for index in 1...4 {
        let name = String(format: "IMG_%04d", index)
        for pathExtension in ["ARW", "JPG"] {
            let source = standard.appendingPathComponent(
                "DCIM/100SONY/\(name).\(pathExtension)")
            let destination = folder.appendingPathComponent("\(name).\(pathExtension)")
            do {
                try FileManager.default.linkItem(at: source, to: destination)
            } catch {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        }
    }

    let report = try await BrowsingPerformanceProbe.run(
        folder: folder,
        configuration: .init(
            warmScanRepetitions: 1, metadataSampleLimit: 2, thumbnailLimit: 4,
            thumbnailInFlight: 2, detailSampleLimit: 2, rawSampleLimit: 1,
            displayPixels: 400))
    #expect(report.context["actualPhotoCount"] == "4")
    #expect(report.context["actualImageFileCount"] == "8")
    #expect(report.context["scanStatus"] == "complete")
    for stage in ["thumbnail", "detail-first-preview", "raw-focus", "grouping-total"] {
        #expect(
            report.measurements.contains {
                $0.name == stage && $0.tags["statistic"] == "p95"
            }, "missing \(stage) p95")
    }
    #expect(
        report.measurements.contains {
            $0.name == "thumbnail-throughput" && $0.tags["cache"] == "cold" && $0.value > 0
        })
    #expect(
        report.measurements.contains {
            $0.name == "raw-focus-cancel-observed" && $0.value == 1
        })
    #expect(
        report.measurements.contains {
            $0.name == "raw-focus-cancel-drain" && $0.tags["statistic"] == "p95"
        })
    let warmTotal = report.measurements.first {
        $0.name == "grouping-total" && $0.tags["cache"] == "warm"
            && $0.tags["statistic"] == "p95"
    }?.value
    let warmTimeStage = report.measurements.first {
        $0.name == "grouping-time-stage" && $0.tags["cache"] == "warm"
            && $0.tags["statistic"] == "p95"
    }?.value
    let total = try #require(warmTotal)
    let timeStage = try #require(warmTimeStage)
    #expect(total >= timeStage)
    #expect(
        report.measurements.contains {
            $0.name == "grouping-feature-completion-sample-count"
                && $0.tags["cache"] == "disk" && $0.value == 4
        })
    #expect(
        report.measurements.contains {
            $0.name == "metric-unavailable" && $0.tags["stage"] == "fixture-identity"
        })
    #expect(
        report.measurements.contains {
            $0.name == "metric-unavailable" && $0.tags["stage"] == "grid-scroll-presentation"
        })
}

/// Opt-in full Mac evidence run. It never runs in the normal Lab test suite:
/// `CLOVE_BROWSING_PERFORMANCE_REPORT=/path/report.json swift test ... --filter collectFullMacReport`.
@Test(
    .enabled(
        if: ProcessInfo.processInfo.environment["CLOVE_BROWSING_PERFORMANCE_REPORT"] != nil
            && Fixtures.set("browsing-2000") != nil),
    .timeLimit(.minutes(60))
)
func collectFullMacReport() async throws {
    let path = try #require(
        ProcessInfo.processInfo.environment["CLOVE_BROWSING_PERFORMANCE_REPORT"])
    let folder = try #require(Fixtures.set("browsing-2000"))
    let revision =
        ProcessInfo.processInfo.environment["CLOVE_SOURCE_REVISION"] ?? "unversioned"
    let app = LabApp(
        bundleIdentifier: "com.mimiqdev.clove.lab.tests", version: "debug", build: revision)
    var report = try await BrowsingPerformanceProbe.run(folder: folder, app: app) { update in
        print("Browsing performance \(update.completed)/\(update.total): \(update.message)")
    }
    report.context["execution"] = "macOS debug Swift Testing runner; production package code"
    report.context["hostLoad"] = "shared Mac host; see PR evidence for uptime and core count"
    report.context["sourceRevision"] = revision
    report.notes.append("Mac-only debug-runner evidence; not an iPhone or release-build result.")
    try report.write(to: URL(fileURLWithPath: path))
    print("Browsing performance report: \(path)")
}
