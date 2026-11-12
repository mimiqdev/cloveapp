import Foundation
import Testing

@testable import CloveCore

@Suite("Shared mover preserves Move Rejects behavior")
struct SharedMoveBehaviorTests {
    @Test func failedLateSidecarProbeDoesNotRefuseMoveRejects() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "", stem: "source", formats: [.raw])
        try writeMoveSet(set, in: fixture.folder)
        fixture.fileSystem.fail(
            .exists, at: fixture.folder.file("source.xmp"), with: POSIXError(.EACCES))
        let plan = try await fixture.plan([set])
        #expect(plan.refusedCount == 0)
        #expect(plan.readyEntries[0].files.count == 1)
        let result = try await fixture.move(plan)
        #expect(result.movedCount == 1)
        #expect(fixture.folder.exists("_Rejected/source.ARW"))
    }

    @Test func moveRejectsKeepsItsOriginalDifferentVolumeMessage() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "", stem: "source", formats: [.raw])
        try writeMoveSet(set, in: fixture.folder)
        fixture.fileSystem.volumeIdentifier = { url in
            url.lastPathComponent == "_Rejected" ? "other-volume" : "source-volume"
        }
        let result = try await fixture.move(try await fixture.plan([set]))
        #expect(result.failed[0].failure.message == "The rejects folder is on a different volume.")
    }
}
