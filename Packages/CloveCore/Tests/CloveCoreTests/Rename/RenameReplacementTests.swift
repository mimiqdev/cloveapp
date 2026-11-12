import Foundation
import Testing

@testable import CloveCore

@Suite("Rename replacements")
struct RenameReplacementTests {
    @Test func rawSetWithSidecarMovesToCustomRejectsWithOneSuffix() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let source = try fixture.item(
            "source", path: "sub", formats: [.raw, .heif], sidecar: "source.xmp")
        let old = try fixture.item("001", path: "sub", formats: [.raw, .heif], sidecar: "001.XMP")
        let oldBytes = old.set.photoSet.fileURLs.map { try? Data(contentsOf: $0) }
        try fixture.folder.write("already rejected", to: "sub/Discard/001.HIF")
        let before = fixture.folder.fileCount()
        let rejects = try #require(RejectsFolderName(rawValue: "Discard"))
        let plan = fixture.plan([source], rejectsFolderName: rejects)
        #expect(plan.canRename)
        #expect(plan.replacementCount == 1)
        let replacement = try #require(plan.rows[0].replacement)
        #expect(
            replacement.files.map { $0.destination.lastPathComponent }
                == ["001-1.ARW", "001-1.HIF", "001-1.XMP"])
        let result = try await fixture.renamer.rename(plan)
        #expect(result.failure == nil)
        #expect(result.renamedCount == 1)
        #expect(result.replacementCount == 1)
        #expect(result.replacedSets[0].stem == "001")
        #expect(result.replacedSets[0].rejectsRelativeFolder == "sub/Discard")
        for (file, bytes) in zip(result.replacedSets[0].files, oldBytes) {
            #expect(try Data(contentsOf: file.destination) == bytes)
        }
        #expect(fixture.folder.exists("sub/001.ARW"))
        #expect(fixture.folder.exists("sub/001.HIF"))
        #expect(fixture.folder.exists("sub/001.xmp"))
        #expect(fixture.folder.fileCount() == before)
        #expect(fixture.folder.contents(of: "sub/Discard/001.HIF") == Data("already rejected".utf8))
    }

    @Test func standaloneReplacementRetainsItsOwnMarksAndIncomingMarks() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let source = try fixture.item("source", formats: [.jpeg])
        let old = try fixture.item("001", formats: [.jpeg])
        let oldBytes = fixture.folder.contents(of: "001.JPG")
        let incomingBytes = fixture.folder.contents(of: "source.JPG")
        let oldMarks = CloveStoredMarks(
            rating: Rating(rawValue: 5), label: ColourLabel(colour: .red))
        let incomingMarks = CloveStoredMarks(
            rating: Rating(rawValue: 1), label: ColourLabel(colour: .blue))
        try await fixture.store.apply(
            CloveMarkChange(rating: oldMarks.rating, label: oldMarks.label), to: old.set.id)
        try await fixture.store.apply(
            CloveMarkChange(rating: incomingMarks.rating, label: incomingMarks.label),
            to: source.set.id)
        let result = try await fixture.renamer.rename(fixture.plan([source]))
        #expect(result.failure == nil)
        #expect(result.replacementCount == 1)
        #expect(fixture.folder.contents(of: "_Rejected/001.JPG") == oldBytes)
        #expect(fixture.folder.contents(of: "001.JPG") == incomingBytes)
        #expect(
            try await fixture.store.marks(for: fixture.identity("001", path: "_Rejected"))
                == oldMarks)
        #expect(try await fixture.store.marks(for: fixture.identity("001")) == incomingMarks)
        #expect(try await fixture.store.marks(for: source.set.id) == nil)
    }

    @Test func failedReplacementStopsBeforeTemporaryPassAndRollsBackTheSet() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let one = try fixture.item("001")
        let two = try fixture.item("002")
        let tail = try fixture.item("tail")
        _ = try fixture.item("003", sidecar: "003.xmp")
        let before = fixture.folder.files()
        let plan = fixture.plan([two, one, tail])
        #expect(plan.requiresTemporaryNames)
        #expect(plan.replacementCount == 1)
        fixture.fileSystem.fail(
            .move, at: fixture.folder.file("_Rejected/003.xmp"), with: POSIXError(.EACCES))
        let result = try await fixture.renamer.rename(plan)
        #expect(result.renamedCount == 0)
        #expect(result.replacementCount == 0)
        #expect(result.temporarySets.isEmpty)
        #expect(result.failure?.identity == fixture.identity("003"))
        #expect(
            result.failure?.message.hasPrefix(
                "Existing 003 could not be moved to the rejects folder:") == true)
        #expect(result.failure?.rollbackFailures.isEmpty == true)
        #expect(fixture.folder.files() == before)
        #expect(
            !fixture.fileSystem.allRecords.contains {
                $0.step == .move && $0.url.lastPathComponent.hasPrefix("clove-rename-")
            })
    }

    @Test func replacementMarkFailureReportsMovedSetAndLeavesOldKey() async throws {
        let markFS = MoveMarkFileSystem()
        let fixture = try RenameFixture(markFileSystem: markFS)
        defer { fixture.cleanup() }
        let source = try fixture.item("source", formats: [.jpeg])
        let old = try fixture.item("001", formats: [.jpeg])
        try await fixture.store.apply(CloveMarkChange(rating: Rating(rawValue: 4)), to: old.set.id)
        markFS.failWrites { _ in POSIXError(.ENOSPC) }
        let result = try await fixture.renamer.rename(fixture.plan([source]))
        #expect(result.renamedCount == 0)
        #expect(result.replacementCount == 1)
        #expect(result.failure?.message.contains("stored marks remain under the old key") == true)
        #expect(fixture.folder.exists("_Rejected/001.JPG"))
        #expect(fixture.folder.exists("source.JPG"))
        #expect(!fixture.folder.exists("001.JPG"))
        #expect(try await fixture.store.marks(for: old.set.id)?.rating == Rating(rawValue: 4))
        #expect(
            try await fixture.store.marks(for: fixture.identity("001", path: "_Rejected")) == nil)
    }

    @Test func completedReplacementsAreReportedWhenNextOneFails() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let first = try fixture.item("first")
        let second = try fixture.item("second")
        _ = try fixture.item("001")
        _ = try fixture.item("002")
        fixture.fileSystem.fail(
            .move, at: fixture.folder.file("_Rejected/002.ARW"), with: POSIXError(.EACCES))
        let result = try await fixture.renamer.rename(fixture.plan([first, second]))
        #expect(result.replacementCount == 1)
        #expect(result.replacedSets[0].stem == "001")
        #expect(result.renamedCount == 0)
        #expect(fixture.folder.exists("_Rejected/001.ARW"))
        #expect(fixture.folder.exists("002.ARW"))
        #expect(fixture.folder.exists("first.ARW"))
        #expect(fixture.folder.exists("second.ARW"))
    }
}
