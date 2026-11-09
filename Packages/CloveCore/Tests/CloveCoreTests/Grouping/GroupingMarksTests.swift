import Foundation
import Testing

import CloveCore

/// PRD P0-11 and Similar groups rules: grouping never writes or changes marks, sidecars or
/// XMP. It only reads the values it is handed and writes its own cache in app-private storage.
@Test func groupingNeverTouchesMarksOrSidecars() async throws {
    let photoFolder = try GroupingTestFolder()
    defer { photoFolder.remove() }
    let storeFolder = try GroupingTestFolder()
    defer { storeFolder.remove() }
    let cacheFolder = try GroupingTestFolder()
    defer { cacheFolder.remove() }

    let raw = photoFolder.file("MMQ05184.ARW")
    let companion = photoFolder.file("MMQ05185.ARW")
    let sidecar = photoFolder.file("MMQ05184.xmp")
    try Data("raw bytes".utf8).write(to: raw)
    try Data("companion bytes".utf8).write(to: companion)
    let packet = Data(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><x:xmpmeta xmlns:x=\"adobe:ns:meta/\"/>".utf8)
    try packet.write(to: sidecar)
    let filesBefore = try photoFolder.entries()

    // The write queue is the only lane that may change marks; grouping never calls it.
    let queue = MarkWriteQueue(storeDirectory: storeFolder.url)
    let store = CloveMarkStore(directory: storeFolder.url)
    let photos = [groupingPhoto("MMQ05184", at: 0), groupingPhoto("MMQ05185", at: 0.2)]

    let result = await groupingRun(
        photos,
        using: InstantSimilarity(answer: .vision(distance: 0.1)),
        cache: SimilarGroupsCache(directory: cacheFolder.url))

    #expect(groupingStems(result) == [["mmq05184", "mmq05185"]])
    #expect(try photoFolder.entries() == filesBefore)
    #expect(try Data(contentsOf: sidecar) == packet)
    #expect(try await store.marks(for: groupingFolder).isEmpty)
    #expect(await queue.unfinishedChanges().isEmpty)
    #expect(try storeFolder.entries().isEmpty)
}

/// PRD Similar groups rules: the only file grouping writes is its own cache, outside the photos.
@Test func theCacheStaysOutsideTheOpenedFolder() async throws {
    let cacheFolder = try GroupingTestFolder()
    defer { cacheFolder.remove() }
    let cache = SimilarGroupsCache(directory: cacheFolder.url)
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]

    _ = await groupingRun(
        photos, using: InstantSimilarity(answer: .vision(distance: 0.1)), cache: cache)

    let written = try cacheFolder.entries()
    #expect(written.count == 1)
    #expect(written.first?.hasSuffix(".json") == true)
    for name in written {
        #expect(!name.hasSuffix(".xmp"))
        #expect(!name.hasSuffix(".ARW"))
    }
}
