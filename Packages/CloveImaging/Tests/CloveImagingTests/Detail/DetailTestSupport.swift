import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CloveImaging

/// Writable scratch space. Generated images go here, never into the shared fixture cache.
struct DetailTestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: url) }

    func path(_ name: String) -> URL { url.appendingPathComponent(name) }

    /// A raster image with optional EXIF orientation and an optional embedded thumbnail.
    func image(
        name: String = "photo.jpg", type: UTType = .jpeg, orientation: Int = 1,
        embedded: Bool = false, width: Int = 1200, height: Int = 800
    ) throws -> URL {
        let file = path(name)
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(file as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, image,
            [
                kCGImagePropertyOrientation: orientation,
                kCGImageDestinationEmbedThumbnail: embedded,
            ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return file
    }

    /// Bytes that no image reader accepts, for the unreadable-file state.
    func notAnImage(name: String = "broken.JPG") throws -> URL {
        let file = path(name)
        try Data("This is not a photo.".utf8).write(to: file)
        return file
    }

    /// A copy of a fixture so a test can change bytes without touching the shared cache.
    func copy(of source: URL, as name: String) throws -> URL {
        let file = path(name)
        try FileManager.default.copyItem(at: source, to: file)
        return file
    }

    func cache(megabytes: Int = 32) -> DetailCache {
        var configuration = DetailCache.Configuration()
        configuration.compressedBytes = megabytes * 1024 * 1024
        return DetailCache(configuration: configuration)
    }
}

/// The shared fixture cache, resolved the way I1's tests resolve it.
enum DetailFixtures {
    static let root = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["CLOVE_FIXTURES_DIR"]
            ?? "/Volumes/T7/Projects/.clove-fixtures")

    static func folder(_ set: String) -> URL { root.appendingPathComponent("sets/\(set)") }

    static var formats: URL { folder("formats") }
    static var cardBasic: URL { folder("card-basic") }

    static var hasFormats: Bool { FileManager.default.fileExists(atPath: formats.path) }
    static var hasCardBasic: Bool { FileManager.default.fileExists(atPath: cardBasic.path) }

    static func file(_ name: String) -> URL { formats.appendingPathComponent(name) }

    static func cardFile(_ name: String) -> URL {
        cardBasic.appendingPathComponent("DCIM/100CANON/\(name)")
    }
}

func detailSource(_ url: URL) throws -> DetailSource { try .read(url) }

func rawRequest(
    _ url: URL, displayPixels: Int = 1200, native: Bool = false, location: String = "test-folder"
) throws -> DetailRequest {
    DetailRequest(
        raw: try detailSource(url), displayPixels: displayPixels,
        wantsNativeResolution: native, locationIdentity: location)
}

func rasterRequest(
    _ url: URL, displayPixels: Int = 1200, native: Bool = false, location: String = "test-folder"
) throws -> DetailRequest {
    DetailRequest(
        jpeg: try detailSource(url), displayPixels: displayPixels,
        wantsNativeResolution: native, locationIdentity: location)
}

func availableDetail(_ result: DetailResult) throws -> DetailImage {
    guard case .available(let image) = result else {
        Issue.record("Expected pixels, got \(result)")
        throw CocoaError(.fileReadCorruptFile)
    }
    return image
}

func detailFailure(_ result: DetailResult) throws -> DetailFailure {
    guard case .unavailable(let failure) = result else {
        Issue.record("Expected an explicit failure, got \(result)")
        throw CocoaError(.fileReadUnknown)
    }
    return failure
}

/// Observes actor queue/active state without spinning against the worker being awaited;
/// `DetailPipeline` exposes no queue-state notification stream seam without altering production code.
func eventually(
    _ description: String = "Condition did not become true in time", _ condition: () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while !(await condition()), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    try #require(await condition(), Comment(rawValue: description))
}

/// Asserts a request was cancelled or superseded rather than delivering pixels.
func expectCancelled<Value: Sendable>(_ task: Task<Value, any Error>) async {
    do {
        _ = try await task.value
        Issue.record("Cancelled or superseded request delivered a result")
    } catch is CancellationError {} catch { Issue.record("Cancelled request failed with \(error)") }
}

func makeDetailImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(gray: 0.4, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

/// Records every entry into the reader and can hold or fail the native route, so tests can
/// see scheduling decisions instead of inferring them from timings.
actor DetailReadGate {
    enum NativeBehaviour: Sendable {
        /// A synthetic native render, so scheduling tests never pay for real demosaicing.
        case synthetic
        /// The real `CIRAWFilter` route.
        case real
        /// No pixels, for the RAW-render-failed state.
        case fail
    }

    var behaviour: NativeBehaviour = .synthetic
    var holdsNative = false
    var holdsPreview = false

    private let previewEntries = AsyncStream<String>.makeStream()
    private let nativeEntries = AsyncStream<String>.makeStream()
    private(set) var nativePaths: [String] = []
    private(set) var previewPaths: [String] = []
    private(set) var fullRasterPaths: [String] = []
    func recordFullRaster(_ source: DetailSource) { fullRasterPaths.append(source.url.path) }
    private(set) var maximumNativeEntries = 0
    private(set) var maximumPreviewEntries = 0
    /// Whether a native image was still held when a render was entered, in entry order.
    private(set) var nativeHeldAtEntry: [Bool] = []
    private(set) var didClose = false
    private(set) var finishedPreviews = 0
    private(set) var finishedNatives = 0
    private var activeNative = 0
    private var activePreview = 0
    private var nativeWaiters: [CheckedContinuation<Void, Never>] = []
    private var previewWaiters: [CheckedContinuation<Void, Never>] = []

    func configure(behaviour: NativeBehaviour, holdNative: Bool, holdPreview: Bool) {
        self.behaviour = behaviour
        self.holdsNative = holdNative
        self.holdsPreview = holdPreview
    }

    func beginNative(_ source: DetailSource) async {
        let name = source.url.lastPathComponent
        nativePaths.append(source.url.path)
        activeNative += 1
        maximumNativeEntries = max(maximumNativeEntries, activeNative)
        if holdsNative {
            await withCheckedContinuation { continuation in
                nativeWaiters.append(continuation)
                nativeEntries.continuation.yield(name)
            }
        } else {
            nativeEntries.continuation.yield(name)
        }
    }

    func endNative() {
        activeNative -= 1
        finishedNatives += 1
    }

    func recordNativeHeld(_ held: Bool) { nativeHeldAtEntry.append(held) }

    func markClosed() { didClose = true }

    func beginPreview(_ source: DetailSource) async {
        let name = source.url.lastPathComponent
        previewPaths.append(source.url.path)
        activePreview += 1
        maximumPreviewEntries = max(maximumPreviewEntries, activePreview)
        if holdsPreview {
            await withCheckedContinuation { continuation in
                previewWaiters.append(continuation)
                previewEntries.continuation.yield(name)
            }
        } else {
            previewEntries.continuation.yield(name)
        }
    }

    func endPreview() {
        activePreview -= 1
        finishedPreviews += 1
    }

    func nextPreviewEntry() async throws -> String {
        var iterator = previewEntries.stream.makeAsyncIterator()
        return try #require(await iterator.next(), "A preview read must enter the gate")
    }

    func nextNativeEntry() async throws -> String {
        var iterator = nativeEntries.stream.makeAsyncIterator()
        return try #require(await iterator.next(), "A native read must enter the gate")
    }

    var totalEntries: Int { previewPaths.count + nativePaths.count }

    /// Resumes every held entry.
    func release() {
        let waiters = nativeWaiters + previewWaiters
        nativeWaiters.removeAll()
        previewWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

/// Keeps releasing held entries until the requested preview and native entries have finished.
///
/// Releasing a fixed number of times would race entries that are still queued in the
/// pipeline, and a release that arrives before its entry waits would leave it held forever.
func letEntriesFinish(_ gate: DetailReadGate, previews: Int = 0, natives: Int = 0) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while ContinuousClock.now < deadline {
        let donePreviews = await gate.finishedPreviews
        let doneNatives = await gate.finishedNatives
        if donePreviews >= previews && doneNatives >= natives { break }
        await gate.release()
        try await Task.sleep(for: .milliseconds(2))
    }
    let donePreviews = await gate.finishedPreviews
    let doneNatives = await gate.finishedNatives
    try #require(donePreviews >= previews && doneNatives >= natives)
}

/// A native size read that reports one fixed answer, so a test can supply the preview-sized or
/// missing size a camera without usable index-0 properties gives (#111).
struct StubDetailNativeSizeReader: DetailNativeSizeReading {
    let size: CGSize?

    func nativeSize(of reference: DetailSource, isRAW: Bool) -> CGSize? { size }
}

/// An embedded-preview size a test substitutes for a named file.
///
/// The fixtures expose no usable camera HIF preview and no tiny RAW preview, so these two
/// preview shapes are supplied here rather than by adding binaries to the cache.
struct DetailPreviewSubstitution: Sendable {
    /// The file name whose embedded preview this substitution replaces.
    let file: String
    let width: Int
    let height: Int
}

/// Forwards reads to the real renderer while reporting each entry to a gate.
struct GatedDetailReader: DetailReading {
    let gate: DetailReadGate
    var substitutions: [DetailPreviewSubstitution] = []
    var failedRasterFiles: Set<String> = []
    let delegate = DetailRenderer()

    func read(_ step: DetailPreviewStep, displayPixels: Int) async -> DetailReadOutcome {
        await gate.beginPreview(step.source)
        let outcome: DetailReadOutcome
        if let substituted = substitute(step) {
            outcome = .image(substituted)
        } else {
            outcome = await delegate.read(step, displayPixels: displayPixels)
        }
        await gate.endPreview()
        return outcome
    }

    private func substitute(_ step: DetailPreviewStep) -> CGImage? {
        guard case .embedded(let source) = step else { return nil }
        guard
            let substitution = substitutions.first(where: {
                $0.file == source.url.lastPathComponent
            })
        else { return nil }
        return try? makeDetailImage(width: substitution.width, height: substitution.height)
    }

    func fullRaster(_ source: DetailSource) async -> DetailReadOutcome {
        await gate.recordFullRaster(source)
        if failedRasterFiles.contains(source.url.lastPathComponent) { return .noUsablePreview }
        return await delegate.fullRaster(source)
    }

    func screenRAW(_ source: DetailSource, longEdge: Int) async -> CGImage? {
        await gate.beginNative(source)
        let pixels: CGImage?
        switch await gate.behaviour {
        case .synthetic:
            pixels = try? makeDetailImage(width: longEdge, height: max(1, longEdge * 2 / 3))
        case .real: pixels = await delegate.screenRAW(source, longEdge: longEdge)
        case .fail: pixels = nil
        }
        await gate.endNative()
        return pixels
    }

    func nativeRAW(_ source: DetailSource) async -> CGImage? {
        await gate.beginNative(source)
        let behaviour = await gate.behaviour
        let pixels: CGImage?
        switch behaviour {
        case .synthetic:
            pixels = try? makeDetailImage(width: 64, height: 48)
        case .real:
            pixels = await delegate.nativeRAW(source)
        case .fail:
            pixels = nil
        }
        await gate.endNative()
        return pixels
    }
}
