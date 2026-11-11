import Foundation
import Testing

@testable import CloveCore

private let green = ColourLabel(colour: .green)
private let three = Rating(rawValue: 3) ?? .unrated
private let five = Rating(rawValue: 5) ?? .unrated

/// A store rooted in a throwaway folder, with the same file seam a test can fail.
private func makeStore(_ folder: WriteTestFolder, _ double: WriteFileSystemDouble)
    -> CloveMarkStore
{
    CloveMarkStore(directory: folder.file("store"), fileSystem: double)
}

@Test func storedMarksAreWrittenReadBackAndReadForTheFolder() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let store = makeStore(folder, WriteFileSystemDouble())
    let identity = try makeIdentity()

    try await store.apply(CloveMarkChange(rating: .rejected, label: green), to: identity)

    let stored = try await store.marks(for: identity)
    #expect(stored?.rating == .rejected)
    #expect(stored?.label == green)
    #expect(stored?.isRejected == true)
    let byFolder = try await store.marks(for: identity.folderID)
    #expect(byFolder.count == 1)
    #expect(byFolder[identity]?.isRejected == true)
    // The store keeps its file inside the injected directory and leaves no staging file.
    let entries = try FileManager.default.contentsOfDirectory(atPath: folder.file("store").path)
    #expect(entries.contains { $0.hasSuffix(".json") })
    #expect(try folder.stagingNames(in: "store").isEmpty)
}

@Test func partialChangesKeepTheStoredFields() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let store = makeStore(folder, WriteFileSystemDouble())
    let identity = try makeIdentity()

    try await store.apply(CloveMarkChange(rating: three), to: identity)
    try await store.apply(CloveMarkChange(label: green), to: identity)
    try await store.apply(CloveMarkChange(rating: .rejected), to: identity)

    let stored = try #require(try await store.marks(for: identity))
    #expect(stored.rating == .rejected)
    #expect(stored.label == green)
    #expect(stored.isRejected)
}

@Test func clearingAStoredLabelRemovesIt() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let store = makeStore(folder, WriteFileSystemDouble())
    let identity = try makeIdentity()

    try await store.apply(CloveMarkChange(rating: five, label: green), to: identity)
    try await store.apply(CloveMarkChange(label: .clear), to: identity)

    let stored = try #require(try await store.marks(for: identity))
    #expect(stored.label == nil)
    #expect(stored.rating == five)
}

@Test func clearingARejectKeepsTheStoredLabel() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let store = makeStore(folder, WriteFileSystemDouble())
    let identity = try makeIdentity()
    try await store.apply(CloveMarkChange(rating: .rejected, label: green), to: identity)

    let cleared = try await store.clearReject(for: identity)
    let stored = try #require(try await store.marks(for: identity))

    #expect(cleared)
    #expect(stored.isRejected == false)
    // Clearing Reject leaves the photo unrated (PRD P0-05).
    #expect(stored.rating == nil)
    #expect(stored.label == green)
    #expect(try await store.clearReject(for: identity) == false)
}

@Test func aPhotoWithNothingStoredIsRemovedFromTheFile() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let store = makeStore(folder, WriteFileSystemDouble())
    let identity = try makeIdentity()
    try await store.apply(CloveMarkChange(rating: .rejected), to: identity)

    try await store.apply(CloveMarkChange(rating: .unrated, label: .clear), to: identity)

    #expect(try await store.marks(for: identity) == nil)
}

@Test func foldersHaveSeparateStorageFiles() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let store = makeStore(folder, WriteFileSystemDouble())
    let first = try makeIdentity("first")
    let second = PhotoIdentity(
        folderID: makeFolderIdentity("other"), relativeFolderPath: "", stem: "MMQ05184")

    try await store.apply(CloveMarkChange(rating: .rejected), to: first)
    try await store.apply(CloveMarkChange(rating: .rejected), to: second)

    #expect(try await store.marks(for: first.folderID).count == 1)
    #expect(try await store.marks(for: second.folderID).count == 1)
    let entries = try FileManager.default.contentsOfDirectory(atPath: folder.file("store").path)
    #expect(entries.filter { $0.hasSuffix(".json") }.count == 2)
}

@Test func aFreshStoreInstanceReadsTheConfirmedFile() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let first = makeStore(folder, WriteFileSystemDouble())
    let identity = try makeIdentity()
    try await first.apply(CloveMarkChange(rating: .rejected, label: green), to: identity)

    let second = makeStore(folder, WriteFileSystemDouble())
    let stored = try #require(try await second.marks(for: identity))

    #expect(stored.rating == .rejected)
    #expect(stored.label == green)
    #expect(stored.isRejected)
}

@Test func damagedMarkStorageIsReportedAndNeverOverwritten() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let store = makeStore(folder, WriteFileSystemDouble())
    let identity = try makeIdentity()
    try await store.apply(CloveMarkChange(rating: .rejected), to: identity)
    let file = await store.fileURL(for: identity.folderID)
    let corrupt = Data("{ this is not Clove storage".utf8)
    try corrupt.write(to: file)

    do {
        try await store.apply(CloveMarkChange(rating: .unrated), to: identity)
        Issue.record("Expected the damaged file to be refused")
    } catch let error as CloveMarkStoreError {
        guard case .corruptStorage(let url, _) = error else {
            Issue.record("Expected corruptStorage, got \(error)")
            return
        }
        #expect(url == file)
    }
    #expect(try Data(contentsOf: file) == corrupt)
    #expect(try folder.stagingNames(in: "store").isEmpty)
    do {
        _ = try await store.marks(for: identity)
        Issue.record("Expected reading the damaged file to throw")
    } catch let error as CloveMarkStoreError {
        guard case .corruptStorage = error else {
            Issue.record("Expected corruptStorage, got \(error)")
            return
        }
    }
}

