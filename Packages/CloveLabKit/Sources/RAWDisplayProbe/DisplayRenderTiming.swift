import CoreGraphics
import Darwin
import Foundation
import ImageIO
import LabSupport

/// Why a render produced no pixels. Recorded as a report tag, never thrown past the suite.
public enum RAWDisplayFailure: Error {
    case rawUnsupported, rawNoOutput, cannotRender, noNativeSize
}

/// The columns every render variant reports: time to the first full bitmap, output
/// size, source size, decoded bytes and sampled resident memory.
public struct DisplayRenderTiming: Sendable {
    /// Time from starting the decoder to a materialized CPU bitmap, in milliseconds.
    public var milliseconds: Double = 0
    public var width: Int = 0
    public var height: Int = 0
    /// The decoder's or container's native pixel size, before any requested reduction.
    public var nativeWidth: Int = 0
    public var nativeHeight: Int = 0
    public var decodedBytes: Int = 0
    public var residentBefore: UInt64 = 0
    public var sampledPeakResident: UInt64 = 0
    /// Source EXIF orientation, 1–8. The RAW route applies it in the decoder; the
    /// camera HEIF full and subsample routes report it and orient only for display.
    public var orientation: Int = 1
    public var error: String?

    public init() {}
}

/// Process RSS, sampled every 5 ms during one synchronous decode. A lower bound on
/// peak RSS, not an isolated allocation count: framework caches and concurrent work
/// in the same process contribute, and buffers can be missed between samples.
final class RAWDisplayResidentSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64
    private let timer: DispatchSourceTimer
    let baseline: UInt64

    init() {
        baseline = Self.resident()
        peak = baseline
        timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "clove.rawdisplay.memory"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
    }

    func finish() -> UInt64 {
        timer.cancel()
        sample()
        return lock.withLock { peak }
    }

    /// Current process RSS in bytes, for before/after measurements.
    static func currentBytes() -> UInt64 {
        resident()
    }

    private func sample() {
        let value = Self.resident()
        lock.withLock { peak = max(peak, value) }
    }

    private static func resident() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.resident_size : 0
    }
}

/// Source EXIF orientation from ImageIO, without decoding pixels.
func displaySourceOrientation(url: URL) -> Int {
    guard
        let source = CGImageSourceCreateWithURL(
            url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return 1 }
    return properties[kCGImagePropertyOrientation] as? Int ?? 1
}

/// Milliseconds between two `ContinuousClock` instants.
func displayMilliseconds(since start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now).components
    return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
}

/// Runs one synchronous decode with the standard clock and RAM sampling, so RAW and
/// camera HEIF variants report the same columns. Cancellation discards the result
/// instead of returning a bitmap the caller no longer wants.
func measureDisplay(
    _ body: () throws -> (image: CGImage, native: CGSize)
) throws -> DisplayRenderTiming {
    try Task.checkCancellation()
    let sampler = RAWDisplayResidentSampler()
    let start = ContinuousClock.now
    var timing = DisplayRenderTiming()
    timing.residentBefore = sampler.baseline
    do {
        let result = try body()
        // Forces provider materialization rather than timing a lazy decoder.
        guard let data = result.image.dataProvider?.data, CFDataGetLength(data) > 0 else {
            throw RAWDisplayFailure.cannotRender
        }
        timing.width = result.image.width
        timing.height = result.image.height
        timing.nativeWidth = Int(result.native.width.rounded())
        timing.nativeHeight = Int(result.native.height.rounded())
        timing.decodedBytes = result.image.bytesPerRow * result.image.height
        try Task.checkCancellation()
    } catch is CancellationError {
        _ = sampler.finish()
        throw CancellationError()
    } catch {
        timing.error = String(describing: error)
    }
    timing.milliseconds = displayMilliseconds(since: start)
    timing.sampledPeakResident = sampler.finish()
    return timing
}

extension DisplayRenderTiming {
    /// One row per render, tagged with the file, variant and phase.
    public func measurements(
        file: String, variantName: String, role: String, phase: RAWDisplayPhase,
        request: [String: String]
    ) -> [LabMeasurement] {
        var tags = request
        tags["file"] = file
        tags["variant"] = variantName
        tags["role"] = role
        tags["phase"] = phase.rawValue
        tags["orientation"] = String(orientation)
        tags["status"] = error ?? "ok"
        return [
            ("render-first-bitmap", milliseconds, "ms"),
            ("render-width", Double(width), "px"),
            ("render-height", Double(height), "px"),
            ("native-width", Double(nativeWidth), "px"),
            ("native-height", Double(nativeHeight), "px"),
            ("render-decoded-memory", Double(decodedBytes), "bytes"),
            ("render-resident-before", Double(residentBefore), "bytes"),
            ("render-sampled-peak-resident", Double(sampledPeakResident), "bytes"),
        ].map { LabMeasurement(name: $0.0, value: $0.1, unit: $0.2, tags: tags) }
    }
}
