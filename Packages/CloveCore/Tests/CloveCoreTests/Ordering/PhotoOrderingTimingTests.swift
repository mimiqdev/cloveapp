import Foundation
import Testing

import CloveCore

/// Reports what ordering costs on macOS for 2,000 photos delivered in the scanner's
/// 64-photo batches, with the grid reading the order after each batch (PRD P0-03,
/// G1 decision 3). It informs only, so it asserts no threshold.
@Test func orderingTwoThousandPhotosTimingIsInformational() {
    let total = 2_000
    let batchSize = 64
    var generator = SeededGenerator(seed: 2_000)
    let photos = (0..<total).map { index in
        photo(
            "frame_\(index)",
            time: capture(seconds(Double(index) * 0.4 + Double(index % 11) * 0.001)),
            fileName: String(format: "DSC_%05d.ARW", index))
    }
    let input = photos.shuffled(using: &generator)

    var ordering = PhotoOrdering()
    var index = 0
    var reads = 0
    var slowestRead = 0.0
    let start = ContinuousClock.now
    while index < input.count {
        let end = min(index + batchSize, input.count)
        ordering.insert(Array(input[index..<end]))
        index = end
        let readStart = ContinuousClock.now
        let shown = ordering.photos()
        slowestRead = max(slowestRead, milliseconds(readStart.duration(to: .now)))
        reads += 1
        #expect(shown.count == index)
    }
    let insertAndOrder = milliseconds(start.duration(to: .now))
    #expect(ordering.pendingCount == 0)

    let nameStart = ContinuousClock.now
    let byName = ordering.photos(order: .fileName)
    let nameOrder = milliseconds(nameStart.duration(to: .now))
    #expect(byName.count == total)

    print(
        String(
            format: "Grid ordering: macOS 2,000 photos, 64-photo batches, "
                + "insert+order %d reads %.1f ms (slowest read %.1f ms); "
                + "one filename order %.1f ms (informational)",
            reads, insertAndOrder, slowestRead, nameOrder))
}
