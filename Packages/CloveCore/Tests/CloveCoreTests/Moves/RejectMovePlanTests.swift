import Foundation
import Testing

@testable import CloveCore

/// The plan is the confirmation sheet's input: counts, destinations and refusals.
///
/// PRD P0-10 asks the confirmation to state how many photos move with their JPEG/HIF companions
/// and XMP, and where they go, without touching the disk beyond existence checks.
@Suite("Reject move plan", .timeLimit(.minutes(1)))
struct RejectMovePlanTests {
    /// Plans a mixed set of RAW+JPEG, RAW+HIF, RAW+JPEG+HIF and a standalone JPEG.
    @Test func plansEverySetWithItsCompanionsAndSidecar() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let first = "DCIM/100AAAAA"
        let second = "DCIM/100BBBBB"
        let rawJPEG = try makeMoveSet(
            root: fixture.folder.url, relativePath: first, stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        let rawHIF = try makeMoveSet(
            root: fixture.folder.url, relativePath: first, stem: "IMG_0002",
            formats: [.raw, .heif], sidecarName: "IMG_0002.XMP")
        let triple = try makeMoveSet(
            root: fixture.folder.url, relativePath: second, stem: "IMG_0003",
            formats: [.raw, .jpeg, .heif], sidecarName: "IMG_0003.xmp")
        let standalone = try makeMoveSet(
            root: fixture.folder.url, relativePath: "", stem: "IMG_0004", formats: [.jpeg])
        let sets = [rawJPEG, rawHIF, triple, standalone]
        for set in sets { try writeMoveSet(set, in: fixture.folder) }
        let before = fixture.folder.files()

        let plan = try await fixture.plan(sets)

        #expect(plan.photoCount == 4)
        // One JPEG, one HIF and a two-companion triple, plus none for the standalone JPEG.
        #expect(plan.companionCount == 4)
        #expect(plan.sidecarCount == 3)
        #expect(plan.refusedCount == 0)
        #expect(plan.destinationURL.lastPathComponent == "_Rejected")
        #expect(fixture.folder.fileCount() == before.count)
        #expect(!fixture.folder.exists("_Rejected"))

        let destinations = plan.readyEntries.flatMap(\.files).map(\.destination)
        #expect(
            Set(destinations.map(\.lastPathComponent))
                == Set([
                    "IMG_0001.ARW", "IMG_0001.JPG", "IMG_0001.xmp",
                    "IMG_0002.ARW", "IMG_0002.HIF", "IMG_0002.XMP",
                    "IMG_0003.ARW", "IMG_0003.JPG", "IMG_0003.HIF", "IMG_0003.xmp",
                    "IMG_0004.JPG",
                ]))
        let rawJPEGPlan = try #require(plan.readyEntries.first { $0.identity == rawJPEG.id })
        #expect(
            relativePath(of: rawJPEGPlan.destinationFolder, in: fixture.folder)
                == "_Rejected/DCIM/100AAAAA")
        #expect(
            relativePath(of: rawJPEGPlan.files[0].destination, in: fixture.folder)
                == "_Rejected/DCIM/100AAAAA/IMG_0001.ARW")
        let standalonePlan = try #require(plan.readyEntries.first { $0.identity == standalone.id })
        #expect(standalonePlan.sidecars.isEmpty)
        #expect(relativePath(of: standalonePlan.destinationFolder, in: fixture.folder) == "_Rejected")
    }

    /// A taken destination name gives the whole set one suffix and keeps extension case.
    @Test func suffixesTheWholeSetWhenOneDestinationNameIsTaken() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM/100AAAAA", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        // Only the RAW's destination exists, so a per-file suffix would split the set's stem.
        try fixture.folder.write("already here", to: "_Rejected/DCIM/100AAAAA/IMG_0001.ARW")

        let plan = try await fixture.plan([set])
        let entry = try #require(plan.readyEntries.first)
        #expect(entry.files.map(\.destination.lastPathComponent) == [
            "IMG_0001-1.ARW", "IMG_0001-1.JPG", "IMG_0001-1.xmp",
        ])
        #expect(plan.photoCount == 1)
        #expect(plan.companionCount == 1)
        #expect(plan.sidecarCount == 1)

        let result = try await fixture.move(plan)
        #expect(result.movedCount == 1)
        #expect(fixture.folder.contents(of: "_Rejected/DCIM/100AAAAA/IMG_0001.ARW")
            == Data("already here".utf8))
        #expect(fixture.folder.exists("_Rejected/DCIM/100AAAAA/IMG_0001-1.ARW"))
        #expect(fixture.folder.exists("_Rejected/DCIM/100AAAAA/IMG_0001-1.JPG"))
        #expect(fixture.folder.exists("_Rejected/DCIM/100AAAAA/IMG_0001-1.xmp"))
        #expect(!fixture.folder.exists("DCIM/100AAAAA/IMG_0001.ARW"))
    }

    /// A packet with an appended extension is C2's ambiguity, so the set is refused.
    @Test func refusesASetWhoseSidecarIsAmbiguous() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001", formats: [.raw])
        try writeMoveSet(set, in: fixture.folder)
        let plain = try fixture.folder.write("<xmp/>", to: "DCIM/IMG_0001.xmp")
        let appended = try fixture.folder.write("<xmp/>", to: "DCIM/IMG_0001.ARW.xmp")
        let ambiguous = ScannedPhotoSet(
            photoSet: set.photoSet, sidecar: .ambiguous([plain, appended]),
            imageFiles: set.imageFiles)

        let plan = try await fixture.plan([ambiguous])
        #expect(plan.photoCount == 0)
        #expect(plan.refusedCount == 1)
        guard case .refused(let identity, let refusal) = try #require(plan.entries.first) else {
            Issue.record("The ambiguous set should not be ready")
            return
        }
        #expect(identity == set.id)
        #expect(refusal == .ambiguousSidecar([plain, appended]))
    }

    /// A set already inside the rejects folder is skipped instead of nested again.
    @Test func refusesASetAlreadyInsideTheRejectsFolder() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "_Rejected/DCIM", stem: "IMG_0001",
            formats: [.raw])
        try writeMoveSet(set, in: fixture.folder)

        let plan = try await fixture.plan([set])
        #expect(plan.photoCount == 0)
        guard case .refused(_, let refusal) = try #require(plan.entries.first) else {
            Issue.record("A set inside the rejects folder should not be ready")
            return
        }
        #expect(refusal == .insideRejectsFolder)
        #expect(refusal.failure == nil)
    }

    /// A set outside the opened folder is refused, so a move cannot leave the folder's scope.
    @Test func refusesASetOutsideTheOpenedFolder() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let otherRoot = try MoveTestFolder()
        defer { otherRoot.remove() }
        let set = try makeMoveSet(
            root: otherRoot.url, relativePath: "", stem: "IMG_0001", formats: [.raw])
        try writeMoveSet(set, in: otherRoot)

        let plan = try await fixture.plan([set])
        #expect(plan.photoCount == 0)
        guard case .refused(_, let refusal) = try #require(plan.entries.first) else {
            Issue.record("A set outside the opened folder should not be ready")
            return
        }
        #expect(refusal == .outsideOpenedFolder)
        #expect(refusal.failure?.reason == .outsideOpenedFolder)
    }

    /// C12's rejects folder name reaches both the move and the scan through one bridge.
    @Test func sharesTheRejectsFolderNameWithTheScan() throws {
        let settings = AppSettings(
            rejectsFolderName: try RejectsFolderName.validated("Keep"), moveRejectsEnabled: false)
        #expect(settings.scanConfiguration.rejectsFolderName == "Keep")
        let configuration = RejectMoveConfiguration(settings: settings)
        #expect(configuration.rejectsFolderName.rawValue == "Keep")
        #expect(configuration.isEnabled == false)
        #expect(
            RejectMoveConfiguration(settings: AppSettings())
                == RejectMoveConfiguration())
    }
}
