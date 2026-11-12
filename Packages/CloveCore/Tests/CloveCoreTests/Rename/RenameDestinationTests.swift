import Foundation
import Testing

@testable import CloveCore

@Suite("Rename destination preflight")
struct RenameDestinationTests {
    @Test func existingFolderSpellingIsUsedForFilesMarksAndResult() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let source = try fixture.item("source", path: "sub", formats: [.jpeg])
        try fixture.folder.write("unrelated", to: "SeLeCtS/other.txt")
        try await fixture.store.apply(
            CloveMarkChange(rating: Rating(rawValue: 3)), to: source.set.id)
        let plan = fixture.plan([source], destination: .folder("selects"))
        #expect(plan.canRename)
        #expect(plan.destination == .folder("SeLeCtS"))
        #expect(plan.rows[0].destinationRelativeFolder == "SeLeCtS")
        #expect(
            plan.rows[0].files[0].destination.deletingLastPathComponent().lastPathComponent
                == "SeLeCtS")
        let result = try await fixture.renamer.rename(plan)
        #expect(result.failure == nil)
        #expect(result.destination == .folder("SeLeCtS"))
        #expect(fixture.folder.exists("SeLeCtS/001.JPG"))
        #expect(
            try await fixture.store.marks(for: fixture.identity("001", path: "SeLeCtS"))?.rating
                == Rating(rawValue: 3))
        #expect(try await fixture.store.marks(for: fixture.identity("001", path: "selects")) == nil)
    }

    @Test func destinationFileIsRefusedBeforeAnythingMoves() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let source = try fixture.item("source")
        try fixture.folder.write("a file", to: "Selects")
        let plan = fixture.plan([source], destination: .folder("selects"))
        #expect(!plan.canRename)
        #expect(
            plan.rows[0].problems.contains { problem in
                guard case .destinationIsFile(let url) = problem else { return false }
                return url.lastPathComponent == "Selects"
            })
        await #expect(throws: BatchRenameRefusal.self) { try await fixture.renamer.rename(plan) }
        #expect(fixture.fileSystem.count(of: .move) == 0)
        #expect(fixture.fileSystem.count(of: .createDirectory) == 0)
        #expect(fixture.folder.contents(of: "Selects") == Data("a file".utf8))
    }

    @Test(arguments: ["_Rejected", "_rejected", "_REJECTED"])
    func rejectsFolderCannotBeTheDestination(name: String) async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let source = try fixture.item("source")
        let plan = fixture.plan([source], destination: .folder(name))
        #expect(!plan.canRename)
        #expect(plan.rows[0].problems.contains(.rejectsDestination(name)))
        await #expect(throws: BatchRenameRefusal.self) { try await fixture.renamer.rename(plan) }
        #expect(fixture.fileSystem.count(of: .move) == 0)
    }

    @Test func configuredRejectsNameIsAlsoRefusedAsDestination() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let source = try fixture.item("source")
        let name = try #require(RejectsFolderName(rawValue: "Discard"))
        let plan = fixture.plan([source], destination: .folder("discard"), rejectsFolderName: name)
        #expect(!plan.canRename)
        #expect(plan.rows[0].problems.contains(.rejectsDestination("discard")))
    }

    @Test func destinationCreationFailureStopsBeforeReplacementsAndTemporaryPass() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let first = try fixture.item("002", path: "Selects")
        let second = try fixture.item("source", path: "sub")
        _ = try fixture.item("001", path: "Selects")
        let before = fixture.folder.files()
        let plan = fixture.plan([first, second], destination: .folder("Selects"))
        #expect(plan.canRename)
        #expect(plan.requiresTemporaryNames)
        #expect(plan.replacementCount == 1)
        fixture.fileSystem.fail(
            .createDirectory, at: fixture.folder.file("Selects"), with: POSIXError(.EACCES))
        let result = try await fixture.renamer.rename(plan)
        #expect(result.renamedCount == 0)
        #expect(result.replacementCount == 0)
        #expect(result.temporarySets.isEmpty)
        #expect(result.failure?.message.hasPrefix("The destination could not be prepared:") == true)
        #expect(fixture.fileSystem.count(of: .move) == 0)
        #expect(fixture.folder.files() == before)
    }

    @Test func destinationIsPreparedBeforeReplacementAndPassOne() async throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let first = try fixture.item("002", path: "Selects")
        let second = try fixture.item("source", path: "sub")
        _ = try fixture.item("001", path: "Selects")
        let result = try await fixture.renamer.rename(
            fixture.plan([first, second], destination: .folder("Selects")))
        #expect(result.failure == nil)
        #expect(result.replacementCount == 1)
        #expect(result.renamedCount == 2)
        let mutations = fixture.fileSystem.allRecords.filter {
            $0.step == .move || $0.step == .createDirectory
        }
        #expect(mutations.first?.step == .createDirectory)
        #expect(mutations.first?.url == fixture.folder.file("Selects"))
        let moves = mutations.filter { $0.step == .move }
        #expect(moves[0].url.lastPathComponent == "001.ARW")
        #expect(moves[0].url.deletingLastPathComponent().lastPathComponent == "_Rejected")
        #expect(moves[1].url.lastPathComponent.hasPrefix("clove-rename-"))
    }
}
