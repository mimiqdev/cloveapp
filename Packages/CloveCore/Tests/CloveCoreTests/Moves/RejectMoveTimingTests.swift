#if os(macOS)
    import Foundation
    import Testing

    @testable import CloveCore

    /// Records the median time to move 50 RAW+HIF+XMP sets.
    ///
    /// PRD P0-10 sets no move target, so this test only records numbers for the pull request;
    /// it asserts that every set moved and cannot fail on a slow host. Each sample creates 50
    /// sets in their own subfolder and runs the whole plan and move on a temporary folder, so
    /// the number includes the plan's existence checks, the per-file confirmation and C4's
    /// stored-Reject lookup.
    @Test(.timeLimit(.minutes(1))) func reportsMedianTimeToMoveFiftySets() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let samples = 5
        let clock = ContinuousClock()
        var durations: [Double] = []
        durations.reserveCapacity(samples)
        for round in 0..<samples {
            var sets: [ScannedPhotoSet] = []
            sets.reserveCapacity(50)
            for index in 0..<50 {
                let set = try makeMoveSet(
                    root: fixture.folder.url, relativePath: "DCIM/100\(round)",
                    stem: "IMG_\(index)", formats: [.raw, .heif],
                    sidecarName: "IMG_\(index).xmp")
                try writeMoveSet(set, in: fixture.folder)
                sets.append(set)
            }
            let plan = try await fixture.plan(sets)
            let start = clock.now
            let result = try await fixture.mover.move(plan)
            let elapsed = clock.now - start
            #expect(result.movedCount == 50)
            durations.append(
                Double(elapsed.components.seconds) * 1000
                    + Double(elapsed.components.attoseconds) / 1e15)
        }
        durations.sort()
        let median = durations[durations.count / 2]
        print("Move rejects timing on macOS (informational, no gate):")
        print("  50 RAW+HIF+XMP sets, \(samples) samples: \(String(format: "%7.3f", median)) ms median")
        print("  samples: \(durations.map { String(format: "%.3f", $0) }.joined(separator: ", ")) ms")
    }
#endif
