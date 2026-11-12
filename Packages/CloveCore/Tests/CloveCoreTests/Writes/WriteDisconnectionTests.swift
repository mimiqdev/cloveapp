import Foundation
import Testing

@testable import CloveCore

struct WriteDisconnectionTests {
    @Test func droppingWaitingWritesLetsTheActiveReplacementFinish() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let set = try makeScannedSet(folder: makeFolderIdentity(), root: folder.url, stem: "photo")
        let fileSystem = WriteFileSystemDouble()
        let (entered, entry) = AsyncStream<Void>.makeStream()
        var entries = entered.makeAsyncIterator()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        fileSystem.beforeOperation = { record in
            if record.step == .synchronize {
                entry.yield(())
                _ = release.wait(timeout: .now() + 5)
            }
        }
        let queue = MarkWriteQueue(storeDirectory: folder.file("store"), fileSystem: fileSystem)
        let active = Task { await queue.apply(.label(ColourLabel(colour: .red)), to: set) }
        await entries.next()
        let waiting = Task { await queue.apply(.rating(.rejected), to: set) }
        try await Task.sleep(for: .milliseconds(150))
        await queue.discardChanges(in: set.id.folderID)
        release.signal()
        #expect(await active.value.state.isConfirmed)
        #expect(await waiting.value.state.failure?.reason == .locationUnavailable)
        await queue.drain()
        let marks = try XMPCodec().read(Data(contentsOf: folder.file("photo.xmp")))
        #expect(marks.label == ColourLabel(colour: .red))
        #expect(marks.rating != .rated(.rejected))
        #expect(fileSystem.count(of: .replace) == 1)
        #expect(try folder.stagingNames().isEmpty)
    }

    @Test func stoppingTheActionQueueDropsItsPendingEntries() {
        let photo = PhotoIdentity(
            folderID: FolderIdentity(rawValue: "disconnected"), relativeFolderPath: "",
            stem: "photo")
        var desired = DesiredPhotoMarks()
        let edit = desired.apply(.rating(.rejected), to: photo, confirmed: PhotoMarks())
        var queue = PhotoActionPipeline()
        let active = queue.submit(.mark(edit))
        let waiting = queue.submit(.mark(edit))
        #expect(queue.beginNext()?.id == active)
        #expect(queue.removePending().map(\.id) == [waiting])
        #expect(queue.active?.id == active)
        queue.finish(active)
        #expect(queue.isEmpty)
        #expect(queue.beginNext() == nil)
    }
}
