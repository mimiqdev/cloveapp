#if os(macOS)
    import Foundation
    import Testing

    @testable import CloveCore

    /// Records the median time to undo a done move of 50 RAW+HIF+XMP sets.
    ///
    /// PRD P0-10's Undo rule sets no target, so this test only records numbers for the pull
    /// request; it asserts that every set came back and cannot fail on a slow host. The mover,
    /// its undo lane and C4's queue use the real `Foundation`/POSIX seam, so the number is not
    /// distorted by a test double's recording. Each sample moves 50 sets in their own subfolder,
    /// then runs the one undo step, so it includes both the per-file confirmation and the stored
    /// Reject write for every set.
    @Test(.timeLimit(.minutes(1))) func reportsMedianTimeToUndoFiftySets() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let queue = MarkWriteQueue(storeDirectory: fixture.folder.storage)
        let mover = RejectMover(markQueue: queue)
        let configuration = RejectMoveConfiguration(settings: moveSettings())
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
                await queue.apply(.reject(true), to: set)
                sets.append(set)
            }
            let plan = try await mover.plan(
                for: RejectMoveRequest(
                    rootURL: fixture.folder.url, sets: sets, configuration: configuration))
            let moved = try await mover.move(plan)
            #expect(moved.movedCount == 50)
            let entry = RejectMoveUndoEntry(batch: moved.id, photoToReturnTo: sets[0].id)
            let start = clock.now
            let result = try await mover.undo(entry)
            let elapsed = clock.now - start
            #expect(result.restoredCount == 50)
            durations.append(
                Double(elapsed.components.seconds) * 1000
                    + Double(elapsed.components.attoseconds) / 1e15)
        }
        durations.sort()
        let median = durations[durations.count / 2]
        print("Move rejects undo timing on macOS (informational, no gate):")
        print(
            "  50 RAW+HIF+XMP sets, \(samples) samples: \(String(format: "%7.3f", median)) ms median"
        )
        print(
            "  samples: \(durations.map { String(format: "%.3f", $0) }.joined(separator: ", ")) ms")
    }
#endif
