import CloveCore
import Foundation
import Testing

@testable import Clove

@MainActor
struct FolderWriteFailureTests {
    @Test func aRealFolderSessionReportsLossAndReopenReadsItsSidecar() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let photos = root.appendingPathComponent("photos")
        let hidden = root.appendingPathComponent("disconnected")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("photo".utf8).write(to: photos.appendingPathComponent("photo.ARW"))
        let sidecar = photos.appendingPathComponent("photo.xmp")
        let two = try #require(Rating(rawValue: 2))
        try XMPCodec().write(.rating(two), into: nil).write(to: sidecar)
        let stores = FolderLibrarySession.Stores(
            access: FolderAccess(
                store: RecentFolderStore(fileURL: root.appendingPathComponent("recents.json"))),
            writes: MarkWriteQueue(storeDirectory: root.appendingPathComponent("marks")),
            groups: SimilarGroupsCache(directory: root.appendingPathComponent("groups")))
        let library = FolderLibrarySession(stores: Task { stores }, similarGroupsEnabled: { false })
        let model = BrowsingModel(library: library)
        await model.openPickedFolder(photos)
        try await waitUntil { !model.isFolderOpening && model.photos.count == 1 }
        let photo = try #require(model.photos.first?.id)
        #expect(model.shownMarks(for: photo).rating == two)
        try FileManager.default.moveItem(at: photos, to: hidden)
        model.apply(.rating(.rejected), to: photo)
        #expect(model.shownMarks(for: photo).isRejected)
        await model.drainActions()
        try await waitUntil { model.folderLocationLoss != nil }
        #expect(!model.canMark)
        #expect(model.shownMarks(for: photo).rating == two)
        #expect(!model.isSaveFailureToastVisible)
        let writesBefore = try Data(contentsOf: hidden.appendingPathComponent("photo.xmp"))
        model.apply(.label(ColourLabel(colour: .red)), to: photo)
        await model.drainActions()
        #expect(try Data(contentsOf: hidden.appendingPathComponent("photo.xmp")) == writesBefore)
        try FileManager.default.moveItem(at: hidden, to: photos)
        let four = try #require(Rating(rawValue: 4))
        try XMPCodec().write(.rating(four), into: writesBefore).write(to: sidecar)
        await model.reopenOpenFolder()
        try await waitUntil { !model.isFolderOpening && model.photos.count == 1 }
        #expect(model.canMark)
        #expect(model.shownMarks(for: photo).rating == four)
        #expect(model.shownMarks(for: photo).label.isClear)
        await library.closeFolder()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw FolderWriteWaitFailure()
    }
}

private struct FolderWriteWaitFailure: Error {}
