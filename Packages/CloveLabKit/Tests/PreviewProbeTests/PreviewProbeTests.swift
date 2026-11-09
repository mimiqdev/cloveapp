import CoreGraphics
import Foundation
import ImageIO
import LabSupport
import Testing
import UniformTypeIdentifiers

@testable import PreviewProbe

@Test func previewsDescriptorMatchesThePlan() {
    #expect(PreviewProbe.descriptor.id == "S2")
    #expect(!PreviewProbe.descriptor.question.isEmpty)
}

@Suite(.serialized)
struct PreviewTests {
    @Test(.enabled(if: Fixtures.set("formats") != nil))
    func fixturesProducePixelsOrExplicitUnsupportedResults() throws {
        let folder = try #require(Fixtures.set("formats"))
        let files = try PreviewMeasurement.files(in: folder)
        #expect(files.count >= 9)
        for file in files {
            for method in [PreviewMethod.embeddedOnly, .ifAbsent, .always, .raw] {
                let result = try PreviewMeasurement.measure(
                    url: file, request: .init(method: method, maxPixel: 400))
                #expect(result.milliseconds >= 0)
                #expect(result.sampledPeakResident >= result.residentBefore)
                if result.error == nil {
                    #expect(result.width > 0 && result.height > 0)
                    #expect(result.decodedBytes >= result.width * result.height)
                } else {
                    #expect(result.width == 0)
                    #expect(result.error?.isEmpty == false)
                }
                // These baseline camera fixtures must support the fallback path.
                if method == .ifAbsent && ["jpg", "dng"].contains(file.pathExtension.lowercased()) {
                    #expect(result.error == nil)
                }
            }
        }
    }

