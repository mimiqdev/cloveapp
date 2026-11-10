import Foundation
import Testing

@testable import CloveCore

@Suite struct FolderProgressTests {
    @Test func countsEachDecidedPhotoOnce() {
        let summary = FolderProgress(
            confirmedMarks: [
                PhotoMarks(), PhotoMarks(rating: Rating(rawValue: 4)!),
                PhotoMarks(label: ColourLabel(colour: .green)),
                PhotoMarks(rating: Rating(rawValue: 3)!, isRejected: true),
            ], isComplete: true)
        #expect(summary.total == 4)
        #expect(summary.marked == 2)
        #expect(summary.rejected == 1)
        #expect(summary.left == 1)
        #expect(!summary.finished)
    }

    @Test func doneRequiresCompleteNonemptyScan() {
        #expect(FolderProgress(marked: 2, rejected: 1, total: 3).finished)
        #expect(!FolderProgress(marked: 2, rejected: 1, total: 3, isComplete: false).finished)
        #expect(!FolderProgress(marked: 0, rejected: 0, total: 0).finished)
        let bounded = FolderProgress(marked: 20, rejected: 4, total: 3)
        #expect(bounded.left == 0)
        #expect(bounded.marked == 0)
        #expect(bounded.rejected == 3)
    }

    @Test func confirmedProgressSurvivesCloseAndReopen() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Shoots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = RecentFolderStore(fileURL: root.appendingPathComponent("recents.json"))
        let access = FolderAccess(store: store)
        let opened = try #require(await access.pick(folder).openedFolder)
        let set = try makeScannedSet(folder: opened.recent.identity, root: folder, stem: "IMG_001")
        let queue = MarkWriteQueue(storeDirectory: root.appendingPathComponent("marks"))
        let status = await queue.apply(.rating(Rating(rawValue: 4)!), to: set)
        #expect(status.state.isConfirmed)
        let photo = set.id
        let partial = FolderProgress(
            confirmedMarks: [PhotoMarks().including(status.requested)], isComplete: false,
            lastViewedPhoto: photo, previewPhotos: [photo])
        try await access.recordProgress(partial, for: opened.recent.identity)
        await queue.drain()
        await opened.session.end()
        let reopened = try #require(await access.reopen(opened.recent.id).openedFolder)
        #expect(reopened.recent.progress?.lastViewedPhoto == photo)
        #expect(reopened.recent.progress?.marked == 1)
        #expect(reopened.recent.progress?.finished == false)
        #expect(reopened.recent.lastOpened >= opened.recent.lastOpened)
        await reopened.session.end()
    }

    @Test func oldRecentJSONStillLoadsWithoutProgress() throws {
        let json =
            #"{"id":"10000000-0000-0000-0000-000000000001","bookmark":"","pathSummary":"/Shoots/2026","identityKeys":{},"mediaType":"unknown","photoCount":12,"scanStatus":"complete","lastOpened":0}"#
        let recent = try JSONDecoder().decode(RecentFolder.self, from: Data(json.utf8))
        #expect(recent.photoCount == 12)
        #expect(recent.progress == nil)
        #expect(recent.needsReconnect == nil)
        let photo = PhotoIdentity(
            folderID: recent.identity, relativeFolderPath: "Shoots", stem: "IMG_001")
        var updated = recent
        updated.progress = FolderProgress(marked: 5, rejected: 2, total: 12, lastViewedPhoto: photo)
        let restored = try JSONDecoder().decode(
            RecentFolder.self, from: JSONEncoder().encode(updated))
        #expect(restored.progress?.lastViewedPhoto == photo)
        #expect(restored.progress?.left == 5)
    }
}
