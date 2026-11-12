import Foundation
import Testing

@testable import CloveCore

@Suite("Batch rename execution")
struct BatchRenamerTests {
    @Test func rawHifAndLateXmpMoveAsAUnitWithoutChangingBytes() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let item = try fixture.item("original", formats: [.raw, .heif])
        try fixture.folder.write("packet stays untouched", to: "original.xmp")
        let original = fixture.folder.files().map { ($0, fixture.folder.contents(of: $0)) }
        let plan = fixture.plan([item])
        let result = try await fixture.renamer.rename(plan)
        #expect(result.renamedCount == 1)
        #expect(result.failure == nil)
        #expect(result.temporarySets.isEmpty)
        #expect(fixture.folder.files() == ["001.ARW", "001.HIF", "001.xmp"])
        for (name, bytes) in original {
            let ext = URL(fileURLWithPath: name).pathExtension
            #expect(fixture.folder.contents(of: "001." + ext) == bytes)
        }
        #expect(fixture.fileSystem.count(of: .move) == 3)
    }

    @Test(arguments: [PhotoFormat.jpeg, .heif])
    func standaloneMarksFollowFinalName(format: PhotoFormat) async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let item = try fixture.item("original", formats: [format])
        try await fixture.store.apply(
            CloveMarkChange(rating: Rating(rawValue: 5), label: ColourLabel(colour: .red)),
            to: item.set.id)
        let result = try await fixture.renamer.rename(fixture.plan([item]))
        #expect(result.renamedCount == 1)
        #expect(result.failure == nil)
        #expect(try await fixture.store.marks(for: item.set.id) == nil)
        #expect(
            try await fixture.store.marks(for: fixture.identity("001"))
                == CloveStoredMarks(rating: Rating(rawValue: 5), label: ColourLabel(colour: .red)))
    }

    @Test func reordersAlreadyNumberedBatchIncludingSwapAndPreservesMarks() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let one = try fixture.item("001", formats: [.jpeg])
        let two = try fixture.item("002", formats: [.jpeg])
        let three = try fixture.item("003", formats: [.jpeg])
        let beforeOne = fixture.folder.contents(of: "001.JPG")
        let beforeTwo = fixture.folder.contents(of: "002.JPG")
        try await fixture.store.apply(CloveMarkChange(rating: Rating(rawValue: 5)), to: one.set.id)
        try await fixture.store.apply(CloveMarkChange(rating: Rating(rawValue: 1)), to: two.set.id)
        let plan = fixture.plan([two, one, three])
        #expect(plan.requiresTemporaryNames)
        let result = try await fixture.renamer.rename(plan)
        #expect(result.renamedCount == 2)
        #expect(result.failure == nil)
        #expect(result.temporarySets.isEmpty)
        #expect(fixture.folder.contents(of: "001.JPG") == beforeTwo)
        #expect(fixture.folder.contents(of: "002.JPG") == beforeOne)
        #expect(
            try await fixture.store.marks(for: fixture.identity("001"))?.rating
                == Rating(rawValue: 1))
        #expect(
            try await fixture.store.marks(for: fixture.identity("002"))?.rating
                == Rating(rawValue: 5))
        #expect(fixture.folder.files() == ["001.JPG", "002.JPG", "003.JPG"])
        #expect(fixture.fileSystem.count(of: .move) == 4)
        #expect(try await fixture.store.marks(for: FolderIdentity(rawValue: "folder-1")).count == 2)
    }

    @Test func cycleOfThreeKeepsTheSuppliedOrder() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let items = try ["001", "002", "003"].map { try fixture.item($0) }
        let bytes = items.map {
            fixture.folder.contents(of: $0.set.photoSet.primary.url.lastPathComponent)
        }
        let result = try await fixture.renamer.rename(fixture.plan([items[2], items[0], items[1]]))
        #expect(result.renamedCount == 3)
        #expect(result.failure == nil)
        #expect(fixture.folder.contents(of: "001.ARW") == bytes[2])
        #expect(fixture.folder.contents(of: "002.ARW") == bytes[0])
        #expect(fixture.folder.contents(of: "003.ARW") == bytes[1])
    }

    @Test(arguments: [false, true])
    func namedDestinationFlattensSubfoldersAndRekeysRelativeFolder(existing: Bool) async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let raw = try fixture.item(
            "raw", path: "DCIM/one", formats: [.raw, .heif], sidecar: "raw.XMP")
        let jpeg = try fixture.item("jpeg", path: "DCIM/two", formats: [.jpeg])
        try await fixture.store.apply(CloveMarkChange(rating: Rating(rawValue: 4)), to: jpeg.set.id)
        if existing { try fixture.folder.write("leave me", to: "Selects/other.txt") }
        let plan = fixture.plan([raw, jpeg], destination: .folder("Selects"))
        #expect(plan.canRename)
        #expect(!plan.requiresTemporaryNames)
        #expect(!fixture.folder.exists("Selects") || existing)
        let result = try await fixture.renamer.rename(plan)
        #expect(result.renamedCount == 2)
        #expect(result.failure == nil)
        #expect(fixture.folder.exists("Selects/001.ARW"))
        #expect(fixture.folder.exists("Selects/001.HIF"))
        #expect(fixture.folder.exists("Selects/001.XMP"))
        #expect(fixture.folder.exists("Selects/002.JPG"))
        #expect(!fixture.folder.exists("DCIM/two/jpeg.JPG"))
        #expect(try await fixture.store.marks(for: jpeg.set.id) == nil)
        #expect(
            try await fixture.store.marks(for: fixture.identity("002", path: "Selects"))?.rating
                == Rating(rawValue: 4))
        if existing {
            #expect(fixture.folder.contents(of: "Selects/other.txt") == Data("leave me".utf8))
        }
    }

    @Test func namedDestinationCollisionRefusesWholeBatch() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let first = try fixture.item("first", path: "one")
        let second = try fixture.item("second", path: "two")
        try fixture.folder.write("outside", to: "Selects/002.ARW")
        let plan = fixture.plan([first, second], destination: .folder("Selects"))
        #expect(!plan.canRename)
        #expect(
            plan.rows[1].problems.contains { problem in
                guard case .targetExists(let url) = problem else { return false }
                return PhotoFilePath.matches(url, fixture.folder.file("Selects/002.ARW"))
            })
        await #expect(throws: BatchRenameRefusal.self) { try await fixture.renamer.rename(plan) }
        #expect(fixture.fileSystem.count(of: .move) == 0)
        #expect(fixture.folder.exists("one/first.ARW"))
    }

    @Test func destinationBatchCollisionTemporariesStayInEachOriginalFolder() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let first = try fixture.item("002", path: "Selects")
        let second = try fixture.item("source", path: "two")
        let plan = fixture.plan([first, second], destination: .folder("Selects"))
        #expect(plan.requiresTemporaryNames)
        let result = try await fixture.renamer.rename(plan)
        #expect(result.failure == nil)
        let temporaryMoves = fixture.fileSystem.allRecords.filter {
            $0.step == .move && $0.url.lastPathComponent.hasPrefix("clove-rename-")
        }
        #expect(temporaryMoves.count == 2)
        #expect(temporaryMoves[0].url.deletingLastPathComponent() == fixture.folder.file("Selects"))
        #expect(temporaryMoves[1].url.deletingLastPathComponent() == fixture.folder.file("two"))
        #expect(fixture.folder.exists("Selects/001.ARW"))
        #expect(fixture.folder.exists("Selects/002.ARW"))
    }

    @Test func passTwoFailureReportsRemainingVisibleTemporaryNamesAndStops() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let one = try fixture.item("001", formats: [.jpeg])
        let two = try fixture.item("002", formats: [.jpeg])
        let three = try fixture.item("003", formats: [.jpeg])
        try await fixture.store.apply(CloveMarkChange(rating: Rating(rawValue: 5)), to: one.set.id)
        fixture.fileSystem.fail(
            .move, at: fixture.folder.file("002.JPG"), with: POSIXError(.ENOSPC))
        let result = try await fixture.renamer.rename(fixture.plan([two, three, one]))
        #expect(result.renamedCount == 1)
        #expect(result.failure?.identity == three.set.id)
        #expect(result.temporarySets.count == 2)
        #expect(fixture.folder.exists("001.JPG"))
        for set in result.temporarySets {
            #expect(set.stem.hasPrefix("clove-rename-"))
            #expect(!set.stem.hasPrefix("."))
            for file in set.files { #expect(FileManager.default.fileExists(atPath: file.path)) }
        }
        let temporaryOne = try #require(result.temporarySets.first { $0.identity == one.set.id })
        #expect(
            try await fixture.store.marks(for: fixture.identity(temporaryOne.stem))?.rating
                == Rating(rawValue: 5)
        )
        #expect(fixture.folder.fileCount() == 3)
        #expect(fixture.fileSystem.count(of: .move) == 5)
    }

    @Test func firstPassFailureReportsEarlierTemporariesAndStops() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let one = try fixture.item("001")
        let two = try fixture.item("002")
        fixture.fileSystem.fail(
            .move,
            where: {
                $0.lastPathComponent.hasPrefix("clove-rename-")
                    && $0.lastPathComponent.hasSuffix("-2.ARW")
            }, with: POSIXError(.EACCES))
        let result = try await fixture.renamer.rename(fixture.plan([two, one]))
        #expect(result.renamedCount == 0)
        #expect(result.failure?.identity == one.set.id)
        #expect(result.temporarySets.count == 1)
        #expect(result.temporarySets.first?.identity == two.set.id)
        #expect(fixture.folder.exists("001.ARW"))
        #expect(fixture.folder.fileCount() == 2)
        #expect(fixture.fileSystem.count(of: .move) == 2)
    }

    @Test func failedSecondPassRestoresWholeSetToItsTemporaryStem() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let one = try fixture.item("001", formats: [.raw, .heif], sidecar: "001.xmp")
        let two = try fixture.item("002", formats: [.raw, .heif], sidecar: "002.xmp")
        fixture.fileSystem.fail(
            .move, at: fixture.folder.file("001.HIF"), with: POSIXError(.EACCES))
        let result = try await fixture.renamer.rename(fixture.plan([two, one]))
        #expect(result.renamedCount == 0)
        #expect(result.temporarySets.count == 2)
        #expect(result.temporarySets.allSatisfy { $0.files.count == 3 })
        #expect(result.failure?.rollbackFailures.isEmpty == true)
        #expect(fixture.folder.fileCount() == 6)
        #expect(!fixture.folder.exists("001.ARW"))
        for set in result.temporarySets {
            for file in set.files { #expect(FileManager.default.fileExists(atPath: file.path)) }
        }
    }

    @Test func noOpDoesNotMoveButSameNameInAnotherFolderDoes() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let item = try fixture.item("001", formats: [.jpeg])
        try await fixture.store.apply(CloveMarkChange(rating: .rejected), to: item.set.id)
        let unchanged = try await fixture.renamer.rename(fixture.plan([item]))
        #expect(unchanged.renamedCount == 0)
        #expect(unchanged.failure == nil)
        #expect(fixture.fileSystem.count(of: .move) == 0)
        let moved = try await fixture.renamer.rename(
            fixture.plan([item], destination: .folder("Selects")))
        #expect(moved.renamedCount == 1)
        #expect(moved.failure == nil)
        #expect(fixture.folder.exists("Selects/001.JPG"))
        #expect(
            try await fixture.store.marks(for: fixture.identity("001", path: "Selects"))?.rating
                == .rejected)
    }

    @Test func partialSetFailureRollsBackAndLaterSetsAreUntouched() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let first = try fixture.item("first", formats: [.raw, .heif], sidecar: "first.xmp")
        let second = try fixture.item("second")
        let before = fixture.folder.files()
        fixture.fileSystem.fail(
            .move, at: fixture.folder.file("001.HIF"), with: POSIXError(.EACCES))
        let result = try await fixture.renamer.rename(fixture.plan([first, second]))
        #expect(result.renamedCount == 0)
        #expect(result.failure?.identity == first.set.id)
        #expect(result.failure?.rollbackFailures.isEmpty == true)
        #expect(result.temporarySets.isEmpty)
        #expect(fixture.folder.files() == before)
        #expect(!fixture.folder.exists("002.ARW"))
    }

    @Test func rollbackFailureReportsSplitSetLocations() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let item = try fixture.item("original", formats: [.raw, .heif])
        fixture.fileSystem.fail(
            .move, at: fixture.folder.file("001.HIF"), with: POSIXError(.ENOSPC))
        fixture.fileSystem.fail(
            .move, at: fixture.folder.file("original.ARW"), with: POSIXError(.EACCES))
        let result = try await fixture.renamer.rename(fixture.plan([item]))
        let failure = try #require(result.failure)
        #expect(!failure.rollbackFailures.isEmpty)
        #expect(failure.files.map(\.location) == [.destination, .source])
        #expect(fixture.folder.exists("001.ARW"))
        #expect(fixture.folder.exists("original.HIF"))
        #expect(result.renamedCount == 0)
    }

    @Test func changedFactsRefuseBeforeMovingAndExclusiveRenameSurvivesRace() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let item = try fixture.item("source")
        let plan = fixture.plan([item])
        try fixture.folder.write("outside", to: "001.ARW")
        await #expect(throws: BatchRenameRefusal.self) { try await fixture.renamer.rename(plan) }
        #expect(fixture.fileSystem.count(of: .move) == 0)
        try FileManager.default.removeItem(at: fixture.folder.file("001.ARW"))
        fixture.fileSystem.beforeOperation = { record in
            if record.step == .move, record.url.lastPathComponent == "001.ARW" {
                try? Data("raced".utf8).write(to: record.url)
            }
        }
        let result = try await fixture.renamer.rename(plan)
        #expect(result.failure != nil)
        #expect(result.renamedCount == 0)
        #expect(fixture.folder.contents(of: "001.ARW") == Data("raced".utf8))
        #expect(fixture.folder.exists("source.ARW"))
    }

    @Test func differentVolumeFailsWithoutMovingOrCopying() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let item = try fixture.item("source")
        fixture.fileSystem.volumeIdentifier = { url in
            url.lastPathComponent == "Selects" ? "other-volume" : "source-volume"
        }
        let result = try await fixture.renamer.rename(
            fixture.plan([item], destination: .folder("Selects")))
        #expect(result.failure?.message == "The destination is on a different volume.")
        #expect(fixture.fileSystem.count(of: .move) == 0)
        #expect(fixture.fileSystem.count(of: .createDirectory) == 0)
        #expect(fixture.folder.exists("source.ARW"))
    }

    @Test func markStoreFailureStopsAfterCountingFinalMove() async throws {
        let markFS = MoveMarkFileSystem()
        let fixture = try RenameFixture(markFileSystem: markFS)
        defer { fixture.cleanup() }
        let first = try fixture.item("first", formats: [.jpeg])
        let second = try fixture.item("second", formats: [.jpeg])
        try await fixture.store.apply(
            CloveMarkChange(rating: Rating(rawValue: 5)), to: first.set.id)
        markFS.failWrites { _ in POSIXError(.ENOSPC) }
        let result = try await fixture.renamer.rename(fixture.plan([first, second]))
        #expect(result.renamedCount == 1)
        #expect(result.failure?.identity == first.set.id)
        #expect(fixture.folder.exists("001.JPG"))
        #expect(fixture.folder.exists("second.JPG"))
        #expect(!fixture.folder.exists("002.JPG"))
    }

    @Test func progressReportsEachPassAndFinalResult() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let one = try fixture.item("001")
        let two = try fixture.item("002")
        let stream = await fixture.renamer.progressUpdates()
        let collector = Task { () -> [BatchRenameProgress] in
            var events: [BatchRenameProgress] = []
            for await event in stream {
                events.append(event)
                if case .finished = event { break }
            }
            return events
        }
        let result = try await fixture.renamer.rename(fixture.plan([two, one]))
        let events = await collector.value
        #expect(
            events == [
                .setStarted(two.set.id, pass: .temporary),
                .setFinished(two.set.id, pass: .temporary),
                .setStarted(one.set.id, pass: .temporary),
                .setFinished(one.set.id, pass: .temporary),
                .setStarted(two.set.id, pass: .finalName),
                .setFinished(two.set.id, pass: .finalName),
                .setStarted(one.set.id, pass: .finalName),
                .setFinished(one.set.id, pass: .finalName),
                .finished(result),
            ])
    }
}
