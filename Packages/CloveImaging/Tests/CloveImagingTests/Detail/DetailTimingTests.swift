import Foundation
import Testing

@testable import CloveImaging

/// Informational timings for G1's "First detail preview, p95 ≤ 300 ms" and "Full RAW for
/// focus checks, p95 ≤ 2 s". Nothing here gates: the numbers are printed for the pull
/// request and nothing asserts on them.
@Suite(.serialized, .enabled(if: DetailFixtures.hasFormats))
struct DetailTimingTests {
    private static let rawExtensions: Set<String> = [
        "cr3", "nef", "arw", "raf", "orf", "rw2", "dng",
    ]
    private static let samples = 3
    private static let renderSamples = 2

    private struct Timings {
        var milliseconds: [Double]
        var median: Double {
            let sorted = milliseconds.sorted()
            guard sorted.count > 1 else { return sorted.first ?? 0 }
            // An even sample count averages the middle pair, an odd one takes the middle.
            return sorted.count.isMultiple(of: 2)
                ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
                : sorted[sorted.count / 2]
        }
        var maximum: Double { milliseconds.max() ?? 0 }
    }

    @Test func firstPreviewAndRawRenderTimings() async throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: DetailFixtures.formats.path)
            .sorted()
            .filter { name in
                let ext = (name as NSString).pathExtension.lowercased()
                // The generated HEIC fixture exposes no embedded preview, so it has no
                // first-preview number to report.
                return Self.rawExtensions.contains(ext) || ext == "jpg" || ext == "jpeg"
            }
        var previews: [Timings] = []
        for name in files {
            let url = DetailFixtures.file(name)
            let isRaw = Self.rawExtensions.contains(url.pathExtension.lowercased())
            var samples: [Double] = []
            for _ in 0..<Self.samples {
                let pipeline = DetailPipeline(cache: DetailCache())
                let request =
                    isRaw
                    ? try rawRequest(url, displayPixels: 1200)
                    : try rasterRequest(url, displayPixels: 1200)
                let start = ContinuousClock.now
                let result = try await pipeline.preview(for: request)
                samples.append(elapsedMilliseconds(since: start))
                _ = try? availableDetail(result)
                await pipeline.close()
            }
            let timings = Timings(milliseconds: samples)
            previews.append(timings)
            print(
                "DETAIL first-preview file=\(name) n=\(Self.samples)"
                    + " median_ms=\(format(timings.median)) max_ms=\(format(timings.maximum))")
        }

        var renders: [Timings] = []
        for name in files
        where Self.rawExtensions.contains(
            (name as NSString).pathExtension.lowercased())
        {
            let url = DetailFixtures.file(name)
            var samples: [Double] = []
            for _ in 0..<Self.renderSamples {
                let start = ContinuousClock.now
                let pixels = await DetailRenderer().nativeRAW(try detailSource(url))
                samples.append(elapsedMilliseconds(since: start))
                _ = pixels
            }
            let timings = Timings(milliseconds: samples)
            renders.append(timings)
            print(
                "DETAIL raw-render file=\(name) n=\(Self.renderSamples)"
                    + " median_ms=\(format(timings.median)) max_ms=\(format(timings.maximum))")
        }

        // Compared against G1's 300 ms first-preview and 2 s full-RAW targets.
        print(
            "DETAIL summary formats=\(files.count)"
                + " first_preview_worst_median_ms=\(format(previews.map(\.median).max() ?? 0))"
                + " first_preview_max_ms=\(format(previews.map(\.maximum).max() ?? 0))"
                + " first_preview_target_ms=300"
                + " raw_render_worst_median_ms=\(format(renders.map(\.median).max() ?? 0))"
                + " raw_render_max_ms=\(format(renders.map(\.maximum).max() ?? 0))"
                + " raw_render_target_ms=2000")
    }

    private func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: .now).components
        return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
