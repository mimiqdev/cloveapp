import CoreGraphics
import Foundation
import Testing

@testable import RAWDisplayProbe

/// An instant, countable engine so loop bounds and cancellation are tested without
/// decoding a file. It has the same synchronous shape as the live measurement path.
final class StubMeasuring: RAWDisplayMeasuring, @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    /// Seconds one RAW or camera render takes when the test wants work in flight.
    private let renderDelay: Double
    /// When set, a render returns a timing with this error instead of pixels.
    private let renderError: String?
    /// When set, every render announces that it entered and then blocks until the
    /// tester releases the gate, so cancellation meets work that is truly in flight.
    private let renderEntered: AsyncStream<Void>.Continuation?
    private let renderRelease: DispatchSemaphore?
    /// When set, every embedded-preview request announces itself, so a test can time
    /// a cancellation to a specific photo without sleeping.
    private let previewEntered: AsyncStream<Void>.Continuation?
    /// Signalled when a render enters; later preview requests wait for it when
    /// `previewWaitsForRender` is set, so a test knows the first render is in flight.
    private let renderEntrySignal: DispatchSemaphore?
    private let previewWaitsForRender: Bool

    init(
        renderDelay: Double = 0, renderError: String? = nil,
        renderEntered: AsyncStream<Void>.Continuation? = nil,
        renderRelease: DispatchSemaphore? = nil,
        previewEntered: AsyncStream<Void>.Continuation? = nil,
        renderEntrySignal: DispatchSemaphore? = nil,
        previewWaitsForRender: Bool = false
    ) {
        self.renderDelay = max(0, renderDelay)
        self.renderError = renderError
        self.renderEntered = renderEntered
        self.renderRelease = renderRelease
        self.previewEntered = previewEntered
        self.renderEntrySignal = renderEntrySignal
        self.previewWaitsForRender = previewWaitsForRender
    }

    func count(_ name: String) -> Int {
        lock.withLock { counts[name, default: 0] }
    }

    private func increment(_ name: String) {
        lock.withLock { counts[name, default: 0] += 1 }
    }

    private func finishRender() throws {
        renderEntered?.yield()
        renderEntrySignal?.signal()
        if let renderRelease {
            // Bounded so a broken implementation cannot hang the suite.
            _ = renderRelease.wait(timeout: .now() + 5)
        } else if renderDelay > 0 {
            Thread.sleep(forTimeInterval: renderDelay)
        }
        increment("render-drained")
        try Task.checkCancellation()
    }

    func renderRAW(url: URL, variant: RAWDisplayVariant) throws -> DisplayRenderTiming {
        try Task.checkCancellation()
        increment("raw-render")
        increment("raw-\(variant.name)")
        try finishRender()
        var timing = DisplayRenderTiming()
        timing.milliseconds = renderDelay * 1_000 + 0.1
        timing.width = max(variant.requestedLongEdge, 120)
        timing.height = max(variant.requestedLongEdge, 120) * 2 / 3
        timing.nativeWidth = 4_000
        timing.nativeHeight = 3_000
        timing.decodedBytes = timing.width * timing.height * 4
        timing.error = renderError
        if renderError != nil {
            timing.width = 0
            timing.height = 0
            timing.decodedBytes = 0
        }
        return timing
    }

    func renderCameraPreview(
        url: URL, variant: CameraPreviewVariant
    ) throws -> DisplayRenderTiming {
        try Task.checkCancellation()
        increment("camera-render")
        increment("camera-\(variant.name)")
        try finishRender()
        var timing = DisplayRenderTiming()
        timing.milliseconds = renderDelay * 1_000 + 0.1
        timing.width = max(variant.requestedLongEdge, 160)
        timing.height = max(variant.requestedLongEdge, 160) * 2 / 3
        timing.nativeWidth = 4_000
        timing.nativeHeight = 3_000
        timing.decodedBytes = timing.width * timing.height * 4
        timing.error = renderError
        if renderError != nil {
            timing.width = 0
            timing.height = 0
            timing.decodedBytes = 0
        }
        return timing
    }

    func rawImage(url: URL, variant: RAWDisplayVariant) throws -> CGImage {
        try Task.checkCancellation()
        increment("raw-image")
        return try solidImage(width: 8, height: 6)
    }

    func cameraPreviewImage(url: URL, variant: CameraPreviewVariant) throws -> CGImage {
        try Task.checkCancellation()
        increment("camera-image")
        return try solidImage(width: 8, height: 6)
    }

    func embeddedPreview(url: URL, maxPixel: Int) throws -> EmbeddedPreviewTiming {
        try Task.checkCancellation()
        previewEntered?.yield()
        increment("embedded-preview")
        if previewWaitsForRender,
            lock.withLock({ counts["embedded-preview", default: 0] }) > 1
        {
            // Bounded; the second photo's preview waits until the first render entered.
            _ = renderEntrySignal?.wait(timeout: .now() + 5)
        }
        return EmbeddedPreviewTiming(milliseconds: 0.05, width: 400, height: 267)
    }

    func embeddedPreviewImage(url: URL, maxPixel: Int) throws -> CGImage {
        try Task.checkCancellation()
        increment("embedded-preview-image")
        return try solidImage(width: 8, height: 6, red: 128, green: 128, blue: 128)
    }
}

/// A solid sRGB bitmap, for colour and stub images.
func solidImage(
    width: Int, height: Int, red: UInt8 = 0, green: UInt8 = 0, blue: UInt8 = 0
) throws -> CGImage {
    let bytesPerRow = width * 4
    var bytes = [UInt8](repeating: 255, count: bytesPerRow * height)
    for index in stride(from: 0, to: bytes.count, by: 4) {
        bytes[index] = red
        bytes[index + 1] = green
        bytes[index + 2] = blue
    }
    let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    return try #require(
        CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent))
}
