import Foundation
import Testing

@testable import CloveCore

@Suite("Stored marks follow renamed photos")
struct MarkStoreRekeyTests {
    @Test func changesRelativeFolderAndStemWhilePreservingOtherEntries() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let old = fixture.identity("old", path: "source")
        let new = fixture.identity("new", path: "Selects")
        let other = fixture.identity("other")
        let marks = CloveStoredMarks(
            rating: .rejected, label: ColourLabel(rawValue: "External label"))
        try await fixture.store.apply(
            CloveMarkChange(rating: marks.rating, label: marks.label), to: old)
        try await fixture.store.apply(CloveMarkChange(rating: Rating(rawValue: 2)), to: other)
        try await fixture.store.rekey(from: old, to: new)
        let reopened = CloveMarkStore(directory: fixture.folder.storage)
        #expect(try await reopened.marks(for: old) == nil)
        #expect(try await reopened.marks(for: new) == marks)
        #expect(try await reopened.marks(for: other)?.rating == Rating(rawValue: 2))
    }

    @Test func unmarkedSourceClearsStaleTargetAndSameIdentityIsNoOp() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let old = fixture.identity("unmarked")
        let new = fixture.identity("stale")
        try await fixture.store.apply(CloveMarkChange(rating: .rejected), to: new)
        try await fixture.store.rekey(from: new, to: new)
        #expect(try await fixture.store.marks(for: new)?.rating == .rejected)
        try await fixture.store.rekey(from: old, to: new)
        #expect(try await fixture.store.marks(for: new) == nil)
    }

    @Test func failedWriteLeavesOriginalStoredEntry() async throws {
        let markFS = MoveMarkFileSystem()
        let fixture = try RenameFixture(markFileSystem: markFS)
        defer { fixture.cleanup() }
        let old = fixture.identity("old")
        let new = fixture.identity("new")
        try await fixture.store.apply(CloveMarkChange(rating: .rejected), to: old)
        markFS.failWrites { _ in POSIXError(.ENOSPC) }
        await #expect(throws: (any Error).self) {
            try await fixture.store.rekey(from: old, to: new)
        }
        #expect(try await fixture.store.marks(for: old)?.rating == .rejected)
        #expect(try await fixture.store.marks(for: new) == nil)
    }

    @Test func differentOpenedFolderIsRefused() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let old = fixture.identity("old")
        let new = PhotoIdentity(
            folderID: FolderIdentity(rawValue: "other-folder"), relativeFolderPath: "", stem: "new")
        await #expect(throws: CloveMarkStoreError.differentFolderIdentities) {
            try await fixture.store.rekey(from: old, to: new)
        }
    }
}
