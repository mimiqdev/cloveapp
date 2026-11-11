import Foundation
import Testing

@testable import CloveCore

struct WriteDisconnectionTests {
    @Test func disconnectCancelsAStagedWriteAndDropsEveryQueuedStatus() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let identity = makeFolderIdentity("disconnected")
        let sidecar = folder.file("photo.xmp")
        try writeTestUnknownPacket.write(to: sidecar)
        let set = try makeScannedSet(
            folder: identity, root: folder.url, stem: "photo", sidecar: .resolved(sidecar))
        let fileSystem = WriteFileSystemDouble()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        fileSystem.beforeOperation = { record in
            if record.step == .synchronize {
                entered.signal()
                _ = waitForTestSignal(release)
            }
        }
        let queue = MarkWriteQueue(
            storeDirectory: folder.file("store"), fileSystem: fileSystem)
        let first = Task { await queue.apply(.label(ColourLabel(colour: .red)), to: set) }
        #expect(waitForTestSignal(entered))
        let later = Task { await queue.apply(.rating(.rejected), to: set) }
        for _ in 0..<1000 {
            if await queue.latestChange(for: set.id)?.state == .pending { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await queue.latestChange(for: set.id)?.state == .pending)
        await queue.discardChanges(in: identity)
        release.signal()
        let firstResult = await first.value
        let laterResult = await later.value
        await queue.drain()
        #expect(firstResult.state.failure?.reason == .locationUnavailable)
        #expect(laterResult.state.failure?.reason == .locationUnavailable)
        #expect(await queue.status(of: firstResult.id) == nil)
        #expect(await queue.latestChange(for: set.id) == nil)
        #expect(await queue.unfinishedChanges().isEmpty)
        #expect(fileSystem.count(of: .replace) == 0)
        #expect(try Data(contentsOf: sidecar) == writeTestUnknownPacket)
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
        queue.submit(.mark(edit))
        #expect(queue.beginNext()?.id == active)
        queue.removePending()
        queue.finish(active)
        #expect(queue.isEmpty)
        #expect(queue.beginNext() == nil)
    }
}