    @Test(.enabled(if: Fixtures.set("card-basic") != nil))
    func cardScanSkipsJunkAndRejects() throws {
        let folder = try #require(Fixtures.set("card-basic"))
        let files = try PreviewMeasurement.files(in: folder)
        #expect(!files.isEmpty)
        #expect(
            files.allSatisfy {
                !$0.pathComponents.contains("_Rejected") && !$0.lastPathComponent.hasPrefix(".")
            })
        #expect(
            files.allSatisfy {
                PreviewMeasurement.extensions.contains($0.pathExtension.lowercased())
            })
        #expect(files.contains { $0.pathExtension.lowercased() == "cr3" })
    }

    @Test func cameraHIFExtensionsAreEnumerated() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["upper.HIF", "lower.hif", "mixed.HiF", "ignored.txt"] {
            try Data([1]).write(to: directory.appendingPathComponent(name))
        }
        #expect(
            try PreviewMeasurement.files(in: directory).map(\.lastPathComponent) == [
                "lower.hif", "mixed.HiF", "upper.HIF",
            ])
    }

    @Test func fallbackOrientationAndCacheInvalidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "clove-previews-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("oriented.jpg")
        let pixels = Data(repeating: 127, count: 2_400 * 1_600 * 4)
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        let image = try #require(
            CGImage(
                width: 2_400, height: 1_600, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 9_600,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, image,
            [kCGImagePropertyOrientation: 6, kCGImageDestinationEmbedThumbnail: false]
                as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let request = PreviewRequest(method: .ifAbsent, maxPixel: 400)
        let transformed = try PreviewMeasurement.measure(url: url, request: request)
        let untransformed = try PreviewMeasurement.measure(
            url: url, request: .init(method: .ifAbsent, maxPixel: 400, transform: false))
        #expect(transformed.error == nil)
        #expect(transformed.width < transformed.height && transformed.height == 400)
        #expect(untransformed.width == 400 && untransformed.height == transformed.width)
        let embedded = try PreviewMeasurement.measure(
            url: url, request: .init(method: .embeddedOnly, maxPixel: 400))
        #expect(embedded.error == "noThumbnail")
        let jpegBytes = [UInt8](try Data(contentsOf: url))
        let jpegStarts = zip(jpegBytes, jpegBytes.dropFirst()).filter { $0 == 0xff && $1 == 0xd8 }
            .count
        #expect(jpegStarts == 1)  // no nested JPEG thumbnail in this generated control
        let key = try PreviewCacheKey.make(url: url, request: request)
        #expect(key == (try PreviewCacheKey.make(url: url, request: request)))
        #expect(
            key
                != (try PreviewCacheKey.make(
                    url: url, request: .init(method: .always, maxPixel: 400))))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: url.path)
        #expect(key != (try PreviewCacheKey.make(url: url, request: request)))
        let cache = try PreviewSuite.cacheMeasurements(file: url, directory: directory)
        #expect(cache.contains { $0.name == "cache-hit" && $0.value == 1 })
        #expect(cache.contains { $0.name == "cache-disk-size" && $0.value > 0 })
        let missing = try PreviewMeasurement.measure(
            url: directory.appendingPathComponent("missing.raw"), request: request)
        #expect(missing.error == "cannotOpen")
        let invalidRAW = directory.appendingPathComponent("invalid.dng")
        try Data("not a RAW image".utf8).write(to: invalidRAW)
        let unsupported = try PreviewMeasurement.measure(
            url: invalidRAW, request: .init(method: .raw, maxPixel: 400))
        #expect(
            ["rawUnsupported", "rawNoOutput", "cannotRender"].contains(unsupported.error ?? ""))
        #expect(unsupported.width == 0 && unsupported.decodedBytes == 0)
        let copy = directory.appendingPathComponent("copy.jpg")
        try FileManager.default.copyItem(at: url, to: copy)
        #expect(
            try PreviewCacheKey.make(url: url, request: request)
                != PreviewCacheKey.make(url: copy, request: request))
        let beforeSizeChange = try PreviewCacheKey.make(url: url, request: request)
        var changed = try Data(contentsOf: url)
        changed.append(0)
        try changed.write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: url.path)
        #expect(beforeSizeChange != (try PreviewCacheKey.make(url: url, request: request)))
    }

    @Test(.enabled(if: Fixtures.set("formats") != nil))
    func boundedThroughputAndCancellation() async throws {
        let folder = try #require(Fixtures.set("formats"))
        let file = try #require(
            PreviewMeasurement.files(in: folder).first { $0.pathExtension.lowercased() == "jpg" })
        let throughput = try await PreviewSuite.throughput(
            files: [file, file, file], concurrency: 2)
        #expect(throughput.contains { $0.name == "grid-success" && $0.value == 3 })
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try PreviewMeasurement.measure(
                url: file, request: .init(method: .ifAbsent, maxPixel: 400))
        }
        do {
            _ = try await cancelled.value
            Issue.record("A pre-cancelled request must not deliver pixels")
        } catch is CancellationError {} catch { Issue.record(error) }
        let probe = await PreviewSuite.cancellationProbe(file: file)
        #expect(probe.count == 2)
        #expect(probe.first?.tags["status"] != nil)
    }

    @Test(.enabled(if: Fixtures.set("formats") != nil))
    func fullRAWProducesNativePixels() throws {
        let folder = try #require(Fixtures.set("formats"))
        let url = folder.appendingPathComponent("apple-iphone-12-pro.DNG")
        let result = try PreviewMeasurement.measure(
            url: url, request: .init(method: .raw, maxPixel: 0))
        #expect(result.error == nil)
        #expect(max(result.width, result.height) > 2_000)
        #expect(result.decodedBytes >= result.width * result.height * 4)
    }

    /// Opt-in artifact collection uses the exact same suite as Clove Lab. Normal
    /// verify exercises functions without running full-resolution benchmarks.
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["CLOVE_PREVIEWS_REPORT"] != nil
                && Fixtures.set("formats") != nil))
    func collectReport() async throws {
        let folder = try #require(Fixtures.set("formats"))
        var report = try await PreviewSuite.run(folder: folder)
        report.notes.append(
            "macOS measurements taken on a shared, loaded host with two other spike workers.")
        let path = try #require(ProcessInfo.processInfo.environment["CLOVE_PREVIEWS_REPORT"])
        try report.write(to: URL(fileURLWithPath: path))
    }
}
