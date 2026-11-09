import Foundation
import Testing

@testable import CloveCore

/// Moving rejected sets: units, collisions, volumes, confirmations and skips.
///
/// PRD P0-10 makes the move the durable Reject result, so each test checks the files' actual
/// bytes and counts, not only the reported outcome. A failing test must never leave a file
/// copied, deleted or overwritten.
@Suite("Reject mover", .timeLimit(.minutes(1)))
struct RejectMoverTests {
    /// Every set moves with its companions and sidecar into the matching subfolder.
    @Test func movesEverySetAsOneUnitIntoItsSubfolder() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let first = "DCIM/100AAAAA"
        let second = "DCIM/100BBBBB"
        let sets = [
            try makeMoveSet(
                root: fixture.folder.url, relativePath: first, stem: "IMG_0001",
                formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp"),
            try makeMoveSet(
                root: fixture.folder.url, relativePath: first, stem: "IMG_0002",
                formats: [.raw, .heif], sidecarName: "IMG_0002.XMP"),
            try makeMoveSet(
                root: fixture.folder.url, relativePath: second, stem: "IMG_0003",
                formats: [.raw, .jpeg, .heif], sidecarName: "IMG_0003.xmp"),
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "", stem: "IMG_0004", formats: [.jpeg]),
        ]
        for set in sets { try writeMoveSet(set, in: fixture.folder) }
        let before = fixture.folder.files()

        let plan = try await fixture.plan(sets)
        let result = try await fixture.move(plan)

