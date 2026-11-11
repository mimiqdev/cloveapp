import Foundation
import Testing

@testable import CloveCore

private let green = ColourLabel(colour: .green)
private let three = Rating(rawValue: 3) ?? .unrated
private let four = Rating(rawValue: 4) ?? .unrated

/// Reads a packet's marks through the codec, independent of the queue's own confirmation.
private func marks(at url: URL) throws -> XMPMarks {
    try XMPCodec().read(try Data(contentsOf: url))
}

/// A queue whose Clove storage lives inside the test folder.
private func makeQueue(_ folder: WriteTestFolder, _ double: WriteFileSystemDouble)
    -> MarkWriteQueue
{
    MarkWriteQueue(storeDirectory: folder.file("store"), fileSystem: double)
}

@Test func aRatingAndLabelAreSavedAfterTheSidecarReadsBack() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let double = WriteFileSystemDouble()
    let queue = makeQueue(folder, double)
    let set = try makeScannedSet(folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184")
    let sidecar = folder.file("MMQ05184.xmp")

    let status = await queue.apply(MarkChange(rating: three, label: green), to: set)

    #expect(status.state == .savedInSidecar)
    #expect(status.requested.rating == three)
    #expect(try marks(at: sidecar) == XMPMarks(rating: .rated(three), label: green))
    #expect(try folder.stagingNames().isEmpty)
}

@Test func aNewSidecarIsCreatedWithTheReplacedExtensionName() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let queue = makeQueue(folder, WriteFileSystemDouble())
    let set = try makeScannedSet(folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184")
    let sidecar = folder.file("MMQ05184.xmp")

    let status = await queue.apply(.rating(three), to: set)

    #expect(status.state == .savedInSidecar)
    #expect(FileManager.default.fileExists(atPath: sidecar.path))
    #expect(try marks(at: sidecar).rating == .rated(three))
}

@Test func anExistingUpperCasedSidecarSpellingIsReused() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let double = WriteFileSystemDouble()
    let queue = makeQueue(folder, double)
    let upper = folder.file("MMQ05184.XMP")
    try writeTestUnknownPacket.write(to: upper)
    let set = try makeScannedSet(
        folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184",
        sidecar: .resolved(upper))

    let status = await queue.apply(.rating(four), to: set)

    #expect(status.state == .savedInSidecar)
    #expect(try marks(at: upper).rating == .rated(four))
    // G1 Sidecar naming: the actual `.XMP` spelling stays, with no second packet beside it.
    #expect(try folder.entries().filter { $0.lowercased() == "mmq05184.xmp" } == ["MMQ05184.XMP"])
}

@Test func anAmbiguousSidecarIsRefusedWithItsOwnReason() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let double = WriteFileSystemDouble()
    let queue = makeQueue(folder, double)
    let existing = folder.file("MMQ05184.XMP")
    let appended = folder.file("MMQ05184.ARW.xmp")
    try writeTestUnknownPacket.write(to: existing)
    try writeTestUnknownPacket.write(to: appended)
    let set = try makeScannedSet(
        folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184",
        sidecar: .ambiguous([existing, appended]))

    let status = await queue.apply(.rating(three), to: set)

    #expect(status.state.failure?.reason == .ambiguousSidecar)
    #expect(status.state.isSaved == false)
    #expect(double.count(of: .writeStaging) == 0)
    #expect(try Data(contentsOf: existing) == writeTestUnknownPacket)
    #expect(try Data(contentsOf: appended) == writeTestUnknownPacket)
}

@Test func aZeroByteSidecarIsRefusedThroughTheQueue() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let queue = makeQueue(folder, WriteFileSystemDouble())
    let sidecar = folder.file("MMQ05184.xmp")
    try Data().write(to: sidecar)
    let set = try makeScannedSet(
        folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184",
        sidecar: .resolved(sidecar))

    let status = await queue.apply(.label(green), to: set)

    #expect(status.state.failure?.reason == .packetRefused)
    #expect(status.state.failure?.codecError == .emptyPacket)
    #expect(try Data(contentsOf: sidecar).isEmpty)
}

