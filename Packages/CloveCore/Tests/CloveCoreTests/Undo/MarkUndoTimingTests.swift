#if os(macOS)
    import Foundation
    import Testing

    @testable import CloveCore

    /// Median milliseconds per call, with a monotonic clock.
    private func markUndoMedianMilliseconds(
        iterations: Int, _ body: (Int) async -> Void
    ) async -> Double {
        let clock = ContinuousClock()
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for index in 0..<iterations {
            let start = clock.now
            await body(index)
            let elapsed = clock.now - start
            samples.append(
                Double(elapsed.components.seconds) * 1000
                    + Double(elapsed.components.attoseconds) / 1e15)
        }
        samples.sort()
        return samples[samples.count / 2]
    }

    /// Reports the median time to record and undo one change and a batch of 20.
    ///
    /// G1's Starting performance targets set no undo target, so this test only records numbers
    /// for the pull request; it asserts nothing about speed and cannot fail on a slow host.
    /// Each sample records the change and undoes it on a temporary folder, so the measured
    /// pair is the full marking-then-undo round trip.
    @Suite("Undo timing")
    struct MarkUndoTimingTests {
        @Test func reportsMedianUndoTimeForOnePhotoAndABatch() async throws {
            let fixture = try UndoTestFixture(
                stems: ["TIMING"] + (0..<20).map { "TIMING_\($0)" })
            defer { fixture.remove() }
            let ratings = try (1...5).map { try #require(Rating(rawValue: $0)) }
            let single = try #require(fixture.photoSets.first).id
            let batchPhotos = fixture.photoSets.dropFirst().map(\.id)

            let onePhoto = await markUndoMedianMilliseconds(iterations: 20) { index in
                await fixture.record(.rating(ratings[index % ratings.count]), on: single)
                _ = await undoStep(fixture)
            }
            let batchOfTwenty = await markUndoMedianMilliseconds(iterations: 5) { index in
                await fixture.recordBatch(
                    .rating(ratings[index % ratings.count]), on: batchPhotos)
                _ = await undoStep(fixture)
            }

            print("Undo timing on macOS (informational, no gate):")
            print(
                "  one photo, 20 samples:      \(String(format: "%7.3f", onePhoto)) ms median"
            )
            print(
                "  batch of 20, 5 samples:     \(String(format: "%7.3f", batchOfTwenty)) ms median"
            )

            #expect(await fixture.history.canUndo == false)
            #expect(await fixture.history.canRedo)
        }
    }
#endif
