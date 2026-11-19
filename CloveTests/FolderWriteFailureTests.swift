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
        #expect(model.failureToastMessage == nil)
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

    @Test func rereadsASidecarCreatedAfterTheScanOnFailureAndMoveUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let photos = root.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("photo".utf8).write(to: photos.appendingPathComponent("photo.ARW"))
        let fileSystem = FolderWriteFileSystem()
        let stores = FolderLibrarySession.Stores(
            access: FolderAccess(
                store: RecentFolderStore(fileURL: root.appendingPathComponent("recents.json"))),
            writes: MarkWriteQueue(
                storeDirectory: root.appendingPathComponent("marks"), fileSystem: fileSystem),
            groups: SimilarGroupsCache(directory: root.appendingPathComponent("groups")))
        let library = FolderLibrarySession(stores: Task { stores }, similarGroupsEnabled: { false })
        let model = BrowsingModel(library: library)
        await model.openPickedFolder(photos)
        try await waitUntil { !model.isFolderOpening && model.photos.count == 1 }
        let photo = try #require(model.photos.first?.id)
        #expect(library.scannedSet(for: photo)?.sidecar == .absent)
        let three = try #require(Rating(rawValue: 3))
        model.apply(.rating(three), to: photo)
        await model.drainActions()
        fileSystem.setFailing(true)
        model.apply(.label(ColourLabel(colour: .red)), to: photo)
        await model.drainActions()
        #expect(model.failureToastMessage == BrowsingModel.saveFailureToastMessage)
        #expect(model.shownMarks(for: photo) == PhotoMarks(rating: three))
        fileSystem.setFailing(false)
        model.apply(.rating(.rejected), to: photo)
        await model.drainActions()
        let plan = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        model.runRejectMove(plan, kept: []) { _ in }
        await model.drainActions()
        let completed = try #require(model.lastRejectMove)
        #expect(model.photos.isEmpty)
        model.undoRejectMove(completed)
        await model.drainActions()
        #expect(model.shownMarks(for: photo).isRejected)
        let packet = try XMPCodec().read(
            Data(contentsOf: photos.appendingPathComponent("photo.xmp")))
        #expect(packet.rating == .rated(.rejected))
        await library.closeFolder()
    }

    @Test func unreadableSidecarsPreserveKnownMarksAndDoNotHidePhotos() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let photos = root.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("photo".utf8).write(to: photos.appendingPathComponent("photo.ARW"))
        let sidecar = photos.appendingPathComponent("photo.xmp")
        let three = try #require(Rating(rawValue: 3))
        try XMPCodec().write(.rating(three), into: nil).write(to: sidecar)
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
        #expect(model.shownMarks(for: photo).rating == three)
        try FileManager.default.removeItem(at: sidecar)
        try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: false)
        model.apply(.label(ColourLabel(colour: .red)), to: photo)
        await model.drainActions()
        #expect(model.shownMarks(for: photo) == PhotoMarks(rating: three))
        #expect(model.failureToastMessage == BrowsingModel.saveFailureToastMessage)
        #expect(model.failureToastBurst == 1)
        try FileManager.default.removeItem(at: sidecar)
        try await library.rereadMarks(for: [photo])
        try await waitUntil { model.shownMarks(for: photo) == PhotoMarks() }
        model.dismissFailureToast()
        try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: false)
        try Data("photo".utf8).write(to: photos.appendingPathComponent("other.ARW"))
        try XMPCodec().write(.rating(three), into: nil).write(
            to: photos.appendingPathComponent("other.xmp"))
        await model.reopenOpenFolder()
        try await waitUntil { !model.isFolderOpening && model.photos.count == 2 }
        let other = try #require(model.photos.first { $0.id.stem == "other" }?.id)
        #expect(model.shownMarks(for: other).rating == three)
        #expect(model.failureToastMessage == BrowsingModel.readFailureToastMessage)
        #expect(model.failureToastBurst == 2)
        await library.closeFolder()
    }

    @Test func scanIsolatesUnreadableSidecarFromHealthySiblingsBeforeAndAfter() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let photos = root.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codec = XMPCodec()
        let four = try #require(Rating(rawValue: 4))
        let two = try #require(Rating(rawValue: 2))

        try Data("photo".utf8).write(to: photos.appendingPathComponent("a_before.ARW"))
        try codec.write(
            XMPEdit(
                rating: .set(four),
                label: .set(ColourLabel(colour: .green)),
                keywords: .set(["harbour", "dawn"])),
            into: nil
        ).write(to: photos.appendingPathComponent("a_before.xmp"))

        try Data("photo".utf8).write(to: photos.appendingPathComponent("b_unreadable.ARW"))
        try FileManager.default.createDirectory(
            at: photos.appendingPathComponent("b_unreadable.xmp"),
            withIntermediateDirectories: false)

        try Data("photo".utf8).write(to: photos.appendingPathComponent("c_after.ARW"))
        try codec.write(
            XMPEdit(
                rating: .set(two),
                label: .set(ColourLabel(colour: .blue)),
                keywords: .set(["cliff", "mist"])),
            into: nil
        ).write(to: photos.appendingPathComponent("c_after.xmp"))

        let stores = FolderLibrarySession.Stores(
            access: FolderAccess(
                store: RecentFolderStore(fileURL: root.appendingPathComponent("recents.json"))),
            writes: MarkWriteQueue(storeDirectory: root.appendingPathComponent("marks")),
            groups: SimilarGroupsCache(directory: root.appendingPathComponent("groups")))
        let library = FolderLibrarySession(stores: Task { stores }, similarGroupsEnabled: { false })
        let model = BrowsingModel(library: library)
        await model.openPickedFolder(photos)
        try await waitUntil { !model.isFolderOpening && model.photos.count == 3 }

        let before = try #require(model.photos.first { $0.id.stem == "a_before" }?.id)
        let unreadable = try #require(model.photos.first { $0.id.stem == "b_unreadable" }?.id)
        let after = try #require(model.photos.first { $0.id.stem == "c_after" }?.id)

        #expect(
            model.shownMarks(for: before)
                == PhotoMarks(
                    rating: four,
                    label: ColourLabel(colour: .green),
                    keywords: ["harbour", "dawn"]))
        #expect(model.shownMarks(for: unreadable) == PhotoMarks())
        #expect(
            model.shownMarks(for: after)
                == PhotoMarks(
                    rating: two,
                    label: ColourLabel(colour: .blue),
                    keywords: ["cliff", "mist"]))
        #expect(model.failureToastMessage == BrowsingModel.readFailureToastMessage)
        await library.closeFolder()
    }

    @Test func rereadMarksPreservesUnreadablePhotoAndUpdatesHealthySibling() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let photos = root.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codec = XMPCodec()
        let one = try #require(Rating(rawValue: 1))
        let three = try #require(Rating(rawValue: 3))
        let five = try #require(Rating(rawValue: 5))

        try Data("photo".utf8).write(to: photos.appendingPathComponent("a_unreadable.ARW"))
        let unreadableSidecar = photos.appendingPathComponent("a_unreadable.xmp")
        try codec.write(
            XMPEdit(
                rating: .set(three),
                label: .set(ColourLabel(colour: .red)),
                keywords: .set(["meadow"])),
            into: nil
        ).write(to: unreadableSidecar)

        try Data("photo".utf8).write(to: photos.appendingPathComponent("b_healthy.ARW"))
        let healthySidecar = photos.appendingPathComponent("b_healthy.xmp")
        try codec.write(.rating(one), into: nil).write(to: healthySidecar)

        let stores = FolderLibrarySession.Stores(
            access: FolderAccess(
                store: RecentFolderStore(fileURL: root.appendingPathComponent("recents.json"))),
            writes: MarkWriteQueue(storeDirectory: root.appendingPathComponent("marks")),
            groups: SimilarGroupsCache(directory: root.appendingPathComponent("groups")))
        let library = FolderLibrarySession(stores: Task { stores }, similarGroupsEnabled: { false })
        let model = BrowsingModel(library: library)
        await model.openPickedFolder(photos)
        try await waitUntil { !model.isFolderOpening && model.photos.count == 2 }

        let unreadable = try #require(model.photos.first { $0.id.stem == "a_unreadable" }?.id)
        let healthy = try #require(model.photos.first { $0.id.stem == "b_healthy" }?.id)
        let expectedUnreadableMarks = PhotoMarks(
            rating: three,
            label: ColourLabel(colour: .red),
            keywords: ["meadow"])
        #expect(model.shownMarks(for: unreadable) == expectedUnreadableMarks)
        #expect(model.shownMarks(for: healthy) == PhotoMarks(rating: one))

        try FileManager.default.removeItem(at: unreadableSidecar)
        try FileManager.default.createDirectory(
            at: unreadableSidecar, withIntermediateDirectories: false)
        try codec.write(
            XMPEdit(
                rating: .set(five),
                label: .set(ColourLabel(colour: .purple)),
                keywords: .set(["summit", "ridge"])),
            into: nil
        ).write(to: healthySidecar)

        try await library.rereadMarks(for: [unreadable, healthy])
        let expectedHealthyMarks = PhotoMarks(
            rating: five,
            label: ColourLabel(colour: .purple),
            keywords: ["summit", "ridge"])
        try await waitUntil { model.shownMarks(for: healthy) == expectedHealthyMarks }
        #expect(model.shownMarks(for: unreadable) == expectedUnreadableMarks)
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

private final class FolderWriteFileSystem: MarkWriteFileSystem, @unchecked Sendable {
    private let backing = FoundationMarkWriteFileSystem()
    private let lock = NSLock()
    private var fails = false

    func setFailing(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        fails = value
    }

    func read(_ url: URL) throws -> Data? { try backing.read(url) }
    func attributes(of url: URL) throws -> MarkFileAttributes? { try backing.attributes(of: url) }
    func createDirectory(_ url: URL) throws { try backing.createDirectory(url) }
    func writeStaging(_ data: Data, to url: URL) throws {
        lock.lock()
        let failure = fails
        lock.unlock()
        if failure { throw CocoaError(.fileWriteUnknown) }
        try backing.writeStaging(data, to: url)
    }
    func synchronize(_ url: URL) throws { try backing.synchronize(url) }
    func replace(_ url: URL, withItemAt staging: URL) throws {
        try backing.replace(url, withItemAt: staging)
    }
    func setPermissions(_ permissions: UInt16, of url: URL) throws {
        try backing.setPermissions(permissions, of: url)
    }
    func remove(_ url: URL) throws { try backing.remove(url) }
}