@Test func rejectIsWrittenToTheSidecarAsRatingMinusOne() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let double = WriteFileSystemDouble()
    let queue = makeQueue(folder, double)
    let set = try makeScannedSet(folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184")
    let sidecar = folder.file("MMQ05184.xmp")

    let status = await queue.apply(.rating(.rejected), to: set)

    // Reject is the rating −1, so a RAW set writes it to its one storage and reads it back.
    #expect(status.state == .savedInSidecar)
    #expect(status.state.isSaved)
    #expect(try marks(at: sidecar).rating == .rated(.rejected))
    #expect(double.count(of: .replace, at: sidecar) == 1)
    #expect(try await queue.storedMarks(for: set.id) == nil)
}

@Test func standaloneJpegMarksAreSavedInCloveOnly() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let double = WriteFileSystemDouble()
    let queue = makeQueue(folder, double)
    let set = try makeScannedSet(
        folder: makeFolderIdentity(), root: folder.url, stem: "IMG_0001", formats: [.jpeg])
    let jpeg = folder.file("IMG_0001.JPG")
    let proposedSidecar = folder.file("IMG_0001.xmp")

    let status = await queue.apply(MarkChange(rating: four, label: green), to: set)
    let stored = try await queue.storedMarks(for: set.id)

    #expect(status.state == .savedInCloveOnly)
    #expect(status.state.isSaved)
    #expect(stored?.rating == four)
    #expect(stored?.label == green)
    #expect(stored?.isRejected == false)
    // G1 decision 6: no sidecar and no in-file write for a standalone JPEG.
    #expect(double.records(for: jpeg).isEmpty)
    #expect(double.count(of: .replace, at: proposedSidecar) == 0)
    #expect(!FileManager.default.fileExists(atPath: proposedSidecar.path))
}

@Test func aRatingAndLabelWriteToTheOneStorageTheSetUses() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let queue = makeQueue(folder, WriteFileSystemDouble())
    let set = try makeScannedSet(folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184")
    let sidecar = folder.file("MMQ05184.xmp")

    let status = await queue.apply(MarkChange(rating: three, label: green), to: set)
    let stored = try await queue.storedMarks(for: set.id)

    #expect(status.state == .savedInSidecar)
    #expect(try marks(at: sidecar) == XMPMarks(rating: .rated(three), label: green))
    #expect(stored == nil)
}

@Test func rejectUsesTheStandardRatingAndNeverACloveNamespace() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let double = WriteFileSystemDouble()
    let queue = makeQueue(folder, double)
    let set = try makeScannedSet(
        folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184",
        formats: [.raw, .jpeg, .heif])
    let sidecar = folder.file("MMQ05184.xmp")

    let status = await queue.apply(.rating(.rejected), to: set)

    #expect(status.state == .savedInSidecar)
    let text = try String(contentsOf: sidecar, encoding: .utf8)
    #expect(!text.lowercased().contains("clove"), "a Clove namespace reached XMP")
    #expect(!text.contains("Reject"), "a separate Reject field reached XMP")
    #expect(text.contains("-1"), "Reject did not write the standard rating −1")
    #expect(try marks(at: sidecar) == XMPMarks(rating: .rated(.rejected)))

    // G1 decisions 1–2: companions are reference files, never opened for writing.
    for companion in [folder.file("MMQ05184.JPG"), folder.file("MMQ05184.HIF")] {
        #expect(double.records(for: companion).isEmpty, "\(companion.lastPathComponent) was opened")
    }
    let destinations = Set(double.allRecords.filter { $0.step == .replace }.map(\.url))
    #expect(
        destinations.allSatisfy {
            $0 == sidecar || $0.path.hasPrefix(folder.file("store").path)
        }, "a file outside the sidecar and Clove storage was replaced")
}

@Test func rejectingARawSetRewritesItsSidecarRating() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let queue = makeQueue(folder, WriteFileSystemDouble())
    let set = try makeScannedSet(folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184")
    let sidecar = folder.file("MMQ05184.xmp")
    _ = await queue.apply(.rating(three), to: set)
    let before = try Data(contentsOf: sidecar)

    let status = await queue.apply(.rating(.rejected), to: set)

    #expect(status.state == .savedInSidecar)
    #expect(try Data(contentsOf: sidecar) != before)
    #expect(try marks(at: sidecar).rating == .rated(.rejected))
}