@Test func anOutOfRangeStoredRatingIsCorruptStorage() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let store = makeStore(folder, WriteFileSystemDouble())
    let identity = try makeIdentity()
    try FileManager.default.createDirectory(
        at: folder.file("store"), withIntermediateDirectories: true)
    let file = await store.fileURL(for: identity.folderID)
    let json = """
        {"version":1,"folderID":"\(identity.folderID.rawValue)","photos":\
        [{"relativeFolderPath":"","stem":"mmq05184","isRejected":false,"rating":9}]}
        """
    try Data(json.utf8).write(to: file)

    do {
        _ = try await store.marks(for: identity)
        Issue.record("Expected an out-of-range rating to be refused")
    } catch let error as CloveMarkStoreError {
        guard case .corruptStorage = error else {
            Issue.record("Expected corruptStorage, got \(error)")
            return
        }
    }
}

@Test func anOldFileWithARejectFieldStillDecodesAndDropsTheReject() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let store = makeStore(folder, WriteFileSystemDouble())
    let identity = try makeIdentity()
    let rejectedIdentity = PhotoIdentity(
        folderID: identity.folderID, relativeFolderPath: "DCIM", stem: "mmq05185")
    try FileManager.default.createDirectory(
        at: folder.file("store"), withIntermediateDirectories: true)
    let file = await store.fileURL(for: identity.folderID)
    // The old shape stored Reject in its own field; no migration runs, so it is ignored. The
    // new shape stores Reject as the rating −1.
    let json = """
        {"version":1,"folderID":"\(identity.folderID.rawValue)","photos":[
        {"relativeFolderPath":"DCIM","stem":"mmq05184","isRejected":true},
        {"relativeFolderPath":"DCIM","stem":"mmq05185","isRejected":false,"rating":-1}]}
        """
    try Data(json.utf8).write(to: file)

    let old = try await store.marks(for: identity)
    let new = try await store.marks(for: rejectedIdentity)

    // The old reject is dropped, as the owner decided, and the file still decodes.
    #expect(old?.rating == nil)
    #expect(old?.isRejected == false)
    // A rating of −1 in the new shape is the stored Reject.
    #expect(new?.rating == .rejected)
    #expect(new?.isRejected == true)
}

@Test func aWriteFailureKeepsThePreviousFileAndLeavesNoStaging() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let double = WriteFileSystemDouble()
    let store = makeStore(folder, double)
    let identity = try makeIdentity()
    try await store.apply(CloveMarkChange(rating: .rejected), to: identity)
    let file = await store.fileURL(for: identity.folderID)
    let before = try Data(contentsOf: file)
    double.fail(.replace, at: file, with: POSIXError(.ENOSPC))

    do {
        try await store.apply(CloveMarkChange(rating: three), to: identity)
        Issue.record("Expected the failed replacement to throw")
    } catch {
        let failure = MarkWriteFailure(classifying: error)
        #expect(failure.reason == .insufficientSpace)
    }
    #expect(try Data(contentsOf: file) == before)
    #expect(try folder.stagingNames(in: "store").isEmpty)
}

@Test func aReadBackMismatchIsReportedAndLeavesNoStaging() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let double = WriteFileSystemDouble()
    let store = makeStore(folder, double)
    let identity = try makeIdentity()
    let file = await store.fileURL(for: identity.folderID)
    // The store's first read loads the file; the read-back after the rename is the second.
    double.readResult = { record in
        record.url == file && record.count == 2 ? Data("{}".utf8) : nil
    }

    do {
        try await store.apply(CloveMarkChange(rating: .rejected), to: identity)
        Issue.record("Expected the unconfirmed write to throw")
    } catch let error as CloveMarkStoreError {
        guard case .readBackMismatch(let url) = error else {
            Issue.record("Expected readBackMismatch, got \(error)")
            return
        }
        #expect(url == file)
    }
    #expect(try folder.stagingNames(in: "store").isEmpty)
}

@Test func concurrentWritesToDifferentPhotosOfOneFolderKeepEveryEntry() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let store = makeStore(folder, WriteFileSystemDouble())
    let folderID = makeFolderIdentity()

    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<20 {
            group.addTask {
                try await store.apply(
                    CloveMarkChange(rating: .rejected),
                    to: PhotoIdentity(
                        folderID: folderID, relativeFolderPath: "DCIM", stem: "IMG_\(index)"))
            }
        }
        try await group.waitForAll()
    }

    let stored = try await store.marks(for: folderID)
    #expect(stored.count == 20)
    #expect(stored.values.filter { !$0.isRejected }.isEmpty)
    #expect(try folder.stagingNames(in: "store").isEmpty)
}

/// A photo identity for a test folder.
private func makeIdentity(_ name: String = "folder") throws -> PhotoIdentity {
    PhotoIdentity(
        folderID: makeFolderIdentity(name), relativeFolderPath: "DCIM", stem: "MMQ05184")
}
