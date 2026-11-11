import Testing

@testable import CloveCore

struct WriteDisconnectionTests {
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
