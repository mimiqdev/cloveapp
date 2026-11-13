import Darwin
import Foundation

/// Samples process resident memory without attributing it to one allocation or stage.
/// The five-millisecond peak is a lower bound: framework caches and concurrent work
/// contribute, and short-lived buffers can fall between samples.
public final class LabResidentSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var sampledPeak: UInt64
    private let timer: DispatchSourceTimer

    /// Process RSS when sampling started, in bytes.
    public let baseline: UInt64

    public init() {
        baseline = Self.currentBytes()
        sampledPeak = baseline
        timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "clove.lab.resident-memory"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
    }

    /// The greatest sampled process RSS so far, in bytes.
    public var peak: UInt64 {
        sample()
        return lock.withLock { sampledPeak }
    }

    /// Takes a final sample and stops the timer. Returns the sampled peak in bytes.
    @discardableResult
    public func finish() -> UInt64 {
        timer.cancel()
        return peak
    }

    /// Current process RSS in bytes, or zero when the platform does not supply it.
    public static func currentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.resident_size : 0
    }

    private func sample() {
        let value = Self.currentBytes()
        lock.withLock { sampledPeak = max(sampledPeak, value) }
    }
}
