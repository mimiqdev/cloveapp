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
            displayPixels: 400, detailFormatLimit: 0))
    #expect(report.context["actualPhotoCount"] == "4")
    #expect(report.context["actualImageFileCount"] == "8")
    #expect(report.context["scanStatus"] == "complete")
    #expect(report.context["detailDisplayPixels"] == "400")
    #expect(report.context["detailScreenPixels"] == "400")
    for stage in [
        "thumbnail", "detail-first-preview", "detail-screen", "raw-focus", "grouping-total",
    ] {
        #expect(
            report.measurements.contains {
                $0.name == stage && $0.tags["statistic"] == "p95"
            }, "missing \(stage) p95")
    }
    #expect(
        report.measurements.contains {
            $0.name == "detail-screen" && $0.tags["cache"] == "warm"
                && $0.tags["statistic"] == "p95"
                && $0.tags["screenPixels"] == "400"
        })
    let warmRAWFocusP95 = try #require(
        report.measurements.first {
            $0.name == "raw-focus" && $0.tags["cache"] == "warm"
                && $0.tags["statistic"] == "p95"
        }?.value)
    // Removing CGDataProviderCopyData avoids copying the 20-80 MiB bitmap on warm cache hits.
    #expect(warmRAWFocusP95 < 20.0)
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
    #expect(
        report.measurements.contains {
            $0.name == "raw-focus-native-results" && $0.value == 1
                && $0.tags["quality"] == "nativeRAW"
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

@Test(
    .enabled(if: Fixtures.set("browsing-2000") != nil && Fixtures.set("formats") != nil),
    .timeLimit(.minutes(5))
)
func parameterizedScreenEdgeMeasuresSmallAndTwentyPlusMegapixelRAWs() async throws {
    let standard = try #require(Fixtures.set("browsing-2000"))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
        "clove-browsing-formats-test-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for index in 1...2 {
        let name = String(format: "IMG_%04d", index)
        let source = standard.appendingPathComponent("DCIM/100SONY/\(name).ARW")
        let destination = folder.appendingPathComponent("\(name).ARW")
        do {
            try FileManager.default.linkItem(at: source, to: destination)
        } catch {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    let report = try await BrowsingPerformanceProbe.run(
        folder: folder,
        configuration: .init(
            warmScanRepetitions: 0, metadataSampleLimit: 1, thumbnailLimit: 2,
            thumbnailInFlight: 2, detailSampleLimit: 1, rawSampleLimit: 1,
            featureSampleLimit: 1,
            displayPixels: 1_320,
            screenPixels: BrowsingPerformanceConfiguration.iPadPro13ScreenPixels,
            detailFormatLimit: 2, detailFormatRepetitions: 1))

    #expect(report.context["detailDisplayPixels"] == "1320")
    #expect(report.context["detailScreenPixels"] == "2752")
    #expect(report.context["detailFormatFolder"] == "formats")
    #expect(report.context["detailFormatSampleCount"] == "2")
    #expect(report.context["detail20MPFormatCount"] == "1")

    for format in ["sony-ilce-7s.ARW", "canon-eos-r6.CR3"] {
        #expect(
            report.measurements.contains {
                $0.name == "detail-format-screen" && $0.tags["cache"] == "cold"
                    && $0.tags["format"] == format
                    && $0.tags["screenPixels"] == "2752"
                    && $0.tags["statistic"] == "p95"
            }, "missing detail-format-screen for \(format)")
    }
    for stage in ["detail-20mp-preview", "detail-20mp-screen", "detail-20mp-native"] {
        for cache in ["cold", "warm"] {
            #expect(
                report.measurements.contains {
                    $0.name == stage && $0.tags["cache"] == cache
                        && $0.tags["statistic"] == "p95"
                }, "missing \(stage) \(cache) p95")
        }
    }
    let warm20MPNative = try #require(
        report.measurements.first {
            $0.name == "detail-20mp-native" && $0.tags["cache"] == "warm"
                && $0.tags["statistic"] == "p95"
        }?.value)
    #expect(warm20MPNative < 20.0)
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
    let environment = ProcessInfo.processInfo.environment
    let path = try #require(environment["CLOVE_BROWSING_PERFORMANCE_REPORT"])
    let folder = try #require(Fixtures.set("browsing-2000"))
    let revision = environment["CLOVE_SOURCE_REVISION"] ?? "unversioned"
    let screenPixels = environment["CLOVE_DETAIL_SCREEN_PIXELS"].flatMap(Int.init)
    let formatLimit = environment["CLOVE_DETAIL_FORMAT_LIMIT"].flatMap(Int.init)
    let formatRepetitions = environment["CLOVE_DETAIL_FORMAT_REPETITIONS"].flatMap(Int.init)
    let configuration = BrowsingPerformanceConfiguration(
        displayPixels: screenPixels ?? BrowsingPerformanceConfiguration.defaultScreenPixels,
        screenPixels: screenPixels,
        detailFormatLimit: formatLimit ?? 8,
        detailFormatRepetitions: formatRepetitions ?? 5)
    #if DEBUG
        let buildConfig = "debug"
    #else
        let buildConfig = "release"
    #endif
    let app = LabApp(
        bundleIdentifier: "com.mimiqdev.clove.lab.tests", version: buildConfig, build: revision)
    var report = try await BrowsingPerformanceProbe.run(
        folder: folder, configuration: configuration, app: app
    ) { update in
        print("Browsing performance \(update.completed)/\(update.total): \(update.message)")
    }
    report.context["execution"] =
        "macOS \(buildConfig) Swift Testing runner; production package code"
    report.context["hostLoad"] = "shared Mac host; see PR evidence for uptime and core count"
    report.context["sourceRevision"] = revision
    report.notes.append("Mac-only \(buildConfig)-runner evidence; not an iPhone result.")
    try report.write(to: URL(fileURLWithPath: path))
    print("Browsing performance report: \(path)")
}
