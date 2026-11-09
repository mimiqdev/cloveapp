import CoreGraphics
import Foundation
import Testing

@testable import CloveImaging

/// Informational timings for G1 "Vision feature per photo: measure in I3", next to S5's device
/// medians (3.25 ms Vision, 0.225 ms dHash, 7.47 ms preview read on an iPhone 17 Pro Max).
/// Nothing here gates: the numbers are printed for the pull request and nothing asserts on them.
@Suite(.serialized, .enabled(if: FeatureFixtures.hasFormats))
struct ImageFeatureTimingTests {
    private static let samples = 3

    private struct Timings {
        var milliseconds: [Double]
        var median: Double {
            let sorted = milliseconds.sorted()
            guard sorted.count > 1 else { return sorted.first ?? 0 }
            return sorted.count.isMultiple(of: 2)
                ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
                : sorted[sorted.count / 2]
        }
        var maximum: Double { milliseconds.max() ?? 0 }
    }

    @Test func previewVisionAndHashTimings() async throws {
        let names = try FileManager.default.contentsOfDirectory(
            atPath: FeatureFixtures.formats.path
        ).sorted()
        let printReader = VisionFeaturePrintReader()
        let hashReader = DifferenceHashReader()
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clove-feature-timings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let cache = try ImageFeatureCache(directory: cacheDirectory)
        let requestReader = ThumbnailPreviewReader()
        var previews: [Timings] = []
        var prints: [Timings] = []
        var hashes: [Timings] = []
        var diskBytes: [Int] = []
        var visionFailures: [String] = []

        for name in names {
            let request = try featureRequest(FeatureFixtures.file(name))
            var previewTimes: [Double] = []
            var image: CGImage?
            for _ in 0..<Self.samples {
                let start = ContinuousClock.now
                let read = await requestReader.preview(for: request.preview)
                previewTimes.append(elapsedMilliseconds(since: start))
                guard case .preview(let preview) = read else {
                    image = nil
                    continue
                }
                image = preview.image
            }
            guard let image else {
                print("FEATURE timings file=\(name) skipped=no-preview")
                continue
            }
            var visionTimes: [Double] = []
            var hashTimes: [Double] = []
            var features: ImageFeatures?
            for _ in 0..<Self.samples {
                let hashStart = ContinuousClock.now
                let hash = hashReader.hash(of: image)
                hashTimes.append(elapsedMilliseconds(since: hashStart))
                let visionStart = ContinuousClock.now
                switch VisionFeaturePrintReader.requestPrint(of: image) {
                case .success(let print):
                    features = ImageFeatures(print: print, differenceHash: hash)
                case .failure(let failure):
                    features = ImageFeatures(differenceHash: hash, visionFailure: failure)
                    if !visionFailures.contains(String(describing: failure)) {
                        visionFailures.append(String(describing: failure))
                    }
                }
                visionTimes.append(elapsedMilliseconds(since: visionStart))
            }
            if let features {
                // The stored record, not the print alone: G1 asks for the on-disk feature size.
                let before = cache.diskByteCount
                try cache.store(
                    features, route: .ifAbsent, visionRevision: printReader.revision,
                    for: request)
                diskBytes.append(cache.diskByteCount - before)
            }
            let previewTimings = Timings(milliseconds: previewTimes)
            let hashTimings = Timings(milliseconds: hashTimes)
            previews.append(previewTimings)
            hashes.append(hashTimings)
            if !visionTimes.isEmpty, visionFailures.isEmpty {
                let visionTimings = Timings(milliseconds: visionTimes)
                prints.append(visionTimings)
                print(
                    "FEATURE timings file=\(name) n=\(Self.samples)"
                        + " preview_median_ms=\(format(previewTimings.median))"
                        + " vision_median_ms=\(format(visionTimings.median))"
                        + " hash_median_ms=\(format(hashTimings.median))")
            } else {
                print(
                    "FEATURE timings file=\(name) n=\(Self.samples)"
                        + " preview_median_ms=\(format(previewTimings.median))"
                        + " vision=unavailable hash_median_ms=\(format(hashTimings.median))")
            }
        }

        let recordBytes = Timings(milliseconds: diskBytes.map(Double.init))
        print(
            "FEATURE summary formats=\(names.count)"
                + " preview_worst_median_ms=\(format(previews.map(\.median).max() ?? 0))"
                + " preview_max_ms=\(format(previews.map(\.maximum).max() ?? 0))"
                + " vision_worst_median_ms=\(format(prints.map(\.median).max() ?? 0))"
                + " vision_max_ms=\(format(prints.map(\.maximum).max() ?? 0))"
                + " hash_worst_median_ms=\(format(hashes.map(\.median).max() ?? 0))"
                + " record_bytes_median=\(Int(recordBytes.median))"
                + " record_bytes_max=\(Int(recordBytes.maximum))"
                + " vision_failures=\(visionFailures.isEmpty ? "none" : visionFailures.joined(separator: "|"))"
        )
        // The comparison G1 asks for lives in the pull request: S5 measured 3.25 ms Vision,
        // 0.225 ms dHash and 7.47 ms preview read per photo on an iPhone 17 Pro Max.
    }

    private func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: .now).components
        return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
