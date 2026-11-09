#if os(macOS)
    import Foundation
    import Testing

    import CloveCore

    /// Median milliseconds per call; the clock is monotonic and includes the codec's own
    /// read-back of every written packet.
    private func medianMilliseconds(
        iterations: Int, _ body: () throws -> Void
    ) rethrows -> Double {
        let clock = ContinuousClock()
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = clock.now
            try body()
            let elapsed = clock.now - start
            samples.append(
                Double(elapsed.components.seconds) * 1000
                    + Double(elapsed.components.attoseconds) / 1e15)
        }
        samples.sort()
        return samples[samples.count / 2]
    }

    /// Reports median read and write time per committed packet.
    ///
    /// G1 sets no XMP codec target, so this test only records numbers for the pull request;
    /// it asserts nothing about speed and cannot fail on a slow host.
    @Test func reportsMedianReadAndWriteTimePerPacket() throws {
        let packets = try XMPTestFixtures.committedPackets().filter {
            !$0.data.isEmpty && !$0.name.contains("malformed")
        }
        let rating = try #require(Rating(rawValue: 3))
        let edit = XMPEdit(rating: .set(rating), label: .set(ColourLabel(colour: .green)))
        let iterations = 40

        print(
            "XMP codec timing on macOS, \(iterations) samples, median milliseconds "
                + "(informational, no gate)"
        )
        for (name, data) in packets {
            let read = try medianMilliseconds(iterations: iterations) {
                _ = try xmpCodec.read(data)
            }
            let write = try medianMilliseconds(iterations: iterations) {
                _ = try xmpCodec.write(edit, into: data)
            }
            print(
                "  \(name.padding(toLength: 28, withPad: " ", startingAt: 0))"
                    + " \(String(format: "%6.3f", read)) ms read"
                    + "  \(String(format: "%6.3f", write)) ms write"
                    + "  \(data.count) bytes"
            )
        }
        let create = try medianMilliseconds(iterations: iterations) {
            _ = try xmpCodec.write(edit, into: nil)
        }
        print(
            "  \("new packet".padding(toLength: 28, withPad: " ", startingAt: 0))"
                + "            \(String(format: "%6.3f", create)) ms write")

        #expect(packets.count >= 8)
        #expect(create > 0)
    }
#endif
