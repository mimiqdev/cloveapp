import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CloveImaging

/// Writable scratch space. Generated images and feature caches go here, never into the shared
/// fixture cache.
struct FeatureTestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: url) }

    func path(_ name: String) -> URL { url.appendingPathComponent(name) }

    func cache(
        memory: Int = 4 * 1024 * 1024, disk: Int = 8 * 1024 * 1024, version: Int = 1
    ) throws -> ImageFeatureCache {
        var configuration = ImageFeatureCache.Configuration()
        configuration.memoryBytes = memory
        configuration.diskBytes = disk
        configuration.payloadVersion = version
        return try ImageFeatureCache(
            directory: path("features"), configuration: configuration)
    }

    /// A small file whose revision can be read; the pixels come from a stub reader, so no
    /// image encoding is needed.
    func textFile(_ name: String) -> URL {
        let file = path(name)
        try? Data("feature test photo".utf8).write(to: file)
        return file
    }

    /// A generated JPEG, so a request's revision can be read from a real file.
    @discardableResult
    func jpeg(_ name: String, _ image: CGImage) throws -> URL {
        let file = path(name)
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                file as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return file
    }
}

/// The generated scenes feature tests compare.
///
/// Vision distances were checked on this host: the shifted scene is about 0.13 away and the
/// unrelated scene about 1.0, and the hashes are 0 and 31 bits apart. "Closer than unrelated"
/// therefore holds for both kinds with a wide margin, without relying on fixture content.
enum FeatureScene {
    static let width = 600
    static let height = 400

    static func identical() -> CGImage { image { draw($0, shift: 0) } }

    /// The same scene moved four pixels: near-identical for Vision and the same hash.
    static func shifted() -> CGImage { image { draw($0, shift: 4) } }

    /// The same scene plus one extra patch.
    static func extended() -> CGImage { image { draw($0, shift: 0, extra: true) } }

    /// An unrelated composition.
    static func unrelated() -> CGImage {
        image { context in
            for column in 0..<12 {
                context.setFillColor(
                    column.isMultiple(of: 2)
                        ? CGColor(gray: 0.1, alpha: 1) : CGColor(gray: 0.9, alpha: 1))
                context.fill(CGRect(x: column * 50, y: 0, width: 50, height: height))
            }
        }
    }

    private static func image(_ draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let context else { fatalError("Cannot create a test bitmap") }
        draw(context)
        guard let image = context.makeImage() else { fatalError("Cannot render a test scene") }
        return image
    }

    private static func draw(_ context: CGContext, shift: CGFloat, extra: Bool = false) {
        context.setFillColor(CGColor(gray: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.15, green: 0.25, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 60 + shift, y: 60, width: 180, height: 240))
        context.setFillColor(CGColor(red: 0.9, green: 0.6, blue: 0.1, alpha: 1))
        context.fillEllipse(in: CGRect(x: 340 + shift, y: 150, width: 160, height: 160))
        if extra {
            context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 380, y: 20, width: 60, height: 60))
        }
    }
}

/// The shared fixture cache, resolved the way I1's and I2's tests resolve it.
enum FeatureFixtures {
    static let root = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["CLOVE_FIXTURES_DIR"]
            ?? "/Volumes/T7/Projects/.clove-fixtures")

    static var formats: URL { root.appendingPathComponent("sets/formats") }
    static var hasFormats: Bool { FileManager.default.fileExists(atPath: formats.path) }
    static func file(_ name: String) -> URL { formats.appendingPathComponent(name) }
}

/// A request whose revision comes from the file, as the app builds it.
func featureRequest(
    _ source: URL, pixels: Int = 400, location: String = "test-folder"
) throws -> ImageFeatureRequest {
    ImageFeatureRequest(
        source: source, revision: try .read(from: source), locationIdentity: location,
        previewPixels: pixels)
}

/// A request with an explicit revision, so cache keys can be probed without touching a file.
func featureRequest(
    _ source: URL, revision: ThumbnailRevision, pixels: Int = 400,
    location: String = "test-folder"
) -> ImageFeatureRequest {
    ImageFeatureRequest(
        source: source, revision: revision, locationIdentity: location, previewPixels: pixels)
}

/// Elements a test can compare by hand; 4 floats keep the arithmetic readable.
func samplePrint(revision: Int = 2, base: Float = 1) -> VisionFeaturePrint {
    VisionFeaturePrint(revision: revision, elements: [base, base + 1, base + 2, base + 3])
}

