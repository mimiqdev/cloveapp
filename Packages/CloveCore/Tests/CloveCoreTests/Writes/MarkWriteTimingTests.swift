#if os(macOS)
    import Foundation
    import Testing

    @testable import CloveCore

    /// Median milliseconds per call, with a monotonic clock.
    private func medianMilliseconds(
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

    /// Reports the median time to **Saved** for one XMP change and for a batch of 50.
    ///
    /// G1's Starting performance targets set no write target, so this test only records
    /// numbers for the pull request; it asserts nothing about speed and cannot fail on a slow
    /// host. Each sample runs the full staged write and read-back on a temporary folder.
    @Test func reportsMedianTimeToSavedForOneChangeAndABatchOfFifty() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let queue = MarkWriteQueue(
            storeDirectory: folder.file("store"), fileSystem: WriteFileSystemDouble())
        let identity = makeFolderIdentity()
        let single = try makeScannedSet(folder: identity, root: folder.url, stem: "TIMING_ONCE")
        let ratings = try (1...5).map { try #require(Rating(rawValue: $0)) }
        var sets: [ScannedPhotoSet] = []
        for index in 0..<50 {
            sets.append(
                try makeScannedSet(
                    folder: identity, root: folder.url, stem: "TIMING_\(index)"))
        }

        let oneChange = await medianMilliseconds(iterations: 20) { index in
            _ = await queue.apply(.rating(ratings[index % ratings.count]), to: single)
        }
        let batchOfFifty = await medianMilliseconds(iterations: 5) { index in
            _ = await queue.apply(.rating(ratings[index % ratings.count]), to: sets)
        }

        print(
            "XMP write timing to Saved on macOS (informational, no gate):")
        print("  one photo, 20 samples:       \(String(format: "%7.3f", oneChange)) ms median")
        print(
            "  batch of 50, 5 samples:     \(String(format: "%7.3f", batchOfFifty)) ms median"
        )

        let last = await queue.apply(.rating(ratings[2]), to: single)
        let lastBatch = await queue.apply(.rating(ratings[2]), to: sets)
        #expect(last.state == .savedInSidecar)
        #expect(lastBatch.confirmedCount == 50)
        #expect(try await queue.storedMarks(for: single.id) == nil)
        #expect(try folder.stagingNames().isEmpty)
    }
#endif