@Test func aLiveCloveStoreIsReadBackByTheQueue() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let queue = makeQueue(folder, WriteFileSystemDouble())
    let identity = makeFolderIdentity()
    let first = try makeScannedSet(
        folder: identity, root: folder.url, stem: "IMG_0001", formats: [.jpeg])
    let second = try makeScannedSet(
        folder: identity, root: folder.url, stem: "IMG_0002", relativeFolderPath: "DCIM",
        formats: [.jpeg])
    _ = await queue.apply(.rating(.rejected), to: first)
    _ = await queue.apply(.rating(four), to: second)

    let stored = try await queue.storedMarks(for: identity)

    #expect(stored.count == 2)
    #expect(stored[first.id]?.isRejected == true)
    #expect(stored[second.id]?.rating == four)
    #expect(stored[second.id]?.isRejected == false)
}

@Test func clearingRejectAfterAConfirmedMoveIsConfirmedByReadBack() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let queue = makeQueue(folder, WriteFileSystemDouble())
    let set = try makeScannedSet(
        folder: makeFolderIdentity(), root: folder.url, stem: "IMG_0001", formats: [.jpeg])
    _ = await queue.apply(.rating(.rejected), to: set)

    let cleared = try await queue.clearReject(for: set.id)
    let stored = try await queue.storedMarks(for: set.id)

    #expect(cleared)
    // The only stored mark was the Reject rating, so the entry is gone.
    #expect(stored == nil)
    #expect(try await queue.clearReject(for: set.id) == false)
}

@Test func aBatchReportsSavedAndFailedCounts() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let double = WriteFileSystemDouble()
    let queue = makeQueue(folder, double)
    let identity = makeFolderIdentity()
    var sets: [ScannedPhotoSet] = []
    for index in 0..<3 {
        sets.append(
            try makeScannedSet(folder: identity, root: folder.url, stem: "BATCH_\(index)"))
    }
    let failing = folder.file("BATCH_1.xmp")
    double.fail(.replace, at: failing, with: POSIXError(.ENOSPC))

    let result = await queue.apply(.rating(three), to: sets)

    #expect(result.outcomes.count == 3)
    #expect(result.confirmedCount == 2)
    #expect(result.failedCount == 1)
    #expect(result.failed.first?.identity == sets[1].id)
    #expect(result.failed.first?.state.failure?.reason == .insufficientSpace)
    #expect(result.partialFailureSummary == "Saved 2 photos. 1 photos couldn't be saved.")
    #expect(try folder.stagingNames().isEmpty)
}

@Test func rapidChangesToOnePhotoWriteEveryRequestWithoutLosingFields() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let double = WriteFileSystemDouble()
    let set = try makeScannedSet(folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184")
    let sidecar = folder.file("MMQ05184.xmp")
    let reached = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    // Hold the first write after staging, so the next two requests arrive while it runs.
    double.beforeOperation = { record in
        guard record.step == .replace, record.url == sidecar, record.count == 1 else { return }
        reached.signal()
        _ = release.wait(timeout: .now() + 10)
    }
    let queue = makeQueue(folder, double)

    async let first = queue.apply(.rating(three), to: set)
    #expect(waitForTestSignal(reached))
    async let second = queue.apply(.label(green), to: set)
    async let third = queue.apply(.rating(.rejected), to: set)
    try await Task.sleep(for: .milliseconds(150))
    release.signal()
    let results = await [first, second, third]

    #expect(results[0].state == .savedInSidecar)
    #expect(results[1].state == .savedInSidecar)
    #expect(results[2].state == .savedInSidecar)
    #expect(double.count(of: .replace, at: sidecar) == 3)
    #expect(try marks(at: sidecar) == XMPMarks(rating: .rated(.rejected), label: green))
    #expect(try await queue.storedMarks(for: set.id) == nil)
    #expect(try folder.stagingNames().isEmpty)
}