/// A coarse pixel digest, so a test can prove two stages saw the same bitmap.
func pixelDigest(_ image: CGImage) -> UInt64 {
    let width = 16
    let height = 16
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { buffer in
        guard
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in pixels {
        hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
    }
    return hash
}

/// Records every preview read, its pixels, and how many ran at once.
actor PreviewReadRecorder {
    private(set) var entries: [String] = []
    private(set) var digests: [UInt64] = []
    private(set) var finished = 0
    private(set) var maximumConcurrent = 0
    private var active = 0
    private var holds = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var count: Int { entries.count }
    var activeCount: Int { active }

    func setHolds(_ value: Bool) { holds = value }

    func begin(_ name: String, digest: UInt64) async {
        entries.append(name)
        digests.append(digest)
        active += 1
        maximumConcurrent = max(maximumConcurrent, active)
        if holds { await withCheckedContinuation { waiters.append($0) } }
    }

    func end() {
        active -= 1
        finished += 1
    }

    func release() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

/// Serves generated pixels per file name, so a scheduling test never pays for a real decode.
struct StubFeaturePreviewReader: ImageFeaturePreviewReading {
    let recorder: PreviewReadRecorder
    let images: [String: CGImage]
    /// Files this reader reports as having no usable preview.
    var unavailable: Set<String> = []

    func preview(for request: ThumbnailRequest) async -> ImageFeaturePreviewRead {
        let name = request.source.lastPathComponent
        if unavailable.contains(name) { return .unavailable(.noUsablePreview) }
        guard let image = images[name] else { return .unavailable(.cannotOpen) }
        await recorder.begin(name, digest: pixelDigest(image))
        await recorder.end()
        return .preview(ImageFeaturePreview(image: image, route: .ifAbsent))
    }
}

/// Forwards to I1's real preview reader while recording what it delivered.
struct RecordingThumbnailReader: ImageFeaturePreviewReading {
    let recorder: PreviewReadRecorder
    var delegate = ThumbnailPreviewReader()

    func preview(for request: ThumbnailRequest) async -> ImageFeaturePreviewRead {
        let read = await delegate.preview(for: request)
        if case .preview(let preview) = read {
            await recorder.begin(
                request.source.lastPathComponent, digest: pixelDigest(preview.image))
            await recorder.end()
        }
        return read
    }
}

/// Records which pixels each Vision attempt was given.
actor PrintReadRecorder {
    private(set) var digests: [UInt64] = []
    var count: Int { digests.count }
    func record(_ digest: UInt64) { digests.append(digest) }
}

/// Injects a Vision outcome, so P0-11's fallback is tested without depending on the host.
struct StubFeaturePrintReader: FeaturePrintReading {
    enum Behaviour: Sendable {
        case succeed
        case fail(FeatureFailure)
    }

    var revision = VisionFeaturePrintReader.requestRevision
    var behaviour: Behaviour = .succeed
    var recorder: PrintReadRecorder?

    func featurePrint(of image: CGImage) async -> Result<VisionFeaturePrint, FeatureFailure> {
        await recorder?.record(pixelDigest(image))
        switch behaviour {
        case .succeed: return .success(Self.print(for: image))
        case .fail(let failure): return .failure(failure)
        }
    }

    /// Four elements from a 2×2 render: identical pixels answer identical prints, which is all
    /// a fake needs to stand in for Vision.
    static func print(for image: CGImage) -> VisionFeaturePrint {
        var samples = [UInt8](repeating: 0, count: 4)
        samples.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: 2, height: 2, bitsPerComponent: 8,
                    bytesPerRow: 2, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)
            else { return }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return VisionFeaturePrint(
            revision: VisionFeaturePrintReader.requestRevision,
            elements: samples.map { Float($0) / 255 })
    }
}

/// Forwards to the real Vision reader while recording the pixels and the outcome.
struct RecordingVisionReader: FeaturePrintReading {
    let recorder: PrintReadRecorder
    var delegate = VisionFeaturePrintReader()

    var revision: Int { delegate.revision }

    func featurePrint(of image: CGImage) async -> Result<VisionFeaturePrint, FeatureFailure> {
        await recorder.record(pixelDigest(image))
        return await delegate.featurePrint(of: image)
    }
}

/// Waits for a condition, because scheduling decisions are observed, not inferred from timing.
///
/// The wait sleeps instead of spinning on `Task.yield()`: a busy poll competes with the very
/// worker task it is waiting for, which makes these tests flaky on a loaded host.
func awaitCondition(
    _ description: String, timeout: Duration = .seconds(20), _ condition: () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !(await condition()), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    try #require(await condition(), "Condition did not become true: \(description)")
}

/// Releases held preview reads until the requested number finished.
///
/// A single release can arrive before the next read waits, so this keeps releasing, as I2's
/// scheduling tests do.
func letPreviewReadsFinish(_ recorder: PreviewReadRecorder, count: Int) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while ContinuousClock.now < deadline {
        if await recorder.finished >= count { break }
        await recorder.release()
        try await Task.sleep(for: .milliseconds(2))
    }
    try #require(await recorder.finished >= count, "Held preview reads did not finish")
}

/// Collects a whole feature stream, so a test can assert on every photo's result.
func collect(_ stream: AsyncStream<ImageFeatureResult>) async -> [ImageFeatureResult] {
    var results: [ImageFeatureResult] = []
    for await result in stream { results.append(result) }
    return results
}

/// The features a result settled on, or a recorded failure for the test.
func features(of result: ImageFeatureResult) throws -> ImageFeatures {
    guard case .features(let features) = result.outcome else {
        Issue.record("Expected features, got \(result.outcome)")
        throw CocoaError(.fileReadUnknown)
    }
    return features
}
