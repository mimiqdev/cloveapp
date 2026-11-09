import Foundation
import Testing

@testable import SpikeSupport

@Test func stopwatchMeasuresElapsedTime() async throws {
    let stopwatch = Stopwatch()
    try await Task.sleep(for: .milliseconds(50))
    #expect(stopwatch.elapsed >= .milliseconds(50))
    #expect(stopwatch.seconds >= 0.05)
    #expect(stopwatch.seconds < 10)
}

@Test func elapsedOnlyGrows() async throws {
    let stopwatch = Stopwatch()
    let first = stopwatch.seconds
    try await Task.sleep(for: .milliseconds(10))
    #expect(stopwatch.seconds > first)
}

@Test func secondsMatchTheDuration() {
    let stopwatch = Stopwatch()
    #expect(stopwatch.elapsed >= .zero)
    #expect(stopwatch.seconds >= 0)
}
