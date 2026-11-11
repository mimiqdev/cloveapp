import CloveCore
import CloveImaging
import CoreGraphics
import Foundation
import Testing

@testable import Clove

struct EntryThumbnailStoreTests {
    @Test func storesPreviewsByIdentityAndSourceRevision() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EntryThumbnailStore(directory: directory)
        let photo = photo(stem: "first")
        let revision = revision()
        #expect(await store.image(for: photo) == nil)
        #expect(await store.contains(photo, revision: revision) == false)

        await store.store(try image(width: 8), for: photo, revision: revision)
        #expect(await store.contains(photo, revision: revision))
        #expect(await store.image(for: photo)?.width == 8)
        await store.store(try image(width: 16), for: photo, revision: revision)
        #expect(await store.image(for: photo)?.width == 8)

        let changed = [
            self.revision(name: "renamed.jpg"), self.revision(size: 200),
            self.revision(date: Date(timeIntervalSince1970: 2)),
        ]
        for revision in changed {
            #expect(await store.contains(photo, revision: revision) == false)
        }
        let newer = changed[1]
        await store.store(try image(width: 16), for: photo, revision: newer)
        #expect(await store.contains(photo, revision: revision) == false)
        let reopened = EntryThumbnailStore(directory: directory)
        #expect(await reopened.contains(photo, revision: newer))
        #expect(await reopened.image(for: photo)?.width == 16)
    }

    @Test func retainPrunesOnlyTheSelectedFoldersOtherPreviewsAndMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EntryThumbnailStore(directory: directory)
        let keep = photo(stem: "keep")
        let remove = photo(stem: "remove")
        let otherFolder = photo(stem: "keep", folder: "other-folder")
        let image = try image(width: 8)
        let revision = revision()
        for photo in [keep, remove, otherFolder] {
            await store.store(image, for: photo, revision: revision)
        }
        await store.retain([keep, otherFolder], in: keep.folderID)
        #expect(await store.contains(keep, revision: revision))
        #expect(await store.image(for: remove) == nil)
        #expect(await store.contains(remove, revision: revision) == false)
        #expect(await store.contains(otherFolder, revision: revision))
        let retained = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
        #expect(retained.filter { $0.hasSuffix(".jpg") }.count == 2)
        #expect(retained.filter { $0.hasSuffix(".json") }.count == 2)

        await store.retain([], in: keep.folderID)
        #expect(await store.contains(keep, revision: revision) == false)
        #expect(await store.contains(otherFolder, revision: revision))
        let remaining = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
        #expect(remaining.filter { $0.hasSuffix(".jpg") }.count == 1)
        #expect(remaining.filter { $0.hasSuffix(".json") }.count == 1)
    }

    @Test func aCacheWriteFailureLeavesAPreviewMiss() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a directory".utf8).write(to: directory)
        let store = EntryThumbnailStore(directory: directory)
        let photo = photo(stem: "first")
        let revision = revision()
        await store.store(try image(width: 8), for: photo, revision: revision)
        #expect(await store.contains(photo, revision: revision) == false)
        #expect(await store.image(for: photo) == nil)
    }

    private func photo(stem: String, folder: String = "preview-folder") -> PhotoIdentity {
        PhotoIdentity(
            folderID: FolderIdentity(rawValue: folder), relativeFolderPath: "", stem: stem)
    }

    private func revision(
        name: String = "photo.jpg", size: Int64 = 100,
        date: Date = Date(timeIntervalSince1970: 1)
    ) -> EntryThumbnailStore.SourceRevision {
        .init(sourceName: name, file: .init(size: size, modificationTime: date))
    }

    private func image(width: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: 4, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: 4))
        return try #require(context.makeImage())
    }
}
