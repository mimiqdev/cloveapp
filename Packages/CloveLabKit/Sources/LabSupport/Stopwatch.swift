import Foundation

/// Measures elapsed time with a monotonic `ContinuousClock`, which never jumps
/// when the wall clock changes.
public struct Stopwatch: Sendable {
    private let start: ContinuousClock.Instant

    /// Starts the clock.
    public init() {
        self.start = ContinuousClock.now
    }

    /// Time since the stopwatch started.
    public var elapsed: Duration {
        ContinuousClock.now - start
    }

    /// ``elapsed`` in seconds, for ``LabMeasurement`` values.
    public var seconds: Double {
        let parts = elapsed.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