        #expect(result.movedCount == 4)
        #expect(result.failedCount == 0)
        #expect(result.outcomes.map(\.identity) == sets.map(\.id))
        #expect(Set(result.movedIdentities) == Set(sets.map(\.id)))
        #expect(result.partialFailureSummary == nil)
        for set in sets {
            for url in set.photoSet.fileURLs {
                let source = relativePath(of: url, in: fixture.folder)
                #expect(!fixture.folder.exists(source))
                #expect(
                    fixture.folder.contents(of: "_Rejected/\(source)")
                        == (try moveTestBytes(for: url, in: fixture.folder)))
            }
        }
        #expect(fixture.folder.files() == before.map { "_Rejected/\($0)" }.sorted())
        // A move renames; it never changes the folder's file count.
        #expect(fixture.folder.fileCount() == before.count)
        for moved in result.moved {
            #expect(moved.removedStoredReject == false)
            #expect(moved.staleRejectRecord == nil)
        }
    }

    /// A destination created after the plan is refused by the rename and never overwritten.
    @Test func refusesADestinationThatAppearedAfterTheCheck() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        let plan = try await fixture.plan([set])
        try fixture.folder.write("intruder", to: "_Rejected/DCIM/IMG_0001.JPG")
        let before = fixture.folder.fileCount()

        let result = try await fixture.move(plan)

        #expect(result.failedCount == 1)
        #expect(result.movedCount == 0)
        let failure = try #require(result.failed.first?.failure)
        #expect(failure.reason == .conflict)
        #expect(
            failure.errorChain.contains { $0.domain == NSPOSIXErrorDomain && $0.code == EEXIST })
        #expect(fixture.folder.contents(of: "_Rejected/DCIM/IMG_0001.JPG") == Data("intruder".utf8))
        for url in set.photoSet.fileURLs {
            #expect(fixture.folder.exists(relativePath(of: url, in: fixture.folder)))
        }
        #expect(fixture.folder.fileCount() == before)
    }

    /// A destination on another volume is refused before any folder is created or file moved.
    @Test func refusesASetOnAnotherVolume() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001", formats: [.raw])
        try writeMoveSet(set, in: fixture.folder)
        let before = fixture.folder.fileCount()
        fixture.fileSystem.volumeIdentifier = { url in
            url.path(percentEncoded: false).contains("_Rejected") ? "other-volume" : "this-volume"
        }

        let result = try await fixture.move(try await fixture.plan([set]))

        #expect(result.failedCount == 1)
        let failure = try #require(result.failed.first?.failure)
        #expect(failure.reason == .differentVolume)
        #expect(fixture.fileSystem.count(of: .move) == 0)
        #expect(fixture.fileSystem.count(of: .createDirectory) == 0)
        #expect(fixture.folder.fileCount() == before)
    }

    /// `EXDEV` is a failure, and the set moves back rather than falling through to a copy.
    @Test func reportsEXDEVWithoutCopying() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        let plan = try await fixture.plan([set])
        let second = try #require(plan.readyEntries.first?.files[1].destination)
        fixture.fileSystem.fail(.move, at: second, with: POSIXError(.EXDEV))
        let before = fixture.folder.fileCount()

        let result = try await fixture.move(plan)

        let failure = try #require(result.failed.first?.failure)
        #expect(failure.reason == .differentVolume)
        #expect(failure.errorChain.contains { $0.domain == NSPOSIXErrorDomain && $0.code == EXDEV })
        for url in set.photoSet.fileURLs {
            #expect(fixture.folder.exists(relativePath(of: url, in: fixture.folder)))
            #expect(
                !fixture.folder.exists("_Rejected/" + relativePath(of: url, in: fixture.folder)))
        }
        #expect(fixture.folder.fileCount() == before)
    }

    /// A failed destination folder stops the set before any file is touched.
    @Test func failsWhenTheDestinationFolderCannotBeCreated() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        let plan = try await fixture.plan([set])
        fixture.fileSystem.fail(.createDirectory, with: POSIXError(.EACCES))
        let before = fixture.folder.fileCount()

        let result = try await fixture.move(plan)

        let failure = try #require(result.failed.first?.failure)
        #expect(failure.reason == .permissionLost)
        #expect(fixture.fileSystem.count(of: .move) == 0)
        #expect(fixture.folder.fileCount() == before)
    }

    /// A later file's failure moves the set's earlier files back.
    @Test func movesEarlierFilesBackWhenALaterFileFails() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg, .heif], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        let plan = try await fixture.plan([set])
        let third = try #require(plan.readyEntries.first?.files[2].destination)
        fixture.fileSystem.fail(.move, at: third, with: POSIXError(.ENOSPC))
        let before = fixture.folder.files()

        let result = try await fixture.move(plan)

        let failure = try #require(result.failed.first?.failure)
        #expect(failure.reason == .insufficientSpace)
        #expect(fixture.folder.files() == before)
        // Two files moved forward, the third was refused, and the two moved back.
        #expect(fixture.fileSystem.count(of: .move) == 5)
    }

    /// An unconfirmed destination rolls the whole set back instead of reporting it moved.
    @Test func rollsBackWhenTheDestinationCannotBeConfirmed() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        let plan = try await fixture.plan([set])
        let first = try #require(plan.readyEntries.first?.files[0].destination)
        fixture.fileSystem.fail(.fileSize, at: first, with: POSIXError(.ENOSPC))
        let before = fixture.folder.files()

        let result = try await fixture.move(plan)

        let failure = try #require(result.failed.first?.failure)
        #expect(failure.reason == .insufficientSpace)
        #expect(fixture.folder.files() == before)
        #expect(!fixture.folder.exists("_Rejected/" + before[0]))
    }

    /// A source that is gone before the first rename fails the set with nothing moved.
    @Test func failsWhenASourceIsGone() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        let plan = try await fixture.plan([set])
        let second = try #require(plan.readyEntries.first?.files[1].source)
        fixture.fileSystem.fail(.fileSize, at: second, with: POSIXError(.ENOENT))
        let before = fixture.folder.fileCount()

        let result = try await fixture.move(plan)

        let failure = try #require(result.failed.first?.failure)
        #expect(failure.reason == .locationUnavailable)
        #expect(fixture.fileSystem.count(of: .move) == 0)
        #expect(fixture.folder.fileCount() == before)
    }

    /// A move back that also fails reports a split with every file's actual location.
    @Test func reportsASplitWhenTheMoveBackFails() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg, .heif], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        let plan = try await fixture.plan([set])
        let entry = try #require(plan.readyEntries.first)
        fixture.fileSystem.fail(.move, at: entry.files[2].destination, with: POSIXError(.EACCES))
        fixture.fileSystem.fail(.move, at: entry.files[0].source, with: POSIXError(.EACCES))
        let before = fixture.folder.fileCount()

        let result = try await fixture.move(plan)

        #expect(result.splitCount == 1)
        #expect(result.failedCount == 0)
        let split = try #require(result.split.first)
        #expect(split.failure.reason == .permissionLost)
        #expect(split.rollbackFailures.isEmpty == false)
        #expect(split.files.count == 4)
        let locations = Dictionary(uniqueKeysWithValues: split.files.map { ($0.role, $0) })
        #expect(locations[.primary]?.location == .destination)
        #expect(locations[.primary]?.url == entry.files[0].destination)
        #expect(locations[.jpegCompanion]?.location == .source)
        #expect(locations[.heifCompanion]?.location == .source)
        #expect(locations[.sidecar]?.location == .source)
        // Nothing was lost: the same number of files exists, in two places.
        #expect(fixture.folder.fileCount() == before)
        #expect(
            fixture.folder.exists(relativePath(of: entry.files[0].destination, in: fixture.folder)))
    }

    /// An ambiguous sidecar fails the set and leaves every candidate where it is.
    @Test func refusesAnAmbiguousSidecar() async throws {
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
        let before = fixture.folder.files()

        let result = try await fixture.move(try await fixture.plan([ambiguous]))

        let failure = try #require(result.failed.first?.failure)
        #expect(failure.reason == .ambiguousSidecar)
        #expect(fixture.fileSystem.count(of: .move) == 0)
        #expect(fixture.folder.files() == before)
    }

    /// A set whose mark change failed is skipped, then moves after the change is retried.
    @Test func skipsASetWhoseMarkChangeFailed() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        let plan = try await fixture.plan([set])
        let before = fixture.folder.files()
        let sidecarFolder = fixture.folder.file("DCIM")
        fixture.markFileSystem.failWrites { url in
            RejectMovePath.matches(url.deletingLastPathComponent(), sidecarFolder)
                ? POSIXError(.EIO) : nil
        }
        let rating = try #require(Rating(rawValue: 3))
        let change = await fixture.queue.apply(.rating(rating), to: set)
        #expect(change.state.failure != nil)

        let skipped = try await fixture.move(plan)

        #expect(skipped.skippedCount == 1)
        #expect(skipped.skipped.first?.reason == .failedMarkChange)
        #expect(fixture.folder.files() == before)

        fixture.markFileSystem.failWrites { _ in nil }
        let retried = await fixture.queue.retry(change.id)
        #expect(retried?.state == .savedInSidecar)
        let moved = try await fixture.move(plan)
        #expect(moved.movedCount == 1)
        #expect(fixture.folder.fileCount() == before.count)
    }

    /// A mark change admitted after the drain keeps its set in place until it finishes.
    @Test func skipsASetWhoseMarkChangeIsStillWriting() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let movable = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM/A", stem: "IMG_0001",
            formats: [.raw], sidecarName: "IMG_0001.xmp")
        let writing = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM/B", stem: "IMG_0002",
            formats: [.raw], sidecarName: "IMG_0002.xmp")
        for set in [movable, writing] { try writeMoveSet(set, in: fixture.folder) }
        let plan = try await fixture.plan([movable, writing])
        let before = fixture.folder.files()

        // Hold the first set's rename until the second set's mark write is admitted, so the
        // mover's per-set check sees a change that is still writing.
        let moveGate = DispatchSemaphore(value: 0)
        let movablePrimary = try #require(plan.readyEntries.first?.files.first?.destination)
        fixture.fileSystem.beforeOperation = { record in
            if record.step == .move, record.url == movablePrimary { moveGate.wait() }
        }
        let writeGate = DispatchSemaphore(value: 0)
        let writingFolder = fixture.folder.file("DCIM/B")
        fixture.markFileSystem.blockWrites { url in
            RejectMovePath.matches(url.deletingLastPathComponent(), writingFolder)
                ? writeGate : nil
        }
        let moveTask = Task { try await fixture.mover.move(plan) }
        let started = await eventually {
            fixture.fileSystem.allRecords.contains(where: { $0.step == .move })
        }
        let rating = try #require(Rating(rawValue: 2))
        let changeTask = Task { await fixture.queue.apply(.rating(rating), to: writing) }
        let admitted = await eventually { await fixture.queue.unfinishedChanges().isEmpty == false }
        moveGate.signal()
        guard started, admitted else {
            writeGate.signal()
            _ = await changeTask.value
            _ = try? await moveTask.value
            Issue.record("The move or the mark write never reached its waiting point")
            return
        }

        let result = try await moveTask.value

        writeGate.signal()
        _ = await changeTask.value
        #expect(result.movedCount == 1)
        #expect(result.outcomes.map(\.identity) == [movable.id, writing.id])
        #expect(result.skipped.first?.identity == writing.id)
        #expect(result.skipped.first?.reason == .unfinishedMarkChange)
        #expect(fixture.folder.exists("DCIM/B/IMG_0002.ARW"))
        #expect(fixture.folder.fileCount() == before.count)
    }

    /// A disabled setting refuses the plan and the run before any file is touched.
    @Test func refusesTheWholeRequestWhenTheSettingIsOff() async throws {
        let fixture = try MoveFixture(enabled: false)
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001", formats: [.raw])
        try writeMoveSet(set, in: fixture.folder)
        let before = fixture.folder.files()

        var refusal: RejectMoveRefusal?
        do {
            _ = try await fixture.plan([set])
        } catch let error as RejectMoveRefusal {
            refusal = error
        }
        #expect(refusal == .disabled)
        #expect(fixture.folder.files() == before)
    }

    /// A read-only location refuses the run even when a plan was already confirmed.
    @Test func refusesAReadOnlyLocation() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001", formats: [.raw])
        try writeMoveSet(set, in: fixture.folder)
        let plan = try await fixture.plan([set])
        fixture.fileSystem.reportsReadOnlyVolume = true
        let before = fixture.folder.files()

        var refusal: RejectMoveRefusal?
        do {
            _ = try await fixture.move(plan)
        } catch let error as RejectMoveRefusal {
            refusal = error
        }
        guard case .readOnlyLocation(let failure)? = refusal else {
            Issue.record("A read-only location should refuse the whole request")
            return
        }
        #expect(failure.reason == .readOnlyStorage)
        #expect(fixture.folder.files() == before)
        #expect(fixture.fileSystem.count(of: .move) == 0)
    }

    /// Every injected failure leaves the same files behind: no delete, no copy, no overwrite.
    @Test func noFailureModeDeletesOrCopiesAFile() async throws {
        for mode in FailureMode.allCases { try await checkNoFileIsLost(mode) }
    }

    /// The failure modes the sweep injects, one per seam step that can fail during a set.
    private enum FailureMode: String, CaseIterable {
        case createDirectory
        case firstMove
        case laterMove
        case destinationCheck
        case sourceCheck
        case moveBack
    }

    /// Runs one failure mode and checks the folder's files and bytes are unchanged as a set.
    private func checkNoFileIsLost(_ mode: FailureMode) async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM/100AAAAA", stem: "IMG_0001",
            formats: [.raw, .jpeg, .heif], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        let before = contents(fixture.folder)
        let plan = try await fixture.plan([set])
        let entry = try #require(plan.readyEntries.first)
        switch mode {
        case .createDirectory:
            fixture.fileSystem.fail(.createDirectory, with: POSIXError(.EACCES))
        case .firstMove:
            fixture.fileSystem.fail(
                .move, at: entry.files[0].destination, with: POSIXError(.EXDEV))
        case .laterMove:
            fixture.fileSystem.fail(
                .move, at: entry.files[2].destination, with: POSIXError(.ENOSPC))
        case .destinationCheck:
            fixture.fileSystem.fail(
                .fileSize, at: entry.files[0].destination, with: POSIXError(.ENOSPC))
        case .sourceCheck:
            fixture.fileSystem.fail(.exists, at: entry.files[0].source, with: POSIXError(.EIO))
        case .moveBack:
            fixture.fileSystem.fail(
                .move, at: entry.files[1].destination, with: POSIXError(.EACCES))
            fixture.fileSystem.fail(.move, at: entry.files[0].source, with: POSIXError(.EACCES))
        }

        let result = try await fixture.mover.move(plan)

        #expect(contents(fixture.folder) == before, "\(mode.rawValue) changed the folder's files")
        switch mode {
        case .createDirectory, .firstMove, .laterMove, .destinationCheck:
            #expect(result.failedCount == 1, "\(mode.rawValue) should fail the set")
            #expect(result.splitCount == 0)
        case .moveBack:
            #expect(result.splitCount == 1, "\(mode.rawValue) should report a split")
            #expect(result.split.first?.files.allSatisfy { $0.location != .missing } == true)
        case .sourceCheck:
            // The injected check keeps failing, so the rollback cannot be confirmed. The set is
            // split and the unreadable file is reported as unknown, never as lost.
            #expect(result.splitCount == 1)
            #expect(result.split.first?.files.first?.location == .unknown)
        }
    }

    /// Every file's bytes, sorted, so a failure can be compared as a multiset of contents.
    private func contents(_ folder: MoveTestFolder) -> [String] {
        folder.files().compactMap { folder.contents(of: $0) }
            .map { $0.base64EncodedString() }.sorted()
    }

    /// Cancellation stops the run between sets and leaves the rest untouched.
    @Test func cancelsBetweenSetsOnly() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let sets = try (0..<3).map { index in
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "DCIM/\(index)", stem: "IMG_000\(index)",
                formats: [.raw])
        }
        for set in sets { try writeMoveSet(set, in: fixture.folder) }
        let plan = try await fixture.plan(sets)
        let firstPrimary = try #require(plan.readyEntries.first?.files.first?.destination)
        fixture.fileSystem.beforeOperation = { record in
            if record.step == .move, record.url == firstPrimary {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }

        let result = try await Task { try await fixture.mover.move(plan) }.value

        #expect(result.movedCount == 1)
        #expect(result.outcomes.map(\.identity) == sets.map(\.id))
        #expect(result.skippedCount == 2)
        #expect(result.skipped.allSatisfy { $0.reason == .cancelled })
        #expect(result.isCancelled)
        #expect(fixture.fileSystem.count(of: .move) == 1)
        for set in sets.dropFirst() {
            #expect(
                fixture.folder.exists(
                    relativePath(of: set.photoSet.primary.url, in: fixture.folder)))
        }
    }
}