@Test func aWriteUsesTheLatestPhotoSetAfterARescan() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let double = WriteFileSystemDouble()
    let identity = makeFolderIdentity()
    let first = try makeScannedSet(folder: identity, root: folder.url, stem: "MMQ05184")
    let existing = folder.file("MMQ05184.XMP")
    let appended = folder.file("MMQ05184.ARW.xmp")
    try writeTestUnknownPacket.write(to: existing)
    try writeTestUnknownPacket.write(to: appended)
    // The rescan resolves the stem's sidecar as ambiguous after the first change was admitted.
    let rescanned = try makeScannedSet(
        folder: identity, root: folder.url, stem: "MMQ05184",
        sidecar: .ambiguous([existing, appended]))
    let sidecar = folder.file("MMQ05184.xmp")
    let reached = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    double.beforeOperation = { record in
        guard record.step == .replace, record.url == sidecar, record.count == 1 else { return }
        reached.signal()
        _ = release.wait(timeout: .now() + 10)
    }
    let queue = makeQueue(folder, double)

    async let firstChange = queue.apply(.rating(three), to: first)
    #expect(waitForTestSignal(reached))
    async let secondChange = queue.apply(.label(green), to: rescanned)
    try await Task.sleep(for: .milliseconds(150))
    release.signal()
    let results = await [firstChange, secondChange]

    // The change already writing finished with the set it started from.
    #expect(results[0].state == .savedInSidecar)
    // The next write took the newest set, so it refused the now-ambiguous sidecar instead of
    // writing to the stale destination.
    #expect(results[1].state.failure?.reason == .ambiguousSidecar)
    #expect(double.count(of: .replace, at: sidecar) == 1)
    #expect(try marks(at: sidecar) == XMPMarks(rating: .rated(three), label: .clear))
}

@Test func corruptCloveStorageIsReportedAndNeverOverwritten() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let queue = makeQueue(folder, WriteFileSystemDouble())
    let set = try makeScannedSet(
        folder: makeFolderIdentity(), root: folder.url, stem: "IMG_0001", formats: [.jpeg])
    _ = await queue.apply(.rating(.rejected), to: set)
    let storeDirectory = folder.file("store")
    let names = try FileManager.default.contentsOfDirectory(atPath: storeDirectory.path)
    let name = try #require(names.first { $0.hasSuffix(".json") })
    let storage = storeDirectory.appendingPathComponent(name)
    let corrupt = Data("{ this is not Clove storage".utf8)
    try corrupt.write(to: storage)

    let status = await queue.apply(.rating(.unrated), to: set)

    #expect(status.state.failure?.storeError != nil)
    #expect(status.state.isSaved == false)
    #expect(try Data(contentsOf: storage) == corrupt, "corrupt storage was overwritten")
    #expect(try folder.stagingNames().isEmpty)
    do {
        _ = try await queue.storedMarks(for: set.id)
        Issue.record("Expected reading the corrupt file to throw")
    } catch let error as CloveMarkStoreError {
        guard case .corruptStorage = error else {
            Issue.record("Expected corruptStorage, got \(error)")
            return
        }
    }
}

@Test func aMarkAfterAFailureDoesNotCarryAbandonedFields() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let double = WriteFileSystemDouble()
    let queue = makeQueue(folder, double)
    let identity = makeFolderIdentity("abandoned")
    let set = try makeScannedSet(folder: identity, root: folder.url, stem: "MMQ05184")
    let sidecar = folder.file("MMQ05184.xmp")
    double.fail(.replace, at: sidecar, with: POSIXError(.ENOSPC))
    let abandoned = await queue.apply(.rating(three), to: set)
    #expect(abandoned.state.failure?.reason == .insufficientSpace)

    await queue.drain()
    double.stopFailing(.replace)
    let later = await queue.apply(.label(green), to: set)

    // PRD Failure and recovery: the next open reads the actual XMP, so a later mark starts from
    // what is on disk instead of merging a request the user abandoned.
    #expect(later.requested.rating == nil)
    #expect(later.state == .savedInSidecar)
    #expect(try marks(at: sidecar) == XMPMarks(label: green))
}
