import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CloveImaging

@Suite(.serialized)
actor ThumbnailExtractionTests {
    private nonisolated let queue = DispatchSerialQueue(label: "CloveTests.ThumbnailExtraction")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    @Test func rasterFallbackAndOrientation() throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let source = try directory.image(orientation: 6)
        let request = try thumbnailRequest(source)
        let result = try availableThumbnail(ThumbnailExtractor().extract(request))
        #expect(result.width == 267 && result.height == 400)
        #expect(result.route == .ifAbsent)
        #expect(result.decodedBytes > 0)
        // The colour boundary rotates from left/right to top/bottom.
        let bytes = try #require(result.image.dataProvider?.data)
        #expect(CFDataGetLength(bytes) > 0)
    }

    @Test func tinyJPEGPreviewUsesOneGeneratedFallback() throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let source = try directory.image(embedded: true)
        let image = try availableThumbnail(
            ThumbnailExtractor().extract(try thumbnailRequest(source, pixels: 800)))
        #expect(max(image.width, image.height) == 800)
        #expect(image.route == .always)
    }

    @Test func cameraHEIFUsesEmbeddedPreviewWithOrientation() throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        // An actual HEIF container under the camera extension, with an embedded thumbnail.
        let source = try directory.image(
            name: "camera.HIF", type: .heic, orientation: 6, embedded: true)
        let image = try availableThumbnail(
            ThumbnailExtractor().extract(try thumbnailRequest(source)))
        #expect(image.route == .embeddedOnly)
        // ImageIO embeds a 320 px preview in this generated control. The 400 px
        // request is a cap; embedded-only must neither upscale nor fully decode.
        #expect(image.height == 320)
        #expect(image.width == 212)
    }

    @Test func missingHEIFPreviewIsUnavailableEvenWhenRenamed() throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        for name in ["no-preview.HIF", "renamed.jpg"] {
            let source = try directory.image(name: name, type: .heic)
            let result = ThumbnailExtractor().extract(try thumbnailRequest(source))
            guard case .unavailable(.noUsablePreview) = result else {
                Issue.record("HEIF must not fall back to a full decode: \(result)")
                continue
            }
        }
        let invalid = directory.url.appendingPathComponent("broken.ARW")
        try Data("not an image".utf8).write(to: invalid)
        guard case .unavailable = ThumbnailExtractor().extract(try thumbnailRequest(invalid)) else {
            Issue.record("Invalid input must have an explicit unavailable result")
            return
        }
    }

    @Test func fixtureARWAndJPEGProduceExpectedGridSize() throws {
        let root =
            ProcessInfo.processInfo.environment["CLOVE_FIXTURES_DIR"]
            ?? "/Volumes/T7/Projects/.clove-fixtures"
        let folder = URL(fileURLWithPath: root).appendingPathComponent("sets/formats")
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        for name in ["sony-ilce-7s.ARW", "canon-eos-6d.JPG"] {
            let image = try availableThumbnail(
                ThumbnailExtractor().extract(
                    try thumbnailRequest(folder.appendingPathComponent(name))))
            #expect(max(image.width, image.height) == 400)
            #expect(min(image.width, image.height) >= 260)
            #expect(image.route == (name.hasSuffix("ARW") ? .embeddedOnly : .always))
        }
    }

    /// Short opt-in measurements: no latency assertions, cache disabled, three
    /// sequential observations per format followed by twelve jobs at four workers.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLOVE_THUMBNAIL_TIMINGS"] == "1"))
    func informationalTimings() async throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let root =
            ProcessInfo.processInfo.environment["CLOVE_FIXTURES_DIR"]
            ?? "/Volumes/T7/Projects/.clove-fixtures"
        let folder = URL(fileURLWithPath: root).appendingPathComponent("sets/formats")
        let hif = try directory.image(name: "camera.HIF", type: .heic, embedded: true)
        let sources = [
            folder.appendingPathComponent("sony-ilce-7s.ARW"), hif,
            folder.appendingPathComponent("canon-eos-6d.JPG"),
        ]
        let requests = try sources.map { try thumbnailRequest($0) }
        for request in requests {
            var samples: [Double] = []
            for _ in 0..<3 {
                let start = ContinuousClock.now
                _ = try availableThumbnail(ThumbnailExtractor().extract(request))
                samples.append(elapsedMilliseconds(start))
            }
            print("THUMBNAIL \(request.source.pathExtension) median_ms=\(samples.sorted()[1]) n=3")
        }
        let pipeline = ThumbnailPipeline(cache: try directory.cache(memory: 0, disk: 0))
        let start = ContinuousClock.now
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask {
                    _ = try availableThumbnail(await pipeline.thumbnail(for: requests[index % 3]))
                }
            }
            try await group.waitForAll()
        }
        print(
            "THUMBNAIL workers=4 successes=12 elapsed_ms=\(elapsedMilliseconds(start)) throughput_per_s=\(12000 / elapsedMilliseconds(start))"
        )
    }

    private func elapsedMilliseconds(_ start: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: .now).components
        return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
    }
}
